#!/bin/bash
# Стопка → приложение-обёртка с расширением для Safari.
# Конвертирует, подписывает сертификатом разработчика и ставит в /Applications.
# Запуск: ./safari/build.sh
#
# Нужен Apple ID с Apple Developer Program в Xcode → Settings → Accounts.
# Team ID берётся оттуда сам; если команд несколько — задай STOPKA_TEAM_ID.
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

# Команда разработчика. В репозиторий не зашита: берём из Xcode, где
# пользователь вошёл своим Apple ID. Берём только платные команды: по
# документации Apple подпись сертификатом разработчика — для участников
# Developer Program. Бесплатную Personal Team не проверяли.
TEAM_ID="${STOPKA_TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  TEAMS="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | awk '
    /isFreeProvisioningTeam = 0;/ { paid = 1 }
    /teamID = / { id = $3; sub(/;$/, "", id) }
    /}/ { if (paid && id != "") print id; paid = 0; id = "" }
  ' | sort -u || true)"
  case "$(printf '%s' "$TEAMS" | grep -c .)" in
    1) TEAM_ID="$TEAMS" ;;
    0) echo "В Xcode нет платной команды разработчика." >&2
       echo "Xcode → Settings → Accounts → + → Apple ID с Apple Developer Program." >&2
       exit 1 ;;
    *) echo "В Xcode несколько команд, выбери одну:" >&2
       printf '  %s\n' $TEAMS >&2
       echo "STOPKA_TEAM_ID=<ID> ./safari/build.sh" >&2
       exit 1 ;;
  esac
fi
echo "→ Команда: $TEAM_ID"

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

# 3. Сборка с подписью «Apple Development». Расширение с сертификатом
#    разработчика Safari грузит сам — без «Разрешить неподписанные
#    расширения». Сертификат и профиль Xcode выпустит при первом запуске
#    (-allowProvisioningUpdates), Мак зарегистрирует как устройство.
#    derivedData во временной папке: иначе Safari видит два одинаковых
#    расширения — одно из сборки, второе из /Applications.
DERIVED="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT" "$DERIVED"' EXIT
echo "→ Собираю (Release, подпись команды $TEAM_ID)"
xcodebuild -project "$PROJ" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -quiet

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "Приложение не собралось" >&2; exit 1; }

# 4. Установка. Safari держит расширение по пути приложения, поэтому
#    оно должно лежать в постоянном месте, а не в папке сборки.
echo "→ Ставлю в $INSTALLED"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"

# Подпись проверяем до регистрации: ad-hoc или чужая команда означали бы,
# что Safari снова потребует галку про неподписанные расширения.
# `|| true`: при pipefail упавший codesign уронил бы скрипт молча, без
# сообщения ниже. То же выше у разбора команд: нет ключа — нет аккаунта.
SIGNED_TEAM="$(codesign -dv "$INSTALLED/Contents/PlugIns/$APP_NAME Extension.appex" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"
if [ "$SIGNED_TEAM" != "$TEAM_ID" ]; then
  echo "Расширение подписано не той командой: '$SIGNED_TEAM' вместо '$TEAM_ID'" >&2
  exit 1
fi
echo "→ Подпись: команда $SIGNED_TEAM"

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
