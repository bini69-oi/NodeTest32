#!/usr/bin/env bash
# NodeTest32 — интерактивный тестер нод VPN от Manual32. Проверяет и сам сервер
# (железо, стил, канал, IP), и реальный трафик через туннель. Все проверки в одном
# меню: можно запускать по отдельности или прогнать всё сразу. При первом запуске
# один раз подтягивает всё нужное, дальше стартует моментально. Сервер не меняет.
#
#   меню:     bash <(curl -sL https://raw.githubusercontent.com/bini69-oi/NodeTest32/main/nodetest32.sh)
#   команда:  bash <(...nodetest32.sh) --install   →   потом просто `nodetest32`
#   базовый:  ./nodetest32.sh --basic              (только встроенные проверки)
#
# Manual32 · manual32.online

VERSION="2.1.0"
NT_REPO_RAW="${NT_REPO_RAW:-https://raw.githubusercontent.com/bini69-oi/NodeTest32/main}"
NT_HOME="${NODETEST32_HOME:-$HOME/.nodetest32}"
NO_EXTERNAL=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null)"
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="."

# ------------------------------------------------------------------ бренд-кит
# рядом (clone) -> source; иначе тянем lib/brand.sh с пина; иначе минимальный inline
if [ -f "$SCRIPT_DIR/lib/brand.sh" ]; then
  . "$SCRIPT_DIR/lib/brand.sh"
else
  _lib="$(mktemp 2>/dev/null || echo /tmp/nt32lib.$$)"
  if curl -fsSL -m 15 "$NT_REPO_RAW/lib/brand.sh" -o "$_lib" 2>/dev/null && head -1 "$_lib" 2>/dev/null | grep -q '^#'; then
    . "$_lib"; rm -f "$_lib"
  else
    rm -f "$_lib"
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then BR=$'\033[38;5;29m'; OKC=$'\033[38;5;35m'; WN=$'\033[38;5;172m'; FL=$'\033[38;5;167m'; DIM=$'\033[2m'; B=$'\033[1m'; R=$'\033[0m'; GB=$'\033[48;5;29m\033[38;5;231m'; else BR=''; OKC=''; WN=''; FL=''; DIM=''; B=''; R=''; GB=''; fi
    hd(){ printf '\n%s\n' "${BR}${B}▸ $1${R}${DIM} — $2${R}"; }; ok(){ printf '  %s✓%s %s\n' "$OKC" "$R" "$1"; }
    warn(){ printf '  %s!%s %s\n' "$WN" "$R" "$1"; }; bad(){ printf '  %s✗%s %s\n' "$FL" "$R" "$1"; }
    dim(){ printf '  %s%s%s\n' "$DIM" "$1" "$R"; }; have(){ command -v "$1" >/dev/null 2>&1; }
    banner(){ printf '\n  %s NodeTest32 %s  %s%s›_%s %s%s%s\n  %sпроверка ноды · manual32.online%s\n\n' "$GB" "$R" "$BR" "$B" "$R" "$DIM" "${1:-}" "$R" "$DIM" "$R"; }
    pkg_mgr(){ if have apt-get;then echo apt;elif have dnf;then echo dnf;elif have yum;then echo yum;elif have apk;then echo apk;elif have pacman;then echo pacman;fi; }
    fetch_verified(){ echo "модуль недоступен" >&2; return 1; }
    warn "не удалось подключить lib/brand.sh — часть проверок недоступна"
  fi
fi

# ------------------------------------------------------------------ контекст запуска
CTX="ambi"; CTX_IP=""; CTX_OS=""; CTX_VIRT=""
detect_context() {
  CTX_OS="$(uname -s 2>/dev/null)"
  CTX_IP="$(curl -4 -fsS -m 5 https://api.ipify.org 2>/dev/null)"
  local tun; tun="$( (ifconfig 2>/dev/null || ip -o link show 2>/dev/null) | grep -oE '(utun|tun|wg|tap)[0-9]+' | head -1)"
  have systemd-detect-virt && CTX_VIRT="$(systemd-detect-virt 2>/dev/null)"
  if [ "$CTX_OS" = "Darwin" ] || [ -n "$tun" ]; then CTX="client"
  elif [ "$CTX_OS" = "Linux" ] && [ -f /proc/cpuinfo ] && [ "$(id -u 2>/dev/null)" = "0" ]; then CTX="node"
  else CTX="ambi"; fi
}

# ------------------------------------------------------------------ доустановка пакетов-зависимостей
dep_offer() {   # $1=команда $2=пакет — предлагает поставить, возвращает 0 если есть/поставили
  local cmd="$1" pkg="${2:-$1}"
  have "$cmd" && return 0
  local m; m="$(pkg_mgr)"
  if [ -z "$m" ]; then warn "$cmd не найден, пакетный менеджер не определён — поставь вручную"; return 1; fi
  printf '  %s%s не установлен. Поставить (%s)? [y/N]: %s' "$WN" "$cmd" "$pkg" "$R"; read -r a
  case "$a" in y|Y|д|Д) pkg_install "$pkg" >/dev/null 2>&1; have "$cmd" && { ok "$cmd установлен"; return 0; } || { bad "не удалось поставить $cmd"; return 1; };; *) return 1;; esac
}

# ------------------------------------------------------------------ запуск наших под-скриптов
get_sub() {   # $1=имя (node-check.sh) -> путь к копии: рядом > кэш > скачать один раз
  [ -f "$SCRIPT_DIR/$1" ] && { echo "$SCRIPT_DIR/$1"; return; }
  local cache="$NT_HOME/$1"
  [ -f "$cache" ] && { echo "$cache"; return; }
  mkdir -p "$NT_HOME" 2>/dev/null
  if curl -fsSL -m 20 "$NT_REPO_RAW/$1" -o "$cache.tmp" 2>/dev/null && head -1 "$cache.tmp" 2>/dev/null | grep -q '^#!'; then
    mv "$cache.tmp" "$cache" 2>/dev/null && echo "$cache"; return
  fi
  rm -f "$cache.tmp" 2>/dev/null; echo ""
}
run_native() {   # $1=имя скрипта, дальше аргументы
  mkdir -p "$NT_HOME" 2>/dev/null
  local name="$1"; shift; local p; p="$(get_sub "$name")"
  [ -z "$p" ] && { bad "не удалось получить $name"; return 1; }
  bash "$p" "$@"
}

# ------------------------------------------------------------------ запуск модуля-проверки (с проверкой целостности)
run_ext() {   # $1=модуль $2=заголовок $3=подпись; далее — аргументы модулю
  local tool="$1" title="$2" sub="$3"; shift 3
  hd "$title" "$sub"
  if [ -n "$NO_EXTERNAL" ]; then warn "в базовом режиме недоступно (запусти без --basic)"; return; fi
  local f; f="$(fetch_verified "$tool")" || { bad "модуль недоступен, пропускаю"; return 1; }
  bash "$f" "$@"
}

# ------------------------------------------------------------------ пункты меню
ask_link() { printf '  %sвставь vless://-ссылку тест-юзера (Enter — пропустить): %s' "$B" "$R"; read -r NT_LINK; }
ask_ip()   { printf '  %sIP ноды [порт] (напр. 1.2.3.4 443): %s' "$B" "$R"; read -r NT_IP NT_PORT; }

m_check_full() { ask_link; [ -z "$NT_LINK" ] && { dim "ссылка не введена"; return; }; run_native node-check.sh "$NT_LINK"; }
m_check_ip()   { ask_ip;   [ -z "$NT_IP" ]   && { dim "IP не введён"; return; };       run_native node-check.sh "$NT_IP" ${NT_PORT:+$NT_PORT}; }
m_inside()     { run_native node-inside.sh; }
m_iperf_ru()   { hd "Скорость до РФ" "iperf3 до серверов внутри России"; [ -n "$NO_EXTERNAL" ] && { warn "в базовом режиме недоступно"; return; }; dep_offer iperf3 iperf3 || return; local f; f="$(fetch_verified iperf3ru)" || { bad "модуль недоступен"; return; }; bash "$f"; }
m_dpi()        { run_ext censorcheck "ТСПУ / DPI" "палится ли нода на российском DPI" --mode dpi; }
m_geoblock()   { run_ext censorcheck "Геоблок" "что режется с этого адреса" --mode geoblock; }
m_ipquality()  { run_ext ipquality "Репутация IP" "блок-листы и чистота адреса"; }
m_ipregion()   { run_ext ipregion "Регион по сервисам" "какую страну видят Spotify/Netflix/CDN"; }
m_yabs()       { run_ext yabs "Железо: CPU / диск / сеть" "полный бенчмарк сервера" -4; }
m_sysbench()   { hd "Быстрый тест CPU" "один поток"; dep_offer sysbench sysbench || return; sysbench cpu run --threads=1 2>/dev/null | grep -E 'events per second|total time' | sed 's/^/  /'; }
m_bench()      { hd "Сводка сервера" "параметры + скорость"; dim "секция скорости за рубеж из РФ часто не отрабатывает — параметры сервера покажет в любом случае"; [ -n "$NO_EXTERNAL" ] && { warn "в базовом режиме недоступно"; return; }; local f; f="$(fetch_verified bench)" || { bad "модуль недоступен"; return; }; bash "$f"; }

pause() { printf '\n  %sEnter — назад в меню...%s' "$DIM" "$R"; read -r _; }

# ------------------------------------------------------------------ общая проверка — все тесты подряд
run_all() {
  hd "Общая проверка" "все тесты подряд для текущего режима · Enter запустить, s пропустить"
  local items
  if [ "$CTX" = "client" ]; then items="m_check_full"
  else items="m_inside m_iperf_ru m_dpi m_geoblock m_ipquality m_ipregion m_yabs m_sysbench m_bench"; fi
  local fn
  for fn in $items; do
    printf '\n  %sследующий тест — Enter запустить · s пропустить · q выход: %s' "$B" "$R"; read -r a || return
    case "$a" in s|S) dim "пропущено"; continue;; q|Q) return;; esac
    "$fn"
  done
  ok "общая проверка завершена"
}

# ------------------------------------------------------------------ подготовка: подтянуть всё один раз
setup_tools() {
  local ready="$NT_HOME/tools" xr="$NT_HOME/xray/xray"
  local have_tools=0; [ -d "$ready" ] && [ -n "$(ls -A "$ready" 2>/dev/null)" ] && have_tools=1
  local have_xray=0; [ -x "$xr" ] && have_xray=1
  local want_xray=0; { [ "$CTX" = "client" ] || [ "$CTX" = "ambi" ]; } && want_xray=1
  [ -n "$NO_EXTERNAL" ] && have_tools=1   # в базовом режиме модули не нужны
  if [ "$have_tools" = 1 ] && { [ "$want_xray" = 0 ] || [ "$have_xray" = 1 ]; }; then return; fi
  hd "Подготовка" "качаю всё нужное один раз, дальше запуск моментальный"
  mkdir -p "$NT_HOME" 2>/dev/null
  get_sub node-check.sh >/dev/null 2>&1; get_sub node-inside.sh >/dev/null 2>&1; ok "тесты готовы"
  if [ -z "$NO_EXTERNAL" ] && [ "$have_tools" = 0 ]; then
    local t
    for t in ipregion censorcheck iperf3ru yabs ipquality bench; do
      fetch_verified "$t" >/dev/null 2>&1 || dim "модуль $t подтянется при запуске"
    done
    ok "модули проверок готовы"
  fi
  if [ "$want_xray" = 1 ] && [ "$have_xray" = 0 ]; then
    run_native node-check.sh --prefetch >/dev/null 2>&1 && ok "xray-ядро готово" || dim "xray подтянется при сквозной проверке"
  fi
}

# ------------------------------------------------------------------ меню
row() {   # $1=номер $2=название $3=подпись — выравнивание по числу символов (UTF-8), а не байтов
  local pad=$(( 30 - ${#2} )); [ "$pad" -lt 1 ] && pad=1
  printf '  %s%2s%s  %s%*s%s%s%s\n' "$OKC" "$1" "$R" "$2" "$pad" "" "$DIM" "$3" "$R"
}
show_menu() {
  banner "menu $VERSION"
  local mode; case "$CTX" in client) mode="КЛИЕНТ";; node) mode="НОДА";; *) mode="?";; esac
  dim "точка: ${CTX_IP:-?} · ${CTX_OS:-?}${CTX_VIRT:+/$CTX_VIRT} · режим: $mode"
  [ "$CTX" = "client" ] && local mk="$OKC" nk="$DIM" || { local mk="$DIM" nk="$OKC"; }
  printf '\n %s%sСНАРУЖИ%s %s— с чистого компа или соседнего VPS, НЕ с ноды%s\n' "$mk" "$B" "$R" "$DIM" "$R"
  row 1 "Сквозная проверка по ссылке"      "идёт ли трафик реально"
  row 2 "Быстрый чек по IP"                "порт, канал, маскировка, IP"
  printf '\n %s%sИЗНУТРИ%s %s— на самой ноде (root по SSH)%s\n' "$nk" "$B" "$R" "$DIM" "$R"
  row 3  "Аудит сервера"                   "железо, стил, канал, IP"
  row 4  "Скорость до РФ"                   "до серверов внутри России"
  row 5  "ТСПУ / DPI"                       "палится ли нода"
  row 6  "Геоблок"                          "что режется с ноды"
  row 7  "Репутация IP"                     "блок-листы, чистота"
  row 8  "Регион по сервисам"               "какую страну видят"
  row 9  "Железо: CPU / диск / сеть"        "полный бенчмарк"
  row 10 "Быстрый тест CPU"                 "один поток"
  row 11 "Сводка сервера"                   "параметры + скорость"
  printf '\n  %sa%s  Общая проверка — все тесты подряд\n' "$B" "$R"
  printf '  %si%s  Установить командой nodetest32     %sq%s  Выход\n\n' "$B" "$R" "$B" "$R"
  printf '  %sвыбор: %s' "$B" "$R"
}

menu_loop() {
  while true; do
    show_menu; read -r c || { printf '\n  %sввод закончился — выход%s\n' "$DIM" "$R"; exit 0; }
    case "$c" in
      1) m_check_full; pause;; 2) m_check_ip; pause;; 3) m_inside; pause;;
      4) m_iperf_ru; pause;; 5) m_dpi; pause;; 6) m_geoblock; pause;;
      7) m_ipquality; pause;; 8) m_ipregion; pause;; 9) m_yabs; pause;;
      10) m_sysbench; pause;; 11) m_bench; pause;;
      a|A) run_all; pause;;
      i|I) do_install; pause;;
      q|Q|0) printf '  %sдо связи%s\n' "$DIM" "$R"; exit 0;;
      *) warn "нет такого пункта";;
    esac
  done
}

# ------------------------------------------------------------------ установка командой
do_install() {
  hd "Установка командой nodetest32" "в /usr/local/bin"
  local dst="/usr/local/bin/nodetest32" tmp; tmp="$(mktemp 2>/dev/null || echo /tmp/nti.$$)"
  if ! curl -fsSL -m 20 "$NT_REPO_RAW/nodetest32.sh" -o "$tmp" 2>/dev/null; then bad "не скачался скрипт"; rm -f "$tmp"; return 1; fi
  head -1 "$tmp" | grep -q '^#!' || { bad "скачалось не то (кэш CDN) — повтори позже"; rm -f "$tmp"; return 1; }
  if [ -w "$(dirname "$dst")" ] || [ "$(id -u)" = 0 ]; then mv "$tmp" "$dst" && chmod +x "$dst" && ok "готово: запускай командой ${B}nodetest32${R}"
  else warn "нет прав на $dst — запусти под root или: sudo mv $tmp $dst && sudo chmod +x $dst"; fi
}

# ------------------------------------------------------------------ main
for arg in "$@"; do
  case "$arg" in
    --install) detect_context; do_install; exit 0;;
    --basic|--no-external) NO_EXTERNAL=1;;
    -h|--help) banner "menu $VERSION"; dim "меню: ./nodetest32.sh · установка: --install · базовый режим: --basic"; exit 0;;
  esac
done

detect_context
setup_tools
menu_loop
