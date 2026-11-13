@echo off
setlocal
chcp 65001 > nul

rem ───【管理者権限への自動昇格処理】───
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo [権限昇格] 管理者権限を要求しています...
    powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList 'minimized' -Verb RunAs"
    exit /b
)

if not "%~1"=="minimized" (
    start /min "" "%~f0" minimized
    exit /b
)

set CURRENT_DIR=%~dp0
set INI_FILE=%CURRENT_DIR%mode_config.ini
set INSTANCE_NAME=Pie64
set AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey.exe
set AHK_SCRIPT=app_load_test_monitor.ahk
set B_PATH=C:\Program Files\BlueStacks_nxt

rem ───【mode_config.ini の [Paths] から環境パスを読み込み】───
if exist "%INI_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%INI_FILE%") do (
        if /i "%%A"=="InstanceName" set INSTANCE_NAME=%%B
        if /i "%%A"=="AhkPath" set AHK_EXE=%%B
        if /i "%%A"=="BlueStacksPath" set B_PATH=%%B
    )
)

echo [初期化] 古いAutoHotkeyプロセスが残っている場合は終了します...
taskkill /f /im AutoHotkey.exe > nul 2>&1
taskkill /f /im AutoHotkey64.exe > nul 2>&1

:loop
echo [ログ] 🔄テスト対象エミュレータをバックグラウンドで起動中...
start "" "%B_PATH%\HD-Player.exe" --instance %INSTANCE_NAME%
timeout /t 5 /nobreak > nul

:ahk_only_loop
echo [ログ] 🔄AHK監視スクリプトを【同期実行】中...
"%AHK_EXE%" "%CURRENT_DIR%%AHK_SCRIPT%" auto_start
set EXIT_CODE=%errorlevel%
echo [ログ] AHKが終了コード %EXIT_CODE% で停止しました。

rem ───【1. 安全停止】ユーザーによる手動停止・GUI閉じる操作（コード0） ───
if %EXIT_CODE%==0 (
    echo [安全停止] 🛑ユーザーによる手動停止を検知しました。エミュレータは維持します。
    timeout /t 5
    exit /b
)

rem ───【2. AHKのみ再起動】エミュレータは維持しAHK監視だけ再起動（コード11） ───
if %EXIT_CODE%==11 (
    echo [AHK再起動] 🔄エミュレータを維持したままAHK監視スクリプトのみ再起動します...
    timeout /t 2 /nobreak > nul
    goto ahk_only_loop
)

rem ───【3. 予期せぬ終了】AHKエラー落ち・起動失敗（コード0, 10, 11以外） ───
if not %EXIT_CODE%==10 (
    echo [異常停止] ⚠️AHKが予期せぬ終了コード（%EXIT_CODE%）で停止しました。エミュレータは維持してバッチを終了します。
    pause
    exit /b
)

rem ───【3. クリーンアップ自動移行（コード10限定）】───
echo [クリーンアップ] ⚡エミュレータプロセスを強制終了（タスクキル）中...
taskkill /f /t /im HD-Player.exe > nul 2>&1
timeout /t 3 /nobreak > nul

if exist "%B_PATH%\DiskCompressTool.exe" (
    echo [クリーンアップ] システム標準ディスククリーンアップを実行します...
    "%B_PATH%\DiskCompressTool.exe" --instance %INSTANCE_NAME% --silent
    echo [クリーンアップ] ✨ディスク圧縮が完了しました。
) else (
    echo [クリーンアップ] ⚠️公式圧縮ツール未検出のため、タスクキル清掃のみでリスタートします。
)

timeout /t 5 /nobreak > nul
goto loop
