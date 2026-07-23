# Lock and Study v15 最終検証記録

検証日: 2026-07-23

## 実装結果

- `true_false`を正規化後も「正しい」「誤り」の正確な2択へ限定
- `number_choice`を短い数値・比率・期間・金額へ限定し、単位の欠落・混在を拒否
- NFKCにより全角数字、`％`、日本語数字を同一ゲートで検査
- prompt、choice、誤答理由、解説、`keyPoint`、preview全体、`contrastNote`、`sourceNote`へ草稿marker検査を拡張
- `sourceNote`の具体性と`reviewedAt`の実在日付を必須化
- 教材authoring commandのPython bytecode生成を抑止
- v15の正常系・異常系フィクスチャを`verify_platform_v14.py`へ追加

## 承認状態

無料V2は実機確認済みで、確認された宅建問題の内容・方向性も受け入れ済みである。ただし、この確認を400候補の個別校閲記録へ読み替えていない。

- 公開中の宅建: 100問
- v2候補: 400問、すべて`ai_draft` / distractor `pending`
- `expectedItemCount`: 100
- `saleReady`: `false`
- 新たに自動昇格した候補: 0問
- 旧200問: `ContentSource/Reviewed`に隔離したまま

`scripts/platform_freeze_v14.json`、公開100問、400候補、catalogのSHA-256は検証前後で一致した。Swift本体への変更はなく、Lock Core、Catalog / Commerce、Experience Runtime、Content transaction、SwiftUI、unlock、commerce、reportingのfreezeを維持した。

## 教材・Release検証

実行:

```sh
./scripts/audit_takken_content_v14
./scripts/export_takken_review_batch 1
./scripts/release_readiness
```

batch 1は50件、全件`ai_draft` / distractor `pending`であることを確認後、生成JSONを削除した。

結果:

- Takken content isolation and review-queue audit: passed
- v9〜v15統合検証: passed
- Released content / Privacy / StoreKit / App Icon / legacy identifier / release safety: passed
- Release readiness: passed
- `scripts`配下の`__pycache__` / `.pyc`: 0件
- Swift parse: 94ファイル passed

v15回帰フィクスチャは、正常な校閲済み項目、日付のみ・offset付き日時、NFKC数字・日本語数字を受理する。未校閲項目、不正な○×選択肢、3択○×、数値単位欠落、単位混在、草稿marker、入力placeholder、`sourceNote`欠落、存在しない日付を拒否する。

## Xcode Build / Test

環境:

- iPhone 16 Pro Max Simulator
- iOS 18.4
- arm64
- StoreKit configurationを使用する`LockAndStudy` scheme

結果:

- Debug simulator build: passed
- Release simulator build: passed
- Unit Test: passed
- UI Test: passed
- 合計: 196 tests passed / 0 failed / 0 skipped
- xcresult: `.build/V15FinalTestDerivedData/Logs/Test/Test-LockAndStudy-2026.07.23_12-39-56-+0900.xcresult`

## Release Archive

実行:

```sh
xcodebuild -quiet \
  -project LockAndStudy.xcodeproj \
  -scheme LockAndStudy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-v15-final.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  archive
```

結果:

- Archive: passed
- Bundle ID: `com.ameneko.lockandstudy`
- Architecture: arm64
- App Extension: 3件
  - `LockAndStudyDeviceActivityMonitorExtension.appex`
  - `LockAndStudyShieldActionExtension.appex`
  - `LockAndStudyShieldConfigurationExtension.appex`

## 残る人手工程

400候補をReviewedまたはReleaseへ昇格するには、各項目について校閲担当者、実在する校閲日、具体的な校閲メモと出典、5項目の法令チェック、誤答理由を記録する。無料V2の実機・教材方針の確認だけでは、この個別記録を代替しない。

App Store提出前には配布署名でOrganizerのValidate Appを実行し、Family Controls許可、Device Activity、Shield表示・解除、購入・復元を実機で最終確認する。
