# Lock and Study v12 最終検証記録

検証日: 2026-07-23

## 結果

v12最終ポリッシュ後のリリース検証、全テスト、Debug/Releaseビルド、署名なしReleaseアーカイブはすべて成功した。

### リリース前検査

```sh
LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 ./scripts/release_readiness
```

結果:

- Released content verification: passed
- Platform v9 data-only fixture verification: passed
- Platform v10 completion verification: passed
- Platform v11 final hardening verification: passed
- Platform v12 final polish verification: passed
- Release readiness: passed

### 全体検証

```sh
./scripts/verify
```

結果:

- Debug simulator build: passed
- Release simulator build: passed
- Unit Test: passed
- UI Test: passed
- StoreKit configurationを使用したTest Scheme: passed
- 合計: 190 tests passed / 0 failed / 0 skipped
- 実行環境: iPhone 16 Pro Max Simulator, iOS 18.4, arm64
- xcresult: `.build/VerifyDerivedData/Logs/Test/Test-LockAndStudy-2026.07.23_05-34-13-+0900.xcresult`

### Releaseアーカイブ

```sh
xcodebuild -quiet \
  -project LockAndStudy.xcodeproj \
  -scheme LockAndStudy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/LockAndStudy-v12-final-20260723.xcarchive \
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

## 提出前に所有者環境で行うこと

この検証は署名なしアーカイブまでを対象とする。App Store提出前には配布証明書とProvisioning Profileを設定し、OrganizerのValidate App、実機でのFamily Controls許可、Device Activity、Shield表示・解除、購入復元を確認する。
