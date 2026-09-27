#!/bin/bash
# Стопка: полный откат установки для Safari.
#
#   ./uninstall.sh                 — снести агента, .app и логи
#   ./uninstall.sh --reset-safari  — плюс снять «функции для веб-разработчиков»
#   ./uninstall.sh -y              — без вопроса
set -euo pipefail

LABEL="com.stopka.youtube.keeper"
APP_NAME="Стопка"
SAFARI_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/stopka-keeper.log"
INSTALLED="/Applications/$APP_NAME.app"

RESET_SAFARI=0
ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    --reset-safari) RESET_SAFARI=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    *) echo "Неизвестный ключ: $a" >&2; exit 2 ;;
  esac
done

# Каждая проверка с `|| true`: при set -e несработавшее `[ ... ] && echo`
# возвращает 1 и роняет скрипт ещё до подтверждения.
echo "Будет удалено:"
[ -f "$PLIST" ]     && echo "  LaunchAgent  $PLIST"     || true
[ -d "$INSTALLED" ] && echo "  приложение   $INSTALLED" || true
[ -f "$LOG" ]       && echo "  лог          $LOG"       || true
[ "$RESET_SAFARI" -eq 1 ] && echo "  плюс снимется галочка «функции для веб-разработчиков» в Safari" || true
echo "Не трогается: исходники расширения и папка safari/project."

if [ "$ASSUME_YES" -eq 0 ]; then
  read -r -p "Продолжить? [y/N] " ans
  case "$ans" in y|Y|yes|да) ;; *) echo "Отменено."; exit 0 ;; esac
fi

if [ "$RESET_SAFARI" -eq 1 ]; then
  if pgrep -qx Safari; then
    echo "→ Снимаю галочку в настройках Safari"
    osascript "$SAFARI_DIR/src/restore-webdev.applescript" || \
      echo "  не вышло — сними вручную: Настройки → Дополнения"
  else
    echo "→ Safari не запущен, галочку не трогаю (сними вручную: Настройки → Дополнения)"
  fi
fi

echo "→ Выгружаю агента"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
pkill -f "$SAFARI_DIR/src/watcher.sh" 2>/dev/null || true

# Снимаем регистрацию до удаления: после rm путь к appex уже не существует
# и pluginkit ничего не найдёт.
echo "→ Снимаю регистрацию расширения"
pluginkit -r "$INSTALLED/Contents/PlugIns/$APP_NAME Extension.appex" 2>/dev/null || true

echo "→ Удаляю файлы"
rm -f "$PLIST"
rm -rf "$INSTALLED"
rm -f "$LOG"

echo "→ Проверка"
launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 && echo "  ВНИМАНИЕ: агент всё ещё в launchd" || echo "  агента в launchd нет"
[ -e "$PLIST" ]     && echo "  ВНИМАНИЕ: plist на месте"      || echo "  plist удалён"
[ -e "$INSTALLED" ] && echo "  ВНИМАНИЕ: приложение на месте" || echo "  приложение удалено"
pgrep -f "watcher.sh" >/dev/null 2>&1 && echo "  ВНИМАНИЕ: сторож ещё жив" || echo "  сторож не запущен"

cat <<'HINT'

Осталось то, что система хранит у себя и скрипт удалить не может —
чистится только руками, если записи там есть:

  Системные настройки → Конфиденциальность и безопасность
    → Универсальный доступ — убрать StopkaKeeper, applet, Стопка Хранитель
      и /usr/bin/osascript, если добавляли
    → Автоматизация — там же

«Разрешить неподписанные расширения» откатывать не нужно: этот флаг
живёт только в памяти Safari и гаснет сам при следующем запуске.
HINT
