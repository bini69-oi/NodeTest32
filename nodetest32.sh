#!/usr/bin/env bash
# NodeTest32 — меню проверки ноды VPN от Manual32. Проверенные инструменты в одном месте.
# Запускать на самой ноде. При первом запуске всё подтягивается один раз, дальше из кэша.
#
#   меню:     bash <(curl -sL https://raw.githubusercontent.com/bini69-oi/NodeTest32/main/nodetest32.sh)
#   команда:  bash <(...nodetest32.sh) --install   →   потом просто `nodetest32`
#
# Manual32 · manual32.online

VERSION="3.0.0"
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

# ------------------------------------------------------------------ пункты
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
  for fn in m_audit m_iperf m_dpi m_geoblock m_ipq m_region m_yabs m_cpu m_bench; do
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
    local p; for p in iperf3 sysbench wget; do have "$p" || pkg_install "$p" >/dev/null 2>&1; done
    ok "пакеты (iperf3, sysbench)"
  else
    dim "пакетный менеджер не найден — iperf3/sysbench поставь вручную"
  fi
  # наши тесты и модули проверок
  get_sub node-inside.sh >/dev/null 2>&1
  local t; for t in ipregion censorcheck iperf3ru yabs ipquality bench; do fetch_verified "$t" >/dev/null 2>&1; done
  ok "инструменты"
  touch "$done_flag" 2>/dev/null
}

# ------------------------------------------------------------------ меню
row() { printf '   %s %2s %s  %s\n' "$GB" "$1" "$R" "$2"; }
show_menu() {
  banner "menu $VERSION"
  dim "нажми номер теста и Enter"
  printf '\n'
  row 1 "Аудит сервера"
  row 2 "Скорость до РФ"
  row 3 "DPI / ТСПУ"
  row 4 "Геоблокировки"
  row 5 "Репутация IP"
  row 6 "Регион по IP"
  row 7 "Железо: CPU / диск / сеть"
  row 8 "Тест CPU"
  row 9 "Сводка сервера"
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
      1) m_audit; pause;; 2) m_iperf; pause;; 3) m_dpi; pause;;
      4) m_geoblock; pause;; 5) m_ipq; pause;; 6) m_region; pause;;
      7) m_yabs; pause;; 8) m_cpu; pause;; 9) m_bench; pause;;
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
