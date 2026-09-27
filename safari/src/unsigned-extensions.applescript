-- Стопка: включает «Разрешить неподписанные расширения» в Safari.
--
-- Safari 26 убрал этот пункт из меню «Разработка» — он живёт в
-- Настройки → Разработчик, поэтому скрипт работает с окном настроек.
--
-- Идемпотентность: состояние читается из AXValue чекбокса. Если флажок
-- уже стоит — клика не будет. Если Safari не запущен — тихий выход.
--
-- Трогает ровно две настройки и ничего сверх них:
--   1. «Показывать функции для веб-разработчиков» (Настройки → Дополнения)
--      — и только если вкладки «Разработчик» ещё нет;
--   2. «Разрешить неподписанные расширения» (Настройки → Разработчик).
--
-- Права: Универсальный доступ для /usr/bin/osascript + Автоматизация
-- (Safari, System Events).
--
-- Окно настроек адресуется по индексу, а не по имени: имя окна совпадает
-- с названием открытой вкладки и меняется при каждом переключении, из-за
-- чего сохранённая по имени ссылка протухает посреди работы.

property kSettingsMarker : {"Основные", "General"}
property kDeveloperTab : {"Разработчик", "Developer"}
property kAdvancedTab : {"Дополнения", "Advanced"}
property kUnsignedFragments : {"еподписанн", "nsigned"}
property kWebDevFragments : {"еб-разработ", "web developer", "web-developer"}

-- Режимы:
--   без аргументов — включить флаг осторожно: Safari мог работать давно,
--     флаг может уже стоять, поэтому перед кликом честное чтение с
--     перерисовкой панели, после клика — проверка переоткрытием окна.
--     Так зовёт build.sh и сторож, заставший Safari уже открытым;
--   "launch" — сторож только что увидел новый процесс Safari. Флаг
--     сбрасывается при каждом старте, так что он заведомо выключен:
--     сразу на вкладку «Разработчик», клик, закрыть. Без пляски по
--     вкладкам до галочки и без переоткрытия окна после;
--   "check" — только прочитать состояние, ничего не кликая.
on run argv
	if argv contains "check" then
		set s to my checkState()
		my logLine("проверка: " & s)
		return s
	end if
	set s to my applyFix(argv contains "launch")
	my logLine(s)
	return s
end run


on checkState()
	tell application "System Events"
		if not (exists process "Safari") then return "safari-not-running"
	end tell
	set mb to my waitForMenuBar(20)
	if mb is not "ok" then return mb
	set wasOpen to (my findSettings() > 0)
	set idx to my openSettings()
	if idx is 0 then return "settings-window-missing"
	if not my tabExists(idx, kDeveloperTab) then
		my closeSettings(idx, wasOpen)
		return "developer-tab-missing"
	end if
	my clickTab(idx, kDeveloperTab)
	if not my waitCheckbox(idx, kUnsignedFragments, 20) then
		my closeSettings(idx, wasOpen)
		return "unsigned-checkbox-not-found"
	end if
	my refreshPane(idx)
	set v to my readCheckbox(idx, kUnsignedFragments)
	my closeSettings(idx, wasOpen)
	if v is 1 then return "state-on"
	return "state-off"
end checkState


on applyFix(freshLaunch)
	tell application "System Events"
		if not (exists process "Safari") then return "safari-not-running"
	end tell

	-- Safari поднимает интерфейс не мгновенно; скрипт, запущенный по факту
	-- запуска, иначе видит недособранное окно.
	set mb to my waitForMenuBar(20)
	if mb is not "ok" then return mb

	set wasOpen to (my findSettings() > 0)
	set idx to my openSettings()
	if idx is 0 then return "settings-window-missing"

	-- Вкладка «Разработчик» появляется только когда включены функции
	-- веб-разработчика: её наличие и есть проверка первой галочки.
	if not my tabExists(idx, kDeveloperTab) then
		set r to my enableWebDev(idx)
		if r is not "ok" then
			my closeSettings(idx, wasOpen)
			return r
		end if
		delay 1.0
		set idx to my findSettings()
		if idx is 0 then return "settings-window-lost"
		if not my tabExists(idx, kDeveloperTab) then
			my closeSettings(idx, wasOpen)
			return "developer-tab-missing"
		end if
	end if

	my clickTab(idx, kDeveloperTab)
	if not my waitCheckbox(idx, kUnsignedFragments, 20) then
		my closeSettings(idx, wasOpen)
		return "unsigned-checkbox-not-found"
	end if

	-- Первое чтение тоже бывает несвежим: пока панель не перерисовалась,
	-- AXValue отдаёт ноль независимо от реального состояния — и скрипт
	-- выключил бы уже стоящую галочку вместо того, чтобы её не трогать.
	-- Лечится уходом на соседнюю вкладку и возвратом, но это и есть то
	-- мельтешение, которое видно при открытии Safari. На свежем запуске
	-- оно не нужно: флаг сброшен, «ноль» — правда. За месяц лога ни один
	-- свежий запуск не застал флаг включённым. Чтение ниже всё равно
	-- делаем: несвежее значение всегда ноль, так что единица — настоящая,
	-- и если пользователь успел поставить галочку сам, мы её не снимем.
	if not freshLaunch then my refreshPane(idx)

	if my readCheckbox(idx, kUnsignedFragments) is 1 then
		my closeSettings(idx, wasOpen)
		return "already-on"
	end if

	-- Клик проходит только когда окно настроек активно: в фоне AX
	-- рапортует успех, а состояние не меняется. Поднимаем Safari прямо
	-- перед кликом и без подтверждённого фронта не кликаем вовсе.
	tell application "Safari" to activate
	if not my waitFrontmost(20) then
		my closeSettings(idx, wasOpen)
		return "safari-not-frontmost"
	end if

	-- Ответ clickCheckbox обязателен к проверке: он глотает ошибку AX и
	-- возвращает false, а рапортовать «нажал» вслепую нельзя.
	if not my clickCheckbox(idx, kUnsignedFragments) then
		my closeSettings(idx, wasOpen)
		return "click-failed"
	end if
	delay 0.8

	-- Проверка ниже закрывает окно, открывает заново и снова идёт на
	-- вкладку — ещё одно мигание. На свежем запуске она бесполезна: сторож
	-- возвращает расширение при любом исходе клика, а на повторный прогон
	-- в этом процессе Safari не пойдёт. Да и подтверждала она редко —
	-- неделю подряд отвечала clicked-unverified.
	if freshLaunch then
		my closeSettings(idx, wasOpen)
		return "clicked"
	end if

	-- Заново открытое окно — единственный способ получить честное значение.
	-- Перерисовки вкладкой после клика не хватает, а без подтверждения
	-- следующий прогон принимает включённую галочку за выключенную и гасит
	-- её. Проверено дорого: попытка сэкономить эти секунды каждый раз
	-- оставляла флаг выключенным.
	my forceCloseSettings(idx)
	delay 1.0
	set idx to my openSettings()
	if idx is 0 then return "clicked-unverified"
	my clickTab(idx, kDeveloperTab)
	my waitCheckbox(idx, kUnsignedFragments, 20)
	set v to my readCheckbox(idx, kUnsignedFragments)
	my closeSettings(idx, wasOpen)

	if v is 1 then return "turned-on"
	return "clicked-unverified"
end applyFix


-- Свойство `UI elements enabled` врёт: оно отдаёт false и там, где AX
-- прекрасно работает. Поэтому наличие прав определяем по реальной ошибке.
on waitForMenuBar(tries)
	set lastErr to ""
	repeat with i from 1 to tries
		try
			tell application "System Events" to tell process "Safari"
				if (count of menu bar items of menu bar 1) > 3 then return "ok"
			end tell
		on error errMsg
			set lastErr to errMsg
		end try
		delay 0.5
	end repeat
	if lastErr contains "assistive" or lastErr contains "ссистивн" or lastErr contains "спомогательн" or lastErr contains "прощен" or lastErr contains "прощён" then
		return "no-accessibility: " & lastErr
	end if
	if lastErr is not "" then return "menubar-error: " & lastErr
	return "menubar-timeout"
end waitForMenuBar


-- Индекс окна настроек или 0. Опознаём по вкладке «Основные»: у обычного
-- окна Safari тоже есть toolbar, по нему одному их не различить.
on findSettings()
	tell application "System Events" to tell process "Safari"
		repeat with i from 1 to (count of windows)
			try
				if exists toolbar 1 of window i then
					repeat with n in kSettingsMarker
						if exists (first button of toolbar 1 of window i whose title is (n as text)) then
							return i
						end if
					end repeat
				end if
			end try
		end repeat
	end tell
	return 0
end findSettings


on openSettings()
	-- Именно activate приложения, а не frontmost процесса: пока окно не
	-- отрисовано, AX отдаёт значения по умолчанию, и «уже включено»
	-- неотличимо от «выключено».
	tell application "Safari" to activate
	my waitFrontmost(20)
	-- Окна могут быть скрыты (⌘H) — тогда System Events их не видит,
	-- и открыть настройки не получится, пока приложение не показано.
	try
		tell application "System Events" to set visible of process "Safari" to true
	end try
	set idx to my findSettings()

	-- Сразу после запуска Safari окно настроек открывается не с первого
	-- раза: ⌘, может уйти в ещё не готовое окно. Поэтому две попытки
	-- с раздельным ожиданием, а не одна.
	repeat with attempt from 1 to 2
		if idx > 0 then exit repeat
		tell application "Safari" to activate
		-- keystroke всегда уходит во фронтовое приложение, независимо от
		-- того, кому адресован tell. Если Safari поднять не удалось, ⌘,
		-- открыл бы настройки чужого приложения — поэтому не шлём вслепую.
		if not my waitFrontmost(20) then exit repeat
		tell application "System Events" to tell process "Safari"
			try
				keystroke "," using command down
			end try
		end tell
		repeat with i from 1 to 20
			delay 0.5
			set idx to my findSettings()
			if idx > 0 then exit repeat
		end repeat
	end repeat
	if idx is 0 then return 0
	try
		tell application "System Events" to tell process "Safari" to perform action "AXRaise" of window idx
	end try
	delay 0.5
	return idx
end openSettings


-- Если окно настроек было открыто до нас — оставляем как было.
-- Закрываем только кнопкой самого окна. Никакого ⌘W в запасе: если окно
-- настроек не найдётся, сочетание уйдёт во фронтовое окно Safari и закроет
-- вкладку пользователя. Лучше оставить настройки открытыми.
on closeSettings(idx, wasOpen)
	if wasOpen then return
	tell application "System Events" to tell process "Safari"
		try
			click (first button of window idx whose subrole is "AXCloseButton")
		end try
	end tell
end closeSettings


-- AX отдаёт прежнее значение чекбокса, пока панель не перерисовалась —
-- причём стабильно, так что повторными чтениями это не лечится. Уход на
-- соседнюю вкладку и возврат ничего не меняет в настройках, но заставляет
-- панель перерисоваться, и состояние становится честным.
on refreshPane(idx)
	my clickTab(idx, kSettingsMarker)
	delay 0.8
	my clickTab(idx, kDeveloperTab)
	my waitCheckbox(idx, kUnsignedFragments, 20)
end refreshPane


-- Панель настроек рисуется не мгновенно; ждём именно появления элемента,
-- а не «достаточно длинной» паузы.
on waitCheckbox(idx, fragments, tries)
	repeat with i from 1 to tries
		if (my findCheckbox(idx, fragments)) is 1 then return true
		delay 0.5
	end repeat
	return false
end waitCheckbox


on waitFrontmost(tries)
	repeat with i from 1 to tries
		try
			tell application "System Events" to tell process "Safari"
				if frontmost then return true
			end tell
		end try
		delay 0.5
	end repeat
	return false
end waitFrontmost


on forceCloseSettings(idx)
	tell application "System Events" to tell process "Safari"
		try
			click (first button of window idx whose subrole is "AXCloseButton")
		end try
	end tell
end forceCloseSettings


on tabExists(idx, names)
	tell application "System Events" to tell process "Safari"
		repeat with n in names
			try
				if exists (first button of toolbar 1 of window idx whose title is (n as text)) then return true
			end try
		end repeat
	end tell
	return false
end tabExists


on clickTab(idx, names)
	tell application "System Events" to tell process "Safari"
		repeat with n in names
			try
				click (first button of toolbar 1 of window idx whose title is (n as text))
				return true
			end try
		end repeat
	end tell
	return false
end clickTab


-- Чекбоксы лежат на третьем уровне вложенности (окно → группа → группа),
-- а `entire contents` на этих SwiftUI-панелях отдаёт битые ссылки.
-- Возвращаем не ссылку, а путь до элемента: сохранённая ссылка отдаёт
-- закэшированное значение и после клика продолжает врать.
on walk(el, fragments, depth)
	if depth > 8 then return missing value
	tell application "System Events"
		set kids to {}
		try
			set kids to UI elements of el
		end try
		repeat with k in kids
			set r to ""
			try
				set r to role of k
			end try
			if r is "AXCheckBox" then
				set t to ""
				try
					set t to (title of k) as text
				end try
				repeat with f in fragments
					if t contains (f as text) then return contents of k
				end repeat
			end if
			set found to my walk(k, fragments, depth + 1)
			if found is not missing value then return found
		end repeat
	end tell
	return missing value
end walk


on findCheckbox(idx, fragments)
	set el to missing value
	try
		tell application "System Events" to tell process "Safari"
			set el to my walk(window idx, fragments, 0)
		end tell
	end try
	if el is missing value then return 0
	return 1
end findCheckbox


on clickCheckbox(idx, fragments)
	try
		tell application "System Events" to tell process "Safari"
			set el to my walk(window idx, fragments, 0)
			if el is missing value then return false
			click el
		end tell
	on error
		return false
	end try
	return true
end clickCheckbox


-- Ищем элемент заново на каждой попытке и ждём двух совпавших чтений.
on readCheckbox(idx, fragments)
	set prev to -2
	repeat with i from 1 to 14
		set v to -1
		try
			tell application "System Events" to tell process "Safari"
				set el to my walk(window idx, fragments, 0)
				if el is not missing value then
					try
						set v to (value of el) as integer
					end try
				end if
			end tell
		end try
		if v is prev and v is not -1 then return v
		set prev to v
		delay 0.5
	end repeat
	if prev is less than 0 then return 0
	return prev
end readCheckbox


on enableWebDev(idx)
	if not my clickTab(idx, kAdvancedTab) then return "advanced-tab-missing"
	if not my waitCheckbox(idx, kWebDevFragments, 20) then return "webdev-checkbox-not-found"
	if my readCheckbox(idx, kWebDevFragments) is 0 then
		tell application "Safari" to activate
		if not my waitFrontmost(20) then return "safari-not-frontmost"
		if not my clickCheckbox(idx, kWebDevFragments) then return "webdev-click-failed"
		delay 0.8
	end if
	return "ok"
end enableWebDev


-- Статус пишем сами: скрипт зовут из сторожа, его stdout уходит в никуда.
on logLine(s)
	set logPath to (POSIX path of (path to home folder)) & "Library/Logs/stopka-keeper.log"
	try
		do shell script "printf '%s applescript %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" " & quoted form of (s as text) & " >> " & quoted form of logPath
	end try
end logLine
