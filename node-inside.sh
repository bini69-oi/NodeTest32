#!/usr/bin/env bash
# NodeTest32 · node-inside — проверка САМОГО сервера изнутри (по SSH, root на ноде).
# Отвечает на «годен ли этот VPS под ноду»: виртуализация, CPU и оверселл, AES-NI,
# память/диск/swap, ядро/BBR, IPv6, фаервол, время. Гоняй в первый час аренды —
# пока действует возврат: плохой сервер видно сразу.
#
#   на ноде:   bash node-inside.sh
#   удалённо:  ssh root@IP 'bash -s' < node-inside.sh
#
# Manual32 · manual32.online

VERSION="1.0.0"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BR=$'\033[38;5;29m'; OKC=$'\033[38;5;35m'; WN=$'\033[38;5;172m'; FL=$'\033[38;5;167m'
  DIM=$'\033[2m'; B=$'\033[1m'; R=$'\033[0m'; GB=$'\033[48;5;29m\033[38;5;231m'
else
  BR=''; OKC=''; WN=''; FL=''; DIM=''; B=''; R=''; GB=''
fi

SUMFILE="$(mktemp 2>/dev/null || echo /tmp/nti.$$)"; : > "$SUMFILE"
WORST=0
sev()  { case "$1" in OK) echo 0;; WARN) echo 1;; FAIL) echo 2;; *) echo 0;; esac; }
mark() { local s; s=$(sev "$1"); [ "$s" -gt "$WORST" ] && WORST=$s; printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$SUMFILE"; }
hd()   { printf '\n%s\n' "${BR}${B}▸ $1${R}${DIM} — $2${R}"; }
ok()   { printf '  %s✓%s %s\n' "$OKC" "$R" "$1"; }
warn() { printf '  %s!%s %s\n' "$WN" "$R" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$FL" "$R" "$1"; }
dim()  { printf '  %s%s%s\n' "$DIM" "$1" "$R"; }
have() { command -v "$1" >/dev/null 2>&1; }
cleanup() { [ -f "$SUMFILE" ] && rm -f "$SUMFILE"; }
trap cleanup EXIT

banner() {
  printf '\n'
  printf '%s\n'   "  ${GB} NodeTest32 ${R}  ${BR}${B}›_${R} ${DIM}node-inside ${VERSION}${R}"
  printf '%s\n\n' "  ${DIM}проверка сервера изнутри · manual32.online${R}"
}

s1_virt() {
  hd "1 · Виртуализация" "KVM годится, OpenVZ/LXC — мимо (нет своего ядра и tun)"
  local virt=""
  if have systemd-detect-virt; then virt="$(systemd-detect-virt 2>/dev/null)"; fi
  [ -z "$virt" ] && have virt-what && virt="$(virt-what 2>/dev/null | head -1)"
  local ovz="нет"; [ -d /proc/vz ] && ovz="да"
  local tun="нет"
  if [ -c /dev/net/tun ]; then tun="есть"
  elif cat /dev/net/tun 2>&1 | grep -q "bad state"; then tun="есть"; fi
  dim "ядро: $(uname -r)"
  case "$virt" in
    kvm|qemu|xen|vmware|microsoft|amazon|"")
      if [ "$ovz" = "да" ]; then
        bad "OpenVZ/Virtuozzo (/proc/vz есть) — контейнер на чужом ядре, под ноду не бери"
        mark FAIL "Виртуализация" "OpenVZ" "нет своего ядра: BBR/tun/тюнинг недоступны. Меняй на KVM"
      elif [ "$tun" != "есть" ]; then
        warn "виртуализация ${virt:-неизвестна}, но /dev/net/tun недоступен — WARP/WireGuard не поднять"
        mark WARN "Виртуализация" "нет tun" "попроси хостера включить TUN/TAP"
      else
        ok "${virt:-полноценная ВМ} + tun на месте — годится под ноду"
        mark OK "Виртуализация" "${virt:-KVM}, tun ок"
      fi;;
    openvz|lxc|container-other|systemd-nspawn|docker)
      bad "$virt — контейнер на общем ядре: BBR, sysctl-тюнинг и tun недоступны"
      mark FAIL "Виртуализация" "$virt (контейнер)" "бери KVM — Xray формально заведётся, но упрётся в тюнинге";;
    *)
      dim "тип: $virt"; ok "не контейнер"; mark OK "Виртуализация" "$virt";;
  esac
}

s2_cpu() {
  hd "2 · Процессор" "оверселл (steal) и аппаратное шифрование (AES-NI)"
  local model cores; model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')"
  cores="$(nproc 2>/dev/null || echo '?')"
  dim "${model:-CPU} · ядер: $cores"
  # AES-NI
  if grep -qm1 ' aes' /proc/cpuinfo 2>/dev/null || grep -qm1 '^flags.*aes' /proc/cpuinfo 2>/dev/null; then
    ok "AES-NI есть — TLS-шифрование аппаратное"
    mark OK "AES-NI" "есть"
  else
    warn "AES-NI НЕ проброшен (cpu qemu64?) — шифрование в разы медленнее"
    mark WARN "AES-NI" "нет" "проси у хостера cpu-host, иначе туннель упрётся в CPU"
  fi
  # steal time за короткое окно
  if have vmstat; then
    local st; st="$(LC_ALL=C vmstat 1 3 2>/dev/null | tail -1 | awk '{print $(NF-2)}')"
    case "$st" in ''|*[!0-9]*) st="";; esac
    if [ -n "$st" ]; then
      if [ "$st" -gt 10 ]; then bad "steal ${st}% — узел перегружен соседями, нода будет колоть скорость"; mark FAIL "CPU steal" "${st}%" "меряй в прайм-тайм; высокий steal = меняй тариф/хостера"
      elif [ "$st" -gt 5 ]; then warn "steal ${st}% — терпимо, но следи в вечерний пик"; mark WARN "CPU steal" "${st}%"
      else ok "steal ${st}% — соседи не мешают (проверь ещё вечером)"; mark OK "CPU steal" "${st}%"; fi
    fi
  else dim "vmstat нет (apt install procps) — steal не измерить"; fi
  # быстрый бенч шифрования
  if have openssl; then
    local speed; speed="$(openssl speed -elapsed -evp aes-256-gcm 2>/dev/null | tail -1 | awk '{print $NF}')"
    [ -n "$speed" ] && dim "openssl aes-256-gcm (16к блок): $speed — единицы ГБ/с = ок, сотни МБ/с = плохо"
  fi
}

s3_mem() {
  hd "3 · Память и диск" "RAM, свободное место, swap, следы OOM"
  if have free; then
    local avail total; avail="$(free -m | awk '/Mem:/{print $7}')"; total="$(free -m | awk '/Mem:/{print $2}')"
    [ -z "$avail" ] && avail="$(free -m | awk '/Mem:/{print $4}')"
    dim "RAM: ${total}МБ всего, ${avail}МБ доступно"
    if [ -n "$total" ] && [ "$total" -lt 400 ]; then warn "меньше 512МБ RAM — впритык, поставь swap"; mark WARN "RAM" "${total}МБ"
    else ok "RAM ${total}МБ — под голую ноду хватает"; mark OK "RAM" "${total}МБ"; fi
  fi
  # диск
  local dusef; dusef="$(df -P / 2>/dev/null | awk 'END{gsub("%","",$5); print $5}')"
  if [ -n "$dusef" ]; then
    if [ "$dusef" -ge 90 ]; then bad "диск / занят ${dusef}% — забитый диск роняет ноду; чисти логи/ротацию"; mark FAIL "Диск" "${dusef}% занято" "ротация логов Xray + docker system prune"
    else ok "диск / занят ${dusef}% — есть запас"; mark OK "Диск" "${dusef}%"; fi
  fi
  # swap
  local swap; swap="$(free -m | awk '/Swap:/{print $2}')"
  if [ "${swap:-0}" -eq 0 ] 2>/dev/null; then warn "swap нет — в пике OOM-killer прибьёт xray"; dim "фикс: fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"; mark WARN "Swap" "нет" "сделай 1ГБ swap + vm.swappiness=10"
  else ok "swap ${swap}МБ — страховка от OOM есть"; mark OK "Swap" "${swap}МБ"; fi
  # следы OOM
  if have dmesg; then
    local oom; oom="$(dmesg 2>/dev/null | grep -ci 'out of memory\|oom-kill' 2>/dev/null)"
    [ "${oom:-0}" -gt 0 ] 2>/dev/null && { warn "в dmesg $oom записей OOM — памяти реально не хватало"; mark WARN "OOM" "$oom в dmesg"; }
  fi
}

s4_kernel() {
  hd "4 · Ядро и сеть" "BBR (быстрее на дальних линках) и исходящий IPv6"
  local cc avail kmaj kmin; cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"; avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)"
  kmaj="$(uname -r | cut -d. -f1)"; kmin="$(uname -r | cut -d. -f2)"
  local bbrfix; bbrfix="printf 'net.core.default_qdisc=fq\\nnet.ipv4.tcp_congestion_control=bbr\\n' >/etc/sysctl.d/99-bbr.conf && sysctl --system"
  if [ "$cc" = "bbr" ]; then ok "TCP congestion control = bbr"; mark OK "BBR" "включён"
  elif echo "$avail" | grep -qw bbr; then warn "bbr доступен, но активен $cc — включи для дальних маршрутов"; dim "фикс: $bbrfix"; mark WARN "BBR" "выключен ($cc)" "включи bbr — прирост на РФ↔Европа"
  elif [ "${kmaj:-0}" -gt 4 ] 2>/dev/null || { [ "${kmaj:-0}" -eq 4 ] && [ "${kmin:-0}" -ge 9 ]; } 2>/dev/null; then
    warn "bbr не загружен (модуль), активен $cc — ядро $(uname -r) его умеет"; dim "фикс: modprobe tcp_bbr && $bbrfix"; mark WARN "BBR" "модуль не загружен" "modprobe tcp_bbr + включить"
  else dim "bbr в ядре нет ($cc), ядро $(uname -r) старее 4.9 — задумайся о хостере"; mark WARN "BBR" "нет в ядре"; fi
  # исходящий IPv6: адрес есть, а дефолтного маршрута нет = сайты виснут (UseIPv4)
  local has6addr has6route
  has6addr="$(ip -6 addr show scope global 2>/dev/null | grep -c inet6)"
  has6route="$(ip -6 route show default 2>/dev/null | grep -c default)"
  if [ "${has6addr:-0}" -gt 0 ] && [ "${has6route:-0}" -eq 0 ]; then
    warn "IPv6-адрес есть, а дефолтного v6-маршрута НЕТ — частая причина «сайты 0/5»"
    dim "фикс в профиле ноды: dns.queryStrategy=UseIPv4 + freedom domainStrategy=UseIPv4"
    mark WARN "IPv6" "адрес без маршрута" "UseIPv4 в Config Profile"
  else ok "исходящий IP: v4 в порядке${has6route:+, v6-маршрут есть}"; mark OK "IPv6" "без сюрпризов"; fi
}

s5_ports() {
  hd "5 · Порты и фаервол" "что слушает нода и что режет фаервол/хостер"
  if have ss; then
    dim "слушают (TCP):"; ss -tlnp 2>/dev/null | awk 'NR>1{print $4}' | sort -u | head -12 | while read -r a; do dim "  $a"; done
  fi
  # ufw
  if have ufw; then local uf; uf="$(ufw status 2>/dev/null | head -1)"; dim "ufw: ${uf:-неизвестно}"; fi
  dim "Docker публикует порты в обход ufw (свои правила в iptables) — remnanode виден снаружи даже при ufw deny"
  # исходящий 443 (нужен) и 25 (обычно режут — не страшно)
  if have curl; then
    curl -s -m 6 -o /dev/null https://api.ipify.org 2>/dev/null && ok "исходящий 443 открыт (нода достучится до интернета)" || warn "исходящий 443 не прошёл — хостер режет?"
    mark OK "Порты" "слушатели показаны"
  fi
}

s6_time() {
  hd "6 · Время" "перекос часов ломает TLS/Reality-рукопожатие"
  if have timedatectl; then
    local synced; synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
    dim "$(timedatectl 2>/dev/null | grep -i 'Time zone' | sed 's/^ *//')"
    if [ "$synced" = "yes" ]; then ok "время синхронизировано по NTP"; mark OK "Время" "NTP синхронизирован"
    else warn "NTP не синхронизирован — включи: timedatectl set-ntp true"; mark WARN "Время" "NTP не синхр." "перекос часов рвёт TLS"; fi
  else dim "timedatectl нет — проверь дату вручную: date -u"; fi
}

summary() {
  printf '\n%s\n\n' "${BR}${B}▸ ИТОГ${R}"
  local st nm val hint icon col
  while IFS=$'\t' read -r st nm val hint; do
    case "$st" in OK) icon="${OKC}✓${R}"; col="$OKC";; WARN) icon="${WN}!${R}"; col="$WN";; FAIL) icon="${FL}✗${R}"; col="$FL";; esac
    printf '  %s %s%-14s%s %s\n' "$icon" "$col" "$nm" "$R" "$val"
    [ -n "$hint" ] && printf '      %s↳ %s%s\n' "$DIM" "$hint" "$R"
  done < "$SUMFILE"
  printf '\n'
  case "$WORST" in
    0) printf '  %s%s● сервер годен под ноду%s\n\n' "$GB" " " "$R";;
    1) printf '  %s%s● годен, но подкрути %s помеченное%s\n\n' "$WN" "$B" "!" "$R";;
    2) printf '  %s%s● под ноду не бери — есть %s, меняй пока действует возврат%s\n\n' "$FL" "$B" "✗" "$R";;
  esac
  printf '  %sтеперь проверь трафик снаружи: node-check.sh со ссылкой на тест-юзера%s\n' "$DIM" "$R"
  printf '  %sразбор каждой проверки — мануал «Проверка ноды» на manual32.online%s\n\n' "$DIM" "$R"
}

main() {
  banner
  [ "$(id -u 2>/dev/null)" = "0" ] || dim "не root — часть проверок (steal, ss -p) будут неполными; запусти под root"
  [ -f /proc/cpuinfo ] || { printf '  %s✗ это не Linux-сервер. node-inside гоняй на самой ноде (ssh root@IP)%s\n\n' "$FL" "$R"; exit 2; }
  s1_virt; s2_cpu; s3_mem; s4_kernel; s5_ports; s6_time
  summary
  exit "$WORST"
}
main "$@"
