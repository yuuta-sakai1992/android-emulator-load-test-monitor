#Requires AutoHotkey v2.0
#SingleInstance Force

; ==================================
; 管理者権限への自動昇格処理
; ==================================
cmd := DllCall("GetCommandLine", "str")
isRst := RegExMatch(cmd, " /restart(?!\S)")
if not (A_IsAdmin || isRst) {
  try {
    p_auth := A_ScriptFullPath
    if A_IsCompiled
      Run '*RunAs "' . p_auth . '" /restart'
    else
      Run '*RunAs "' . p_auth . '" /restart "' . p_auth . '"'
  }
  ExitApp
}

ListLines 0
ProcessSetPriority "High"
CoordMode "Pixel", "Screen"   ;
CoordMode "Mouse", "Screen"   ;

; ==================================
; システム共通グローバル宣言
; ==================================
global SCRIPT_DIR := A_ScriptDir . "\", IMG_DIR := SCRIPT_DIR . "img\", ERROR_LOG_DIR := SCRIPT_DIR . "error_logs\"
global REPORT_DIR := SCRIPT_DIR . "reports\", METRICS_CSV := REPORT_DIR . "metrics_log.csv", EVENTS_CSV := REPORT_DIR . "events_log.csv", REPORT_HTML := REPORT_DIR . "test_report.html"
global INI_FILE := SCRIPT_DIR . "mode_config.ini", LOG_FILE := SCRIPT_DIR . "load_test_log.txt"
global BS_PATH := "C:\Program Files\BlueStacks_nxt", BS_INSTANCE := "Pie64"
global ADB_EXE := "C:\Program Files\BlueStacks_nxt\HD-Adb.exe", ADB_PORT := "127.0.0.1:5555"
global MODE_SELECTION := 2, CURRENT_STAGE_COUNT := 0, ORIGINAL_BRIGHTNESS := 50
global IS_SCREEN_OFF_ENABLED := false, IS_SUSPEND_SCREEN_OFF := false
global IS_CYCLE_RESTART_ENABLED := 1, IS_MEM_CLEAR_ENABLED := 1, SHUTDOWN_TARGET_TIME := "", IS_SHUTDOWN_TRIGGERED := false
global MONITOR_INTERVAL_MS := 10000, MEM_CLEAR_INTERVAL_MS := 10000, MEM_CLEAR_KEY := "q", SS_CAPTURE_MODE := 1, IS_ADB_LOG_ENABLED := 1, ADB_LOG_MINUTES := 3
global AUTO_RESTART_MODE := 1, IS_CRASH_HANDLED := false
global IS_WEBHOOK_ENABLED := 0, WEBHOOK_URL := "", IS_WEBHOOK_WARN_ENABLED := 0
global LogStatus := "", LogAction := "", LogNextOff := "", LogNextMonitor := ""
global BtnStageToggle := "", EditSDTime := "", LogSDStatus := "", BtnCycleToggle := ""
global SESSION_START_TICK := A_TickCount, LAST_EVIDENCE_TS := ""

global TARGET_EXE := "ahk_exe HD-Player.exe"

GetMonitorActionText() {
  global CURRENT_STAGE_COUNT
  return "高負荷検証モード（第 " . CURRENT_STAGE_COUNT . " サイクル検証中）。監視スキャン稼働中。"
}

UpdateLog(statusText, actionText, writeFile := true) {
  global LogStatus, LogAction
  try {
    if (LogStatus != "")
      LogStatus.Text := "状態: " . statusText
    if (LogAction != "")
      LogAction.Text := "動作: " . actionText
  }
  if (writeFile)
    WriteToFile("[" . statusText . "] " . actionText)
}

UpdateLogNextOff(text) {
  global LogNextOff
  try {
    if (LogNextOff != "")
      LogNextOff.Text := "暗転: " . text
  }
  WriteToFile("[暗転] " . text)
}

WriteToFile(text) {
  global LOG_FILE
  try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . " - " . text . "`n", LOG_FILE, "UTF-8")
}

SaveModeToIni(modeNum) {
  global INI_FILE
  try IniWrite(modeNum, INI_FILE, "Settings", "Mode")
}
SaveShutdownTimeRuntime() {
  global EditSDTime, LogSDStatus, INI_FILE, SHUTDOWN_TARGET_TIME
  timeStr := RegExReplace(EditSDTime.Text, "\D") 
  if (timeStr = "") {
    SHUTDOWN_TARGET_TIME := "", LogSDStatus.Text := "制限なし"
    try IniWrite("", INI_FILE, "Settings", "ShutdownTime")
    MsgBox("シャットダウン連動制限を解除しました。", "通知", "IconI T2")
    return
  }
  if (StrLen(timeStr) != 12) {
    MsgBox("入力エラー：数字12桁で指定してください。", "エラー", "IconX")
    return
  }
  SHUTDOWN_TARGET_TIME := timeStr
  LogSDStatus.Text := "設定中: " . SubStr(timeStr, 5, 2) . "/" . SubStr(timeStr, 7, 2) . " " . SubStr(timeStr, 9, 2) . ":" . SubStr(timeStr, 11, 2)
  try IniWrite(timeStr, INI_FILE, "Settings", "ShutdownTime")
  MsgBox("シャットダウン予定時刻を保存しました。", "成功", "IconI T2")
}

CheckShutdownTimer() {
  global SHUTDOWN_TARGET_TIME, IS_SHUTDOWN_TRIGGERED, INI_FILE, MODE_SELECTION
  if (SHUTDOWN_TARGET_TIME == "")
    return
  d := DateDiff(SHUTDOWN_TARGET_TIME, A_Now, "Minutes")
  if (d < 0) {
    SHUTDOWN_TARGET_TIME := ""
    try IniWrite("", INI_FILE, "Settings", "ShutdownTime")
    global LogSDStatus
    if (LogSDStatus != "")
      LogSDStatus.Text := "制限なし"
    return
  }
  if (d > 5 && d <= 7 && MODE_SELECTION == 1) {
    SaveModeToIni(2), ChangeModeRuntime(2, false, false), SetDisplayBrightness(10)
    UpdateLog("シャットダウン準備", "PC終了7分前：暗転を先行解除しました。")
  }
  if (!IS_SHUTDOWN_TRIGGERED && d <= 5) {
    IS_SHUTDOWN_TRIGGERED := true
    UpdateLog("シャットダウン連動", "⚠️PC終了5分前。検証アプリの安全終了シーケンスを開始します。")
    SafeCloseSequence(false)   
  }
}

ToggleStageCountRuntime() {
  global CURRENT_STAGE_COUNT, BtnStageToggle, INI_FILE
  CURRENT_STAGE_COUNT := CURRENT_STAGE_COUNT >= 12 ? 0 : CURRENT_STAGE_COUNT + 1
  if (BtnStageToggle != "")
    BtnStageToggle.Text := "🔄 検証ステージ切替 [現在: " . CURRENT_STAGE_COUNT . "サイクル目]"
  try IniWrite(CURRENT_STAGE_COUNT, INI_FILE, "Settings", "StageCount")
  UpdateMonitorTimeDisplay(), UpdateLogCurrentStageText() 
}

ToggleCycleRestartRuntime() {
  global IS_CYCLE_RESTART_ENABLED, BtnCycleToggle
  IS_CYCLE_RESTART_ENABLED := !IS_CYCLE_RESTART_ENABLED
  flg := IS_CYCLE_RESTART_ENABLED ? "【ON】" : "【OFF】"
  if (BtnCycleToggle != "")
    BtnCycleToggle.Text := "🔁 2時間再起動: " . flg
  UpdateLog("モード切替", "2時間定時再起動リセットを " . flg . " にしました。")
}

UpdateMonitorTimeDisplay() {
  global CURRENT_STAGE_COUNT, LogNextMonitor
  if (LogNextMonitor != "")
    LogNextMonitor.Text := "監視: 10分毎の定期ポーリング実行中"
}

UpdateLogCurrentStageText(writeFile := false) {
  global CURRENT_STAGE_COUNT
  UpdateLog("高負荷検証モード", GetMonitorActionText(), writeFile)
}

MonitorSystemWake() {
  if (MODE_SELECTION == 1 && IS_SCREEN_OFF_ENABLED && !IS_SUSPEND_SCREEN_OFF)
    SendMessage(0x112, 0xF170, 2,, "Program Manager")
}

TriggerManualRestartWithAuth() {
  global IS_SUSPEND_SCREEN_OFF, ORIGINAL_BRIGHTNESS
  IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager"), SetDisplayBrightness(ORIGINAL_BRIGHTNESS)
  n := Random(1, 9), g := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow", "安全認証ストッパー")
  g.SetFont("s11 Bold", "Segoe UI"), g.Add("Text", "w260 Center cRed", "⚠️ 誤操作防止システム"), g.Add("Text", "w260 Center y+5", "本当にシステムを強制再起動しますか？")
  lbl := g.Add("Text", "w260 Center y+5", "【 " . n . " 】 のボタンをタップしてください"), lbl.SetFont("cBlue s12 Bold")
  Loop 9 {
    x := (Mod(A_Index-1, 3) == 0) ? "x45 y+10" : "x+10"
    g.Add("Button", x . " w50 h40", A_Index).OnEvent("Click", (ctrl, *) => OnAuthButtonClick(ctrl, g, n))
  }
  g.Add("Button", "x45 y+15 w170 h35", "❌ キャンセル").OnEvent("Click", (ctrl, *) => (g.Destroy(), CancelManualRestart())), g.Show("Center")
}

OnAuthButtonClick(ctrl, AuthGui, n) {
  res := Integer(ctrl.Text), AuthGui.Destroy()
  if (res == n)
    ExecuteManualRestart()
  else
    CancelManualRestart()
}

CancelManualRestart() {
  global IS_SUSPEND_SCREEN_OFF, MODE_SELECTION, IS_SCREEN_OFF_ENABLED, LogStatus
  if (LogStatus != "" && (InStr(LogStatus.Text, "標準検証") || InStr(LogStatus.Text, "検証") || InStr(LogStatus.Text, "高負荷"))) {
    IS_SUSPEND_SCREEN_OFF := false
    if (MODE_SELECTION == 1 && IS_SCREEN_OFF_ENABLED)
      Sleep(300), SendMessage(0x112, 0xF170, 2,, "Program Manager")
  }
}
ExecuteManualRestart() {
  global IS_SUSPEND_SCREEN_OFF, CURRENT_STAGE_COUNT, INI_FILE
  UpdateLog("手動再起動", "ユーザーの認証承認を検知。安全中断シークエンスを開始します...")
  Sleep(500), ExitApp(10)
}

ManualPauseTrigger(HotkeyName) {
  global ORIGINAL_BRIGHTNESS
  SendMessage(0x112, 0xF170, -1,, "Program Manager"), SetDisplayBrightness(ORIGINAL_BRIGHTNESS)
  SaveSessionElapsedSeconds()
  GenerateHtmlReport(false)
  WriteToFile("--- ユーザーの手動Pauseにより中断されました ---"), ExitApp(0)
}

CheckHotkeys(HotkeyName) {
  if (MODE_SELECTION == 1 && ((GetKeyState("PgUp", "P") && GetKeyState("PgDn", "P")) || (GetKeyState("Home", "P") && GetKeyState("End", "P"))))
    Sleep(300), SaveModeToIni(2), ChangeModeRuntime(2), MsgBox("キー常時点灯切替を検出しました。", "通知", "IconI T2")
}

InitializeMacro() {
  global CURRENT_STAGE_COUNT, MODE_SELECTION, INI_FILE, LOG_FILE, SHUTDOWN_TARGET_TIME
  try {
    SplitPath(INI_FILE, , &iniDir), (iniDir != "" && !DirExist(iniDir) && DirCreate(iniDir))
  }
  isBth := false
  if (A_Args.Length > 0) {
    Loop A_Args.Length
      if (A_Args[A_Index] == "auto_start") {
        isBth := true
        break
      }
  }
  if FileExist(INI_FILE) {
    try {
      global MONITOR_INTERVAL_MS, MEM_CLEAR_INTERVAL_MS, MEM_CLEAR_KEY, IS_MEM_CLEAR_ENABLED, SS_CAPTURE_MODE, IS_ADB_LOG_ENABLED, ADB_LOG_MINUTES, ADB_EXE, ADB_PORT, TARGET_EXE, IS_WEBHOOK_ENABLED, WEBHOOK_URL, IS_WEBHOOK_WARN_ENABLED, AUTO_RESTART_MODE, BS_PATH, BS_INSTANCE
      MODE_SELECTION := Integer(IniRead(INI_FILE, "Settings", "Mode", "2"))
      CURRENT_STAGE_COUNT := Integer(IniRead(INI_FILE, "Settings", "StageCount", "1"))
      SHUTDOWN_TARGET_TIME := IniRead(INI_FILE, "Settings", "ShutdownTime", "")
      MONITOR_INTERVAL_MS := Integer(IniRead(INI_FILE, "Settings", "MonitorInterval", "10000"))
      MEM_CLEAR_INTERVAL_MS := Integer(IniRead(INI_FILE, "Settings", "MemClearInterval", "10000"))
      MEM_CLEAR_KEY := IniRead(INI_FILE, "Settings", "MemClearKey", "q")
      SS_CAPTURE_MODE := Integer(IniRead(INI_FILE, "Settings", "SSCaptureMode", "1"))
      IS_ADB_LOG_ENABLED := Integer(IniRead(INI_FILE, "Settings", "AdbLogEnabled", "1"))
      ADB_LOG_MINUTES := Integer(IniRead(INI_FILE, "Settings", "AdbLogMinutes", "3"))
      AUTO_RESTART_MODE := Integer(IniRead(INI_FILE, "Settings", "AutoRestartMode", "1"))
      BS_INSTANCE := IniRead(INI_FILE, "Paths", "InstanceName", BS_INSTANCE)
      BS_PATH := IniRead(INI_FILE, "Paths", "BlueStacksPath", BS_PATH)
      ADB_EXE := IniRead(INI_FILE, "Paths", "AdbPath", ADB_EXE)
      ADB_PORT := IniRead(INI_FILE, "Paths", "AdbPort", ADB_PORT)
      TARGET_EXE := IniRead(INI_FILE, "Paths", "TargetExe", TARGET_EXE)
      IS_WEBHOOK_ENABLED := Integer(IniRead(INI_FILE, "Webhook", "Enabled", "0"))
      WEBHOOK_URL := Trim(IniRead(INI_FILE, "Webhook", "Url", ""), ' "')
      IS_WEBHOOK_WARN_ENABLED := Integer(IniRead(INI_FILE, "Webhook", "NotifyWarning", "0"))
      if (MEM_CLEAR_INTERVAL_MS <= 0)
        IS_MEM_CLEAR_ENABLED := 0
      if (SHUTDOWN_TARGET_TIME != "" && DateDiff(SHUTDOWN_TARGET_TIME, A_Now, "Minutes") < 0)
        SHUTDOWN_TARGET_TIME := "", IniWrite("", INI_FILE, "Settings", "ShutdownTime")
      if (!isBth)
        MODE_SELECTION := 2, SaveModeToIni(2), WriteToFile("--- 手動起動 (常時点灯環境で安全開始) ---")
      else
        WriteToFile("--- 自動再起動 (前回モードを引き継ぎ) ---")
    } catch
      MODE_SELECTION := 2, CURRENT_STAGE_COUNT := 1, SHUTDOWN_TARGET_TIME := "", WriteToFile("--- 起動 (INI破損デフォルト) ---")
  } else {
    WriteToFile("--- 起動 (新規生成) ---")
    SaveModeToIni(2)
    IniWrite(CURRENT_STAGE_COUNT, INI_FILE, "Settings", "StageCount")
    IniWrite("", INI_FILE, "Settings", "ShutdownTime")
    IniWrite(ADB_EXE, INI_FILE, "Paths", "AdbPath")
    IniWrite(ADB_PORT, INI_FILE, "Paths", "AdbPort")
    IniWrite(TARGET_EXE, INI_FILE, "Paths", "TargetExe")
  }
  StartMacro(MODE_SELECTION)
}

StartMacro(modeNum) {
  global MODE_SELECTION, IS_SCREEN_OFF_ENABLED, LogStatus, LogAction, LogNextOff, LogNextMonitor, BtnStageToggle, CURRENT_STAGE_COUNT, EditSDTime, LogSDStatus, SHUTDOWN_TARGET_TIME, BtnCycleToggle, IS_CYCLE_RESTART_ENABLED, IS_MEM_CLEAR_ENABLED
  MODE_SELECTION := modeNum
  if WinExist("アプリケーション耐久負荷テスト 監視エビデンス")
    return
  g := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "アプリケーション耐久負荷テスト 監視エビデンス"), g.SetFont("s10", "Segoe UI")
  g.OnEvent("Close", (*) => (SaveSessionElapsedSeconds(), GenerateHtmlReport(false), WriteToFile("--- GUIの閉じるボタンにより終了しました ---"), ExitApp(0)))

  LogStatus := g.Add("Text", "w280 r1", "状態: 初期化中..."), LogAction := g.Add("Text", "w280 r2", "動作: ログ生成中...")
  LogNextOff := g.Add("Text", "w280 r1 cRed", "暗転: 計算中...")
  LogNextMonitor := g.Add("Text", "w280 r1 cGreen", ""), g.SetFont("s9")
  g.Add("GroupBox", "w280 h70 y+10 cRed", "PCシャットダウン安全中断連動"), g.Add("Text", "xp+10 yp+20", "予定日時:")
  EditSDTime := g.Add("Edit", "x+5 w120 h20", SHUTDOWN_TARGET_TIME), btn := g.Add("Button", "x+5 w50 h22", "保存"), btn.OnEvent("Click", (c, *) => SaveShutdownTimeRuntime())
  LogSDStatus := g.Add("Text", "x15 y+12 w280 r1 cRed", "制限なし")
  if (SHUTDOWN_TARGET_TIME != "")
    LogSDStatus.Text := "設定中: " . SubStr(SHUTDOWN_TARGET_TIME, 5, 2) . "/" . SubStr(SHUTDOWN_TARGET_TIME, 7, 2) . " " . SubStr(SHUTDOWN_TARGET_TIME, 9, 2) . ":" . SubStr(SHUTDOWN_TARGET_TIME, 11, 2)
  g.Add("GroupBox", "w280 h130 y+10 cBlue", "テストシナリオ動的切替")
  BtnCycleToggle := g.Add("Button", "xp+15 yp+20 w250 h30", "🔁 2時間再起動: " . (IS_CYCLE_RESTART_ENABLED ? "【ON】" : "【OFF】")), BtnCycleToggle.OnEvent("Click", (c, *) => ToggleCycleRestartRuntime())
  g.Add("Button", "x15 y+10 w120 h25", "🌙今すぐ消灯").OnEvent("Click", (c, *) => (SaveModeToIni(1), ChangeModeRuntime(1, true, true)))
  g.Add("Button", "x+10 w120 h25", "☀️常時点灯").OnEvent("Click", (c, *) => (SaveModeToIni(2), ChangeModeRuntime(2, true, false)))
  g.SetFont("s10 Bold")
  BtnStageToggle := g.Add("Button", "x15 y+15 w280 h35", "🔄 検証ステージ切替 [現在: " . CURRENT_STAGE_COUNT . "サイクル目]"), BtnStageToggle.OnEvent("Click", (c, *) => ToggleStageCountRuntime())
  g.Add("Button", "x15 y+10 w280 h32", "⏸️ 一括監視オフ (設定変更用)").OnEvent("Click", (c, *) => DisableAllMonitorsForConfig())
  g.Add("Button", "x15 y+10 w280 h32", "⚙️ 詳細設定 (監視頻度・メモリ解放)").OnEvent("Click", (c, *) => OpenDetailSettingsGui())
  g.Add("Button", "x15 y+10 w280 h32", "📊 テストレポート出力・表示").OnEvent("Click", (c, *) => (SaveSessionElapsedSeconds(), GenerateHtmlReport(true)))
  g.Add("Button", "x15 y+10 w280 h32", "🆕 テスト記録を新規リセット").OnEvent("Click", (c, *) => ResetTestReportWithArchive())
  g.Add("Button", "x15 y+10 w280 h32 cRed", "🔄 今すぐ再起動 (安全ストッパー付)").OnEvent("Click", (c, *) => TriggerManualRestartWithAuth()), g.Show("X1300 Y560 NoActivate")
  ChangeModeRuntime(MODE_SELECTION, false, false), UpdateMonitorTimeDisplay()
  Hotkey("Pause", ManualPauseTrigger, "On"), Hotkey("~PgUp", CheckHotkeys, "On"), Hotkey("~PgDn", CheckHotkeys, "On"), Hotkey("~Home", CheckHotkeys, "On"), Hotkey("~End", CheckHotkeys, "On")
  SetTimer(MonitorSystemWake, 5000), SetTimer(CheckShutdownTimer, 10000), SetTimer(MainWorkflow, -1)
}
LaunchAndStartTestApp() {
  global TARGET_EXE, IS_SUSPEND_SCREEN_OFF
  UpdateLog("アプリ起動", "エミュレータの起動とダミーアプリのアイコンを探索中...")

  ; 1. ホーム画面のアプリアイコンが出るまで待機（最大60秒）
  startWait := A_TickCount
  appLaunched := false
  Loop {
    if (A_TickCount - startWait >= 60000) {
      IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager"), Sleep(200)
      UpdateLog("起動失敗", "⚠️60秒経過してもアプリアイコン（app_launcher_icon.bmp）を検知できませんでした。")
      PrepareEvidenceTimestamp()
      CaptureErrorScreenshot("launch_timeout")
      CaptureAdbLogcat("launch_timeout")
      RecordTestEvent("LAUNCH_TIMEOUT", "60秒経過してもアプリアイコン未検知", "launch_timeout")
      SendWebhookNotification("LAUNCH_TIMEOUT", "60秒経過してもアプリアイコン未検知が発生しました。", "launch_timeout")
      SaveSessionElapsedSeconds()
      GenerateHtmlReport(false)
      ExecuteErrorRecoveryByMode()
      break
    }
    if ChkImg("app_launcher_icon.bmp") {
      UpdateLog("アプリ起動", "アプリアイコンを検知。クリックしてアプリを起動します。")
      ClickImg("app_launcher_icon.bmp")
      appLaunched := true
      break
    }
    ; すでにアプリが起動済み（「開始」ボタンが見えている）場合はスキップ
    if ChkImg("app_start_btn.bmp") {
      UpdateLog("アプリ起動", "すでにアプリが起動していることを検知しました。")
      appLaunched := true
      break
    }
    Sleep(1000)
  }

  ; 2. アプリ起動後、「開始」ボタンが表示されたら自動で押す（最大30秒待機）
  if (appLaunched) {
    Sleep(2000)
    startBtnWait := A_TickCount
    Loop {
      if (A_TickCount - startBtnWait >= 30000) {
        IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager"), Sleep(200)
        UpdateLog("起動失敗", "⚠️30秒経過しても開始ボタン（app_start_btn.bmp）を検知できませんでした。")
        PrepareEvidenceTimestamp()
        CaptureErrorScreenshot("launch_timeout")
        CaptureAdbLogcat("launch_timeout")
        RecordTestEvent("LAUNCH_TIMEOUT", "30秒経過しても開始ボタン未検知", "launch_timeout")
        SendWebhookNotification("LAUNCH_TIMEOUT", "30秒経過しても開始ボタン未検知が発生しました。", "launch_timeout")
        SaveSessionElapsedSeconds()
        GenerateHtmlReport(false)
        ExecuteErrorRecoveryByMode()
        break
      }

      if ChkImg("app_start_btn.bmp") {
        UpdateLog("テスト開始", "「開始」ボタンを検知。クリックして負荷テストを開始します！")
        ClickImg("app_start_btn.bmp")
        Sleep(1000)
        break
      }
      Sleep(500)
    }
  }
}

MainWorkflow() {
  ; ループに入る前にアプリの自動起動＆テスト開始を実行
  LaunchAndStartTestApp()

  ; 監視開始時のみファイルにもログを記録し、以降の定期ループはGUI表示のみ更新
  UpdateLogCurrentStageText(true)

  global MONITOR_INTERVAL_MS, MEM_CLEAR_INTERVAL_MS, MEM_CLEAR_KEY
  lMnt := A_TickCount, lMem := A_TickCount, lMetric := A_TickCount, TOTAL_TEST_START_TIME := A_TickCount
  RecordResourceMetric("START")
  
  Loop {
    ; 1分ごとにBlueStacksのCPU・メモリ使用量をCSVへ蓄積
    if ((A_TickCount - lMetric) >= 60000) {
      RecordResourceMetric("NORMAL")
      lMetric := A_TickCount
    }

    if (IS_CYCLE_RESTART_ENABLED && (A_TickCount - TOTAL_TEST_START_TIME) >= 7200000) {
      if WinExist(TARGET_EXE) {
        IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager"), Sleep(1500)
      }
      CURRENT_STAGE_COUNT := CURRENT_STAGE_COUNT >= 12 ? 1 : CURRENT_STAGE_COUNT + 1
      try IniWrite(CURRENT_STAGE_COUNT, INI_FILE, "Settings", "StageCount")
      UpdateLog("定時リセット", "2時間経過。次のテストサイクル（Stage " . CURRENT_STAGE_COUNT . " / 12）へ移行し安全再起動を実行。")
      RecordTestEvent("CYCLE_COMPLETE", "2時間耐久サイクル完走（次ステージ: " . CURRENT_STAGE_COUNT . "）")
      SendWebhookNotification("CYCLE_COMPLETE", "2時間の耐久テストサイクルを完走しました（次ステージ: Stage " . CURRENT_STAGE_COUNT . " / 12）。")
      SaveSessionElapsedSeconds()
      GenerateHtmlReport(false)
      Sleep(1000), ExitApp(10)
    }

    ; 1. メモリ解放キー送信タイマー（独立稼働）
    if (IS_MEM_CLEAR_ENABLED && MEM_CLEAR_INTERVAL_MS > 0 && (A_TickCount - lMem) >= MEM_CLEAR_INTERVAL_MS) {
      if WinExist(TARGET_EXE) {
        IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager")
        WinActivate(TARGET_EXE), Sleep(200), Send(MEM_CLEAR_KEY), Sleep(500)
        if (MODE_SELECTION == 1) {
          Sleep(200), SendMessage(0x112, 0xF170, 2,, "Program Manager")
        }
        IS_SUSPEND_SCREEN_OFF := false
      }
      lMem := A_TickCount
    }

    ; 2. 画面監視スキャンタイマー（独立稼働・無効時はすべて停止）
    if (MONITOR_INTERVAL_MS > 0) {
      if ((A_TickCount - lMnt) >= MONITOR_INTERVAL_MS) {
        if WinExist(TARGET_EXE) {
          IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager")
          
          CloseWarningDialogs()
          
          if (ChkImg("test_step_10.bmp")) {
            UpdateLog("スキャン検証", "🎯テストログの出力を検知。外部DUMPトリガーを執行します。")
            ClickImg("metric_log_trigger.bmp")
            UpdateLog("スキャン検証", "✅ログDUMP完了。次の定期スキャンまで待機します。")
          }

          if (MODE_SELECTION == 1) {
            Sleep(200), SendMessage(0x112, 0xF170, 2,, "Program Manager")
          }
          IS_SUSPEND_SCREEN_OFF := false
          UpdateLogCurrentStageText()
        }
        lMnt := A_TickCount
      }

      global AUTO_RESTART_MODE, IS_CRASH_HANDLED
      if (ChkImg("fatal_crash_alert.bmp")) {
        if (!IS_CRASH_HANDLED) {
          IS_CRASH_HANDLED := true
          IS_SUSPEND_SCREEN_OFF := true, SendMessage(0x112, 0xF170, -1,, "Program Manager"), Sleep(200)
          UpdateLog("異常検知", "⚠️対象アプリケーションのフリーズまたはクラッシュを検知。エビデンスを保存します。")
          RecordResourceMetric("CRASH")
          PrepareEvidenceTimestamp()
          CaptureErrorScreenshot("crash")
          CaptureAdbLogcat("crash")
          RecordTestEvent("CRASH", AUTO_RESTART_MODE == 4 ? "対象アプリのフリーズ/クラッシュを検知（デモ待機）" : "対象アプリのフリーズ/クラッシュを検知し復旧処理を実行", "crash")
          SendWebhookNotification("CRASH", AUTO_RESTART_MODE == 4 ? "対象アプリのフリーズまたはクラッシュを検知しました（両方OFF・デモ待機中）。" : "対象アプリのフリーズまたはクラッシュを検知しました。復旧処理を実行します。", "crash")
          SaveSessionElapsedSeconds()
          GenerateHtmlReport(false)
          ExecuteErrorRecoveryByMode()
        }
      } else if (IS_CRASH_HANDLED) {
        ; アプリ側で手動リセットされてクラッシュ画面が消えたらフラグを解除
        IS_CRASH_HANDLED := false
        UpdateLog("監視再開", "クラッシュ画面の解除を確認。通常監視を再開しました。")
      }
    }

    Sleep(1000)
  }
}

SafeCloseSequence(isCrashOrTimeout := false) {
  global IS_SUSPEND_SCREEN_OFF, ORIGINAL_BRIGHTNESS
  IS_SUSPEND_SCREEN_OFF := true
  SendMessage(0x112, 0xF170, -1,, "Program Manager")
  SetDisplayBrightness(ORIGINAL_BRIGHTNESS)
  Sleep(200)
  UpdateLog("安全終了処理", "終了シーケンスを実行し、バッチ側へリカバリ制御（終了コード10）を引き渡します。")
  WriteToFile(isCrashOrTimeout ? "[高負荷離脱] 異常検知に伴うクリーンアップ要求。終了コード10で再起動します。" : "[中断処理] 安全終了シーケンス完了。終了コード10を要求。")
  Sleep(500)
  ExitApp(10)
}

ChangeModeRuntime(targetMode, showNotice := true, executeOff := true) {
  global MODE_SELECTION, IS_SCREEN_OFF_ENABLED, IS_SUSPEND_SCREEN_OFF
  MODE_SELECTION := targetMode
  if (MODE_SELECTION == 1) {
    IS_SCREEN_OFF_ENABLED := true
    if (executeOff == true && !IS_SUSPEND_SCREEN_OFF)
      Sleep(500), SendMessage(0x112, 0xF170, 2,, "Program Manager"), UpdateLogNextOff("🌙 省電力暗転モード（スタンバイ状態維持）")
    else UpdateLogNextOff("🌙 スケジュール開始後に自動暗転")
    if (showNotice)
      UpdateLog("MODE_SELECTION", "スイッチ：🌙今すぐ消灯へ切り替えました")
  } else if (MODE_SELECTION == 2) {
    IS_SCREEN_OFF_ENABLED := false, SendMessage(0x112, 0xF170, -1,, "Program Manager"), UpdateLogNextOff("☀️ 暗転なし（常時点灯）")
    if (showNotice)
      UpdateLog("MODE_SELECTION", "スイッチ：☀️常時点灯へ切り替えました")
  }
}

CloseWarningDialogs() {
  Loop 3 {
    dialogFile := "warning_popup_close" . A_Index . ".bmp"
    if ChkImg(dialogFile) {
      UpdateLog("警告ダイアログ検知", dialogFile . " を検知。クローズ処理を実行してテストを継続します。")
      ClickImg(dialogFile)
      Sleep(1000)
      if ChkImg(dialogFile) {
        UpdateLog("警告ダイアログ検知", "⚠️ポップアップが残存しているためリトライを実行します。")
        ClickImg(dialogFile)
        Sleep(1000)
      }
      if !ChkImg(dialogFile) {
        UpdateLog("警告ダイアログ検知", "✨警告ポップアップを正常に閉じました。")
        RecordTestEvent("WARNING_CLOSED", dialogFile . " を自動クローズしてテスト継続")
        if (IS_WEBHOOK_WARN_ENABLED == 1)
          SendWebhookNotification("WARNING_CLOSED", "軽微な警告ダイアログ（" . dialogFile . "）を自動クローズし、テストを継続しました。")
      }
    }
  }
}

ChkImg(imgName) {
  global TARGET_EXE, IMG_DIR
  if (!WinExist(TARGET_EXE) || WinGetMinMax(TARGET_EXE) = -1)
    return false
  X := 0, Y := 0, W := 0, H := 0
  try WinGetPos(&X, &Y, &W, &H, TARGET_EXE)
  catch {
    return false
  }
  OutX := 0, OutY := 0
  sParam := InStr(imgName, "metric_log_trigger") ? "*135 *Trans0x000000 " : "*45 "
  try {
    return ImageSearch(&OutX, &OutY, X - 20, Y - 20, X + W + 20, Y + H + 20, String(sParam . IMG_DIR . imgName))
  } catch {
    return false
  }
}

ClickImg(imgName) {
  global TARGET_EXE, IMG_DIR
  if (!WinExist(TARGET_EXE) || WinGetMinMax(TARGET_EXE) = -1)
    return false
  X := 0, Y := 0, W := 0, H := 0
  try WinGetPos(&X, &Y, &W, &H, TARGET_EXE)
  catch {
    return false
  }
  OutX := 0, OutY := 0
  sParam := InStr(imgName, "metric_log_trigger") ? "*135 *Trans0x000000 " : "*45 "
  try {
    if ImageSearch(&OutX, &OutY, X - 20, Y - 20, X + W + 20, Y + H + 20, String(sParam . IMG_DIR . imgName)) {
      if (WinGetTransparent(TARGET_EXE) != "")
        WinActivate(TARGET_EXE), Sleep(100)
      MouseGetPos(&OldX, &OldY)
      if InStr(imgName, "metric_log_trigger") {
        Click(OutX + 15, OutY + 12)
      } else {
        Click(OutX + 45, OutY + 25)
      }
      Sleep(100), MouseMove(OldX, OldY, 0)
      return true
    }
  } catch {
    return false
  }
  return false
}

SetDisplayBrightness(level) {
  try {
    for method in ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\\root\\WMI").ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
      method.WmiSetBrightness(0, level)
  }
}

OpenDetailSettingsGui() {
  global MONITOR_INTERVAL_MS, MEM_CLEAR_INTERVAL_MS, MEM_CLEAR_KEY, INI_FILE, IS_MEM_CLEAR_ENABLED, SS_CAPTURE_MODE, IS_ADB_LOG_ENABLED, ADB_LOG_MINUTES, IS_WEBHOOK_ENABLED, WEBHOOK_URL, IS_WEBHOOK_WARN_ENABLED, AUTO_RESTART_MODE
  if WinExist("詳細設定 - 監視・メモリ解放") {
    WinActivate("詳細設定 - 監視・メモリ解放")
    return
  }

  sg := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow", "詳細設定 - 監視・メモリ解放")
  sg.SetFont("s10", "Segoe UI")

  ; タブコントロール作成（4タブ構成）
  tab := sg.Add("Tab3", "w320 h225", ["監視設定", "メモリ解放", "エビデンス", "外部通知"])

  ; --- タブ1：監視設定 ---
  tab.UseTab(1)
  sg.Add("Text", "x30 y48", "画像認識スキャン間隔:")
  monChoices := ["1秒", "3秒", "5秒", "10秒", "無効"]
  monValues := Array(1000, 3000, 5000, 10000, 0)
  monIdx := 4
  for idx, val in monValues {
    if (val == MONITOR_INTERVAL_MS)
      monIdx := idx
  }
  ddlMon := sg.Add("DropDownList", "x30 y+6 w250 Choose" . monIdx, monChoices)

  sg.Add("Text", "x30 y+12", "異常検知時の自動再起動モード:")
  rstChoices := ["1: 両方オン (本番耐久モード)", "2: BlueStacksのみ再起動 (AHK維持)", "3: AHKのみ再起動 (BlueStacks維持)", "4: 両方オフ (デモ・確認モード)"]
  rstIdx := (AUTO_RESTART_MODE >= 1 && AUTO_RESTART_MODE <= 4) ? AUTO_RESTART_MODE : 1
  ddlRst := sg.Add("DropDownList", "x30 y+6 w250 Choose" . rstIdx, rstChoices)

  btnDemo := sg.Add("Button", "x30 y+12 w250 h28", "🧪 デモ体験 (疑似クラッシュ・レポート生成)")
  btnDemo.OnEvent("Click", (*) => RunSimulatedDemoScenario())

  ; --- タブ2：メモリ解放 ---
  tab.UseTab(2)
  sg.Add("Text", "x30 y50", "キー送信間隔:")
  memChoices := ["10秒", "30秒", "1分", "5分", "無効"]
  memValues := Array(10000, 30000, 60000, 300000, 0)
  memIdx := 1
  if (!IS_MEM_CLEAR_ENABLED || MEM_CLEAR_INTERVAL_MS == 0) {
    memIdx := 5
  } else {
    for idx, val in memValues {
      if (val == MEM_CLEAR_INTERVAL_MS)
        memIdx := idx
    }
  }
  ddlMem := sg.Add("DropDownList", "x30 y+8 w250 Choose" . memIdx, memChoices)
  sg.Add("Text", "x30 y+12", "送信キー (例: q / {F5}):")
  edtKey := sg.Add("Edit", "x+10 yp-3 w80", MEM_CLEAR_KEY)

  ; --- タブ3：エビデンス（スクショ・ADBログ設定） ---
  tab.UseTab(3)
  sg.Add("Text", "x30 y45", "異常検知時のスクショ撮影範囲:")
  ssChoices := ["PC画面全体 (ログGUI含む)", "BlueStacksウィンドウのみ", "撮らない (無効)"]
  ssIdx := (SS_CAPTURE_MODE >= 1 && SS_CAPTURE_MODE <= 3) ? SS_CAPTURE_MODE : 1
  ddlSS := sg.Add("DropDownList", "x30 y+5 w250 Choose" . ssIdx, ssChoices)

  sg.Add("Text", "x30 y+10", "ADB内部ログ (Logcat) 自動取得:")
  adbChoices := ["取得する (有効)", "取得しない (無効)"]
  adbIdx := (IS_ADB_LOG_ENABLED == 1) ? 1 : 2
  ddlAdb := sg.Add("DropDownList", "x30 y+5 w145 Choose" . adbIdx, adbChoices)

  minChoices := ["直近1分", "直近3分", "直近5分", "直近10分", "直近30分"]
  minValues := Array(1, 3, 5, 10, 30)
  minIdx := 2
  for idx, val in minValues {
    if (val == ADB_LOG_MINUTES)
      minIdx := idx
  }
  ddlMin := sg.Add("DropDownList", "x+5 yp w100 Choose" . minIdx, minChoices)

  btnExtract := sg.Add("Button", "x30 y+12 w250 h28", "🔍 エラー起点ログ抽出 (前後〇分切出)")
  btnExtract.OnEvent("Click", (*) => OpenErrorLogExtractorGui())

  ; --- タブ4：外部通知（Discord / Slack Webhook） ---
  tab.UseTab(4)
  sg.Add("Text", "x30 y45", "Webhook リアルタイム通知:")
  whChoices := ["通知する (有効)", "通知しない (無効)"]
  whIdx := (IS_WEBHOOK_ENABLED == 1) ? 1 : 2
  ddlWh := sg.Add("DropDownList", "x30 y+4 w260 Choose" . whIdx, whChoices)

  sg.Add("Text", "x30 y+8", "Webhook URL (Discord / Slack):")
  edtWhUrl := sg.Add("Edit", "x30 y+4 w260 h22", WEBHOOK_URL)

  sg.Add("Text", "x30 y+8", "軽微な警告ダイアログ時も通知:")
  whWarnChoices := ["送る (有効)", "送らない (無効)"]
  whWarnIdx := (IS_WEBHOOK_WARN_ENABLED == 1) ? 1 : 2
  ddlWhWarn := sg.Add("DropDownList", "x30 y+4 w130 Choose" . whWarnIdx, whWarnChoices)

  btnWhTest := sg.Add("Button", "x+10 yp-1 w120 h25", "🧪 テスト送信")
  btnWhTest.OnEvent("Click", (*) => TestWebhookFromGui(edtWhUrl.Text))

  ; --- タブ終了・共通ボタン ---
  tab.UseTab()
  btnSave := sg.Add("Button", "x15 y+15 w150 h32", "💾 保存して適用")
  btnCancel := sg.Add("Button", "x+10 w150 h32", "キャンセル")

  btnSave.OnEvent("Click", (*) => SaveDetailSettings(sg, ddlMon.Value, monValues, ddlRst.Value, ddlMem.Value, memValues, edtKey.Text, ddlSS.Value, ddlAdb.Value, ddlMin.Value, minValues, ddlWh.Value, edtWhUrl.Text, ddlWhWarn.Value))
  btnCancel.OnEvent("Click", (*) => sg.Destroy())

  sg.Show("Center")
}

SaveDetailSettings(sg, monChoiceIdx, monValues, rstChoiceIdx, memChoiceIdx, memValues, inputKey, ssChoiceIdx, adbChoiceIdx, minChoiceIdx, minValues, whChoiceIdx, inputWhUrl, whWarnChoiceIdx) {
  global MONITOR_INTERVAL_MS, MEM_CLEAR_INTERVAL_MS, MEM_CLEAR_KEY, INI_FILE, IS_MEM_CLEAR_ENABLED, SS_CAPTURE_MODE, IS_ADB_LOG_ENABLED, ADB_LOG_MINUTES, IS_WEBHOOK_ENABLED, WEBHOOK_URL, IS_WEBHOOK_WARN_ENABLED, AUTO_RESTART_MODE, IS_CRASH_HANDLED
  
  MONITOR_INTERVAL_MS := monValues[monChoiceIdx]
  AUTO_RESTART_MODE := rstChoiceIdx
  IS_CRASH_HANDLED := false
  MEM_CLEAR_INTERVAL_MS := memValues[memChoiceIdx]
  MEM_CLEAR_KEY := (Trim(inputKey) != "") ? Trim(inputKey) : "q"
  SS_CAPTURE_MODE := ssChoiceIdx
  IS_ADB_LOG_ENABLED := (adbChoiceIdx == 1) ? 1 : 0
  ADB_LOG_MINUTES := minValues[minChoiceIdx]
  IS_WEBHOOK_ENABLED := (whChoiceIdx == 1) ? 1 : 0
  WEBHOOK_URL := Trim(inputWhUrl)
  IS_WEBHOOK_WARN_ENABLED := (whWarnChoiceIdx == 1) ? 1 : 0

  if (MEM_CLEAR_INTERVAL_MS == 0) {
    IS_MEM_CLEAR_ENABLED := 0
  } else {
    IS_MEM_CLEAR_ENABLED := 1
  }

  try {
    IniWrite(MONITOR_INTERVAL_MS, INI_FILE, "Settings", "MonitorInterval")
    IniWrite(AUTO_RESTART_MODE, INI_FILE, "Settings", "AutoRestartMode")
    IniWrite(MEM_CLEAR_INTERVAL_MS, INI_FILE, "Settings", "MemClearInterval")
    IniWrite(MEM_CLEAR_KEY, INI_FILE, "Settings", "MemClearKey")
    IniWrite(SS_CAPTURE_MODE, INI_FILE, "Settings", "SSCaptureMode")
    IniWrite(IS_ADB_LOG_ENABLED, INI_FILE, "Settings", "AdbLogEnabled")
    IniWrite(ADB_LOG_MINUTES, INI_FILE, "Settings", "AdbLogMinutes")
    IniWrite(IS_WEBHOOK_ENABLED, INI_FILE, "Webhook", "Enabled")
    IniWrite('"' . WEBHOOK_URL . '"', INI_FILE, "Webhook", "Url")
    IniWrite(IS_WEBHOOK_WARN_ENABLED, INI_FILE, "Webhook", "NotifyWarning")
  }

  rstNames := ["両方ON", "BSのみ再起動", "AHKのみ再起動", "両方OFF(デモ)"]
  rstLabel := rstNames[AUTO_RESTART_MODE]
  ssLabel := (SS_CAPTURE_MODE == 3) ? "無効" : ((SS_CAPTURE_MODE == 2) ? "BlueStacksのみ" : "PC画面全体")
  adbLabel := (IS_ADB_LOG_ENABLED == 1) ? "有効(直近" . ADB_LOG_MINUTES . "分)" : "無効"
  whLabel := (IS_WEBHOOK_ENABLED == 1) ? "有効" : "無効"
  UpdateLog("設定変更", "監視: " . (MONITOR_INTERVAL_MS == 0 ? "無効" : (MONITOR_INTERVAL_MS // 1000) . "秒") . " / 再起動: " . rstLabel . " / メモリ解放: " . (MEM_CLEAR_INTERVAL_MS == 0 ? "無効" : (MEM_CLEAR_INTERVAL_MS // 1000) . "秒 (" . MEM_CLEAR_KEY . ")") . " / SS: " . ssLabel . " / ADB: " . adbLabel . " / 通知: " . whLabel)
  sg.Destroy()
  MsgBox("設定を保存し、リアルタイムで適用しました。", "完了", "IconI T2")
}

PrepareEvidenceTimestamp() {
  global LAST_EVIDENCE_TS
  LAST_EVIDENCE_TS := A_YYYY . A_MM . A_DD . "_" . A_Hour . A_Min . A_Sec
}

CaptureErrorScreenshot(reasonLabel := "error") {
  global ERROR_LOG_DIR, SS_CAPTURE_MODE, TARGET_EXE, LAST_EVIDENCE_TS
  if (SS_CAPTURE_MODE == 3)
    return
  try {
    if (!DirExist(ERROR_LOG_DIR))
      DirCreate(ERROR_LOG_DIR)

    ts := (LAST_EVIDENCE_TS != "") ? LAST_EVIDENCE_TS : (A_YYYY . A_MM . A_DD . "_" . A_Hour . A_Min . A_Sec)
    filePath := ERROR_LOG_DIR . ts . "_" . reasonLabel . ".png"

    capX := 0, capY := 0, capW := A_ScreenWidth, capH := A_ScreenHeight
    if (SS_CAPTURE_MODE == 2 && WinExist(TARGET_EXE) && WinGetMinMax(TARGET_EXE) != -1) {
      WinGetPos(&wx, &wy, &ww, &wh, TARGET_EXE)
      if (ww > 0 && wh > 0) {
        capX := wx, capY := wy, capW := ww, capH := wh
      }
    }

    psCmd := "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; "
           . "$b = New-Object System.Drawing.Bitmap(" . capW . "," . capH . "); "
           . "$g = [System.Drawing.Graphics]::FromImage($b); "
           . "$g.CopyFromScreen(" . capX . "," . capY . ",0,0,$b.Size); "
           . "$b.Save('" . filePath . "',[System.Drawing.Imaging.ImageFormat]::Png); "
           . "$g.Dispose(); $b.Dispose();"

    RunWait('powershell -NoProfile -ExecutionPolicy Bypass -Command "' . psCmd . '"', , "Hide")
    WriteToFile("[エビデンス保存] スクリーンショットを保存しました: " . ts . "_" . reasonLabel . ".png")
  } catch as err {
    WriteToFile("[エビデンス失敗] スクリーンショットの保存に失敗しました: " . err.Message)
  }
}

CaptureAdbLogcat(reasonLabel := "error") {
  global ERROR_LOG_DIR, IS_ADB_LOG_ENABLED, ADB_EXE, ADB_PORT, LAST_EVIDENCE_TS, ADB_LOG_MINUTES
  if (IS_ADB_LOG_ENABLED != 1)
    return
  if (!FileExist(ADB_EXE)) {
    WriteToFile("[ADBログ失敗] HD-Adb.exe が見つかりません: " . ADB_EXE)
    return
  }
  try {
    if (!DirExist(ERROR_LOG_DIR))
      DirCreate(ERROR_LOG_DIR)

    ts := (LAST_EVIDENCE_TS != "") ? LAST_EVIDENCE_TS : (A_YYYY . A_MM . A_DD . "_" . A_Hour . A_Min . A_Sec)
    logPath := ERROR_LOG_DIR . ts . "_" . reasonLabel . "_logcat.txt"

    ; 現在時刻から指定分数(ADB_LOG_MINUTES)を引いた開始時刻を算出 (MM-DD HH:mm:ss.000)
    startTime := DateAdd(A_Now, -ADB_LOG_MINUTES, "Minutes")
    sinceStr := FormatTime(startTime, "MM-dd HH:mm:ss") . ".000"

    adbCmd := '""' . ADB_EXE . '" connect ' . ADB_PORT . ' > nul 2>&1 & "' . ADB_EXE . '" -s ' . ADB_PORT . ' logcat -d -v time -T "' . sinceStr . '" > "' . logPath . '""'
    RunWait(A_ComSpec . ' /c ' . adbCmd, , "Hide")
    WriteToFile("[ADBログ保存] 直近" . ADB_LOG_MINUTES . "分間のAndroid内部ログを保存しました: " . ts . "_" . reasonLabel . "_logcat.txt")
  } catch as err {
    WriteToFile("[ADBログ失敗] Logcatの取得に失敗しました: " . err.Message)
  }
}

OpenErrorLogExtractorGui() {
  global ERROR_LOG_DIR, ADB_EXE, ADB_PORT
  if WinExist("エラー起点ログ抽出") {
    WinActivate("エラー起点ログ抽出")
    return
  }
  if (!FileExist(ADB_EXE)) {
    MsgBox("HD-Adb.exe が見つかりません: " . ADB_EXE, "エラー", "IconX")
    return
  }
  try {
    if (!DirExist(ERROR_LOG_DIR))
      DirCreate(ERROR_LOG_DIR)
    tmpLog := ERROR_LOG_DIR . "_temp_full_logcat.txt"
    adbCmd := '""' . ADB_EXE . '" connect ' . ADB_PORT . ' > nul 2>&1 & "' . ADB_EXE . '" -s ' . ADB_PORT . ' logcat -d -v time > "' . tmpLog . '""'
    RunWait(A_ComSpec . ' /c ' . adbCmd, , "Hide")

    if (!FileExist(tmpLog)) {
      MsgBox("Logcatの取得に失敗しました。", "エラー", "IconX")
      return
    }

    rawText := FileRead(tmpLog, "UTF-8")
    lines := StrSplit(rawText, "`n", "`r")
    errItems := Array()
    errTimes := Array()

    for idx, line in lines {
      if (RegExMatch(line, "^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\.\d+\s+([FE]/|.*FATAL EXCEPTION|.*OutOfMemoryError|.*ANR in)", &m)) {
        errTimes.Push(m[1])
        errItems.Push(SubStr(line, 1, 95))
      }
    }

    if (errItems.Length == 0) {
      MsgBox("現在のLogcat内にエラー行（E/・F/・FATAL・ANR等）は見つかりませんでした。", "情報", "IconI")
      return
    }

    ; 最新15件に絞って逆順（新しい順）に表示
    dispItems := Array()
    dispTimes := Array()
    startIdx := (errItems.Length > 15) ? (errItems.Length - 14) : 1
    Loop (errItems.Length - startIdx + 1) {
      revIdx := errItems.Length - A_Index + 1
      dispItems.Push(errItems[revIdx])
      dispTimes.Push(errTimes[revIdx])
    }

    eg := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow", "エラー起点ログ抽出")
    eg.SetFont("s9", "Segoe UI")
    eg.Add("Text", "x15 y12", "1. 抽出の基準にするエラーを選択してください（最新15件）:")
    lbErr := eg.Add("ListBox", "x15 y+6 w520 r10 Choose1", dispItems)

    eg.Add("Text", "x15 y+12", "2. 選択したエラー発生時刻の前後何分間を切り出しますか？:")
    rangeChoices := ["前後 1分間", "前後 3分間", "前後 5分間", "前後 10分間"]
    rangeVals := Array(1, 3, 5, 10)
    ddlRange := eg.Add("DropDownList", "x+10 yp-3 w120 Choose2", rangeChoices)

    btnRun := eg.Add("Button", "x15 y+15 w250 h32", "📄 該当時間帯のログを抽出して開く")
    btnClose := eg.Add("Button", "x+20 w250 h32", "閉じる")

    btnRun.OnEvent("Click", (*) => ExtractAroundErrorTime(tmpLog, dispTimes[lbErr.Value], rangeVals[ddlRange.Value]))
    btnClose.OnEvent("Click", (*) => eg.Destroy())
    eg.Show("Center")
  } catch as err {
    MsgBox("エラー解析中に問題が発生しました: " . err.Message, "エラー", "IconX")
  }
}

ExtractAroundErrorTime(tmpLogPath, targetMmDdHhMmSs, halfMin) {
  global ERROR_LOG_DIR
  try {
    ; targetMmDdHhMmSs は "MM-DD HH:mm:ss" 形式
    cleanDigits := RegExReplace(targetMmDdHhMmSs, "\D")
    centerTs := A_YYYY . cleanDigits
    minTs := DateAdd(centerTs, -halfMin, "Minutes")
    maxTs := DateAdd(centerTs, halfMin, "Minutes")

    lines := StrSplit(FileRead(tmpLogPath, "UTF-8"), "`n", "`r")
    outBuf := "=== エラー起点ログ抽出 (基準: " . targetMmDdHhMmSs . " / 前後 " . halfMin . " 分間) ===`n`n"
    hitCount := 0

    for idx, line in lines {
      if (RegExMatch(line, "^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})", &m)) {
        lineTs := A_YYYY . m[1] . m[2] . m[3] . m[4] . m[5]
        if (DateDiff(lineTs, minTs, "Seconds") >= 0 && DateDiff(maxTs, lineTs, "Seconds") >= 0) {
          outBuf .= line . "`n"
          hitCount++
        }
      }
    }

    outFile := ERROR_LOG_DIR . "extracted_" . A_YYYY . A_MM . A_DD . "_" . A_Hour . A_Min . A_Sec . ".txt"
    FileAppend(outBuf, outFile, "UTF-8")
    WriteToFile("[エラー起点抽出] " . targetMmDdHhMmSs . " 前後" . halfMin . "分間のログ(" . hitCount . "行)を保存しました。")
    Run('"' . outFile . '"')
  } catch as err {
    MsgBox("ログ切り出しに失敗しました: " . err.Message, "エラー", "IconX")
  }
}

; ==================================
; CSVメトリクス蓄積 & HTMLレポート自動生成
; ==================================
SaveSessionElapsedSeconds() {
  global INI_FILE, SESSION_START_TICK
  try {
    elapsedSec := (A_TickCount - SESSION_START_TICK) // 1000
    prevTotal := Integer(IniRead(INI_FILE, "Stats", "TotalElapsedSec", "0"))
    IniWrite(prevTotal + elapsedSec, INI_FILE, "Stats", "TotalElapsedSec")
    SESSION_START_TICK := A_TickCount
  }
}

GetBlueStacksStats(&memMB, &cpuPct) {
  memMB := 0, cpuPct := 0
  try {
    for proc in ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT WorkingSetSize FROM Win32_Process WHERE Name='HD-Player.exe'") {
      memMB += Round(proc.WorkingSetSize / 1048576, 1)
    }
    for perf in ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfProc_Process WHERE Name LIKE 'HD-Player%'") {
      cpuPct += Integer(perf.PercentProcessorTime)
    }
    cpuPct := Round(cpuPct / EnvGet("NUMBER_OF_PROCESSORS"), 1)
  }
}

RecordResourceMetric(eventTag := "NORMAL") {
  global REPORT_DIR, METRICS_CSV, CURRENT_STAGE_COUNT
  try {
    if (!DirExist(REPORT_DIR))
      DirCreate(REPORT_DIR)
    if (!FileExist(METRICS_CSV))
      FileAppend("Timestamp,Stage,MemoryMB,CpuPercent,EventTag`n", METRICS_CSV, "UTF-8")
    GetBlueStacksStats(&memMB, &cpuPct)
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    FileAppend(ts . "," . CURRENT_STAGE_COUNT . "," . memMB . "," . cpuPct . "," . eventTag . "`n", METRICS_CSV, "UTF-8")
  }
}

RecordTestEvent(eventType, detailMsg, evidenceLabel := "") {
  global REPORT_DIR, EVENTS_CSV, CURRENT_STAGE_COUNT, LAST_EVIDENCE_TS
  try {
    if (!DirExist(REPORT_DIR))
      DirCreate(REPORT_DIR)
    if (!FileExist(EVENTS_CSV))
      FileAppend("Timestamp,Stage,EventType,Detail,ScreenshotFile,LogcatFile`n", EVENTS_CSV, "UTF-8")
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    ssFile := "", logFile := ""
    if (evidenceLabel != "" && LAST_EVIDENCE_TS != "") {
      ssFile := LAST_EVIDENCE_TS . "_" . evidenceLabel . ".png"
      logFile := LAST_EVIDENCE_TS . "_" . evidenceLabel . "_logcat.txt"
    }
    cleanMsg := StrReplace(detailMsg, ",", "、")
    FileAppend(ts . "," . CURRENT_STAGE_COUNT . "," . eventType . "," . cleanMsg . "," . ssFile . "," . logFile . "`n", EVENTS_CSV, "UTF-8")
  }
}
GenerateHtmlReport(openAfter := false) {
  global REPORT_DIR, METRICS_CSV, EVENTS_CSV, REPORT_HTML, INI_FILE, CURRENT_STAGE_COUNT
  try {
    if (!DirExist(REPORT_DIR))
      DirCreate(REPORT_DIR)

    totalSec := Integer(IniRead(INI_FILE, "Stats", "TotalElapsedSec", "0"))
    hrs := totalSec // 3600
    mins := Mod(totalSec, 3600) // 60
    durationStr := Format("{:02}時間 {:02}分", hrs, mins)

    ; メトリクスCSV読み込み（グラフ用配列生成）
    labelsJs := "", memJs := "", cpuJs := ""
    if FileExist(METRICS_CSV) {
      lines := StrSplit(FileRead(METRICS_CSV, "UTF-8"), "`n", "`r")
      for idx, line in lines {
        if (idx == 1 || Trim(line) == "")
          continue
        cols := StrSplit(line, ",")
        if (cols.Length >= 4) {
          shortTime := SubStr(cols.Get(1), 12, 5)
          labelsJs .= "'" . shortTime . "',"
          memJs .= cols.Get(3) . ","
          cpuJs .= cols.Get(4) . ","
        }
      }
    }

    ; イベントCSV読み込み（件数集計＆テーブル行生成）
    crashCnt := 0, warnCnt := 0, timeoutCnt := 0, cycleCnt := 0
    rowsHtml := ""
    if FileExist(EVENTS_CSV) {
      eLines := StrSplit(FileRead(EVENTS_CSV, "UTF-8"), "`n", "`r")
      for idx, line in eLines {
        if (idx == 1 || Trim(line) == "")
          continue
        cols := StrSplit(line, ",")
        if (cols.Length >= 6) {
          evType := cols.Get(3)
          badge := evType
          if (evType == "CRASH") {
            crashCnt++, badge := "<span class='badge crash'>💥 クラッシュ検知</span>"
          } else if (evType == "WARNING_CLOSED") {
            warnCnt++, badge := "<span class='badge warn'>⚠️ 警告クローズ</span>"
          } else if (evType == "LAUNCH_TIMEOUT") {
            timeoutCnt++, badge := "<span class='badge timeout'>⏰ 起動タイムアウト</span>"
          } else if (evType == "CYCLE_COMPLETE") {
            cycleCnt++, badge := "<span class='badge cycle'>🔄 サイクル完走</span>"
          }
          ssFile := cols.Get(5)
          logFile := cols.Get(6)
          ssLink := (ssFile != "") ? "<a href='../error_logs/" . ssFile . "' target='_blank'>🖼️ 画像を開く</a>" : "-"
          logLink := (logFile != "") ? "<a href='../error_logs/" . logFile . "' target='_blank'>📄 ログを開く</a>" : "-"
          errSnippetHtml := ExtractFatalSummaryHtml(logFile)
          rowsHtml := "<tr><td>" . cols.Get(1) . "</td><td>Stage " . cols.Get(2) . "</td><td>" . badge . "</td><td>" . cols.Get(4) . errSnippetHtml . "</td><td>" . ssLink . "</td><td>" . logLink . "</td></tr>`n" . rowsHtml
        }
      }
    }
    if (rowsHtml == "")
      rowsHtml := "<tr><td colspan='6' style='text-align:center;color:#888;'>記録されたイベントはまだありません</td></tr>"

    genTime := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    chartCdn := "https://" . "cdn.jsdelivr.net/npm/chart.js"
    html := "<!DOCTYPE html><html lang='ja'><head><meta charset='UTF-8'><title>耐久負荷テスト 検証レポート</title>"
          . "<script src='" . chartCdn . "'></script>"
          . "<style>"
          . "body{font-family:'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;margin:0;padding:24px;}"
          . ".container{max-width:1100px;margin:0 auto;}"
          . "h1{font-size:24px;margin-bottom:4px;color:#38bdf8;} .sub{color:#94a3b8;font-size:13px;margin-bottom:24px;}"
          . ".cards{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:24px;}"
          . ".card{background:#1e293b;padding:18px;border-radius:10px;border:1px solid #334155;}"
          . ".card-title{font-size:12px;color:#94a3b8;margin-bottom:8px;} .card-val{font-size:26px;font-weight:bold;}"
          . ".c-blue{color:#38bdf8;} .c-green{color:#4ade80;} .c-red{color:#f87171;} .c-yellow{color:#fbbf24;}"
          . ".panel{background:#1e293b;padding:20px;border-radius:10px;border:1px solid #334155;margin-bottom:24px;}"
          . "h2{font-size:16px;margin-top:0;margin-bottom:16px;color:#f1f5f9;}"
          . "table{width:100%;border-collapse:collapse;font-size:13px;}"
          . "th,td{padding:10px 12px;border-bottom:1px solid #334155;text-align:left;vertical-align:top;}"
          . "th{background:#0f172a;color:#94a3b8;}"
          . ".badge{padding:3px 8px;border-radius:4px;font-size:12px;font-weight:bold;display:inline-block;}"
          . ".crash{background:#7f1d1d;color:#fecaca;} .warn{background:#78350f;color:#fde68a;} .timeout{background:#581c87;color:#e9d5ff;} .cycle{background:#14532d;color:#bbf7d0;}"
          . "details{margin-top:6px;} summary{cursor:pointer;color:#fbbf24;font-size:12px;}"
          . "pre.errbox{background:#0f172a;border:1px solid #7f1d1d;color:#fca5a5;padding:8px;border-radius:6px;font-size:11px;white-space:pre-wrap;margin:6px 0 0 0;max-height:160px;overflow-y:auto;}"
          . "a{color:#38bdf8;text-decoration:none;} a:hover{text-decoration:underline;}"
          . "</style></head><body><div class='container'>"
          . "<h1>📊 アプリケーション耐久負荷テスト 検証レポート</h1>"
          . "<div class='sub'>レポート生成日時: " . genTime . " ｜ 対象プロセス: HD-Player.exe ｜ 現在ステージ: Stage " . CURRENT_STAGE_COUNT . "</div>"
          . "<div class='cards'>"
          . "<div class='card'><div class='card-title'>⏱️ 総テスト稼働時間</div><div class='card-val c-blue'>" . durationStr . "</div></div>"
          . "<div class='card'><div class='card-title'>🔄 完走サイクル数</div><div class='card-val c-green'>" . cycleCnt . " 回</div></div>"
          . "<div class='card'><div class='card-title'>💥 クラッシュ検知・復旧</div><div class='card-val c-red'>" . crashCnt . " 件</div></div>"
          . "<div class='card'><div class='card-title'>⚠️ 警告ポップアップ処理</div><div class='card-val c-yellow'>" . warnCnt . " 件</div></div>"
          . "</div>"
          . "<div class='panel'><h2>📈 BlueStacks リソース消費推移（メモリ使用量 / CPU使用率）</h2><canvas id='resChart' height='95'></canvas></div>"
          . "<div class='panel'><h2>📋 発生イベント・エビデンス一覧（最新順）</h2><table><thead><tr><th>発生日時</th><th>ステージ</th><th>種別</th><th>詳細</th><th>スクショ</th><th>Logcat</th></tr></thead><tbody>"
          . rowsHtml . "</tbody></table></div></div>"
          . "<script>"
          . "const ctx=document.getElementById('resChart').getContext('2d');"
          . "new Chart(ctx,{type:'line',data:{labels:" . Chr(91) . labelsJs . Chr(93) . ",datasets:" . Chr(91)
          . "{label:'メモリ使用量 (MB)',data:" . Chr(91) . memJs . Chr(93) . ",borderColor:'#38bdf8',backgroundColor:'rgba(56,189,248,0.1)',yAxisID:'y',tension:0.3,fill:true},"
          . "{label:'CPU使用率 (%)',data:" . Chr(91) . cpuJs . Chr(93) . ",borderColor:'#4ade80',backgroundColor:'rgba(74,222,128,0.1)',yAxisID:'y1',tension:0.3}"
          . Chr(93) . "},options:{responsive:true,interaction:{mode:'index',intersect:false},scales:{x:{ticks:{color:'#94a3b8'}},y:{type:'linear',position:'left',ticks:{color:'#38bdf8'},title:{display:true,text:'Memory (MB)',color:'#38bdf8'}},y1:{type:'linear',position:'right',min:0,max:100,grid:{drawOnChartArea:false},ticks:{color:'#4ade80'},title:{display:true,text:'CPU (%)',color:'#4ade80'}}},plugins:{legend:{labels:{color:'#e2e8f0'}}}}});"
          . "</script></body></html>"

    if FileExist(REPORT_HTML)
      FileDelete(REPORT_HTML)
    FileAppend(html, REPORT_HTML, "UTF-8")

    if (openAfter)
      Run('"' . REPORT_HTML . '"')
  }
}

ExtractFatalSummaryHtml(logFileName) {
  global ERROR_LOG_DIR
  if (logFileName == "")
    return ""
  fullPath := ERROR_LOG_DIR . logFileName
  if (!FileExist(fullPath))
    return ""
  try {
    lines := StrSplit(FileRead(fullPath, "UTF-8"), "`n", "`r")
    extracted := ""
    captureRemain := 0
    hitCnt := 0
    for idx, line in lines {
      if (InStr(line, "FATAL EXCEPTION") || InStr(line, "OutOfMemoryError") || InStr(line, "ANR in") || InStr(line, "E/AndroidRuntime")) {
        captureRemain := 6
        hitCnt++
      }
      if (captureRemain > 0) {
        safeLine := StrReplace(StrReplace(StrReplace(line, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
        extracted .= safeLine . "`n"
        captureRemain--
        if (hitCnt >= 3 && captureRemain == 0)
          break
      }
    }
    if (extracted == "")
      return ""
    return "<details><summary>🔍 重要エラー抜粋を表示</summary><pre class='errbox'>" . extracted . "</pre></details>"
  } catch {
    return ""
  }
}

; ==================================
; 外部通知連携（Discord / Slack Webhook HTTP POST）
; ==================================
TestWebhookFromGui(urlStr) {
  cleanUrl := Trim(urlStr)
  if (cleanUrl == "") {
    MsgBox("Webhook URLを入力してください。", "エラー", "IconX")
    return
  }
  ok := ExecuteWebhookHttpPost(cleanUrl, "🧪 **【テスト通知】** アプリケーション耐久負荷テスト監視ツールからの接続テストに成功しました！")
  if (ok)
    MsgBox("テスト通知の送信に成功しました！Discord/Slackをご確認ください。", "成功", "IconI T2")
  else
    MsgBox("送信に失敗しました。URLが正しいか、ネットワーク接続をご確認ください。", "送信失敗", "IconX")
}

SendWebhookNotification(eventType, detailMsg, evidenceLabel := "") {
  global IS_WEBHOOK_ENABLED, WEBHOOK_URL, CURRENT_STAGE_COUNT, LAST_EVIDENCE_TS
  if (IS_WEBHOOK_ENABLED != 1 || Trim(WEBHOOK_URL) == "")
    return

  title := "📢【テスト通知】"
  if (eventType == "CRASH")
    title := "🚨【耐久テスト異常検知：クラッシュ】"
  else if (eventType == "LAUNCH_TIMEOUT")
    title := "⏰【耐久テスト異常検知：起動タイムアウト】"
  else if (eventType == "CYCLE_COMPLETE")
    title := "✅【耐久テスト報告：サイクル完走】"
  else if (eventType == "WARNING_CLOSED")
    title := "⚠️【耐久テスト通知：警告ポップアップ自動処理】"

  nowStr := FormatTime(, "yyyy-MM-dd HH:mm:ss")
  msg := title . "`n・発生日時: " . nowStr . "`n・現在ステージ: Stage " . CURRENT_STAGE_COUNT . " / 12`n・内容: " . detailMsg
  if (evidenceLabel != "" && LAST_EVIDENCE_TS != "")
    msg .= "`n・保存エビデンス: " . LAST_EVIDENCE_TS . "_" . evidenceLabel . ".png / _logcat.txt"

  ok := ExecuteWebhookHttpPost(WEBHOOK_URL, msg)
  WriteToFile(ok ? "[外部通知] Webhook通知を送信しました (" . eventType . ")" : "[外部通知失敗] Webhook通知の送信に失敗しました (" . eventType . ")")
}

ExecuteWebhookHttpPost(targetUrl, messageText) {
  try {
    escaped := StrReplace(messageText, "\", "\\")
    escaped := StrReplace(escaped, '"', '\"')
    escaped := StrReplace(escaped, "`r", "")
    escaped := StrReplace(escaped, "`n", "\n")

    ; Slack URLなら "text" キー、Discord URLなら "content" キーでJSONを組み立て
    jsonKey := InStr(targetUrl, "slack.com") ? "text" : "content"
    payload := '{"' . jsonKey . '":"' . escaped . '"}'

    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("POST", targetUrl, false)
    whr.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    whr.Send(payload)
    status := whr.Status
    return (status >= 200 && status < 300)
  } catch {
    return false
  }
}

ResetTestReportWithArchive() {
  global REPORT_DIR, METRICS_CSV, EVENTS_CSV, REPORT_HTML, INI_FILE, SESSION_START_TICK
  res := MsgBox("現在のテストレポート記録をアーカイブフォルダへバックアップし、新規計測を開始しますか？", "新規テスト記録リセット", "YesNo Icon? 4096")
  if (res != "Yes")
    return

  try {
    if (!DirExist(REPORT_DIR))
      DirCreate(REPORT_DIR)

    hasData := (FileExist(METRICS_CSV) || FileExist(EVENTS_CSV) || FileExist(REPORT_HTML))
    archiveMsg := ""
    if (hasData) {
      arcDir := REPORT_DIR . "archive_" . A_YYYY . A_MM . A_DD . "_" . A_Hour . A_Min . A_Sec . "\"
      DirCreate(arcDir)
      if FileExist(METRICS_CSV)
        FileMove(METRICS_CSV, arcDir . "metrics_log.csv", 1)
      if FileExist(EVENTS_CSV)
        FileMove(EVENTS_CSV, arcDir . "events_log.csv", 1)
      if FileExist(REPORT_HTML)
        FileMove(REPORT_HTML, arcDir . "test_report.html", 1)
      archiveMsg := "（旧データは " . arcDir . " へ退避）"
    }

    IniWrite(0, INI_FILE, "Stats", "TotalElapsedSec")
    SESSION_START_TICK := A_TickCount

    RecordResourceMetric("START")
    GenerateHtmlReport(false)

    UpdateLog("記録リセット", "テストレポート記録を初期化し、新規セッションの計測を開始しました。" . archiveMsg)
    MsgBox("過去の記録をバックアップし、新規テスト記録を開始しました！", "完了", "IconI T2 4096")
  } catch as err {
    MsgBox("リセット処理中にエラーが発生しました: " . err.Message, "エラー", "IconX 4096")
  }
}

ExecuteErrorRecoveryByMode() {
  global AUTO_RESTART_MODE, BS_PATH, BS_INSTANCE, IS_CRASH_HANDLED
  if (AUTO_RESTART_MODE == 1) {
    ; 1: 両方オン（バッチ側でBlueStacks強制終了＆圧縮＆AHK再起動）
    SafeCloseSequence(true)
  } else if (AUTO_RESTART_MODE == 2) {
    ; 2: BlueStacksのみ再起動（AHKは維持したままエミュレータだけ再起動してテスト再開）
    UpdateLog("BS単体復旧", "AHKを維持したまま、BlueStacksのみ強制終了・再起動を実行します...")
    RunWait('taskkill /f /t /im HD-Player.exe', , "Hide")
    Sleep(3000)
    Run('"' . BS_PATH . '\HD-Player.exe" --instance ' . BS_INSTANCE)
    Sleep(5000)
    IS_CRASH_HANDLED := false
    LaunchAndStartTestApp()
    UpdateLogCurrentStageText(true)
  } else if (AUTO_RESTART_MODE == 3) {
    ; 3: AHKのみ再起動（終了コード11でバッチへ返し、BlueStacksは維持したままAHKだけ再起動）
    UpdateLog("AHK単体復旧", "BlueStacksを維持したまま、AHK監視スクリプトのみ再起動（終了コード11）を実行します...")
    Sleep(500)
    ExitApp(11)
  } else {
    ; 4: 両方オフ（デモ・確認モード）
    UpdateLog("デモ待機中", "クラッシュ検知・エビデンス保存完了（両方OFF設定のため現状維持中）")
  }
}

DisableAllMonitorsForConfig() {
  global MONITOR_INTERVAL_MS, AUTO_RESTART_MODE, MEM_CLEAR_INTERVAL_MS, IS_MEM_CLEAR_ENABLED, INI_FILE
  MONITOR_INTERVAL_MS := 0
  AUTO_RESTART_MODE := 4
  MEM_CLEAR_INTERVAL_MS := 0
  IS_MEM_CLEAR_ENABLED := 0

  try {
    IniWrite(0, INI_FILE, "Settings", "MonitorInterval")
    IniWrite(4, INI_FILE, "Settings", "AutoRestartMode")
    IniWrite(0, INI_FILE, "Settings", "MemClearInterval")
  }

  UpdateLog("一括停止中", "監視・自動再起動・メモリ解放を一括OFFにしました（詳細設定を変更可能です）。")
}

RunSimulatedDemoScenario() {
  global REPORT_DIR, METRICS_CSV, CURRENT_STAGE_COUNT
  res := MsgBox("BlueStacks環境なしで本ツールの動作を体験できるデモを実行します。`n`n・疑似リソース推移データの生成`n・警告クローズ＆クラッシュ検知イベントの記録`n・HTML検証レポートの自動生成とブラウザ表示`n・Webhook通知送信（設定有効時）`n`nを実行してよろしいですか？", "採用担当者向けデモ体験", "YesNo IconI 4096")
  if (res != "Yes")
    return

  try {
    if (!DirExist(REPORT_DIR))
      DirCreate(REPORT_DIR)
    if (!FileExist(METRICS_CSV))
      FileAppend("Timestamp,Stage,MemoryMB,CpuPercent,EventTag`n", METRICS_CSV, "UTF-8")

    ; 疑似のメモリ上昇波形（185MB → 248MB → 312MB → 復旧後190MB）をCSVへ追加
    t1 := FormatTime(DateAdd(A_Now, -3, "Minutes"), "yyyy-MM-dd HH:mm:ss")
    t2 := FormatTime(DateAdd(A_Now, -2, "Minutes"), "yyyy-MM-dd HH:mm:ss")
    t3 := FormatTime(DateAdd(A_Now, -1, "Minutes"), "yyyy-MM-dd HH:mm:ss")
    t4 := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    FileAppend(t1 . "," . CURRENT_STAGE_COUNT . ",185.4,14.2,NORMAL`n", METRICS_CSV, "UTF-8")
    FileAppend(t2 . "," . CURRENT_STAGE_COUNT . ",248.9,28.5,NORMAL`n", METRICS_CSV, "UTF-8")
    FileAppend(t3 . "," . CURRENT_STAGE_COUNT . ",312.6,46.8,CRASH`n", METRICS_CSV, "UTF-8")
    FileAppend(t4 . "," . CURRENT_STAGE_COUNT . ",190.2,12.0,START`n", METRICS_CSV, "UTF-8")

    RecordTestEvent("WARNING_CLOSED", "【デモ体験】軽微なメモリ警告ダイアログを自動クローズしてテスト継続")
    RecordTestEvent("CRASH", "【デモ体験】OutOfMemoryErrorによるクラッシュを検知し自動復旧を実行")

    SendWebhookNotification("CRASH", "【デモ体験】採用担当者向けデモモードにより、異常検知〜レポート自動生成の一連の動作を実行しました。")

    SaveSessionElapsedSeconds()
    GenerateHtmlReport(true)
    UpdateLog("デモ実行完了", "採用担当者向けデモデータの記録とHTMLレポート出力を完了しました。")
  } catch as err {
    MsgBox("デモ実行中にエラーが発生しました: " . err.Message, "エラー", "IconX 4096")
  }
}

InitializeMacro()
