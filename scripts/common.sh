# Общая часть обоих скриптов: изолированный кэш, версии окружения, разбор вывода генерации.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_CACHE_HOME="${XDG_CACHE_HOME_OVERRIDE:-$ROOT/.cache}"
BINARIES="$XDG_CACHE_HOME/tuist/Binaries"
XATTR_NAME="tuist.cloud.metadata"
# Что машина A передаёт машине B. В репозиторий не коммитится: архив кэша и подпись —
# артефакты конкретного прогона, а не часть набора.
FIXTURES="$ROOT/transfer"

die() { printf '\n%s\n' "ОШИБКА: $*" >&2; exit 1; }
head2() { printf '\n=== %s\n' "$*"; }

# Tuist берём через mise, а не из PATH: версия пинится в mise.toml, поэтому на обеих
# машинах она заведомо одна. Функция перекрывает имя команды, внутри вызывается уже
# бинарник, так что рекурсии нет. Запуск из корня проекта — mise ищет там свой конфиг,
# да и сам tuist должен работать в каталоге проекта.
tuist() { ( cd "$ROOT" && command mise exec -- tuist "$@" ); }

need_tuist() {
  command -v mise >/dev/null 2>&1 || die "mise не найден, поставь его: https://mise.jdx.dev"
  # Свежий клон mise не доверяет и конфиг не читает. Файл здесь свой, из этого же
  # репозитория, и содержит одну строку с версией, поэтому доверяем ему явно.
  if ! ( cd "$ROOT" && command mise config ls >/dev/null 2>&1 ); then
    echo "Доверяю mise.toml этого репозитория (mise trust)"
    command mise trust "$ROOT/mise.toml" >/dev/null || die "mise trust не отработал"
  fi
  if ! ( cd "$ROOT" && command mise which tuist >/dev/null 2>&1 ); then
    echo "Ставлю tuist версии из mise.toml…"
    ( cd "$ROOT" && command mise install ) || die "mise install не отработал"
  fi
}

# В хэши кэша входят версии Swift и Tuist, поэтому расхождение окружения даёт
# ложный промах. Печатаем всё, что влияет, чтобы сверить машины глазами.
print_env() {
  head2 "Окружение (должно совпадать на обеих машинах)"
  # sed вместо head: head закрывает пайп после первой строки, источник падает по
  # SIGPIPE, и ветка с вопросительным знаком срабатывает поверх нормального вывода.
  printf '  tuist      %s\n' "$(tuist version 2>/dev/null | sed -n 1p)"
  printf '  xcodebuild %s\n' "$(xcodebuild -version 2>/dev/null | sed -n 1p)"
  printf '  swift      %s\n' "$(xcrun swift --version 2>/dev/null | sed -n 1p)"
  printf '  кэш        %s\n' "$XDG_CACHE_HOME"
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

# Подпись машины можно получить только у Tuist, запущенного на ней, и только вместе с
# каким-нибудь артефактом кэша. Поэтому собираем проект-пустышку во временном каталоге:
# в репозитории держать его незачем, а так он не может ни устареть, ни попасть в workspace,
# ни повлиять на хэши. Таргет под macOS — рантайм симулятора iOS может быть не установлен,
# а подпись не зависит ни от платформы, ни от содержимого артефакта. Занимает ~3 секунды.
mint_signature() {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/Sources/Mint"
  cat > "$dir/Tuist.swift" <<'MANIFEST'
import ProjectDescription
let config = Config(project: .tuist(cacheOptions: .options(
    profiles: .profiles(default: .allPossible), storages: [.local])))
MANIFEST
  cat > "$dir/Project.swift" <<'MANIFEST'
import ProjectDescription
let project = Project(name: "Mint", targets: [
    .target(name: "Mint", destinations: [.mac], product: .framework,
            bundleId: "io.cacheshare.mint", deploymentTargets: .macOS("14.0"),
            sources: ["Sources/Mint/**"]),
])
MANIFEST
  echo 'public let mint = 1' > "$dir/Sources/Mint/Mint.swift"
  ( export XDG_CACHE_HOME="$dir/.cache"; cd "$dir" && command mise exec -- tuist cache warm ) >/dev/null 2>&1 \
    || echo "  прогрев пустышки не отработал" >&2
  local artifact
  artifact="$(find "$dir/.cache/tuist/Binaries" -mindepth 2 -maxdepth 2 -name '*.xcframework' 2>/dev/null | head -1)"
  [ -n "$artifact" ] && xattr -p "$XATTR_NAME" "$artifact" 2>/dev/null
  rm -rf "$dir"
}
