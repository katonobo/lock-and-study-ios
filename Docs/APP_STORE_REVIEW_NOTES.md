# App Store Review Notes / 審査メモ

## 日本語

ロックンスタディは、利用者が自分のiPhone/iPadを管理し、短い学習で選択したアプリを一時利用できる教育アプリです。遠隔監視、保護者向け遠隔操作、法人端末管理ではありません。Family Controlsは `.individual` 認可だけを要求します。

基本ロック、対象数、管理コード、24時間クールダウン、緊急解除は無料です。IAPは英単語/宅建教材、教材更新、学習計画・分析に対する対価です。固定無料英単語250語または宅建100問だけで、課金画面を経ず何度でも解除できます。公開教材は英単語3,000語（無料250語を含む）と宅建2026の品質確認済み無料100問です。未承認200問とAI草稿700問はアプリに含めません。

Shieldからアプリを直接起動できないため、主ボタンはrequestを保存してShieldを閉じます。通知許可時は案内通知、拒否時は手動でアプリを開く導線を表示します。弱化変更は管理コード、またはコード未設定時の24時間待機と二度目確認で保護します。緊急解除は購入状態に関係なくrolling 24時間に1回、15分です。管理コードはiOS設定からのFamily Controls取消やアプリ削除を防ぐものではありません。

データは端末内だけに保存し、広告、分析、追跡、外部送信はありません。

審査手順：初回画面で説明を進め、Screen Timeを許可（拒否しても完了可能）、無料英単語または無料宅建を選択します。設定でmockではない実対象を選び基本ロックを開始します。対象アプリのShield主ボタンを押し、本アプリを手動または通知から開き、無料問題に回答すると設定時間だけ解除されます。購入画面ではSandbox商品4件、復元、Passと個別購入の表示を確認できます。

## English

Lock and Study is an educational self-management app. A user manages apps on their own iPhone or iPad and temporarily accesses selected apps after a short learning activity. It is not remote parental monitoring, enterprise device management, or remote control. It requests only individual Family Controls authorization.

Core locking, target limits, the management code, the 24-hour cooldown, and emergency access are free. IAP funds learning packs, content updates, planning, and analysis. Users can keep unlocking without a paywall using the fixed 250-word English sample or 100 reviewed real-estate-license questions. Released content is 3,000 English words including the sample and 100 reviewed 2026 questions. The unapproved 200 questions and 700 AI drafts are not bundled.

Because a Shield extension cannot directly launch the app, its primary action stores an idempotent request and closes the Shield. An optional notification guides the user; if notifications are denied, the user opens the app manually. Weaker settings require the management code, or a 24-hour wait plus a second confirmation when no code is set. Emergency access is independent of purchases and permits 15 minutes once in a rolling 24-hour window. The management code cannot prevent revoking Family Controls in iOS Settings or deleting the app.

All data stays on device. There are no ads, analytics, tracking, or external data transmission.

Review steps: complete onboarding (Screen Time may also be skipped), choose either free pack, authorize Screen Time, select an app, and enable the core lock. Open the selected app, press the Shield primary button, then open Lock and Study manually or from the optional notification. Answer the free learning item to unlock for the configured duration. The purchase screen exposes four Sandbox products, restore, and the combined Pass/owned-pack state.
