#!/usr/bin/env bash
# NodeTest32 — меню проверки ноды VPN от Manual32. Проверенные инструменты в одном месте.
# Запускать на самой ноде. При первом запуске всё подтягивается один раз, дальше из кэша.
#
#   меню:     bash <(curl -sL https://raw.githubusercontent.com/bini69-oi/NodeTest32/main/nodetest32.sh)
#   команда:  bash <(...nodetest32.sh) --install   →   потом просто `nodetest32`
#
# Manual32 · manual32.online

VERSION="3.1.0"
NT_REPO_RAW="${NT_REPO_RAW:-https://raw.githubusercontent.com/bini69-oi/NodeTest32/main}"
NT_HOME="${NODETEST32_HOME:-$HOME/.nodetest32}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null)"
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="."

# ------------------------------------------------------------------ бренд-кит
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
    banner(){ printf '\n  %s NodeTest32 %s  %s%s›_%s %s%s%s\n\n' "$GB" "$R" "$BR" "$B" "$R" "$DIM" "${1:-}" "$R"; }
    pkg_mgr(){ if have apt-get;then echo apt;elif have dnf;then echo dnf;elif have yum;then echo yum;elif have apk;then echo apk;elif have pacman;then echo pacman;fi; }
    fetch_verified(){ echo x >&2; return 1; }
    warn "не удалось подключить lib/brand.sh"
  fi
fi

# ------------------------------------------------------------------ запуск
get_sub() {   # node-inside.sh: рядом > кэш > скачать один раз
  [ -f "$SCRIPT_DIR/$1" ] && { echo "$SCRIPT_DIR/$1"; return; }
  local cache="$NT_HOME/$1"
  [ -f "$cache" ] && { echo "$cache"; return; }
  mkdir -p "$NT_HOME" 2>/dev/null
  if curl -fsSL -m 20 "$NT_REPO_RAW/$1" -o "$cache.tmp" 2>/dev/null && head -1 "$cache.tmp" 2>/dev/null | grep -q '^#!'; then
    mv "$cache.tmp" "$cache" 2>/dev/null && echo "$cache"; return
  fi
  rm -f "$cache.tmp" 2>/dev/null; echo ""
}
run_tool() {   # $1=модуль $2=заголовок; далее — аргументы
  local tool="$1" title="$2"; shift 2
  hd "$title" ""
  local f; f="$(fetch_verified "$tool")" || { bad "инструмент недоступен, пропускаю"; return 1; }
  bash "$f" "$@"
}

# ------------------------------------------------------------------ xray-knife (сквозная проверка по ссылке)
KNIFE_VER="v10.1.1"; KNIFE=""
knife_asset() {   # печатает "asset sha256" под платформу
  local s m; s="$(uname -s)"; m="$(uname -m)"
  case "$s" in
    Linux)  case "$m" in aarch64|arm64) echo "linux-arm64-v8a ff3343c57ea2bcfb8e72cbf41a8b3c17ce1c049d9cd0a951c073ae864d23aa68";; *) echo "linux-64 39696103eb99b4cb55ae5d2c2456210d826f4bbcf0f89e298a05fb5fb82f09e5";; esac;;
    Darwin) case "$m" in arm64|aarch64) echo "macos-arm64-v8a ce76e2112a464b336be78ef37dde85d3eac2a082528b36a14cb11ab8fa038600";; *) echo "macos-64 5456543c3da4239ca5ca0e6a14ef91c04a535bc02ce53e72dc8884af4888bce4";; esac;;
    *) echo "";;
  esac
}
ensure_knife() {
  local bin="$NT_HOME/knife/xray-knife"
  [ -x "$bin" ] && { KNIFE="$bin"; return 0; }
  local a asset want; a="$(knife_asset)"; [ -z "$a" ] && return 1
  asset="${a%% *}"; want="${a##* }"
  have unzip || { warn "нужен unzip: apt install unzip"; return 1; }
  mkdir -p "$NT_HOME/knife" 2>/dev/null
  local zip="$NT_HOME/knife/k.zip"
  curl -fsSL -m 180 "https://github.com/lilendian0x00/xray-knife/releases/download/$KNIFE_VER/Xray-knife-$asset.zip" -o "$zip" 2>/dev/null || { rm -f "$zip"; return 1; }
  [ "$(sha256_of "$zip")" != "$want" ] && { rm -f "$zip"; return 1; }
  unzip -o "$zip" xray-knife -d "$NT_HOME/knife" >/dev/null 2>&1; rm -f "$zip"
  [ -f "$bin" ] && chmod +x "$bin" 2>/dev/null
  [ -x "$bin" ] && { KNIFE="$bin"; return 0; }; return 1
}

# ------------------------------------------------------------------ пункты
m_e2e()      {
  hd "Сквозная проверка по ссылке" ""
  dim "запускай с чистой машины или другого сервера — не с самой ноды"
  ensure_knife || { bad "не удалось подготовить проверку"; return; }
  printf '  %sвставь vless://-ссылку тест-юзера и Enter: %s' "$B" "$R"; read -r link
  [ -z "$link" ] && { dim "ссылка не введена"; return; }
  "$KNIFE" http -c "$link" -p --check-preset global
}
m_audit()    { hd "Аудит сервера" ""; local p; p="$(get_sub node-inside.sh)"; [ -z "$p" ] && { bad "недоступно"; return; }; bash "$p"; }
m_iperf()    { hd "Скорость до РФ" ""; have iperf3 || { bad "нет iperf3 (не удалось поставить при подготовке)"; return; }; local f; f="$(fetch_verified iperf3ru)" || { bad "недоступно"; return; }; bash "$f"; }
m_dpi()      { run_tool censorcheck "DPI / ТСПУ" --mode dpi; }
m_geoblock() { run_tool censorcheck "Геоблокировки" --mode geoblock; }
m_ipq()      { run_tool ipquality "Репутация IP"; }
m_region()   { run_tool ipregion "Регион по IP"; }
m_yabs()     { run_tool yabs "Железо: CPU / диск / сеть" -4; }
m_cpu()      { hd "Тест CPU" ""; have sysbench || { bad "нет sysbench (не удалось поставить при подготовке)"; return; }; sysbench cpu run --threads=1 2>/dev/null | grep -E 'events per second|total time' | sed 's/^/  /'; }
m_bench()    { hd "Сводка сервера" ""; local f; f="$(fetch_verified bench)" || { bad "недоступно"; return; }; bash "$f"; }

pause() { printf '\n  %sEnter — назад в меню%s' "$DIM" "$R"; read -r _; }

run_all() {
  hd "Общая проверка" "все тесты подряд · Enter запустить, s пропустить"
  local fn
  for fn in m_e2e m_audit m_iperf m_dpi m_geoblock m_ipq m_region m_yabs m_cpu m_bench; do
    printf '\n  %sследующий — Enter запустить · s пропустить · q выход: %s' "$B" "$R"; read -r a || return
    case "$a" in s|S) dim "пропущено"; continue;; q|Q) return;; esac
    "$fn"
  done
  ok "готово"
}

# ------------------------------------------------------------------ подготовка (один раз)
setup_tools() {
  local done_flag="$NT_HOME/.ready"
  [ -f "$done_flag" ] && { get_sub node-inside.sh >/dev/null 2>&1; return; }
  hd "Подготовка" "ставлю всё нужное один раз, дальше запуск моментальный"
  mkdir -p "$NT_HOME" 2>/dev/null
  # пакеты, которые нужны тестам — ставим сразу, без вопросов
  local pm; pm="$(pkg_mgr)"
  if [ -n "$pm" ]; then
    local p; for p in iperf3 sysbench wget unzip; do have "$p" || pkg_install "$p" >/dev/null 2>&1; done
    ok "пакеты (iperf3, sysbench, unzip)"
  else
    dim "пакетный менеджер не найден — iperf3/sysbench поставь вручную"
  fi
  # наши тесты и модули проверок
  get_sub node-inside.sh >/dev/null 2>&1
  local t; for t in ipregion censorcheck iperf3ru yabs ipquality bench; do fetch_verified "$t" >/dev/null 2>&1; done
  ensure_knife >/dev/null 2>&1
  ok "инструменты"
  touch "$done_flag" 2>/dev/null
}

# ------------------------------------------------------------------ меню
row() { printf '   %s %2s %s  %s\n' "$GB" "$1" "$R" "$2"; }
show_menu() {
  banner "menu $VERSION"
  dim "нажми номер теста и Enter"
  printf '\n'
  row 1 "Сквозная проверка по ссылке"
  row 2 "Аудит сервера"
  row 3 "Скорость до РФ"
  row 4 "DPI / ТСПУ"
  row 5 "Геоблокировки"
  row 6 "Репутация IP"
  row 7 "Регион по IP"
  row 8 "Железо: CPU / диск / сеть"
  row 9 "Тест CPU"
  row 10 "Сводка сервера"
  printf '\n'
  row a "Общая проверка — все тесты"
  row i "Установить командой nodetest32"
  row q "Выход"
  printf '\n  %sномер и Enter →%s ' "$B" "$R"
}

menu_loop() {
  while true; do
    show_menu; read -r c || { printf '\n'; exit 0; }
    case "$c" in
      1) m_e2e; pause;; 2) m_audit; pause;; 3) m_iperf; pause;;
      4) m_dpi; pause;; 5) m_geoblock; pause;; 6) m_ipq; pause;;
      7) m_region; pause;; 8) m_yabs; pause;; 9) m_cpu; pause;;
      10) m_bench; pause;;
      a|A) run_all; pause;;
      i|I) do_install; pause;;
      q|Q|0) exit 0;;
      *) warn "нет такого пункта";;
    esac
  done
}

# ------------------------------------------------------------------ установка командой
do_install() {
  hd "Установка командой nodetest32" ""
  local dst="/usr/local/bin/nodetest32" tmp; tmp="$(mktemp 2>/dev/null || echo /tmp/nti.$$)"
  if ! curl -fsSL -m 20 "$NT_REPO_RAW/nodetest32.sh" -o "$tmp" 2>/dev/null; then bad "не скачался"; rm -f "$tmp"; return 1; fi
  head -1 "$tmp" | grep -q '^#!' || { bad "повтори позже (кэш CDN)"; rm -f "$tmp"; return 1; }
  if [ -w "$(dirname "$dst")" ] || [ "$(id -u)" = 0 ]; then mv "$tmp" "$dst" && chmod +x "$dst" && ok "готово: запускай командой ${B}nodetest32${R}"
  else warn "нужен root: sudo mv $tmp $dst && sudo chmod +x $dst"; fi
}

# ------------------------------------------------------------------ main
case "${1:-}" in
  --install) do_install; exit 0;;
  -h|--help) banner "menu $VERSION"; dim "меню: ./nodetest32.sh · установка: --install"; exit 0;;
esac

setup_tools
menu_loop
