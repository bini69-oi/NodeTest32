#!/usr/bin/env bash
# NodeTest32 · бренд-кит — общие цвета, вывод, сводка, загрузка модулей с проверкой целостности.
# Подключается через `source lib/brand.sh`. Если его нет рядом (одиночный скрипт из
# curl), каждый скрипт держит inline-fallback тех же функций.
# Manual32 · manual32.online

# ------------------------------------------------------------------ оформление
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BR=$'\033[38;5;29m'; OKC=$'\033[38;5;35m'; WN=$'\033[38;5;172m'; FL=$'\033[38;5;167m'
  DIM=$'\033[2m'; B=$'\033[1m'; R=$'\033[0m'; GB=$'\033[48;5;29m\033[38;5;231m'
else
  BR=''; OKC=''; WN=''; FL=''; DIM=''; B=''; R=''; GB=''
fi

# ------------------------------------------------------------------ сводка
# SUMFILE копит строки "статус<TAB>имя<TAB>значение<TAB>подсказка", WORST = худший.
SUMFILE="${SUMFILE:-$(mktemp 2>/dev/null || echo /tmp/nt32.$$)}"; : > "$SUMFILE" 2>/dev/null
WORST="${WORST:-0}"   # 0 ok · 1 warn · 2 fail
sev()  { case "$1" in OK) echo 0;; WARN) echo 1;; FAIL) echo 2;; *) echo 0;; esac; }
mark() { local s; s=$(sev "$1"); [ "$s" -gt "$WORST" ] && WORST=$s; printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$SUMFILE"; }

# ------------------------------------------------------------------ вывод
hd()   { printf '\n%s\n' "${BR}${B}▸ $1${R}${DIM} — $2${R}"; }
ok()   { printf '  %s✓%s %s\n' "$OKC" "$R" "$1"; }
warn() { printf '  %s!%s %s\n' "$WN" "$R" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$FL" "$R" "$1"; }
dim()  { printf '  %s%s%s\n' "$DIM" "$1" "$R"; }
die()  { printf '\n  %s✗ %s%s\n\n' "$FL" "$1" "$R"; [ "$(type -t cleanup)" = function ] && cleanup; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

banner() {   # $1 = подзаголовок (напр. "node-check 1.0.0")
  printf '\n'
  printf '%s\n'   "  ${GB} NodeTest32 ${R}  ${BR}${B}›_${R} ${DIM}${1:-}${R}"
  printf '%s\n\n' "  ${DIM}проверка ноды · manual32.online${R}"
}

# ------------------------------------------------------------------ пакеты
pkg_mgr() {
  if   have apt-get; then echo apt
  elif have dnf;     then echo dnf
  elif have yum;     then echo yum
  elif have apk;     then echo apk
  elif have pacman;  then echo pacman
  else echo ""; fi
}
# установить пакет (с подтверждением зовущей стороны); тихо возвращает 1 если не смог
pkg_install() {
  local p="$1" m; m="$(pkg_mgr)"
  case "$m" in
    apt)    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" >/dev/null 2>&1;;
    dnf)    dnf install -y -q "$p" >/dev/null 2>&1;;
    yum)    yum install -y -q "$p" >/dev/null 2>&1;;
    apk)    apk add --quiet "$p" >/dev/null 2>&1;;
    pacman) pacman -S --noconfirm --quiet "$p" >/dev/null 2>&1;;
    *) return 1;;
  esac
}

# ------------------------------------------------------------------ sha256
sha256_of() {   # печатает hex-дайджест файла $1 или пусто
  if   have sha256sum;   then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif have shasum;      then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif have openssl;     then openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
  else echo ""; fi
}

# ------------------------------------------------------------------ загрузка модулей (пин + проверка целостности)
# Манифест: строки "<tool> <url> <ref> <sha256>". Ищем рядом (ext/manifest) или тянем с пина.
NT_REPO_RAW="${NT_REPO_RAW:-https://raw.githubusercontent.com/bini69-oi/NodeTest32/main}"
manifest_path() {
  local here; here="$(dirname "${BASH_SOURCE[0]:-$0}")"
  if [ -f "$here/../ext/manifest" ]; then echo "$here/../ext/manifest"
  elif [ -f "./ext/manifest" ]; then echo "./ext/manifest"
  else echo ""; fi
}
manifest_line() {   # $1=tool -> "url ref sha256" из локального манифеста или с пина
  local mp; mp="$(manifest_path)"
  if [ -n "$mp" ]; then
    awk -v t="$1" '$1==t{print $2, $3, $4; exit}' "$mp"
  else
    curl -fsSL -m 10 "$NT_REPO_RAW/ext/manifest" 2>/dev/null | awk -v t="$1" '$1==t{print $2, $3, $4; exit}'
  fi
}

# кэш подтянутых модулей — качаем один раз, дальше моментально
NT_CACHE="${NODETEST32_HOME:-$HOME/.nodetest32}/tools"

# fetch_verified <tool> — вернуть путь к готовому проверенному модулю (из кэша или скачать).
# Скачивание с пина + сверка целостности sha256; путь в stdout, тихо при успехе. Код !=0 = отказ.
fetch_verified() {
  local tool="$1" line url want cache tmp got
  cache="$NT_CACHE/$tool.sh"
  line="$(manifest_line "$tool")"
  if [ -z "$line" ]; then echo "нет данных для модуля «$tool»" >&2; return 1; fi
  url="$(echo "$line" | awk '{print $1}')"; want="$(echo "$line" | awk '{print $3}')"
  # уже в кэше и цел — сразу отдаём
  if [ -f "$cache" ] && [ -n "$want" ] && [ "$want" != "-" ]; then
    got="$(sha256_of "$cache")"; [ "$got" = "$want" ] && { echo "$cache"; return 0; }
  fi
  mkdir -p "$NT_CACHE" 2>/dev/null
  tmp="$(mktemp 2>/dev/null || echo /tmp/nt32m.$$)"
  if ! curl -fsSL -m 30 "$url" -o "$tmp" 2>/dev/null; then echo "не загрузился модуль «$tool»" >&2; rm -f "$tmp"; return 1; fi
  if [ -n "$want" ] && [ "$want" != "-" ]; then
    got="$(sha256_of "$tmp")"
    if [ -z "$got" ]; then echo "нечем проверить целостность (нет sha256sum/shasum/openssl)" >&2; rm -f "$tmp"; return 1; fi
    if [ "$got" != "$want" ]; then echo "проверка целостности модуля «$tool» не прошла — пропускаю" >&2; rm -f "$tmp"; return 1; fi
  fi
  mv "$tmp" "$cache" 2>/dev/null && chmod 644 "$cache" 2>/dev/null
  echo "$cache"
}
