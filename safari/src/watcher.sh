#!/bin/bash
# Стопка: сторож запуска Safari.
#
# Запускается при логине (LaunchAgent, RunAtLoad + KeepAlive) и живёт постоянно.
# Замечает новый экземпляр Safari по смене pid и один раз на запуск делает две
# вещи: включает «Разрешить неподписанные расширения» и возвращает расширение
# в список.
#
# Флаг сбрасывается Safari при каждом старте и не имеет ключа в prefs, поэтому
# другого способа, кроме как повторять действие после каждого запуска, нет.
set -uo pipefail
umask 077   # лог и временные файлы — только для владельца

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGIC="$SELF_DIR/unsigned-extensions.applescript"
APP="/Applications/Стопка.app"
APPEX="$APP/Contents/PlugIns/Стопка Extension.appex"
LOG="$HOME/Library/Logs/stopka-keeper.log"
MAX_BYTES=524288   # 512 КБ
KEEP_LINES=500
POLL=0.5

rotate() {
  local sz
  sz="$(stat -f%z "$LOG" 2>/dev/null || echo 0)"
  [ "$sz" -gt "$MAX_BYTES" ] || return 0
  # Урезаем на месте, не переименовывая: launchd держит открытым этот же
  # инод под StandardErrorPath, после mv он писал бы в переименованный файл.
  local tmp
  tmp="$(mktemp)"
  tail -n "$KEEP_LINES" "$LOG" > "$tmp" 2>/dev/null || true
  cat "$tmp" > "$LOG"
  rm -f "$tmp"
  printf '%s watcher --- лог урезан до последних %s строк ---\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$KEEP_LINES" >> "$LOG"
}

log() {
  mkdir -p "$(dirname "$LOG")"
  rotate
  printf '%s watcher %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Включения флага мало. Safari перечисляет неподписанные расширения только
# в момент регистрации appex, а на старте флаг ещё выключен — расширение
# отбрасывается и само уже не возвращается. Поэтому после включения флага
# перерегистрируем appex и коротко поднимаем приложение-контейнер.
register_extension() {
  if [ ! -d "$APPEX" ]; then
    log "appex не найден: $APPEX"
    return
  fi
  /usr/bin/pluginkit -r "$APPEX" 2>>"$LOG"
  sleep 1
  /usr/bin/pluginkit -a "$APPEX" 2>>"$LOG"
  sleep 1
  open -g "$APP" 2>>"$LOG"
  sleep 4
  pkill -x "Стопка" 2>/dev/null
  log "расширение перерегистрировано"
}

apply() {
  if [ ! -f "$LOGIC" ]; then
    log "скрипт не найден: $LOGIC"
    return
  fi
  # Зовём osascript напрямую. Апплет тут не годится: ad-hoc подпись не
  # проходит проверку TCC — строку в «Универсальный доступ» добавить можно,
  # но сверять её не с чем, и право не действует. У /usr/bin/osascript
  # подпись Apple и устойчивая идентичность.
  # $1 = "launch", когда новый pid поймали мы сами: Safari только что
  # стартовал, флаг заведомо сброшен, и скрипт не прыгает по вкладкам
  # ради проверок. Без аргумента — осторожный режим: Safari мог работать
  # давно, и галочка может уже стоять.
  local status
  status="$(/usr/bin/osascript "$LOGIC" ${1:+"$1"} 2>>"$LOG")" || log "osascript вернул код $?"
  case "$status" in
    clicked|turned-on|already-on|clicked-unverified)
      register_extension
      ;;
    *) log "флаг не включён ($status) — расширение не трогаю" ;;
  esac
}

# launchd создаёт файл под StandardErrorPath сам, со своей маской, поэтому
# права выставляем явно, а не полагаемся на umask.
mkdir -p "$(dirname "$LOG")"
[ -e "$LOG" ] || : > "$LOG"
chmod 600 "$LOG" 2>/dev/null || true

trap 'log "остановлен"; exit 0' TERM INT

log "запущен (pid $$), опрос каждые ${POLL}с"

# Следим за pid, а не за фактом «процесс есть/нет». Перезапуск Safari
# бывает быстрее интервала опроса, и переход «нет → есть» тогда не виден
# вовсе; смена pid ловится в любом случае.
last_pid=""
if pid="$(pgrep -x Safari | head -1)" && [ -n "$pid" ]; then
  log "Safari уже запущен (pid $pid) — применяю осторожно"
  apply
  last_pid="$pid"
fi

while true; do
  pid="$(pgrep -x Safari | head -1)"
  if [ -n "$pid" ] && [ "$pid" != "$last_pid" ]; then
    log "Safari запустился (pid $pid) — применяю"
    apply launch
  fi
  last_pid="$pid"
  sleep "$POLL"
done
