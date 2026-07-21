# Legacy Migration

旧アプリは自身のStoreKit 2 `verified` transactionだけからclaimを生成します。UserDefaultsのPremiumフラグは権利証明に使用しません。許可済みsource Bundle ID/product ID mapping以外は新アプリが拒否します。

claimはtransaction/original ID、購入・期限、ownership、nonce、破損検知digestを持ち、同一original transactionを重複生成しません。新アプリは取込時に`consumedAt`を記録します。学習進捗は安定IDを持つeventとしてexportし、複合pack/item IDへmax mergeするため再試行しても加算重複しません。

## 適用

1. Developer Portalで `group.com.ameneko.lockandstudy.migration` を3アプリに付与する。
2. [SharedMigrationKit/LegacyMigrationKit.swift](../LegacyMigrationPatches/SharedMigrationKit/LegacyMigrationKit.swift) を旧アプリのmain targetへコピーする。
3. 旧リポジトリrootで対応patchを `git apply --check`、`git apply` の順に適用する。
4. XcodeGen側は再生成する。宅建側は追加2 Swiftファイルをmain target membershipへ追加する。
5. 旧アプリを更新して「ロックンスタディへ移行」でexport後、新アプリ設定から取込む。

移行対象は購入権利と学習進捗です。Screen Time token、ロック設定、管理コード、緊急解除履歴は移行せず、新アプリで再設定します。App Groupは信頼境界ですが、digestをサーバー署名相当とは扱いません。

実機ではSandboxの買い切り、期限内/期限切れsubscription、Family Sharing、未購入、重複export/import、改変claim、両旧アプリからの連続移行を確認します。
