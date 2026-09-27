#!/bin/bash
# Стопка: ставит сторожа, который после каждого запуска Safari включает
# «Разрешить неподписанные расширения» и возвращает расширение в список.
#
# Пишет в два места вне папки проекта:
#   ~/Library/LaunchAgents/com.stopka.youtube.keeper.plist
#   ~/Library/Logs/stopka-keeper.log
# Всё остальное живёт внутри safari/. Откат — ./uninstall.sh
set -euo pipefail

LABEL="com.stopka.youtube.keeper"
SAFARI_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SAFARI_DIR/src"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/stopka-keeper.log"

[ -f "$SRC_DIR/watcher.sh" ] || { echo "Нет $SRC_DIR/watcher.sh" >&2; exit 1; }
[ -f "$SRC_DIR/unsigned-extensions.applescript" ] || { echo "Нет скрипта логики" >&2; exit 1; }

echo "→ Пишу LaunchAgent: $PLIST"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$SRC_DIR/watcher.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Background</string>
	<key>ThrottleInterval</key>
	<integer>10</integer>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
PLISTEOF

plutil -lint "$PLIST" >/dev/null

echo "→ Загружаю в launchd"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
sleep 1   # без паузы bootstrap ловит «Input/output error» на только что выгруженном сервисе
launchctl bootstrap "gui/$UID" "$PLIST"
sleep 1
launchctl print "gui/$UID/$LABEL" 2>/dev/null | grep -E '^\s+(state|pid) =' || true

cat <<HINT

Готово. Логику AppleScript исполняет /usr/bin/osascript — бинарник с
подписью Apple. Собственный апплет тут не годится: ad-hoc подпись не
проходит проверку TCC, строку в «Универсальный доступ» добавить можно,
но сверять её не с чем, и право не действует.

Прав выдавать не потребовалось. Если в логе появится «no-accessibility»,
добавь в Системные настройки → Конфиденциальность и безопасность →
Универсальный доступ бинарник /usr/bin/osascript (⌘⇧G в окне выбора).

Проверить работу:  tail -f "$LOG"
Снести всё:        $SAFARI_DIR/uninstall.sh
HINT
