# Lock and Study v11 final verification

実施日：2026-07-23
環境：macOS / Xcode 26.5 / iOS Simulator 18.4

## 自動検証

- `xcodegen generate`：成功
- v11専用Unit Tests（9件）：成功
- Debug Simulator Build：成功
- `scripts/verify_platform_v11`：成功
- 全Unit / UI / StoreKit Tests：183件成功、失敗0、skip 0
- Release Simulator Build：成功
- unsigned Release Archive：成功（arm64、Bundle ID `com.ameneko.lockandstudy`）
- Archive内Extension：Device Activity Monitor、Shield Action、Shield Configurationの3種を確認

検証コマンド：`./scripts/verify`
xcresult：`.build/VerifyDerivedData/Logs/Test/Test-LockAndStudy-2026.07.23_04-27-03-+0900.xcresult`
Archive：`/tmp/LockAndStudy-v11-final-20260723.xcarchive`

## v11障害試験

- 保存EnvelopeのPack削除：`aborted`、回復画面、解除なし
- Experience不一致、不明Runtime、不明payload schema、content version不一致：すべて`aborted`
- Category/Series重複、Category cycle：Catalog全体rollback
- Pack-local不整合：対象Packのみ隔離
- cold launchで不正Catalog：永続LKGを復元
- 永続LKG破損：次のbundled候補へ復元
- 全候補不正：`safe-fallback.v1`だけを提供
- Safe Fallback回答：通常進捗・正答率・学習済み数から除外し、解除回数を別集計
- Archived Pack：Active Passだけでは開けず、買い切り所有者だけ利用可能

## 実機・外部サービスでの確認が必要な項目

次はSimulatorまたは署名なしArchiveでは完了できないため、リリース担当者が署名済み実機/App Store Connect環境で確認する。

- App Store Validation
- Family Controls / Device Activity / Shieldの実機Entitlement
- Shield起点の1問・2問・3問解除
- 誤答中のbackground / kill / relaunch
- 再ロック、日跨ぎ、時刻・タイムゾーン変更、権限取消・復帰
- Installed教材の実ネットワークstage / activate / rollback
- SandboxでのPass、買い切り、Family Sharing、解約の組合せ
