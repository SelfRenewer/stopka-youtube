#!/bin/bash
# Стопка → приложение-обёртка с расширением для Safari.
#
#   ./safari/build.sh              — собрать, подписать «Apple Development»
#                                    и поставить себе в /Applications
#   ./safari/build.sh --app-store  — собрать пакет для Mac App Store в safari/dist/
#   ./safari/build.sh --upload     — то же, но сразу отправить в App Store Connect
#
# Нужен Apple ID с Apple Developer Program в Xcode → Settings → Accounts.
# Team ID берётся оттуда сам; если команд несколько — задай STOPKA_TEAM_ID.
set -euo pipefail

MODE=install
for a in "$@"; do
  case "$a" in
    --app-store) MODE=app-store ;;
    --upload)    MODE=upload ;;
    *) echo "Неизвестный ключ: $a (есть --app-store и --upload)" >&2; exit 2 ;;
  esac
done

APP_NAME="Stopka"
RU_NAME="Стопка"
# До перехода на латиницу приложение называлось так — его убираем при установке.
LEGACY_APP="/Applications/Стопка.app"
BUNDLE_ID="com.stopka.youtube"
PRIVACY_URL="https://github.com/SelfRenewer/stopka-youtube/blob/main/PRIVACY.md"
CATEGORY="public.app-category.productivity"
# Конвертер ставит приложению минимальную macOS по версии Xcode (27),
# расширению — 12. С 27 в App Store «Стопку» не поставить на macOS 26 и
# старше, поэтому выравниваем обе цели по расширению.
MIN_MACOS="12.0"

SAFARI_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SAFARI_DIR")"
PROJECT_DIR="$SAFARI_DIR/project"
OVERLAY="$SAFARI_DIR/app"
DIST="$SAFARI_DIR/dist"
INSTALLED="/Applications/$APP_NAME.app"

# Версия — из манифеста, чтобы у расширения и приложения она была одна.
# Номер сборки — время в UTC: растёт сам, App Store Connect требует, чтобы
# каждая отправка была с номером больше прежнего.
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$SRC/manifest.json" | head -1)"
[ -n "$VERSION" ] || { echo "Не нашёл version в manifest.json" >&2; exit 1; }
BUILD_NUMBER="$(date -u +%Y%m%d.%H%M)"

# В бандл расширения уезжает ровно этот список. Всё остальное из папки
# проекта (README, CLAUDE.md, сам safari/, .DS_Store) внутрь не попадает.
EXT_FILES=(manifest.json _locales content.js content.css popup.html popup.css popup.js icons)

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
  # `|| true`: при pipefail отсутствующий ключ (нет аккаунта) уронил бы
  # скрипт молча, без сообщения ниже.
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
echo "→ Команда: $TEAM_ID, версия $VERSION ($BUILD_NUMBER)"

# 1. Стейджинг: конвертер копирует папку целиком, поэтому даём ему
#    чистую копию только с файлами расширения.
STAGE_ROOT="$(mktemp -d)"
DERIVED="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT" "$DERIVED"' EXIT
STAGE="$STAGE_ROOT/stopka"
mkdir -p "$STAGE"
for f in "${EXT_FILES[@]}"; do
  [ -e "$SRC/$f" ] || { echo "Нет файла расширения: $SRC/$f" >&2; exit 1; }
  cp -R "$SRC/$f" "$STAGE/"
done
find "$STAGE" -name '.DS_Store' -delete

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
APP_SRC="$(dirname "$PROJ")/$APP_NAME"
echo "→ Проект: $PROJ"

# Конвертер собирает ID приложения из префикса и имени приложения
# (com.stopka.Stopka, а для кириллицы — com.stopka.------), а ID расширения
# берёт как есть. Сборка падает на проверке префикса, поэтому ID приложения
# выставляем явно — всем записям, кроме расширения.
perl -i -pe 's/(PRODUCT_BUNDLE_IDENTIFIER = )(?!\Q'"$BUNDLE_ID"'.Extension\E;)[^;]+;/$1'"$BUNDLE_ID"';/g' \
  "$PROJ/project.pbxproj"

# 3. Контейнер: наши файлы поверх сгенерированных — окно на английском
#    (Base) и русском (ru), ссылка на политику конфиденциальности (App Review
#    5.1.1 требует её и внутри приложения), чёткая иконка. Исходники — safari/app/.
echo "→ Накладываю safari/app/ на приложение-контейнер"
cp "$OVERLAY/en/Main.html" "$APP_SRC/Resources/Base.lproj/Main.html"
mkdir -p "$APP_SRC/Resources/ru.lproj" "$APP_SRC/ru.lproj"
cp "$OVERLAY/ru/Main.html" "$APP_SRC/Resources/ru.lproj/Main.html"
cp "$OVERLAY/ru/InfoPlist.strings" "$APP_SRC/ru.lproj/InfoPlist.strings"
cp "$OVERLAY/Script.js" "$OVERLAY/Style.css" "$OVERLAY/Icon.png" "$APP_SRC/Resources/"
sed -e "s|__EXTENSION_BUNDLE_ID__|$BUNDLE_ID.Extension|" \
    -e "s|__PRIVACY_URL__|$PRIVACY_URL|" \
    "$OVERLAY/ViewController.swift" > "$APP_SRC/ViewController.swift"
if grep -q '__[A-Z_]*__' "$APP_SRC/ViewController.swift"; then
  echo "В ViewController.swift остались незаменённые метки" >&2; exit 1
fi
rm -rf "$APP_SRC/Assets.xcassets/AppIcon.appiconset"
cp -R "$OVERLAY/AppIcon.appiconset" "$APP_SRC/Assets.xcassets/"

# Меню на русском: строки берём из сгенерированного storyboard (ID у
# элементов меню задаёт шаблон Xcode) и переводим по safari/app/ru/menu.txt.
# Непереведённая строка не молчит — падаем, иначе меню выйдет наполовину английским.
ibtool --generate-strings-file "$DERIVED/Main.strings" "$APP_SRC/Base.lproj/Main.storyboard"
iconv -f UTF-16 -t UTF-8 "$DERIVED/Main.strings" | APP="$APP_NAME" perl -CSD -Mutf8 -e '
  open my $m, "<:encoding(UTF-8)", shift or die; my %ru;
  while (<$m>) { next if /^\s*(#|$)/; chomp; my ($en, $tr) = split / = /, $_, 2;
                 s/\bAPP\b/$ENV{APP}/g for $en; $ru{$en} = $tr }
  my @miss;
  while (<STDIN>) {
    if (/^(".*" = )"(.*)";\s*$/) { exists $ru{$2} ? ($_ = "$1\"$ru{$2}\";\n") : push @miss, $2 }
    print;
  }
  die "Нет перевода меню для: @miss\n" if @miss;
' "$OVERLAY/ru/menu.txt" > "$APP_SRC/ru.lproj/Main.strings"

# Записи о ru-файлах в проекте: localize.pl правит структуру plist,
# а не текст pbxproj. Xcode читает проект и в XML-виде.
plutil -convert json -o - "$PROJ/project.pbxproj" \
  | perl "$OVERLAY/localize.pl" "$APP_NAME" > "$DERIVED/project.json"
plutil -convert xml1 "$DERIVED/project.json" -o "$PROJ/project.pbxproj"

# Категория обязательна для Mac App Store. Шифрования своего нет — флаг
# избавляет от вопроса про экспортный контроль при каждой отправке.
PLIST="$APP_SRC/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string $CATEGORY" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$PLIST"

SETTINGS=(
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM="$TEAM_ID"
  MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
  MARKETING_VERSION="$VERSION"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)

# 4a. App Store: архив → экспорт с подписью Apple Distribution.
#     Сертификаты для App Store Xcode выпустит сам (-allowProvisioningUpdates).
if [ "$MODE" != install ]; then
  ARCHIVE="$DERIVED/$APP_NAME.xcarchive"
  echo "→ Архивирую для App Store"
  xcodebuild archive -project "$PROJ" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    "${SETTINGS[@]}" \
    -quiet

  DESTINATION=export
  [ "$MODE" = upload ] && DESTINATION=upload
  OPTS="$DERIVED/export-options.plist"
  cat > "$OPTS" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DESTINATION</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLISTEOF

  if [ "$MODE" = upload ]; then
    echo "→ Отправляю в App Store Connect (версия $VERSION, сборка $BUILD_NUMBER)"
  else
    echo "→ Экспортирую пакет в $DIST"
  fi
  rm -rf "$DIST"
  mkdir -p "$DIST"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTS" \
    -exportPath "$DIST" \
    -allowProvisioningUpdates

  if [ "$MODE" = app-store ]; then
    PKG="$(find "$DIST" -maxdepth 1 -name '*.pkg' | head -1)"
    [ -n "$PKG" ] || { echo "Пакет не появился в $DIST" >&2; exit 1; }
    echo "→ Пакет: $PKG"
    pkgutil --check-signature "$PKG" | sed -n '1,4p'
    echo "Отправить его: ./safari/build.sh --upload"
  else
    echo "→ Отправлено. Сборка появится в App Store Connect → TestFlight через несколько минут."
  fi
  exit 0
fi

# 4b. Себе: сборка с подписью «Apple Development». Расширение с сертификатом
#     разработчика Safari грузит сам — без «Разрешить неподписанные
#     расширения». Мак Xcode зарегистрирует как устройство при первом запуске.
#     derivedData во временной папке: иначе Safari видит два одинаковых
#     расширения — одно из сборки, второе из /Applications.
echo "→ Собираю (Release, подпись команды $TEAM_ID)"
xcodebuild -project "$PROJ" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${SETTINGS[@]}" \
  -quiet

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "Приложение не собралось" >&2; exit 1; }

# Старое приложение с кириллическим именем и тем же bundle ID надо убрать,
# иначе Safari покажет две «Стопки» и обе будут вешать ＋ на превью.
if [ -d "$LEGACY_APP" ]; then
  echo "→ Убираю старое $LEGACY_APP"
  pluginkit -r "$LEGACY_APP/Contents/PlugIns/$RU_NAME Extension.appex" 2>/dev/null || true
  rm -rf "$LEGACY_APP"
fi

# Safari держит расширение по пути приложения, поэтому оно должно лежать
# в постоянном месте, а не в папке сборки.
echo "→ Ставлю в $INSTALLED"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"

# Подпись проверяем до регистрации: ad-hoc или чужая команда означали бы,
# что Safari снова потребует галку про неподписанные расширения.
# `|| true`: при pipefail упавший codesign уронил бы скрипт молча.
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
echo "Перезапусти Safari (⌘Q): открытые вкладки держат старую версию."
