# Общая часть обоих скриптов: изолированный кэш, версии окружения, разбор вывода генерации.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_CACHE_HOME="${XDG_CACHE_HOME_OVERRIDE:-$ROOT/.cache}"
BINARIES="$XDG_CACHE_HOME/tuist/Binaries"
XATTR_NAME="tuist.cloud.metadata"
# Набор с машины A лежит в репозитории, чтобы на машине B хватило клона и verify.sh.
FIXTURES="$ROOT/machine-A"

die() { printf '\n%s\n' "ОШИБКА: $*" >&2; exit 1; }
head2() { printf '\n=== %s\n' "$*"; }

need_tuist() {
  command -v tuist >/dev/null 2>&1 || die "tuist не найден в PATH"
}

# В хэши кэша входят версии Swift и Tuist, поэтому расхождение окружения даёт
# ложный промах. Печатаем всё, что влияет, чтобы сверить машины глазами.
print_env() {
  head2 "Окружение (должно совпадать на обеих машинах)"
  printf '  tuist    %s\n' "$(tuist version 2>/dev/null || echo '?')"
  printf '  xcodebuild %s\n' "$(xcodebuild -version 2>/dev/null | head -1 || echo '?')"
  printf '  swift    %s\n' "$(xcrun swift --version 2>/dev/null | head -1 || echo '?')"
  printf '  кэш      %s\n' "$XDG_CACHE_HOME"
}

# Единственный надёжный признак попадания — непустой список имён после "targets:".
# Строка печатается и при промахе, поэтому смотреть надо именно на имена.
cache_hits() {
  local out
  out="$(tuist generate --no-open 2>&1 || true)"
  printf '%s' "$out" \
    | grep -i "cache binaries for the following targets:" \
    | head -1 \
    | sed 's/.*targets: *//' \
    | tr -d '\r'
}

report() {
  local label="$1" hits
  hits="$(cache_hits)"
  if [ -n "$hits" ]; then
    printf '  %-46s ПОПАДАНИЕ: %s\n' "$label" "$hits"
  else
    printf '  %-46s промах\n' "$label"
  fi
}

signature_of() { xattr -p "$XATTR_NAME" "$1" 2>/dev/null || true; }

# `tuist hash cache` печатает преамбулу про построение графа; для сравнения машин
# нужны только строки вида "<таргет> - <32 hex>", иначе diff шумит на пустяках.
hash_table() {
  tuist hash cache --configuration Debug 2>/dev/null \
    | grep -E '^[A-Za-z0-9_.-]+ - [0-9a-f]{32}$' \
    | sort
}

any_local_artifact() {
  find "$BINARIES" -mindepth 2 -maxdepth 2 \
    \( -name '*.xcframework' -o -name '*.framework' -o -name '*.macro' \) 2>/dev/null | head -1
}

# Все записи кэша, а не первая: если оставить подпись хотя бы на одной,
# контрольный прогон покажет попадание и результат будет прочитан неверно.
all_entries() { find "$BINARIES" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; }

entry_paths() {
  local entry="$1"
  printf '%s\n' "$entry" "$entry/Metadata.plist"
  for a in "$entry"/*.xcframework "$entry"/*.framework "$entry"/*.macro; do
    [ -e "$a" ] && printf '%s\n' "$a"
  done
}

stamp_all() {
  local sig="$1" entry p
  [ -n "$sig" ] || die "нечем штамповать: пустое значение подписи"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    while IFS= read -r p; do
      [ -n "$p" ] && xattr -w "$XATTR_NAME" "$sig" "$p"
    done < <(entry_paths "$entry")
  done < <(all_entries)
}

strip_all() {
  local entry p
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    while IFS= read -r p; do
      [ -n "$p" ] && xattr -d "$XATTR_NAME" "$p" 2>/dev/null || true
    done < <(entry_paths "$entry")
  done < <(all_entries)
}
