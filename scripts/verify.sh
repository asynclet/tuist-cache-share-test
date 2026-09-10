#!/bin/bash
# Машина B: сверить хэши с машиной A и прогнать четыре случая подряд.
source "$(dirname "$0")/common.sh"
need_tuist
cd "$ROOT"

for f in cache-A.tgz hashes-A.txt signature-A.txt; do
  [ -f "$FIXTURES/$f" ] || die "нет файла transfer/$f — скопируй каталог transfer/ с машины A"
done

print_env

head2 "1. Совпадают ли хэши таргетов с машиной A"
hash_table > hashes-B.txt
if diff -q "$FIXTURES/hashes-A.txt" hashes-B.txt >/dev/null; then
  echo "  ДА, хэши идентичны — перенос кэша в принципе возможен"
else
  echo "  НЕТ, хэши расходятся. Дальше попаданий не будет ни при какой подписи."
  printf '  строк всего: A=%s B=%s, различается: %s\n' \
    "$(wc -l < "$FIXTURES/hashes-A.txt" | tr -d ' ')" "$(wc -l < hashes-B.txt | tr -d ' ')" \
    "$(diff "$FIXTURES/hashes-A.txt" hashes-B.txt | grep -c '^[<>]')"
  echo "  первые расхождения:"
  diff "$FIXTURES/hashes-A.txt" hashes-B.txt | grep '^[<>]' | head -6 | sed 's/^/    /'
fi

head2 "2. Подписи двух машин"
rm -rf "$BINARIES"
mkdir -p "$XDG_CACHE_HOME/tuist"
tar -xzf "$FIXTURES/cache-A.tgz" -C "$XDG_CACHE_HOME/tuist"
art="$(any_local_artifact)"
[ -n "$art" ] || die "в распакованном архиве нет артефактов"
sig_a="$(cat "$FIXTURES/signature-A.txt")"
sig_transferred="$(signature_of "$art")"
if [ "$sig_transferred" = "$sig_a" ]; then
  echo "  подпись доехала в архиве целой (tar сохранил атрибут)"
else
  echo "  подпись в архиве НЕ сохранилась — случай 3 будет проверять отсутствие метки"
fi

head2 "3. Прогоны"
report "чужая подпись как есть (без штамповки)"

strip_all
report "метка снята со всех записей (контроль)"

sig_local=""
if [ -n "${SIGNATURE_LOCAL:-}" ]; then
  sig_local="$SIGNATURE_LOCAL"
else
  # Локальную подпись берём из уже прогретого кэша машины, а если его нет — греем
  # отдельный каталог рядом. Вывод прогрева не глушим: когда он падает, причину надо
  # видеть, иначе последний случай молча остаётся непроверенным.
  echo "  (беру подпись этой машины через bin/tuist-cache-signature)"
  sig_local="$("$ROOT/bin/tuist-cache-signature" read)" || true
fi

if [ -n "$sig_local" ]; then
  stamp_all "$sig_local"
  report "штамп локальной подписью"
  if [ "$sig_local" = "$sig_a" ]; then
    echo "  примечание: локальная подпись совпала с подписью машины A"
  else
    echo "  примечание: локальная подпись отличается от подписи машины A"
  fi
else
  echo "  не удалось получить локальную подпись. Возьми её вручную и перезапусти:"
  echo "    SIGNATURE_LOCAL=\"<значение>\" bash scripts/verify.sh"
fi

cat <<'TXT'

Как читать результат:
  хэши разошлись                  → чинить машинно-зависимые значения в настройках, остальное бессмысленно
  чужая подпись дала попадание    → штамповка не нужна, переносить можно как есть
  чужая дала промах, штамп попал  → штамповка обязательна, рецепт рабочий
  штамп тоже промах               → в проверке участвует что-то ещё, писать в задачу
TXT
