#!/bin/bash
# Стопка: кладёт поле из metadata.md в буфер обмена для вставки в App Store Connect.
#   ./copy-field.sh "Description (en)"
set -euo pipefail
cd "$(dirname "$0")"
# -CSD декодирует файл, но не окружение: имя поля декодируем сами,
# иначе русские названия полей не совпадают никогда.
TEXT="$(FIELD="$1" perl -CSD -Mutf8 -MEncode -ne '
  BEGIN { $want = decode_utf8($ENV{FIELD}) }
  if (/^#{1,3} (.+?)\s*$/) { $on = ($1 eq $want); next }
  next if /<!-- limit:\d+ -->/;
  print if $on;
' metadata.md | perl -0777 -pe 's/^\s+|\s+$//g')"
[ -n "$TEXT" ] || { echo "Нет поля «$1» в metadata.md" >&2; exit 1; }
printf '%s' "$TEXT" | LANG=en_US.UTF-8 pbcopy  # без UTF-8 pbcopy читает байты в кодировке системы и ломает ＋ и кириллицу
echo "В буфере «$1»: $(printf '%s' "$TEXT" | wc -m | tr -d ' ') символов"
