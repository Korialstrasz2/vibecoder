#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook


assistantDir := A_ScriptDir
pttDir := assistantDir "\system\cache\ptt"
stopFile := pttDir "\stop.flag"
errorFile := pttDir "\last_error.txt"

DirCreate(pttDir)

pttActive := false
pttPid := 0

; Ctrl + Alt + Space = old fixed 8-second mode
^!Space:: {
    global assistantDir
    RunWait('cmd.exe /c "' assistantDir '\voice_to_clipboard_auto_v3.bat" 8"', , "Hide")
    Sleep 100
    Send "^v"
}

; Ctrl + Alt + Shift + Space = old fixed 20-second mode
^!+Space:: {
    global assistantDir
    RunWait('cmd.exe /c "' assistantDir '\voice_to_clipboard_auto_v3.bat" 20"', , "Hide")
    Sleep 100
    Send "^v"
}

; Push-to-talk: start when Ctrl + Win + Alt are all held.
; These variants make it work regardless of which modifier you press last.
*^#LAlt::MaybeStartPtt()
*^#RAlt::MaybeStartPtt()
*!#LControl::MaybeStartPtt()
*!#RControl::MaybeStartPtt()
*^!LWin::MaybeStartPtt()
*^!RWin::MaybeStartPtt()

; Stop when any member of the chord is released.
~*LControl Up::MaybeStopPtt()
~*RControl Up::MaybeStopPtt()
~*LAlt Up::MaybeStopPtt()
~*RAlt Up::MaybeStopPtt()
~*LWin Up::MaybeStopPtt()
~*RWin Up::MaybeStopPtt()

MaybeStartPtt() {
    global assistantDir, stopFile, errorFile, pttActive, pttPid

    if pttActive {
        return
    }

    if !(GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))) {
        return
    }

    pttActive := true
    pttPid := 0

    try FileDelete(stopFile)
    try FileDelete(errorFile)

    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' assistantDir '\scripts\push_to_clipboard_hold.ps1" -StopFile "' stopFile '"'

    Run(cmd, assistantDir, "Hide", &pttPid)
    ToolTip("Recording. Release Ctrl+Win+Alt to transcribe.")
}

MaybeStopPtt() {
    global stopFile, errorFile, pttActive, pttPid

    if !pttActive {
        return
    }

    if (GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))) {
        return
    }

    pttActive := false

    FileAppend("", stopFile)
    ToolTip("Transcribing...")

    if pttPid {
        try ProcessWaitClose(pttPid, 60)
    }

    if FileExist(errorFile) {
        err := FileRead(errorFile)
        ToolTip("Voice input failed: " err)
        SetTimer(() => ToolTip(), -4000)
        return
    }

    ToolTip("Copied to clipboard.")
    SetTimer(() => ToolTip(), -900)

    ; Uncomment this if you want it pasted automatically into the active app:
    ; Send "^v"
}