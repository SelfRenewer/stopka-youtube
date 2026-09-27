#!/bin/bash
# Стопка → приложение-обёртка с расширением для Safari.
# Конвертирует, собирает ad-hoc подписью и ставит в /Applications.
# Запуск: ./safari/build.sh
set -euo pipefail

APP_NAME="Стопка"
BUNDLE_ID="com.stopka.youtube"
SAFARI_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SAFARI_DIR")"
PROJECT_DIR="$SAFARI_DIR/project"
INSTALLED="/Applications/$APP_NAME.app"

# В бандл расширения уезжает ровно этот список. Всё остальное из папки
# проекта (README, CLAUDE.md, сам safari/, .DS_Store) внутрь не попадает.
EXT_FILES=(manifest.json content.js content.css popup.html popup.css popup.js icons)

XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
if [ -z "$XCODE" ]; then
  echo "Xcode.app не найден в /Applications. Поставь Xcode из App Store и запусти снова." >&2
  exit 1
fi
export DEVELOPER_DIR="$XCODE/Contents/Developer"
echo "→ Xcode: $XCODE"

# 1. Стейджинг: конвертер копирует папку целиком, поэтому даём ему
#    чистую копию только с файлами расширения.
STAGE_ROOT="$(mktemp -d)"
STAGE="$STAGE_ROOT/stopka"
mkdir -p "$STAGE"
for f in "${EXT_FILES[@]}"; do
  [ -e "$SRC/$f" ] || { echo "Нет файла расширения: $SRC/$f" >&2; exit 1; }
  cp -R "$SRC/$f" "$STAGE/"
done
find "$STAGE" -name '.DS_Store' -delete
trap 'rm -rf "$STAGE_ROOT"' EXIT

# 2. Конвертация. --copy-resources обязателен: без него проект ссылается
#    на исходную папку, а она у нас временная.
echo "→ Конвертирую в $PROJECT_DIR"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
xcrun safari-web-extension-converter "$STAGE" \
  --app-name "$APP_NAME" \
  --bundle-identifier "$BUNDLE_ID" \
  --macos-only \
  --project-location "$PROJECT_DIR" \
  --copy-resources \
  --no-open \
  --no-prompt \
  --force

PROJ="$(find "$PROJECT_DIR" -maxdepth 2 -name '*.xcodeproj' | head -1)"
[ -n "$PROJ" ] || { echo "Xcode-проект не создался" >&2; exit 1; }
echo "→ Проект: $PROJ"

# Конвертер не умеет делать bundle id из кириллического имени: у приложения
# выходит com.stopka.------ и сборка падает на проверке префикса.
if grep -q 'PRODUCT_BUNDLE_IDENTIFIER = "[a-zA-Z.]*-\{2,\}"' "$PROJ/project.pbxproj"; then
  echo "→ Чиню bundle id приложения на $BUNDLE_ID"
  perl -i -pe 's/PRODUCT_BUNDLE_IDENTIFIER = "[a-zA-Z.]*-{2,}";/PRODUCT_BUNDLE_IDENTIFIER = '"$BUNDLE_ID"';/g' \
    "$PROJ/project.pbxproj"
fi

# 3. Сборка. Учётки Apple Developer нет, подписываем ad-hoc.
#    Safari примет её при включённом «Разрешить неподписанные расширения».
#    derivedData во временной папке: иначе Safari видит два одинаковых
#    расширения — одно из сборки, второе из /Applications.
DERIVED="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT" "$DERIVED"' EXIT
echo "→ Собираю (Release, ad-hoc)"
xcodebuild -project "$PROJ" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  -quiet

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "Приложение не собралось" >&2; exit 1; }

# 4. Установка. Safari держит расширение по пути приложения, поэтому
#    оно должно лежать в постоянном месте, а не в папке сборки.
echo "→ Ставлю в $INSTALLED"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"

# Safari перечисляет неподписанные расширения только в момент регистрации
# appex и только при включённом флаге. Поэтому порядок именно такой:
# сначала флаг, потом перерегистрация, потом запуск контейнера.
if pgrep -qx Safari; then
  echo "→ Включаю «Разрешить неподписанные расширения»"
  status="$(/usr/bin/osascript "$SAFARI_DIR/src/unsigned-extensions.applescript" 2>&1)"
  echo "   $status"
else
  echo "→ Safari не запущен, флаг включит сторож при следующем старте"
fi

echo "→ Регистрирую расширение"
pluginkit -r "$INSTALLED/Contents/PlugIns/$APP_NAME Extension.appex" 2>/dev/null || true
sleep 1
pluginkit -a "$INSTALLED/Contents/PlugIns/$APP_NAME Extension.appex" 2>/dev/null || true
sleep 1
open -g "$INSTALLED"
sleep 4
pkill -x "$APP_NAME" 2>/dev/null || true

echo "→ Готово. Проверка регистрации:"
pluginkit -mAvvv -p com.apple.Safari.web-extension 2>/dev/null | grep -A1 "$BUNDLE_ID.Extension" | head -2 || \
  echo "  расширение пока не видно в pluginkit — открой Safari"
