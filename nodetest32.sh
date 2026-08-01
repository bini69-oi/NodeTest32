#!/usr/bin/env bash
# NodeTest32 — интерактивное меню проверки ноды VPN. Наши глубокие тесты (сквозной
# туннель, аудит сервера) + популярные внешние (скорость до РФ, DPI, репутация IP,
# железо) — обёрнуты с проверкой sha256, не вслепую. Ничего на сервере не меняет.
#
#   меню:     bash <(curl -sL https://raw.githubusercontent.com/bini69-oi/NodeTest32/main/nodetest32.sh)
#   команда:  bash <(...nodetest32.sh) --install   →   потом просто `nodetest32`
#   офлайн:   ./nodetest32.sh --no-external   (только наши тесты, без чужого кода)
#
# Manual32 · manual32.online

VERSION="2.0.0"
NT_REPO_RAW="${NT_REPO_RAW:-https://raw.githubusercontent.com/bini69-oi/NodeTest32/main}"
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
    fetch_verified(){ echo "внешние недоступны (нет lib/brand.sh)" >&2; return 1; }
    warn "работаю без lib/brand.sh — внешние тесты недоступны"
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

# ------------------------------------------------------------------ доустановка зависимостей
dep_offer() {   # $1=команда $2=пакет — предлагает поставить, возвращает 0 если есть/поставили
  local cmd="$1" pkg="${2:-$1}"
  have "$cmd" && return 0
  local m; m="$(pkg_mgr)"
  if [ -z "$m" ]; then warn "$cmd не найден, пакетный менеджер не определён — поставь вручную"; return 1; fi
  printf '  %s%s не установлен. Поставить (%s)? [y/N]: %s' "$WN" "$cmd" "$pkg" "$R"; read -r a
  case "$a" in y|Y|д|Д) pkg_install "$pkg" >/dev/null 2>&1; have "$cmd" && { ok "$cmd установлен"; return 0; } || { bad "не удалось поставить $cmd"; return 1; };; *) return 1;; esac
}

# ------------------------------------------------------------------ запуск наших под-скриптов
get_sub() {   # $1=имя (node-check.sh) -> путь к запускаемой копии (локально или с пина)
  if [ -f "$SCRIPT_DIR/$1" ]; then echo "$SCRIPT_DIR/$1"; return; fi
  local tmp; tmp="$(mktemp 2>/dev/null || echo /tmp/nt32sub.$$)"
  if curl -fsSL -m 20 "$NT_REPO_RAW/$1" -o "$tmp" 2>/dev/null && head -1 "$tmp" 2>/dev/null | grep -q '^#!'; then echo "$tmp"; else rm -f "$tmp"; echo ""; fi
}
run_native() {   # $1=имя скрипта, дальше аргументы
  local name="$1"; shift; local p; p="$(get_sub "$name")"
  [ -z "$p" ] && { bad "не нашёл $name (ни локально, ни на $NT_REPO_RAW)"; return 1; }
  bash "$p" "$@"
}

# ------------------------------------------------------------------ запуск внешних (обёртка с проверкой)
run_ext() {   # $1=tool $2=человекочитаемое имя, дальше аргументы внешнему скрипту
  local tool="$1" title="$2"; shift 2
  hd "$title" "внешний инструмент, проверяю по sha256"
  if [ -n "$NO_EXTERNAL" ]; then warn "внешние выключены флагом --no-external"; return; fi
  local f; f="$(fetch_verified "$tool")" || { bad "проверка не прошла — тест пропущен"; return 1; }
  bash "$f" "$@"; local rc=$?
  rm -f "$f" 2>/dev/null
  return $rc
}

# ------------------------------------------------------------------ пункты меню
ask_link() { printf '  %sвставь vless://-ссылку тест-юзера (Enter — пропустить): %s' "$B" "$R"; read -r NT_LINK; }
ask_ip()   { printf '  %sIP ноды [порт] (напр. 1.2.3.4 443): %s' "$B" "$R"; read -r NT_IP NT_PORT; }

m_check_full() { ask_link; [ -z "$NT_LINK" ] && { dim "ссылка не введена"; return; }; run_native node-check.sh "$NT_LINK"; }
m_check_ip()   { ask_ip;   [ -z "$NT_IP" ]   && { dim "IP не введён"; return; };       run_native node-check.sh "$NT_IP" ${NT_PORT:+$NT_PORT}; }
m_inside()     { run_native node-inside.sh; }
m_iperf_ru()   { hd "Скорость до РФ (iperf3)" "внешний: itdoginfo, проверяю по sha256"; [ -n "$NO_EXTERNAL" ] && { warn "выключено --no-external"; return; }; dep_offer iperf3 iperf3 || return; local f; f="$(fetch_verified iperf3ru)" || { bad "проверка не прошла"; return; }; bash "$f"; rm -f "$f"; }
m_dpi()        { run_ext censorcheck "ТСПУ / DPI" --mode dpi; }
m_geoblock()   { run_ext censorcheck "Геоблок" --mode geoblock; }
m_ipquality()  { run_ext ipquality "Репутация / чистота IP (глубоко)"; }
m_ipregion()   { run_ext ipregion "Регион по сервисам"; }
m_yabs()       { run_ext yabs "Железо: CPU / диск / сеть" -4; }
m_sysbench()   { hd "sysbench CPU" "нативно, 1 поток"; dep_offer sysbench sysbench || return; sysbench cpu run --threads=1 2>/dev/null | grep -E 'events per second|total time' | sed 's/^/  /'; }

pause() { printf '\n  %sEnter — назад в меню...%s' "$DIM" "$R"; read -r _; }

# ------------------------------------------------------------------ прогнать всё для режима
run_all() {
  hd "Прогнать всё для режима: $CTX" "Enter — запустить пункт, s — пропустить"
  local items
  if [ "$CTX" = "client" ]; then items="m_check_full"
  else items="m_inside m_iperf_ru m_dpi m_geoblock m_ipquality m_ipregion m_yabs m_sysbench"; fi
  local fn
  for fn in $items; do
    printf '\n  %s%s — Enter запустить · s пропустить · q выход: %s' "$B" "$fn" "$R"; read -r a || return
    case "$a" in s|S) dim "пропущено"; continue;; q|Q) return;; esac
    "$fn"
  done
  ok "прогон завершён"
}

# ------------------------------------------------------------------ меню
xlabel() { [ -n "$NO_EXTERNAL" ] && printf '%s(выключено)%s' "$DIM" "$R" || printf '%sобёртка%s' "$DIM" "$R"; }
show_menu() {
  banner "menu $VERSION"
  local mode; case "$CTX" in client) mode="КЛИЕНТ";; node) mode="НОДА";; *) mode="?";; esac
  dim "точка: ${CTX_IP:-?} · ${CTX_OS:-?}${CTX_VIRT:+/$CTX_VIRT} · режим: $mode"
  [ "$CTX" = "client" ] && local mk="$OKC" nk="$DIM" || { local mk="$DIM" nk="$OKC"; }
  printf '\n %s%sСНАРУЖИ%s %s— с чистого компа/соседнего VPS, НЕ с ноды%s\n' "$mk" "$B" "$R" "$DIM" "$R"
  printf '   %s1%s  Сквозная проверка по ссылке      %sнаш e2e%s\n' "$OKC" "$R" "$DIM" "$R"
  printf '   %s2%s  Быстро: хост/канал/маскировка/IP %sнаш%s\n' "$OKC" "$R" "$DIM" "$R"
  printf '\n %s%sИЗНУТРИ%s %s— на самой ноде (root по SSH)%s\n' "$nk" "$B" "$R" "$DIM" "$R"
  printf '   %s3%s  Аудит сервера                    %sнаш%s\n' "$OKC" "$R" "$DIM" "$R"
  printf '   %s4%s  Скорость до РФ (iperf3)          %s\n' "$OKC" "$R" "$(xlabel)"
  printf '   %s5%s  ТСПУ / DPI                       %s\n' "$OKC" "$R" "$(xlabel)"
  printf '   %s6%s  Геоблок                          %s\n' "$OKC" "$R" "$(xlabel)"
  printf '   %s7%s  Репутация / чистота IP (глубоко) %s\n' "$OKC" "$R" "$(xlabel)"
  printf '   %s8%s  Регион по сервисам               %s\n' "$OKC" "$R" "$(xlabel)"
  printf '   %s9%s  Железо: CPU / диск / сеть        %s\n' "$OKC" "$R" "$(xlabel)"
  printf '  %s10%s  sysbench CPU                     %sнативно%s\n' "$OKC" "$R" "$DIM" "$R"
  printf '\n  %sa%s  прогнать всё для режима   %si%s  установить командой   %sq%s  выход\n\n' "$B" "$R" "$B" "$R" "$B" "$R"
  printf '  %sвыбор: %s' "$B" "$R"
}

menu_loop() {
  while true; do
    show_menu; read -r c || { printf '\n  %sввод закончился — выход%s\n' "$DIM" "$R"; exit 0; }
    case "$c" in
      1) m_check_full; pause;; 2) m_check_ip; pause;; 3) m_inside; pause;;
      4) m_iperf_ru; pause;; 5) m_dpi; pause;; 6) m_geoblock; pause;;
      7) m_ipquality; pause;; 8) m_ipregion; pause;; 9) m_yabs; pause;;
      10) m_sysbench; pause;;
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
  head -1 "$tmp" | grep -q '^#!' || { bad "скачалось не то (CDN-кэш) — повтори позже"; rm -f "$tmp"; return 1; }
  if [ -w "$(dirname "$dst")" ] || [ "$(id -u)" = 0 ]; then mv "$tmp" "$dst" && chmod +x "$dst" && ok "готово: запускай командой ${B}nodetest32${R}"
  else warn "нет прав на $dst — запусти под root или: sudo mv $tmp $dst && sudo chmod +x $dst"; fi
}

# ------------------------------------------------------------------ main
for arg in "$@"; do
  case "$arg" in
    --install) detect_context; do_install; exit 0;;
    --no-external) NO_EXTERNAL=1;;
    -h|--help) banner "menu $VERSION"; dim "меню: ./nodetest32.sh · установка: --install · офлайн: --no-external"; exit 0;;
  esac
done

detect_context
menu_loop
