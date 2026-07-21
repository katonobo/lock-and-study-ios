# ロックンスタディ / Lock and Study

iOS 16以降向けの、自分の端末を学習で一時解除するSwiftUIアプリです。基本ロック、安全機能、固定無料教材は無課金で継続利用できます。課金対象は教材パックとStudy Passです。

## 構成

- メインアプリとShield Configuration、Shield Action、Device Activity Monitorの3拡張
- 英単語3,000語（固定無料250語）
- 宅建2026の公開可能な無料100問
- StoreKit 2による月額・年額Passと2個別教材
- 管理コード、24時間クールダウン、rolling 24時間の緊急解除
- ローカル保存、エクスポート、削除、旧アプリ移行
- 選択教材を単一Rootとして表示する、独立したVocabulary/Takken Study Experience（各5タブ）
- 設定内の教材ラインナップ切り替えと、オンボーディング完了時の即時ロック開始

宅建追加200問はレビュー済みですが最終承認前、AI草稿700問は人手校閲前です。どちらもRelease Resourcesには入りません。

## 開発

Xcode 16以降と[XcodeGen](https://github.com/yonaskolb/XcodeGen)が必要です。

```sh
xcodegen generate
open LockAndStudy.xcodeproj
./scripts/release_readiness
./scripts/verify
```

`scripts/verify` は利用可能なiPhone Simulatorを選び、静的検証、Debug/Release build、Unit/UI Testを実行します。Xcode 26.5のStoreKitTest不具合を避けるため、インストール済みなら最新のiOS 26未満を優先します。特定端末を使う場合は `LOCKANDSTUDY_DESTINATION='platform=iOS Simulator,id=...'` を指定します。

正式App Iconは `AppIcon-Production.png` です。提出前は `LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 ./scripts/release_readiness` を実行してください。画像の存在、1024×1024、alphaなしも検証します。

署名、Family Controls Distribution Entitlement、App Store Connect商品、実機試験などは [OWNER_ACTIONS.md](OWNER_ACTIONS.md) を参照してください。設計資料は [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) から辿れます。
