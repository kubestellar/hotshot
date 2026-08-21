; hotshot.ahk — AutoHotkey v2 hotkey wrapper for hotshot on Windows.
; Optional alternative to the Start Menu shortcut hotkey created by
; install.ps1: AutoHotkey reacts instantly and lets you pick any binding.
;
; Requires AutoHotkey v2 (https://www.autohotkey.com). Run this script (or
; drop a shortcut to it in shell:startup) and press Ctrl+Shift+PrintScreen.
#Requires AutoHotkey v2.0
#SingleInstance Force

HotshotCapture(*) {
    script := A_ScriptDir "\hotshot-capture.ps1"
    if !FileExist(script) {
        MsgBox "hotshot-capture.ps1 not found next to hotshot.ahk (" script ")", "hotshot", "Iconx"
        return
    }
    Run 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' script '"', , "Hide"
}

; Ctrl+Shift+PrintScreen — change to taste.
^+PrintScreen::HotshotCapture()
