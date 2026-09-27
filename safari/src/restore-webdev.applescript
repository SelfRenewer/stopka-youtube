-- Стопка, откат: снимает «Показывать функции для веб-разработчиков».
-- Используется только из uninstall.sh --reset-safari.
-- Идемпотентно: если галочка уже снята — ничего не трогает.
-- «Разрешить неподписанные расширения» откатывать не нужно: этот флаг
-- живёт в памяти и сбрасывается сам при следующем запуске Safari.

property kAdvancedTabNames : {"Дополнения", "Advanced"}
property kWebDevFragments : {"еб-разработ", "web developer", "web-developer"}

on run
	tell application "System Events"
		if not (exists process "Safari") then return "safari-not-running"
	end tell
	tell application "System Events" to tell process "Safari"
		set frontmost to true
		delay 0.3
		keystroke "," using command down
		delay 1.5
		if not (exists window 1) then return "settings-window-missing"
		set w to window 1

		set found to my findWebDevCheckbox(w)
		if found is missing value then
			repeat with n in kAdvancedTabNames
				try
					click (first button of toolbar 1 of w whose name is (n as text))
					delay 0.8
					set found to my findWebDevCheckbox(w)
				end try
				if found is not missing value then exit repeat
			end repeat
		end if

		if found is missing value then
			keystroke "w" using command down
			return "webdev-checkbox-not-found"
		end if

		set res to "already-off"
		try
			if (value of found) as integer is 1 then
				click found
				set res to "turned-off"
			end if
		end try
		delay 0.4
		keystroke "w" using command down
		return res
	end tell
end run

on findWebDevCheckbox(w)
	tell application "System Events"
		try
			repeat with el in (entire contents of w)
				try
					if class of el is checkbox then
						set nm to (name of el) as text
						repeat with f in kWebDevFragments
							if nm contains (f as text) then return el
						end repeat
					end if
				end try
			end repeat
		end try
	end tell
	return missing value
end findWebDevCheckbox
