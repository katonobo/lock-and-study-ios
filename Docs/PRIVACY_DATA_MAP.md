# Privacy Data Map

| データ | 保存先 | 用途 | 保持・削除 |
|---|---|---|---|
| Screen Time選択token | main App Group | shield対象 | ロック終了/全初期化で削除 |
| policy/session/request | main App Group | 安全な解除・拡張連携 | 更新上書き、終了時削除 |
| 管理コードsalt/verifier | Keychain | 保護操作の承認 | 明示削除/全初期化 |
| 緊急解除時刻・理由code | main App Group | rolling 24h制限 | 最大50件 |
| 学習進捗・event | Application Support | SRS/履歴 | 書出し可能、学習履歴削除で削除 |
| 回答snapshot | 月別NDJSON | 過去回答表示 | 書出し可能、学習履歴削除で削除 |
| StoreKit権利cache | main App Group | 起動時表示 | StoreKit再検証で更新 |
| 旧claim/progress | migration App Group | 一度限り移行 | claim消費印を付与、旧アプリ削除は利用者操作 |

外部送信、広告、分析、トラッキング、ランキング、パートナー共有はありません。Family Controls由来token、管理コード、receipt、個別学習履歴をsupport mailへ自動添付しません。問い合わせ本文はapp version、OS、locale、timezoneだけです。

Privacy Manifestはメインと3拡張に配置し、tracking=false、収集データなし、実使用Required Reason APIだけを宣言します。ポリシーURLはbuild settingから注入し、未設定またはexample URLはrelease readinessで失敗します。
