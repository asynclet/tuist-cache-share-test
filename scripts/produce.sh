#!/bin/bash
# Машина A: прогреть кэш, снять хэши и подпись, упаковать кэш системным tar.
# Системный tar на macOS сохраняет расширенные атрибуты, поэтому подпись уезжает
# вместе с архивом — это нужно, чтобы проверить, годится ли чужая подпись как есть.
source "$(dirname "$0")/common.sh"
need_tuist
cd "$ROOT"
mkdir -p "$FIXTURES"

print_env

head2 "Прогреваю кэш"
tuist cache warm

head2 "Хэши таргетов"
hash_table | tee "$FIXTURES/hashes-A.txt" | tail -5
printf '  записано в hashes-A.txt (строк: %s)\n' "$(wc -l < "$FIXTURES/hashes-A.txt" | tr -d ' ')"

art="$(any_local_artifact)"
[ -n "$art" ] || die "в кэше нет артефактов — прогрев не сработал"
signature_of "$art" > "$FIXTURES/signature-A.txt"
printf '\n  подпись машины A записана в signature-A.txt (%s байт)\n' "$(wc -c < "$FIXTURES/signature-A.txt" | tr -d ' ')"

head2 "Упаковываю кэш (системный tar, атрибуты сохраняются)"
tar -czf "$FIXTURES/cache-A.tgz" -C "$XDG_CACHE_HOME/tuist" Binaries
printf '  cache-A.tgz: %s\n' "$(du -h "$FIXTURES/cache-A.tgz" | cut -f1)"

cat <<TXT

Готово, всё сложено в transfer/. Скопируй каталог на машину B в корень того же
репозитория и запусти там bash scripts/verify.sh
TXT
