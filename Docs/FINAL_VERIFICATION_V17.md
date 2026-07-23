# Lock and Study v17 最終検証記録

検証日: 2026-07-23

## 制作データ

### Concept Master

- 論点数: 380
- 分野: 宅建業法140、権利関係110、法令上の制限65、税・その他65
- 重要度: A 120、B 180、C 80
- `reviewStatus`: 全380件 `ai_draft`
- 人間校閲済み: 0件

### Legacy Inventory

旧1,000問を一度ずつ棚卸しし、orphanは0件である。

| disposition | 件数 |
|---|---:|
| `base_variant_candidate` | 325 |
| `additional_variant_candidate` | 506 |
| `duplicate` | 1 |
| `requires_legal_research` | 130 |
| `integrated_case_material` | 38 |
| 合計 | 1,000 |

### Golden 100とVariant草稿

- Golden concepts: exactly 100
- Golden variant AI drafts: 270
- `reviewed` / `release`へ自動昇格: 0
- `distractorReviewStatus = checked`へ自動昇格: 0

| format | 件数 | 比率 |
|---|---:|---:|
| `true_false` | 73 | 27.04% |
| `number_choice` | 59 | 21.85% |
| `wording_contrast` | 59 | 21.85% |
| `multiple_choice` | 60 | 22.22% |
| `case_study` | 19 | 7.04% |
| 合計 | 270 | 100.00% |

同一意味の単純な言い換えは別variantとして認めない。数字、主体、時期、義務・任意、原則・例外、適用範囲、具体的事例の記憶経路をmetadataで区別する。現時点の270件は品質確認用のAI草稿であり、将来の1,000問以上のReviewed full packではない。full-pack gateは`minimumRequired = 1000`、`reviewedVariants = 0`、concept別の`variantShortageCount = 362`として閉じたままである。

## 未確認の出典一覧

完全な一覧はv18で`ContentSource/TakkenConcepts/Generated/source_research_queue_ai_draft.json`へ移行し、380件保存した。全件で次を維持している。

- `status = pending`
- `claimedSource = null`
- `reviewer = null`
- `reviewedAt = null`
- A 120件、B 180件、C 80件
- 宅建業法140件、権利関係110件、法令上の制限65件、税・その他65件

各entryは`conceptID`、論点名、旧問題ID、検索ヒントと必要証拠を持つ。必要証拠は法令名＋条項、公的資料名＋URL・公開日、判例情報などの追跡可能な情報である。具体的根拠を確認していないため、出典を推定・捏造せず全380件を人間のsource research queueへ残した。

## Release保護

- 公開100問SHA-256: `6d4ce62f86a2a0b7805ec39442e3b01968c9f11947b9c2dd7fbbf8055e00d6af`
- 公開catalog SHA-256: `05571a3a05926f1c2ef28caef70f9991a3b2a4df550737345b8a47ff74e44685`
- 公開問題数: 100
- `expectedItemCount = 100`
- `saleReady = false`
- `scripts/platform_freeze_v14.json`: 更新なし
- `ContentSource/ReleaseCandidates`: 生成なし
- StoreKit / Lock Core / Shield / shared Unlock Runtime: 変更なし

Golden、Free Sample、Full Packの各候補ゲートへ現在のAI草稿を入力すると終了コード1でFail Closedする。Release候補ファイルは書き出さない。

## 実装

- v16追跡可能出典ゲート、一般的すぎる出典の拒否、未来`reviewedAt`の拒否
- Concept Master / Legacy InventoryのschemaとValidator
- 決定的な旧1,000問分類、Golden 100抽出、Golden variant草稿生成
- concept review batch、coverage、Golden、free sample、full pack、v17 auditコマンド
- 回答履歴から導出するConcept Masteryと1・3・7・14・30日の復習間隔
- concept-first選択、variant / format分散、弱点misconception対応
- preview concept優先と別variant選択
- unlockで`unlockEligible = false`または30秒超の長文問題を除外
- 宅建レポートの定着済み、定着途中、学び直し、期限到来、複数variant指標
- v14/v15旧昇格経路へのv17 concept membership gate

## Phase回帰

各Phaseで`verify_platform_v14`、`verify_platform_v17`、対象XCTestを実行した。concept-first導入後に次の既存回帰を検出し、次Phaseへ進む前に修正した。

1. 形式ローテーションが不足形式を優先しない回帰を、concept rankのformat penalty追加で修正。
2. 「unlockで長文事例を除外」を全case study除外としていた回帰を、`unlockEligible`と30秒境界へ修正。既存の短時間case studyとの後方互換を回復。

修正後、v14 freeze、v17 static/data gate、対象XCTest、Swift全ファイルparseを再実行してから全回帰へ進んだ。

## 最終検証

環境:

- iPhone 16 Pro Max Simulator
- iOS 18.4
- arm64
- StoreKit configurationを使用する`LockAndStudy` scheme

結果:

- v14〜v17統合verification: passed
- Release Readiness: passed
- Takken v17 content audit: passed
- Golden / Free Sample / Full Pack draft rejection: passed
- 決定的再生成確認: passed
- Swift parse: 96ファイル passed
- Debug simulator build: passed
- Release simulator build: passed
- Unit / UI Test: 204 passed / 0 failed / 0 skipped
- xcresult: `.build/V17FinalTestDerivedData/Logs/Test/Test-LockAndStudy-2026.07.23_15-10-30-+0900.xcresult`

## Release Archive

- Archive: passed
- Archive path: `/tmp/LockAndStudy-v17-verified.xcarchive`
- Bundle ID: `com.ameneko.lockandstudy`
- Architecture: arm64
- App Extension: 3件
  - `LockAndStudyDeviceActivityMonitorExtension.appex`
  - `LockAndStudyShieldActionExtension.appex`
  - `LockAndStudyShieldConfigurationExtension.appex`

## 人間の次工程

source research queueのA tierから、法令名＋条項、公的資料名＋URL・公開日、判例情報を確認する。concept境界、重要度、数字・主体・時期・例外、誤答理由を校閲し、個別metadataが揃ったものだけをReviewed候補へ移す。現在のAI草稿を公開100問や有料packへ置き換えてはならない。
