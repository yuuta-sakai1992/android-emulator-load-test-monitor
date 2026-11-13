# Android エミュレータ耐久負荷テスト 自動監視・復旧ツール

Android エミュレータ（BlueStacks 5）上で動作するアプリケーションの長時間耐久負荷テストを自動化し、**異常検知・エビデンス自動収集・自動復旧・HTMLレポート可視化・外部通知（Discord / Slack）** までを一貫して行うテスト自動化ツールです。

---

## 🎯 開発背景と解決した課題

モバイルアプリの長時間耐久テスト（メモリリーク検証や連続稼働テスト）を手動で行う場合、以下の課題がありました。

1. **アプリやエミュレータのハングアップ・クラッシュ時にテストが止まってしまう**
   - 夜間や無人稼働中に異常終了すると、翌朝までテストが停止したままになり検証工数が無駄になる。
2. **異常発生時の原因特定に必要なエビデンスが揃わない**
   - クラッシュ直前の画面状態や、Android 内部ログ（Logcat）をタイミングよく手動で取得するのが困難。
3. **長時間稼働によるホスト PC 側のメモリ肥大化・監視スクリプト自体の劣化**
   - 単一プロセスで何十時間もループさせると、監視側自体のメモリリークやタイマーずれが発生する。

これらを解決するため、**「監視制御（AutoHotkey v2）」と「プロセス管理・クリーンアップ（Windows Batch）」を終了コードで分離した自動復旧アーキテクチャ** を設計・実装しました。

---

## 📸 画面イメージ・動作実績

### 1. HTML 検証レポート（自動生成ダッシュボード）
テスト稼働時間・サイクル数・検知件数のサマリーに加え、Chart.js によるリソース消費推移グラフと、Logcat から自動抽出したエラー抜粋を一覧表示します。

#### ① リソース消費推移グラフ ＆ サマリー
<img width="1410" height="798" alt="スクリーンショット 2026-11-13 133633" src="https://github.com/user-attachments/assets/3f934bc3-7c5f-4c4e-9f64-163539c82907" />


#### ② 発生イベント・エビデンス一覧
<img width="1118" height="842" alt="スクリーンショット 2026-11-13 133658" src="https://github.com/user-attachments/assets/ec6d3d6d-68ed-47d9-afb7-800d443891da" />


---

### 2. 異常検知時の自動エビデンス撮影（撮影範囲の切替対応）
クラッシュやタイムアウトを検知した瞬間、用途に応じて **「PC画面全体（バッチ・監視GUIの稼働状況含む）」** と **「BlueStacksウィンドウのみ」** のどちらか好きな方を自動保存できます。

#### ① PC画面全体モード（システム全体の状態記録）
<img width="1920" height="1080" alt="20261113_135222_crash" src="https://github.com/user-attachments/assets/fba84888-e767-4968-b4d0-3648e0a28ee1" />


#### ② BlueStacksウィンドウ限定モード
<img width="558" height="958" alt="20261113_135337_crash" src="https://github.com/user-attachments/assets/a62e1da9-016d-4563-a8c5-543d205f19e9" />


---

### 3. リアルタイム外部通知（Discord / Slack Webhook）
異常検知やデモ体験の実行時、設定した Webhook URL へ発生日時・ステージ・詳細を即時通知します。

<img width="922" height="342" alt="ディスコ通知" src="https://github.com/user-attachments/assets/39d4fc30-cad7-46ee-89f4-b7ec90365834" />


---

### 4. メインGUI ＆ 詳細設定（4タブ構成）
監視間隔・4段階の自動復旧モード・メモリ解放・Logcat取得時間・エラー起点ログ抽出・Webhook設定をすべてGUIからリアルタイムに変更可能です。

#### ① メイン操作パネル
<img width="387" height="783" alt="GUIメイン画面" src="https://github.com/user-attachments/assets/62bcce63-c008-4ee1-91e1-676ba0d45e07" />


#### ② 詳細設定（タブ1：監視・復旧・デモ）
<img width="434" height="357" alt="GUI詳細画面(監視設定)" src="https://github.com/user-attachments/assets/f48943ee-4955-4f4e-8dfc-5f3840c13a22" />


#### ③ 詳細設定（タブ2：メモリ解放）
<img width="434" height="357" alt="GUI詳細画面(メモリ解放)" src="https://github.com/user-attachments/assets/b1ce0b33-333c-40a5-95ab-fa0153e3202d" />


#### ④ 詳細設定（タブ3：エビデンス・ログ抽出）
<img width="434" height="357" alt="GUI詳細画面(エビデンス)" src="https://github.com/user-attachments/assets/da9d0b4a-90c2-4164-b9e9-9d622a85bfaa" />


#### ⑤ 詳細設定（タブ4：外部通知 Webhook）
<img width="434" height="357" alt="GUI詳細画面(外部通知)" src="https://github.com/user-attachments/assets/865c0090-4d14-423b-99dd-2abc05490758" />



## 🏗️ システム構成・アーキテクチャ

```text
[ run_load_test.bat (プロセス管理・クリーンアップ層) ]
   │  ├─ 管理者権限への自動昇格
   │  ├─ BlueStacks 5 インスタンス起動
   │  └─ app_load_test_monitor.ahk を同期実行し終了コードを監視
   │       ├─ 終了コード 0  : ユーザー手動停止 → 安全終了
   │       ├─ 終了コード 10 : 異常検知 / 定時サイクル完了 → エミュレータ強制終了・ディスク圧縮後に両方再起動
   │       └─ 終了コード 11 : AHK単体リフレッシュ → エミュレータを維持したままAHKのみ再起動
   ▼
[ app_load_test_monitor.ahk (監視・制御・レポート生成層) ]
   ├─ 独立タイマー制御（画像認識スキャン / メモリ解放キー送信 / 1分間隔リソース計測）
   ├─ 2段階の例外ハンドリング
   │    ├─ 軽微な警告ダイアログ : ポップアップを自動クローズしてテスト継続
   │    └─ 致命的クラッシュ / 起動タイムアウト : スクショ・時刻指定Logcat保存 → Webhook通知 → 復旧分岐
   └─ レポート自動生成（CSV蓄積 → Chart.js 2軸グラフ＆エラー抜粋付き HTML ダッシュボード出力）
```

---

## ✨ 主な機能・技術的アピールポイント

### 1. 終了コード設計によるプロセス分離と4段階の自動復旧モード
- 監視スクリプト（AHK）とエミュレータ（BlueStacks）のライフサイクルをバッチファイルの終了コード（`0` / `10` / `11`）で制御。
- 用途やデモ状況に応じて、GUIから以下の **4つの復旧モード** を動的に切り替え可能です。
  1. **両方オン（本番耐久モード）**：タスクキル・`DiskCompressTool.exe` によるディスク圧縮後に両方再起動
  2. **BlueStacksのみ再起動**：監視GUIを維持したままエミュレータのみ再起動
  3. **AHKのみ再起動**：エミュレータを維持したまま監視プロセスのみリフレッシュ
  4. **両方オフ（デモ・確認モード）**：エビデンス保存・通知・レポート更新まで行い現状維持

### 2. 深刻度に応じた2段階の例外ハンドリング
- **継続可能な警告ダイアログ**：テスト続行可能なメモリ警告等は、クローズボタンを画像認識して自動で閉じテストを継続。
- **致命的クラッシュ・タイムアウト**：復元不能なエラー画面や起動タイムアウトを検知した瞬間、ディスプレイ暗転を自動解除して **スクリーンショット（PNG）** と **検知時刻からさかのぼった直近 N 分間の ADB Logcat（`logcat -T` 時刻指定）** を自動保存します。

### 3. 障害調査を効率化するログ抽出＆HTMLレポート可視化
- **HTML 検証レポート自動生成（`reports/test_report.html`）**：
  - WMI（`Win32_Process` / `Win32_PerfFormattedData_PerfProc_Process`）で取得した BlueStacks のメモリ使用量（MB）・CPU使用率（%）を CSV に蓄積し、**Chart.js** による2軸折れ線グラフで描画。
  - Logcat 内の `FATAL EXCEPTION` / `OutOfMemoryError` / `ANR in` を自動抽出し、一覧表内の折りたたみ（`<details>`）にスタックトレースをハイライト表示。
- **エラー起点ログ抽出 GUI**：直近の Logcat からエラー行をリスト表示し、選択したエラー発生時刻の **前後 N 分間** のログだけをワンクリックで切り出し可能。
- **アーカイブ退避付き新規リセット**：過去の計測 CSV・HTML を `reports/archive_YYYYMMDD_HHMMSS/` へ自動バックアップしてから新規計測を開始可能。

### 4. Discord / Slack Webhook リアルタイム通知連携
- Windows 標準 COM オブジェクト（`WinHttp.WinHttpRequest.5.1`）を使用し、外部ライブラリなしで JSON 形式の HTTP POST 送信を実装。
- 入力された URL から Discord / Slack のペイロード形式（`content` / `text`）を自動判別し、異常検知やサイクル完走をリアルタイム通知します。

### 5. セキュリティ・環境非依存設計と採用担当者向けデモ機能
- **秘匿情報と環境依存パスの外部化**：ツールパスや Webhook URL は `mode_config.ini` へ分離し、`.gitignore` で除外管理（公開用に `mode_config.example.ini` を同梱）。
- **デモ体験モード搭載**：エミュレータ環境がない PC 上でも、詳細設定内の「🧪 デモ体験」ボタンから **疑似リソース波形生成 → イベント記録 → HTMLレポート自動表示 → Webhook送信** の一連の流れをワンクリックで体験できます。

---

## 🛠️ 動作環境・セットアップ手順

### 動作環境
- **OS**：Windows 10 / 11
- **必須ランタイム**：[AutoHotkey v2.0](https://autohotkey.com)
- **テスト対象エミュレータ**：BlueStacks 5（ADB接続有効化済み）

### セットアップ
1. 本リポジトリをクローンまたは ZIP ダウンロードします。
2. `mode_config.example.ini` をコピーし、ファイル名を **`mode_config.ini`** に変更します。
3. 環境に応じて `mode_config.ini` の `[Paths]` セクション（BlueStacks や AutoHotkey のインストール先）を確認・編集します。
4. `run_load_test.bat` を実行すると、管理者権限へ自動昇格しテスト監視が開始されます。

### エミュレータなしで動作確認する場合（採用担当者様向け）
1. `app_load_test_monitor.ahk` を直接ダブルクリックして起動します（BlueStacks は不要です）。
2. GUI の **「⚙️ 詳細設定」** を開き、監視設定タブ下部の **「🧪 デモ体験 (疑似クラッシュ・レポート生成)」** をクリックすると、ブラウザで HTML 検証レポートが自動生成・表示されます。

---

## 📂 ディレクトリ構成

```text
├── run_load_test.bat            # プロセス管理・自動再起動・ディスククリーンアップ制御バッチ
├── app_load_test_monitor.ahk    # 監視制御・例外ハンドリング・HTMLレポート・Webhook通知本体
├── mode_config.example.ini      # 環境設定・通知設定のサンプルファイル
├── .gitignore                   # 個人設定(mode_config.ini)および生成ログ除外設定
├── img/                         # 画像認識用テンプレート画像 (.bmp)
├── error_logs/                  # [自動生成] 異常検知時のスクリーンショット・Logcat保存先
└── reports/                     # [自動生成] メトリクスCSV・HTML検証レポート・アーカイブ保存先
```
