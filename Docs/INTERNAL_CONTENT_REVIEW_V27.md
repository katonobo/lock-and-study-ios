# 宅建v26 Internal Content Review v27

## 信頼境界

Productionの`LockAndStudy` targetは、校閲済み宅建100問を指す`study_pack_catalog.json`だけを利用する。`ai_review_candidate`、v26 candidate quality profile、候補JSONをProduction catalog、Released resources、Archiveへ入れてはならない。

`LockAndStudyContentReview` targetだけが、次を同時に満たす場合に候補をFail Closedで受理する。

- compile conditionが`LOCKANDSTUDY_INTERNAL_CONTENT_REVIEW`
- `saleReady == false`
- quality profileが`takken-v26-distinct-variant-review-candidate`
- metadataが外部法令校閲必須
- 全1,000問が`ai_review_candidate`
- 全法令checklistが5項目ともfalse
- placeholderが0問
- 全1,000問と無料100問のSHAが固定値と一致

候補のsource of truthは`ContentSource/TakkenWork/ReviewCandidates`である。Productionの`LockAndStudy/Resources/Content/Released`へコピーしない。

## Schemeとアクセス切替

XcodeGenのsource of truthは`project.yml`である。

```bash
xcodegen generate
open LockAndStudy.xcodeproj
```

実機ではScheme `LockAndStudyContentReview`を選ぶ。既存Screen Time entitlementとApp Groupをそのまま検証するため、Review appはProductionと同じBundle IDを使い、端末上のProduction appを置き換える。所有者のApple Developer Team `BNS246HYZU`でFamily Controls capabilityとApp Groupsが有効なProvisioning Profileを選ぶ。Review appとProduction appを同時にはインストールできない。

Review buildは既定で全1,000問を内部権限により開く。無料100問だけを確認する場合はSchemeのRun Argumentsへ次を追加する。

```text
-LockAndStudyContentReviewFreeSampleOnly
```

Review画面には常に「内部コンテンツレビュー / 未校閲・販売禁止」を表示し、購入、価格、Study Pass加入、購入復元は無効になる。

## 独立ゲート

Productionと候補のゲートは混在させない。

```bash
PYTHONDONTWRITEBYTECODE=1 ./scripts/release_readiness
PYTHONDONTWRITEBYTECODE=1 ./scripts/validate_takken_v26_candidate
PYTHONDONTWRITEBYTECODE=1 ./scripts/review_candidate_readiness
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_content_review_boundaries
```

build済みappを検査する。

```bash
./scripts/scan_content_review_bundle production /path/to/LockAndStudy.app
./scripts/scan_content_review_bundle review /path/to/LockAndStudyContentReview.app
```

Productionは候補ファイル検出0件、Reviewは候補2ファイルが固定SHA一致でなければ失敗する。

## Build / Test / Archive

```bash
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudy \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' test
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudyContentReview \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' test
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudy \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-Production.xcarchive archive
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudyContentReview \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-ContentReview.xcarchive archive
```

## 実機確認

Review Schemeで、宅建ホーム、分野・形式filter、5形式の回答、誤答解説と再回答、120秒予習、Shieldから1〜3問、一時解除、再ロック、conceptID単位の履歴・レポートを確認する。ロック系実装はProductionと同じで、Review用の分岐を追加していない。

Xcode 26.5でUI Test runnerが`DebuggerLLDB.DebuggerVersionStore.StoreError`により起動しない場合は、コード失敗と分離する。Xcodeを終了しDerivedDataを削除、Simulatorを終了・再起動、`xcrun simctl shutdown all`後に再実行する。それでも再現する場合はUnit Test、Debug/Release build、実機手動フローの結果と環境エラー全文を別記録し、教材を校閲済みへ昇格して回避してはならない。
