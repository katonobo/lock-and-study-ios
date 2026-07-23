# Lock and Study v14 最終検証記録

検証日: 2026-07-23

## 実装確認

- schema別`ContentSchemaPackageValidating`をStageへ追加
- Certification全ファイルのID、合計件数、placeholder、reviewStatus、sample整合をactive化前に検証
- Stageと`TakkenQuestionRepository`で`CertificationQuestionPackagePolicy`を共有
- 宅建v2の人手校閲メタデータ、法令チェック、誤答理由、草稿marker、形式比率ゲート
- 400候補を50問×8 batchとして扱う抽出・昇格・Release候補検証
- 旧200問、Draft 700問、v2候補400問のRelease非混入
- Lock Core、Catalog/Commerce、Experience Runtime、v13 Content transactionのfreeze hash

## 教材状態

人間による新規法令校閲結果は入力されていないため、Release教材を自動昇格していない。

- 公開中の宅建: 100問
- `expectedItemCount`: 100
- `saleReady`: `false`
- 新たに`reviewed`または`release`へ変更したAI草稿: 0問

## Release Readiness

```sh
PYTHONDONTWRITEBYTECODE=1 ./scripts/release_readiness
PYTHONDONTWRITEBYTECODE=1 ./scripts/audit_takken_content_v14
PYTHONDONTWRITEBYTECODE=1 ./scripts/platform_verifications
```

結果:

- Released content verification: passed
- Platform v9〜v14 verification: passed
- Takken v14 content isolation and review-queue audit: passed
- Privacy / StoreKit / App Icon / legacy identifier / release safety: passed
- Release readiness: passed

## Build / Test

Codexのcommand sandboxでは`./scripts/verify`内から起動したXcodeがCoreSimulatorServiceへ接続できなかったため、同スクリプトと等価な`xcodebuild`を許可済みの直接コマンドとして実行した。

結果:

- Debug simulator build: passed
- Release simulator build: passed
- Unit Test: passed
- UI Test: passed
- StoreKit configurationを使用したTest Scheme: passed
- 合計: 196 tests passed / 0 failed / 0 skipped
- 実行環境: iPhone 16 Pro Max Simulator, iOS 18.4, arm64
- xcresult: `.build/V14FinalTestDerivedData/Logs/Test/Test-LockAndStudy-2026.07.23_08-17-23-+0900.xcresult`

v13の194件に、複数ファイル資格packageの正常Stage/Runtime一致と、横断重複・件数不一致・未校閲・placeholderのStage拒否を検証する2件を追加した。

## Releaseアーカイブ

```sh
xcodebuild -quiet \
  -project LockAndStudy.xcodeproj \
  -scheme LockAndStudy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/lockandstudy-v14-verified.ZVOq7d/LockAndStudy-v14-final.xcarchive \
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

無料v2の250〜300問、有料宅建packの全問、2026-04-01法令基準の確認は、資格を持つ校閲担当者による内容確認が必要である。v14はその作業を安全にbatch化し、未完了の教材をReleaseへ入れない実装までを完了した。人手校閲が終わるまではcatalogの件数、hash、`contentQualityProfile`、`saleReady`を更新しない。

App Store提出前には配布署名でOrganizerのValidate Appを実行し、実機でFamily Controls許可、Device Activity、Shield表示・解除、再起動中の教材更新、購入・復元を確認する。
