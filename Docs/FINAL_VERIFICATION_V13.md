# Lock and Study v13 最終検証記録

検証日: 2026-07-23

## 実装確認

- Activation Journalの`prepared`、`migrationApplied`、`pointerCommitted`を永続化
- journal作成直後、migration直後、pointer write直前／直後、journal削除直前のfault injection復旧
- rollback成功後の`previousContentVersion = nil`と明示的な再activate
- Package ValidatorとRuntime Repositoryで共有する`CertificationQuestionWireDecoder`
- 未列挙進捗に対する`defaultPolicy`の`preserve`、`resetChangedItems`、`migrate`
- v9〜v13共通Platform検証とPython bytecode混入防止

## Release Readiness

```sh
LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 ./scripts/release_readiness
```

結果:

- Released content verification: passed
- Platform v9 data-only fixture verification: passed
- Platform v10 completion verification: passed
- Platform v11 final hardening verification: passed
- Platform v12 final polish verification: passed
- Platform v13 content transaction hardening verification: passed
- Release readiness: passed

## 全体検証

```sh
./scripts/verify
```

結果:

- Debug simulator build: passed
- Release simulator build: passed
- Unit Test: passed
- UI Test: passed
- StoreKit configurationを使用したTest Scheme: passed
- 合計: 194 tests passed / 0 failed / 0 skipped
- 実行環境: iPhone 16 Pro Max Simulator, iOS 18.4, arm64
- xcresult: `.build/VerifyDerivedData/Logs/Test/Test-LockAndStudy-2026.07.23_07-05-56-+0900.xcresult`

## Releaseアーカイブ

```sh
xcodebuild -quiet \
  -project LockAndStudy.xcodeproj \
  -scheme LockAndStudy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-v13-final-20260723.xcarchive \
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

## 提出前の所有者確認

この記録は署名なしアーカイブまでを対象とする。App Store提出前には配布署名でOrganizerのValidate Appを実行し、実機でFamily Controls許可、Device Activity、Shield表示・解除、再起動中の教材更新、購入・復元を確認する。
