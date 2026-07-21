# Legacy migration patch usage

1. 同じDeveloper Teamで `group.com.ameneko.lockandstudy.migration` を作成します。
2. `SharedMigrationKit/LegacyMigrationKit.swift` を英単語側は `EitangoLock/Core/Migration/`、宅建側は `takkenlock/Core/Services/` へコピーします。
3. 対応するpatchを旧リポジトリのルートで `git apply --check`、続いて `git apply` します。
4. XcodeGenを使わない宅建側は、追加Swiftファイルをメインターゲットへ明示追加します。
5. 旧アプリ自身のStoreKit 2検証結果だけをwriterへ渡します。UserDefaultsのpremiumフラグからclaimを作ってはいけません。
6. 移行画面を設定画面へNavigationLinkで接続し、Sandbox購入・Family Sharing・期限付き旧Pass・重複importを実機確認します。

実行例：

```sh
git apply --check /path/to/eitangolock-migration.patch
git apply /path/to/eitangolock-migration.patch
xcodegen generate
```

宅建側はXcodeGenを使用していないため、`LegacyMigrationKit.swift` とpatchが追加するadapterの両方を `takkenlock` main targetへ追加してください。Developer Portalでもmigration App Groupを各App IDとprofileへ付け直す必要があります。

App Groupは信頼境界ですが、埋め込み秘密鍵は使用しません。digestは破損検知用であり、サーバー署名の代替ではありません。
