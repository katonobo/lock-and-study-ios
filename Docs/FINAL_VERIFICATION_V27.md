# 宅建v26 Internal Content Review v27 最終検証

検証日: 2026-07-24

## 結論

Productionと内部レビュー候補の信頼境界を分離した。Productionは従来の校閲済み宅建100問だけを公開し、`ai_review_candidate`を引き続き拒否する。`LockAndStudyContentReview`だけが、専用コンパイルフラグ、固定SHA、`saleReady=false`、外部法令校閲必須、法令checklist承認0件をすべて確認した上で、宅建v26候補をFail Closedで受理する。

ProductionのLock Controller、Shield、Device Activity、再ロック、管理コード、緊急解除、StoreKit Product ID、共通Unlock Runtimeのロジックは変更していない。

## 必須数値

| 項目 | 結果 |
|---|---:|
| Production Unit Test | 177 / 177 成功 |
| Production UI Test | 37 / 37 成功 |
| Review Candidate Unit Test | 4 / 4 成功 |
| Review Candidate UI Test | 2 / 2 成功 |
| Production Archive内の候補ファイル検出 | 0 |
| Review Archive内の候補SHA一致 | 2 / 2 |
| Production公開宅建問題 | 100 |
| Review候補問題 | 1,000 |
| Review無料候補 | 100 |
| Review候補Concept | 380 |
| Unlock対象 | 680 |
| `reviewStatus == ai_review_candidate` | 1,000 / 1,000 |
| `saleReady` | catalog / metadataともにfalse |
| legal checklistのtrue | 0 |
| placeholder | 0 |

固定SHA:

- 全1,000問: `af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263`
- 無料100問: `52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e`

Productionの公開4ファイルはv26反映前の内容へ復元した。

- `study_pack_catalog.json`: `05571a3a05926f1c2ef28caef70f9991a3b2a4df550737345b8a47ff74e44685`
- `takken2026_metadata_v1.json`: `39b43f05f1cfe42c787731f710532156cb40d65be8266295e23144d7792f3f66`
- `takken_2026_free_100_v1.json`: `6d4ce62f86a2a0b7805ec39442e3b01968c9f11947b9c2dd7fbbf8055e00d6af`
- `takken2026_credits_v1.txt`: `753afb82e7d9eb63341660ac5085c2431121f59e3e32e710ef087d0a944592a6`

## 検証ゲート

次の独立ゲートはすべて成功した。

```bash
PYTHONDONTWRITEBYTECODE=1 ./scripts/release_readiness
PYTHONDONTWRITEBYTECODE=1 ./scripts/validate_takken_v26_candidate
PYTHONDONTWRITEBYTECODE=1 ./scripts/review_candidate_readiness
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_content_review_boundaries
```

- Production policyが同じv26候補を拒否するXCTest: 成功
- Internal Review modeだけが全条件を満たした候補を受理するXCTest: 成功
- Production catalogへ候補profileを入れた場合の静的拒否: 成功
- top-level `questions` 100件の受理、ID重複、件数不一致、不明rootの拒否: 成功
- 全5問題形式、680問のUnlock対象、case study / integrated mockのUnlock対象外: 成功
- 無料100問 / 全1,000問アクセス切替: 成功

## Build、Test、Archive

以下をProductionとReviewの各Schemeで実行し、Debug simulator build、Unit/UI Test、generic iOS Release build、Archiveが成功した。

```bash
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudy \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' test
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudyContentReview \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' test
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudy \
  -configuration Release -destination 'generic/platform=iOS' build
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudyContentReview \
  -configuration Release -destination 'generic/platform=iOS' build
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudy \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-v27-production.xcarchive archive
xcodebuild -project LockAndStudy.xcodeproj -scheme LockAndStudyContentReview \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-v27-review.xcarchive archive
```

両ArchiveはApple Development署名と、Productionで使用中のFamily Controls / App Group対応Provisioning Profileを使用した。Review Schemeだけに`-DLOCKANDSTUDY_INTERNAL_CONTENT_REVIEW`が入り、Productionのコンパイルコマンドには入っていない。

Archive実物の検査:

```bash
./scripts/scan_content_review_bundle production \
  /tmp/LockAndStudy-v27-production.xcarchive/Products/Applications/LockAndStudy.app
./scripts/scan_content_review_bundle review \
  /tmp/LockAndStudy-v27-review.xcarchive/Products/Applications/LockAndStudyContentReview.app
```

結果:

```text
PASS: Production bundle candidate file count=0
PASS: Review bundle contains both candidate files at exact SHA
```

## UI確認

Review UI Testで次を確認した。

- 常設の「内部コンテンツレビュー / 未校閲・販売禁止」
- review catalogから宅建教材を表示
- 購入機能と価格・Study Pass導線を無効化

Productionの既存UI Test 37件もすべて成功した。テスト中にXcodeの`DebuggerLLDB.DebuggerVersionStore.StoreError`警告が出たが、runnerは起動し、全テストが成功したためコード障害とは判定していない。

## 実機手動確認

検証時に接続されていた物理端末はMacだけで、iPhoneは接続されていなかった。このため、次の実機手動項目は未実施である。

- 宅建ホーム、分野・形式filter、5形式の回答
- 誤答解説と再回答、120秒予習
- Shieldから1〜3問、一時解除、再ロック
- conceptID単位の履歴・レポート

署名済みReview Archiveは作成済みである。iPhone接続後は`LockAndStudyContentReview` Schemeを選び、`Docs/INTERNAL_CONTENT_REVIEW_V27.md`の手順で確認する。Review appはProductionと同じBundle IDを使うため、端末上のProduction appを置き換え、同時インストールはできない。
