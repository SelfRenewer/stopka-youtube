#!/bin/bash
# Стопка: удаление версии для Safari.
#
#   ./safari/uninstall.sh      — снести приложение с расширением
#   ./safari/uninstall.sh -y   — без вопроса
#
# Заодно убирает следы старых установок со сторожем (LaunchAgent и его лог),
# если они остались с тех пор, как сборка была неподписанной.
set -euo pipefail

APP_NAME="Стопка"
INSTALLED="/Applications/$APP_NAME.app"
LEGACY_LABEL="com.stopka.youtube.keeper"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_LOG="$HOME/Library/Logs/stopka-keeper.log"

ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    -y|--yes) ASSUME_YES=1 ;;
    *) echo "Неизвестный ключ: $a" >&2; exit 2 ;;
  esac
done

# Каждая проверка с `|| true`: при set -e несработавшее `[ ... ] && echo`
# возвращает 1 и роняет скрипт ещё до подтверждения.
echo "Будет удалено:"
[ -d "$INSTALLED" ]    && echo "  приложение    $INSTALLED"    || true
[ -f "$LEGACY_PLIST" ] && echo "  старый сторож $LEGACY_PLIST" || true
[ -f "$LEGACY_LOG" ]   && echo "  его лог       $LEGACY_LOG"   || true
echo "Не трогается: исходники расширения и папка safari/project."

if [ "$ASSUME_YES" -eq 0 ]; then
  read -r -p "Продолжить? [y/N] " ans
  case "$ans" in y|Y|yes|да) ;; *) echo "Отменено."; exit 0 ;; esac
fi

if [ -f "$LEGACY_PLIST" ] || launchctl print "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1; then
  echo "→ Выгружаю старого сторожа"
  launchctl bootout "gui/$UID/$LEGACY_LABEL" 2>/dev/null || true
  rm -f "$LEGACY_PLIST" "$LEGACY_LOG"
fi

# Снимаем регистрацию до удаления: после rm путь к appex уже не существует
# и pluginkit ничего не найдёт.
echo "→ Снимаю регистрацию расширения"
pluginkit -r "$INSTALLED/Contents/PlugIns/$APP_NAME Extension.appex" 2>/dev/null || true

echo "→ Удаляю приложение"
rm -rf "$INSTALLED"

echo "→ Проверка"
[ -e "$INSTALLED" ]    && echo "  ВНИМАНИЕ: приложение на месте" || echo "  приложение удалено"
[ -e "$LEGACY_PLIST" ] && echo "  ВНИМАНИЕ: plist сторожа на месте" || echo "  сторожа нет"

cat <<'HINT'

Если раньше стояла неподписанная версия, в Safari могла остаться включённой
галочка «Показывать функции для веб-разработчиков» (Настройки → Дополнения),
а в Системных настройках → Конфиденциальность и безопасность →
Универсальный доступ — /usr/bin/osascript. Это убирается только руками.
HINT
