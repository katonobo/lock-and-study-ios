# Content Delivery Architecture v9

## 適用範囲

Lock and Studyで外部配信できるのは、JSON、SQLite、画像、音声、動画などの宣言的な教材アセットだけである。Swift、JavaScript、動的ライブラリなどの実行コードはApp Store配布物に限り、教材packageからロードしない。

本番`DependencyContainer`は`CompositeContentSource`を使い、検証済み`InstalledContentSource`、Bundle Catalog／教材、Safe Fallbackの順に読む。`ContentPackageStore`でApplication Supportへstage／activateした教材は、アプリ再ビルドなしに同じ`ContentRepository`から利用できる。テストでは`contentSource`または`catalogDataOverride`を注入できる。実ネットワーク、CDN、CMSは対象外であり、`RemoteContentSource`は契約だけを定義する。

## 信頼モデル

将来のremote catalogは、カタログ全体をP-256またはEd25519で署名する。検証用公開鍵はアプリへ同梱し、HTTPSやファイル単体のSHA-256だけを真正性の根拠にしない。署名対象には最低限、次を含める。

- catalog schema versionと生成日時
- Category、Series、Pack、Componentの関係
- pack ID、content version、minimum app version
- 各ファイルの相対path、SHA-256、byte size、schema version、item count
- progress migration document
- 公開・販売・Pass・年度・後継教材の状態

鍵rotationは、現在の信頼済み鍵で次期公開鍵と有効期間を署名する段階的な方式にする。未知の鍵、期限外の鍵、署名不一致のカタログは保存もactivationも行わない。最後に検証済みのカタログを保持し、1件の非互換packが他packを利用不能にしない。

## 安全な取得と展開

remote実装は次の順序を変えない。

1. Application Support配下の一意なtemporary directoryへ取得する。
2. catalog署名と鍵の有効期間を検証する。
3. download byte sizeとSHA-256を検証する。
4. safe extractionを行う。絶対path、`..`、symlink、hard link、package root外参照、過大なファイル数・展開量を拒否する。
5. manifest、minimum app version、Experience、component schema、item count、sample IDを検証する。
6. package内の全descriptorを再度SHA-256検証する。
7. 同一volumeのstaging directoryへflushし、完成したversion directoryへ原子的にrenameする。
8. `active.json`をatomic writeで切り替える。
9. active packageをRepositoryからsmoke testし、失敗時は直前versionへrollbackする。

stagingまたは検証の失敗時は旧active pointerを変更しない。同じpackへのstage、activate、rollback、removeは`ContentPackageStore` actor内で直列化する。active versionは、別の有効versionまたはBundle fallbackを確保する前に削除しない。

## ローカル配置

```text
Application Support/
  Content/
    Packs/
      {packID}/
        active.json
        {contentVersion}/
          package.json
          content files...
```

`packID`、`contentVersion`、descriptor pathはpath componentとして検証する。Repositoryのcache keyは`pack ID + content version + component ID`とし、保存場所をRepositoryへ露出しない。

## Fallbackとオフライン

読み込み優先順位は次のとおりである。

1. 検証済みInstalled active version
2. Bundle同梱version／無料sample
3. Safe Fallback

Installedのhash・件数・schema検証に失敗した場合、Repositoryは次の候補へ進む。Catalogはentryをstrict decodeし、参照破損branchを隔離する。root/schemaなどの重大な更新失敗では、同一Repository instanceが保持する最後の正常Catalogへrollbackする。Remote導入時はこのlast-known-goodを永続化し、署名済みCatalogに拡張する。

通信不能、署名不一致、hash不一致、minimum app version不適合、新しすぎるschemaでは、最後に正常利用できた状態を維持する。購入権の再検証に失敗しても教材ファイルを即時削除しない。ロック、管理コード、緊急解除、再ロックは通信、StoreKit、remote教材に依存させない。

無料sampleとSafe Fallbackは常にアプリへ同梱し、有料権利やdownload状態にかかわらず解除学習の安全な復旧経路として残す。教材破損を無条件解除の理由にはせず、同時に永久ロックにもつなげない。

## Backup、容量、プライバシー

download assetは再取得可能なcacheとして`URLResourceValues.isExcludedFromBackup = true`を設定し、iCloudおよび端末backupの対象外にする。購入権失効時はアクセス範囲だけを戻し、package削除は明示的な容量管理policyまたはユーザー操作で行う。

remote配信の導入を、学習履歴、Screen Time token、対象アプリ名の送信と結び付けない。学習データ同期には別の設計と明示同意が必要である。

## Progress更新

同じpackの更新は`ProgressCompatibilityPolicy`を宣言する。

- 誤字・説明改善：`preserve`
- 正解や論点の変更：`resetChangedItems`
- item IDの置換・統合：`migrate`
- 新年度：別pack ID

migration documentも署名・hash検証の対象とし、適用前backup、冪等な適用、件数確認、適用済みversion記録、失敗時rollbackを必須にする。回答履歴には回答時点の問題snapshotを残す。

## v10で実装・実証済みの保証

- BundleとInstalledを同一Repositoryから読める。
- stage完了前にactiveを変更しない。
- SHA-256、件数、schema、minimum app version、path traversalを検証する。
- active pointerを原子的に切り替え、previous versionへrollbackできる。
- Installed破損時にBundleへfallbackできる。
- 本番と同じ`DependencyContainer`からInstalled四字熟語を開き、Flashcard解除sessionを生成できる。
- Catalog Dataをテスト注入でき、Installed packageを優先できる。
- strict decode、Category参照隔離、last-known-good rollbackをテストする。

署名検証、実download、safe archive extraction、容量管理UIはremote配信導入時の実装項目であり、本番配信を開始する前に上記の信頼モデルを満たす必要がある。
