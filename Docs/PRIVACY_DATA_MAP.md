# Privacy Data Map

| データ | 保存先 | 用途 | 保持・削除 |
|---|---|---|---|
| Screen Time選択token | main App Group | shield対象 | ロック終了/全初期化で削除 |
| policy/session/request | main App Group | 安全な解除・拡張連携 | 更新上書き、終了時削除 |
| 管理コードsalt/verifier | Keychain | 保護操作の承認 | 明示削除/全初期化 |
| 緊急解除時刻・理由code | main App Group | rolling 24h制限 | 最大50件 |
| 学習進捗・event | Application Support | SRS/履歴 | 書出し可能、学習履歴削除で削除 |
| 回答snapshot | 月別NDJSON | 過去回答表示 | 書出し可能、学習履歴削除で削除 |
| 週次レポート | 保存なし（端末内で都度生成） | 本人・家族向けの7日集計 | 画面を閉じると再生成可能な一時値だけ破棄 |
| StoreKit権利cache | main App Group | 起動時表示 | StoreKit再検証で更新 |
| 旧claim/progress | migration App Group | 一度限り移行 | claim消費印を付与、旧アプリ削除は利用者操作 |

外部送信、広告、分析、トラッキング、ランキング、パートナー共有はありません。Family Controls由来token、管理コード、receipt、個別学習履歴をsupport mailへ自動添付しません。問い合わせ本文はapp version、OS、locale、timezoneだけです。

家族共有は利用者が`ShareLink`を押した場合だけ開始し、集計済みテキストだけを渡します。ロック対象アプリ名・FamilyActivitySelection token・管理コード・緊急解除理由・transaction ID・端末識別情報・個別の問題文や誤答内容は含めません。初期版は共有PDFを生成しないため、一時PDFファイルの作成・保持もありません。

Privacy Manifestはメインと3拡張に配置し、tracking=false、収集データなし、実使用Required Reason APIだけを宣言します。ポリシーURLはbuild settingから注入し、未設定またはexample URLはrelease readinessで失敗します。
