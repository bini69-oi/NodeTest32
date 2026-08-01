#!/usr/bin/env bash
# NodeTest32 — разовый вердикт по ноде VPN: жив ли хост, канал, маскировка и
# реально ли ходит трафик через туннель. Один скрипт, зависимости — только curl
# (xray скрипт подтянет сам). Запускать НЕ с самой ноды (см. стадию 0).
#
#   ./node-check.sh 'vless://uuid@host:443?type=...&security=reality&pbk=...#name'   полный прогон
#   ./node-check.sh 1.2.3.4 443                                                       без туннеля (нет ссылки)
#
# Manual32 · manual32.online

VERSION="1.0.0"
XRAY_VER="v26.3.27"          # минимум для XHTTP GET-режима
WORKDIR="${NODETEST32_HOME:-$HOME/.nodetest32}"

# ------------------------------------------------------------------ оформление
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BR=$'\033[38;5;29m'; OKC=$'\033[38;5;35m'; WN=$'\033[38;5;172m'; FL=$'\033[38;5;167m'
  DIM=$'\033[2m'; B=$'\033[1m'; R=$'\033[0m'; GB=$'\033[48;5;29m\033[38;5;231m'
else
  BR=''; OKC=''; WN=''; FL=''; DIM=''; B=''; R=''; GB=''
fi

banner() {
  printf '\n'
  printf '%s\n'   "  ${GB} NodeTest32 ${R}  ${BR}${B}›_${R} ${DIM}node-check ${VERSION}${R}"
  printf '%s\n\n' "  ${DIM}проверка ноды · manual32.online${R}"
}

# статусы + сбор итога
SUMFILE="$(mktemp 2>/dev/null || echo /tmp/nt32.$$)"; : > "$SUMFILE"
WORST=0    # 0 ok · 1 warn · 2 fail
sev()  { case "$1" in OK) echo 0;; WARN) echo 1;; FAIL) echo 2;; *) echo 0;; esac; }
mark() { local s; s=$(sev "$1"); [ "$s" -gt "$WORST" ] && WORST=$s; printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$SUMFILE"; }

hd()   { printf '\n%s\n' "${BR}${B}▸ $1${R}${DIM} — $2${R}"; }
ok()   { printf '  %s✓%s %s\n' "$OKC" "$R" "$1"; }
warn() { printf '  %s!%s %s\n' "$WN" "$R" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$FL" "$R" "$1"; }
dim()  { printf '  %s%s%s\n' "$DIM" "$1" "$R"; }
die()  { printf '\n  %s✗ %s%s\n\n' "$FL" "$1" "$R"; cleanup; exit 2; }

# ------------------------------------------------------------------ утилиты
have() { command -v "$1" >/dev/null 2>&1; }

# резолв IPv4 хоста (dig → host → getent → парс ping)
resolve4() {
  local h="$1" ip=""
  case "$h" in *[!0-9.]*) ;; *) echo "$h"; return;; esac      # уже IP
  if have dig;  then ip=$(dig +short A "$h" 2>/dev/null | grep -E '^[0-9.]+$' | head -1); fi
  if [ -z "$ip" ] && have host;    then ip=$(host -t A "$h" 2>/dev/null | awk '/has address/{print $NF; exit}'); fi
  if [ -z "$ip" ] && have getent;  then ip=$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1; exit}'); fi
  if [ -z "$ip" ]; then ip=$(ping -c1 -W1 "$h" 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1); fi
  echo "$ip"
}

urldecode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }

# извлечь параметр из query-строки (портативно, без ассоц-массивов bash4)
qget() {
  local key="$1" qs="$2" kv
  local IFS='&'
  for kv in $qs; do
    case "$kv" in "$key="*) urldecode "${kv#*=}"; return;; esac
  done
}

# ------------------------------------------------------------------ парсер ссылки
# заполняет: PROTO HOST PORT NET SEC SNI PBK SID FP FLOW UPATH HOSTHDR SPX ALPN SVCNAME UUID NAME
PROTO=""; HOST=""; PORT=""; NET="tcp"; SEC="none"; SNI=""; PBK=""; SID=""; FP=""
FLOW=""; UPATH=""; HOSTHDR=""; SPX=""; ALPN=""; SVCNAME=""; UUID=""; NAME=""
parse_link() {
  local link="$1"
  PROTO="${link%%://*}"; PROTO="$(echo "$PROTO" | tr 'A-Z' 'a-z')"
  case "$PROTO" in vless|trojan) ;; hy2) PROTO="hysteria2";;
    *) die "v1 понимает только vless и trojan. Для $PROTO дай IP отдельно — проверю без туннеля.";; esac
  local rest="${link#*://}"
  # имя после последнего '#'
  case "$rest" in *\#*) NAME="$(urldecode "${rest##*#}")"; rest="${rest%%#*}";; esac
  # query после '?'
  local qs=""; case "$rest" in *\?*) qs="${rest#*\?}"; rest="${rest%%\?*}";; esac
  # uuid@host:port
  UUID="${rest%%@*}"; local hp="${rest#*@}"
  # host может быть [ipv6]
  case "$hp" in
    \[*\]*) HOST="${hp%%\]*}"; HOST="${HOST#\[}"; PORT="${hp##*\]:}";;
    *) HOST="${hp%%:*}"; PORT="${hp#*:}";;
  esac
  case "$PORT" in *[!0-9]*|'') PORT=443;; esac
  UUID="$(urldecode "$UUID")"
  NET="$(qget type "$qs")";    [ -z "$NET" ] && NET="tcp"; [ "$NET" = "raw" ] && NET="tcp"
  SEC="$(qget security "$qs")"
  PBK="$(qget pbk "$qs")"
  SNI="$(qget sni "$qs")"; [ -z "$SNI" ] && SNI="$(qget serverName "$qs")"; [ -z "$SNI" ] && SNI="$(qget host "$qs")"
  SID="$(qget sid "$qs")"
  FP="$(qget fp "$qs")"
  FLOW="$(qget flow "$qs")"
  UPATH="$(qget path "$qs")"
  HOSTHDR="$(qget host "$qs")"
  SPX="$(qget spx "$qs")"
  ALPN="$(qget alpn "$qs")"
  SVCNAME="$(qget serviceName "$qs")"
  # нормализация security как в боевом парсере
  if [ -n "$PBK" ]; then SEC="reality"
  elif [ "$SEC" = "reality" ] && [ -z "$PBK" ]; then SEC="none"
  elif [ "$PROTO" = "trojan" ] && [ -z "$SEC" ]; then SEC="tls"
  elif [ -z "$SEC" ]; then SEC="none"; fi
  # fp из ссылки берём как есть (uTLS тест-клиента, на аутентификацию не влияет); пустой -> chrome
  [ -z "$FP" ] && FP="chrome"
}

# ------------------------------------------------------------------ xray бинарь
XRAYBIN=""
xray_asset() {
  local s m; s="$(uname -s)"; m="$(uname -m)"
  case "$s" in
    Linux)  case "$m" in aarch64|arm64) echo "Xray-linux-arm64-v8a.zip";; *) echo "Xray-linux-64.zip";; esac;;
    Darwin) case "$m" in arm64|aarch64) echo "Xray-macos-arm64-v8a.zip";; *) echo "Xray-macos-64.zip";; esac;;
    *) echo "";;
  esac
}
ensure_xray() {
  local dir="$WORKDIR/xray" bin="$WORKDIR/xray/xray"
  [ -x "$bin" ] && { XRAYBIN="$bin"; return 0; }
  local asset; asset="$(xray_asset)"; [ -z "$asset" ] && return 1
  have unzip || { warn "нет unzip — туннельные стадии пропущу (поставь: apt install unzip / brew install unzip)"; return 1; }
  mkdir -p "$dir"
  local url="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/$asset"
  dim "качаю xray-core $XRAY_VER ($asset)…"
  curl -fsSL -o "$dir/x.zip" "$url" 2>/dev/null || { warn "не скачался xray ($url)"; return 1; }
  unzip -o "$dir/x.zip" xray -d "$dir" >/dev/null 2>&1 || { warn "не распаковался xray"; rm -f "$dir/x.zip"; return 1; }
  rm -f "$dir/x.zip"; chmod 755 "$bin" 2>/dev/null
  [ -x "$bin" ] && { XRAYBIN="$bin"; return 0; }; return 1
}

# ------------------------------------------------------------------ конфиг xray
CFG=""
gen_config() {
  local socks="$1" addr network
  network="$NET"; [ "$network" = "raw" ] && network="tcp"
  # дозваниваемся на резолвленный IPv4, SNI/Host остаются доменом (без DNS-сюрпризов)
  addr="$NODE_IP"; case "$addr" in ""|*[!0-9.]*) addr="$HOST";; esac
  local stream flowj="" sec="$SEC"
  # streamSettings.security-блок
  local secblock=""
  if [ "$sec" = "reality" ]; then
    secblock=",\"realitySettings\":{\"serverName\":\"$SNI\",\"publicKey\":\"$PBK\",\"shortId\":\"$SID\",\"fingerprint\":\"${FP:-chrome}\",\"spiderX\":\"$SPX\"}"
  elif [ "$sec" = "tls" ]; then
    local alpnj=""; [ -n "$ALPN" ] && alpnj=",\"alpn\":[\"$(echo "$ALPN" | sed 's/,/","/g')\"]"
    secblock=",\"tlsSettings\":{\"serverName\":\"${SNI:-$HOST}\",\"allowInsecure\":false,\"fingerprint\":\"${FP:-chrome}\"$alpnj}"
  else sec="none"; fi
  # транспорт
  local trblock=""
  case "$network" in
    ws)          trblock=",\"wsSettings\":{\"path\":\"${UPATH:-/}\"$([ -n "$HOSTHDR" ] && echo ",\"headers\":{\"Host\":\"$HOSTHDR\"}")}";;
    xhttp)       trblock=",\"xhttpSettings\":{\"path\":\"${UPATH:-/}\"$([ -n "$HOSTHDR" ] && echo ",\"host\":\"$HOSTHDR\"")}";;
    grpc)        trblock=",\"grpcSettings\":{\"serviceName\":\"$SVCNAME\"}";;
    httpupgrade) trblock=",\"httpupgradeSettings\":{\"path\":\"${UPATH:-/}\"$([ -n "$HOSTHDR" ] && echo ",\"host\":\"$HOSTHDR\"")}";;
  esac
  stream="\"streamSettings\":{\"network\":\"$network\",\"security\":\"$sec\"$secblock$trblock}"
  local outbound
  if [ "$PROTO" = "vless" ]; then
    outbound="{\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"$addr\",\"port\":$PORT,\"users\":[{\"id\":\"$UUID\",\"encryption\":\"none\",\"flow\":\"$FLOW\"}]}]},$stream}"
  else
    outbound="{\"protocol\":\"trojan\",\"settings\":{\"servers\":[{\"address\":\"$addr\",\"port\":$PORT,\"password\":\"$UUID\"}]},$stream}"
  fi
  CFG="$WORKDIR/cfg.$$.json"
  printf '{"log":{"loglevel":"none"},"inbounds":[{"listen":"127.0.0.1","port":%s,"protocol":"socks","settings":{"udp":false}}],"outbounds":[%s]}\n' "$socks" "$outbound" > "$CFG"
}

free_port() {
  local p
  for p in 10808 10810 10812 10820 11080 12080 18080; do
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then echo "$p"; return; fi
    exec 3>&- 2>/dev/null
  done
  echo 10808
}

XRAYPID=""
cleanup() {
  [ -n "$XRAYPID" ] && kill "$XRAYPID" 2>/dev/null
  [ -n "$CFG" ] && rm -f "$CFG" 2>/dev/null
  [ -f "$SUMFILE" ] && rm -f "$SUMFILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ============================================================ СТАДИИ
NODE_IP=""; MY_IP=""; HAVE_LINK=0

stage0_preflight() {
  hd "0 · Полигон" "откуда запускаем — годится ли точка"
  have curl || die "нет curl — без него никак (apt install curl / уже есть на macOS)"
  MY_IP="$(curl -4 -fsS -m 6 https://api.ipify.org 2>/dev/null)"
  if [ -n "$NODE_IP" ] && [ -n "$MY_IP" ] && [ "$MY_IP" = "$NODE_IP" ]; then
    die "запускаешь С САМОЙ ноды (мой IP = IP ноды). Меряй с другого компа/VPS — localhost завышает скорость и врёт."
  fi
  [ -n "$MY_IP" ] && dim "точка запуска: $MY_IP"
  # активные VPN-интерфейсы уводят трафик мимо цели
  local tuns
  tuns="$( (ifconfig 2>/dev/null || ip -o link show 2>/dev/null) | grep -oE '(utun|tun|wg|tap)[0-9]+' | sort -u | tr '\n' ' ')"
  if echo "$tuns" | grep -qE '(utun|tun|wg|tap)[0-9]'; then
    warn "подняты VPN-интерфейсы: ${tuns}— тест может врать. Выключи все VPN и запусти заново."
  else
    ok "чужих VPN-туннелей нет"
  fi
  have mtr || dim "mtr не установлен — маршрут покажу через traceroute (грубее)"
}

# TCP-connect тайминг: https:// с -k ловит time_connect на TCP-слое (до TLS),
# на Reality/TLS-порту возвращается быстро; exit-код различает refused (7) и timeout (28)
tcp_probe() {   # $1=timeout сек; печатает "мс|код" (мс пусто если не подключились)
  local to="$1" tc ec ms
  tc="$(curl -kso /dev/null --connect-timeout "$to" -m "$to" -w '%{time_connect}' "https://$NODE_IP:$PORT" 2>/dev/null)"; ec=$?
  if [ -n "$tc" ] && [ "$tc" != "0.000000" ]; then
    ms="$(awk -v t="$tc" 'BEGIN{printf "%d", t*1000}')"
    printf '%s|%s' "$ms" "$ec"
  else
    printf '|%s' "$ec"
  fi
}

stage1_host_port() {
  hd "1 · Хост и порт" "жив ли сервер, открыт ли порт инбаунда"
  local r ms ec; r="$(tcp_probe 4)"; ms="${r%%|*}"; ec="${r##*|}"
  local icmp="нет"; ping -c1 -W2 "$NODE_IP" >/dev/null 2>&1 && icmp="есть"
  if [ -n "$ms" ]; then
    ok "порт $PORT открыт (${ms} мс), ICMP-пинг: $icmp"
    mark OK "Хост/порт" "порт $PORT открыт, ${ms}мс"
  elif [ "$ec" = "7" ]; then
    # RST мгновенно: слушателя нет / reject
    bad "порт $PORT отбивает соединение (RST) — xray лежит или порт не тот"
    mark FAIL "Хост/порт" "порт $PORT: connection refused" "docker ps · логи remnanode · тот ли порт инбаунда"
  elif [ "$icmp" = "есть" ]; then
    # пакет молча дропается: фильтр
    bad "порт $PORT молчит (таймаут), хост пингуется — фильтрует ufw или хостер"
    mark FAIL "Хост/порт" "порт $PORT: таймаут (фильтр)" "ufw status · фаервол хостера на $PORT"
  else
    bad "хост не отвечает ни на порт $PORT, ни на ICMP"
    mark FAIL "Хост/порт" "хост недоступен" "проверь IP и что нода вообще включена"
  fi
}

stage2_latency() {
  hd "2 · Латентность" "серия TCP-рукопожатий: медиана и джиттер, не один пинг"
  local i vals="" v r
  for i in 1 2 3 4 5 6 7 8 9 10; do
    r="$(tcp_probe 3)"; v="${r%%|*}"
    [ -n "$v" ] && vals="$vals $v"
    sleep 0.3
  done
  local n; n=$(echo $vals | wc -w | tr -d ' ')
  local loss; loss=$(( (10 - n) * 10 ))
  if [ "$n" -eq 0 ]; then
    bad "все 10 проб не дошли — порт нестабилен/закрыт"
    mark FAIL "Латентность" "100% потерь"; return
  fi
  # медиана + джиттер (max-min) через awk
  read med jit min max < <(echo $vals | tr ' ' '\n' | sort -n | awk '
    {a[NR]=$1} END{
      m=(NR%2)?a[int(NR/2)+1]:(a[NR/2]+a[NR/2+1])/2;
      printf "%.0f %.0f %.0f %.0f", m, a[NR]-a[1], a[1], a[NR]}')
  local vv=OK; local hint=""
  if   [ "$med" -gt 400 ]; then vv=FAIL; hint="далёкая гео или перегруз узла"
  elif [ "$med" -gt 160 ]; then vv=WARN; hint="высоковато — сверь с расстоянием (~1мс на 100км)"; fi
  local jv=OK
  if   [ "$jit" -gt 80 ]; then jv=FAIL
  elif [ "$jit" -gt 30 ]; then jv=WARN; fi
  local lv=OK
  if   [ "$loss" -ge 15 ]; then lv=FAIL
  elif [ "$loss" -gt 0 ];  then lv=WARN; fi
  # худший из трёх
  local worst=OK; for x in "$vv" "$jv" "$lv"; do [ "$(sev "$x")" -gt "$(sev "$worst")" ] && worst="$x"; done
  local line="медиана ${med}мс · джиттер ${jit}мс · потери ${loss}%"
  case "$worst" in OK) ok "$line — стабильно";; WARN) warn "$line";; FAIL) bad "$line";; esac
  mark "$worst" "Латентность" "$line" "$hint"
}

stage3_route() {
  hd "3 · Маршрут" "где путь портится (справочно — потери на середине это норма)"
  if have mtr; then
    dim "mtr 10 циклов…"
    local out; out="$(mtr -rwznc 10 "$NODE_IP" 2>/dev/null)"
    if [ -n "$out" ]; then
      echo "$out" | tail -n +2 | while IFS= read -r l; do dim "$l"; done
      local lastloss; lastloss="$(echo "$out" | tail -1 | grep -oE '[0-9.]+%' | head -1 | tr -d '%')"
      if [ -n "$lastloss" ] && awk -v l="$lastloss" 'BEGIN{exit !(l>10)}'; then
        warn "потери на финальном хопе ${lastloss}% — сверь со стадией 2"
        mark WARN "Маршрут" "потери на финале ${lastloss}%"
      else
        ok "до финального хопа без заметных потерь"; mark OK "Маршрут" "путь чистый"
      fi
    else warn "mtr ничего не вернул"; fi
  elif have traceroute; then
    dim "traceroute…"
    traceroute -n -q1 -m 20 -w2 "$NODE_IP" 2>/dev/null | tail -n +2 | while IFS= read -r l; do dim "$l"; done
    mark OK "Маршрут" "traceroute показан (справочно)"
  else
    dim "ни mtr, ни traceroute — стадию пропускаю"
  fi
}

stage4_mtu() {
  hd "4 · MTU" "чёрная дыра: туннель встаёт, тяжёлые страницы висят"
  local os; os="$(uname -s)"
  # DF-пинг: размер пакета = payload + 28 (20 IP + 8 ICMP). Проверяем от 1500 вниз.
  local payloads="1472 1392 1252 1164"   # -> MTU 1500, 1420(WG), 1280(min IPv6), 1192
  local got="" payload
  for payload in $payloads; do
    if [ "$os" = "Darwin" ]; then
      ping -D -s "$payload" -c1 "$NODE_IP" >/dev/null 2>&1 && { got=$((payload+28)); break; }
    else
      ping -M do -s "$payload" -c1 -W2 "$NODE_IP" >/dev/null 2>&1 && { got=$((payload+28)); break; }
    fi
  done
  if [ -z "$got" ]; then
    dim "ICMP закрыт (DF-пинг не проходит) — MTU так не измерить"
    mark OK "MTU" "не проверить (ICMP закрыт)" "raw-Reality виснет, а gRPC/XHTTP живут = почти наверняка MTU"
  elif [ "$got" -ge 1500 ]; then
    ok "путь держит MTU 1500 — дыры нет"; mark OK "MTU" "1500, чисто"
  else
    warn "path MTU = $got (меньше 1500)"
    dim "фикс на ноде (Xray терминирует TCP сам, поэтому POSTROUTING, не FORWARD):"
    dim "iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((got-40))"
    mark WARN "MTU" "path MTU $got" "MSS-clamp на ноде до $((got-40))"
  fi
}

stage5_mask() {
  [ "$HAVE_LINK" -eq 1 ] || { return; }
  hd "5 · Маскировка" "что отдаёт порт при TLS с твоим SNI"
  have openssl || { dim "нет openssl — пропускаю"; return; }
  local sni="$SNI"; [ -z "$sni" ] && sni="$HOST"
  if [ "$SEC" = "none" ]; then dim "у ссылки security=none — маскировки нет, пропускаю"; return; fi
  local cert; cert="$(echo | openssl s_client -connect "$NODE_IP:$PORT" -servername "$sni" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)"
  if [ -z "$cert" ]; then
    bad "TLS-рукопожатие не удалось (SNI $sni)"
    mark FAIL "Маскировка" "нет TLS-ответа" "порт не отдаёт сертификат — проверь, что нода слушает $PORT"
    return
  fi
  local subj iss end; subj="$(echo "$cert" | sed -n 's/^subject=//p')"; iss="$(echo "$cert" | sed -n 's/^issuer=//p')"; end="$(echo "$cert" | sed -n 's/^notAfter=//p')"
  dim "subject: $subj"; dim "issuer:  $iss"
  if [ "$subj" = "$iss" ]; then
    bad "сертификат самоподписанный — DPI видит подмену, нода под риском"
    mark FAIL "Маскировка" "self-signed cert" "домен-прикрытие настроен неверно (dest/SNI)"
  else
    # срок
    local days=""
    if have openssl; then
      local endsec nowsec
      endsec="$(date -d "$end" +%s 2>/dev/null || { date -jf '%b %e %T %Y %Z' "$end" +%s 2>/dev/null; })"
      nowsec="$(date +%s)"
      [ -n "$endsec" ] && days=$(( (endsec - nowsec) / 86400 ))
    fi
    if [ -n "$days" ] && [ "$days" -lt 14 ]; then
      warn "сертификат домена-прикрытия жив, но истекает через $days дн."
      mark WARN "Маскировка" "серт истекает через ${days}дн"
    else
      ok "порт отдаёт настоящий сертификат домена-прикрытия${days:+ (ещё $days дн.)}"
      mark OK "Маскировка" "серт домена-прикрытия ок"
    fi
  fi
}

SOCKS=""
tunnel_up() {
  ensure_xray || return 1
  SOCKS="$(free_port)"
  gen_config "$SOCKS"
  # валидация конфига до запуска — битая ссылка даст внятную ошибку
  "$XRAYBIN" run -test -c "$CFG" >/dev/null 2>&1 || { bad "конфиг из ссылки не прошёл валидацию xray (проверь ключи)"; return 1; }
  "$XRAYBIN" run -c "$CFG" >/dev/null 2>&1 &
  XRAYPID=$!
  # ждём порт до 6с
  local t=0
  while [ "$t" -lt 40 ]; do
    (exec 3<>"/dev/tcp/127.0.0.1/$SOCKS") 2>/dev/null && { exec 3>&- 2>/dev/null; return 0; }
    sleep 0.15; t=$((t+1))
  done
  return 1
}

stage6_tunnel() {
  [ "$HAVE_LINK" -eq 1 ] || { dim ""; hd "6 · Туннель" "нужна ссылка"; warn "дай vless://-ссылку — проверю ноду насквозь"; return; }
  hd "6 · Туннель (ядро теста)" "поднимаю xray из ссылки и гоню реальный трафик"
  if ! tunnel_up; then
    bad "туннель не поднялся"
    mark FAIL "Туннель" "xray не стартовал" "битые ключи в ссылке, либо нода не принимает этот транспорт"
    return
  fi
  local sx="--socks5-hostname 127.0.0.1:$SOCKS"
  # выходной IP
  local exip; exip="$(curl -4 -sS -m 12 $sx https://api.ipify.org 2>/dev/null)"
  if [ -z "$exip" ]; then
    bad "туннель встал, но данные не идут (пустой выходной IP)"
    dim "вероятно: flow не совпал с панелью · MTU-дыра (стадия 4) · IPv6 без маршрута (фикс UseIPv4) · рассинхрон профиля — рестарт ноды"
    mark FAIL "Туннель" "нет выхода" "flow/MTU/IPv6/рассинхрон — см. подсказки выше"
    return
  fi
  if [ "$exip" = "$NODE_IP" ]; then ok "выход через ноду: $exip"
  else dim "выходной IP $exip ≠ IP ноды $NODE_IP — норма для каскада/WARP, ненорма для обычной ноды"; fi
  # батарея сайтов
  local sites="generate_204:www.google.com:/generate_204 YouTube:www.youtube.com:/ ChatGPT:chatgpt.com:/ Instagram:www.instagram.com:/ Discord:discord.com:/"
  local reach=0 tot=0 s nm hh pp code
  for s in $sites; do
    nm="${s%%:*}"; hh="$(echo "$s" | cut -d: -f2)"; pp="$(echo "$s" | cut -d: -f3)"
    tot=$((tot+1))
    code="$(curl -4 -sS -m 12 -o /dev/null -w '%{http_code}' $sx "https://$hh$pp" 2>/dev/null)"
    case "$code" in
      200|204|3??|400|403|429) reach=$((reach+1)); ok "$nm — достижим (HTTP $code)";;
      503) warn "$nm — 503: сервис режет репутацию этого IP";;
      000|"") bad "$nm — не открылся (нет ответа)";;
      *) warn "$nm — HTTP $code";;
    esac
  done
  # TTFB
  local ttfb; ttfb="$(curl -4 -sS -m 12 -o /dev/null -w '%{time_starttransfer}' $sx https://www.google.com/generate_204 2>/dev/null)"
  local tms=""; [ -n "$ttfb" ] && tms=$(awk -v t="$ttfb" 'BEGIN{printf "%d", t*1000}')
  local vv=OK; local line="сайты $reach/$tot"
  if   [ "$reach" -le 2 ]; then vv=FAIL
  elif [ "$reach" -lt "$tot" ]; then vv=WARN; fi
  if [ -n "$tms" ]; then
    line="$line · TTFB ${tms}мс"
    if [ "$tms" -gt 1500 ]; then [ "$(sev FAIL)" -gt "$(sev $vv)" ] && vv=FAIL
    elif [ "$tms" -gt 600 ]; then [ "$(sev WARN)" -gt "$(sev $vv)" ] && vv=WARN; fi
  fi
  case "$vv" in OK) ok "$line";; WARN) warn "$line";; FAIL) bad "$line";; esac
  mark "$vv" "Туннель e2e" "$line"
}

stage7_speed() {
  [ "$HAVE_LINK" -eq 1 ] && [ -n "$SOCKS" ] || return
  hd "7 · Скорость" "через туннель относительно твоего канала (не абсолют)"
  local url="https://speed.cloudflare.com/__down?bytes=50000000"
  dim "мерю baseline (напрямую)…"
  local base; base="$(curl -4 -sS -m 25 -o /dev/null -w '%{speed_download}' "$url" 2>/dev/null)"
  dim "мерю через туннель…"
  local via; via="$(curl -4 -sS -m 30 -o /dev/null -w '%{speed_download}' --socks5-hostname "127.0.0.1:$SOCKS" "$url" 2>/dev/null)"
  local bmb vmb; bmb=$(awk -v b="${base:-0}" 'BEGIN{printf "%.1f", b*8/1e6}'); vmb=$(awk -v v="${via:-0}" 'BEGIN{printf "%.1f", v*8/1e6}')
  local pct; pct=$(awk -v b="${base:-0}" -v v="${via:-0}" 'BEGIN{printf "%d", (b>0)? v/b*100 : 0}')
  local vv=OK
  if   [ "$pct" -lt 20 ]; then vv=FAIL
  elif [ "$pct" -lt 50 ]; then vv=WARN; fi
  # абсолютный флаг: <10 Мбит при живом канале
  if awk -v v="${vmb:-0}" -v b="${bmb:-0}" 'BEGIN{exit !(v<10 && b>10)}'; then vv=FAIL; fi
  local line="туннель ${vmb} Мбит/с · канал ${bmb} Мбит/с (${pct}%)"
  case "$vv" in OK) ok "$line";; WARN) warn "$line";; FAIL) bad "$line";; esac
  mark "$vv" "Скорость" "$line"
  dim "с домашнего РФ-провайдера это «что почувствует клиент»; чистые цифры ноды — с соседнего VPS"
}

stage8_passport() {
  hd "8 · Паспорт ноды" "гео/ASN/репутация IP (меткам панели не верим)"
  local j; j="$(curl -s -m 8 "http://ip-api.com/line/$NODE_IP?fields=status,country,countryCode,city,isp,as,hosting,proxy,reverse" 2>/dev/null)"
  if [ -z "$j" ] || [ "$(echo "$j" | head -1)" != "success" ]; then
    dim "гео-API не ответил — пропускаю"; return
  fi
  local country cc city isp asn hosting proxy rev
  country="$(echo "$j" | sed -n 2p)"; cc="$(echo "$j" | sed -n 3p)"; city="$(echo "$j" | sed -n 4p)"
  isp="$(echo "$j" | sed -n 5p)"; asn="$(echo "$j" | sed -n 6p)"; hosting="$(echo "$j" | sed -n 7p)"
  proxy="$(echo "$j" | sed -n 8p)"; rev="$(echo "$j" | sed -n 9p)"
  dim "гео: $country ($cc), $city · $isp · $asn"
  [ -n "$rev" ] && dim "PTR: $rev"
  if [ "$proxy" = "true" ]; then
    warn "IP уже помечен как proxy/VPN — капчи, стриминги и банки будут резать"
    mark WARN "Паспорт IP" "$cc · proxy-флаг" "засвеченный IP — переезд на чистый"
  else
    ok "$country ($cc)${hosting:+, hosting}${proxy:+}, proxy-флага нет"
    mark OK "Паспорт IP" "$cc · чисто"
  fi
}

stage9_summary() {
  printf '\n%s\n\n' "${BR}${B}▸ ИТОГ${R}"
  local st nm val hint icon col
  while IFS=$'\t' read -r st nm val hint; do
    case "$st" in
      OK)   icon="${OKC}✓${R}"; col="$OKC";;
      WARN) icon="${WN}!${R}";  col="$WN";;
      FAIL) icon="${FL}✗${R}";  col="$FL";;
    esac
    printf '  %s %s%-16s%s %s\n' "$icon" "$col" "$nm" "$R" "$val"
    [ -n "$hint" ] && printf '      %s↳ %s%s\n' "$DIM" "$hint" "$R"
  done < "$SUMFILE"
  printf '\n'
  case "$WORST" in
    0) printf '  %s%s● нода в порядке — годна под боевую нагрузку%s\n\n' "$GB" " " "$R";;
    1) printf '  %s%s● рабочая, но с оговорками — смотри %s выше%s\n\n' "$WN" "$B" "!" "$R";;
    2) printf '  %s%s● нода не готова — есть %s, чинить до боя%s\n\n' "$FL" "$B" "✗" "$R";;
  esac
  printf '  %sподробный разбор каждой стадии — мануал «Проверка ноды» на manual32.online%s\n' "$DIM" "$R"
  printf '  %sпостоянный мониторинг боевой ноды — раздел «Контроль» там же%s\n\n' "$DIM" "$R"
}

# ============================================================ MAIN
main() {
  local arg1="${1:-}"
  # предзагрузка xray (для мгновенного старта туннельной проверки), без баннера и меню
  if [ "$arg1" = "--prefetch" ]; then
    ensure_xray && [ -n "$XRAYBIN" ] && exit 0 || exit 1
  fi
  banner
  if [ -z "$arg1" ]; then
    printf '  %sкак запускать:%s\n' "$B" "$R"
    printf '    ./node-check.sh %s'\''vless://uuid@host:443?...#name'\''%s   полная проверка через туннель\n' "$BR" "$R"
    printf '    ./node-check.sh %s1.2.3.4 443%s                        без ссылки (хост/канал/маскировка)\n\n' "$BR" "$R"
    printf '  %sссылку возьми из своей подписки или карточки хоста в панели (с ключами тест-юзера)%s\n\n' "$DIM" "$R"
    exit 0
  fi
  case "$arg1" in
    *://*)
      HAVE_LINK=1
      parse_link "$arg1"
      NODE_IP="$(resolve4 "$HOST")"
      [ -z "$NODE_IP" ] && die "не резолвится хост $HOST"
      dim "нода: $PROTO $HOST:$PORT · транспорт $NET · $SEC${NAME:+ · «$NAME»}"
      ;;
    *)
      HAVE_LINK=0
      HOST="$arg1"; PORT="${2:-443}"
      case "$PORT" in *[!0-9]*) PORT=443;; esac
      NODE_IP="$(resolve4 "$HOST")"
      [ -z "$NODE_IP" ] && die "не резолвится хост $HOST"
      dim "нода: $HOST:$PORT (без ссылки — туннель не проверю)"
      ;;
  esac

  stage0_preflight
  stage1_host_port
  stage2_latency
  stage3_route
  stage4_mtu
  stage5_mask
  stage6_tunnel
  stage7_speed
  stage8_passport
  stage9_summary

  exit "$WORST"
}

main "$@"
