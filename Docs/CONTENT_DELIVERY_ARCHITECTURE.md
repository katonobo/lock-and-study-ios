# 教材配信アーキテクチャ

## 境界と現在の構成

`StudyExperience`はApp Storeから配布する実行コード、専用UI、学習エンジンである。`StudyPack`は宣言的な教材データであり、外部から実行コードを取得しない。Manifestの`experienceType`が両者を結び、`packID`は教材・購入権・設定・予習・進捗の永続IDとして扱う。

Phase 0では`ContentAssetSource`を境界にし、`BundledContentSource`が同梱カタログとpackage rootを返す。`ContentRepository`はactorとしてカタログ、SHA-256検証済み教材、無料sample IDを`packID + contentVersion`単位でcacheする。`VocabularyRepository`、`TakkenQuestionRepository`、`VerifiedContentLoader`は解決済みpackage rootだけを受け取り、root外への絶対path、`..`、symlink逸脱を拒否する。

`ContentPackageStore`と`InstalledContentSource`はApplication Supportの次の配置を扱うPhase 1の入口である。

```text
Application Support/
  LockAndStudy/
    Content/
      Packs/
        {packID}/
          active.json
          {contentVersion}/
```

`active.json`はatomic writeで切り替える。利用中versionは削除せず、旧versionはrollback可能な期間を設ける。

## リモートカタログの信頼モデル

Phase 1では、カタログ全体をEd25519またはP-256で署名し、検証用公開鍵をアプリへ同梱する。各ファイルのSHA-256、byte size、schema version、件数は署名対象のカタログに含める。HTTPSとSHA-256だけを信頼の根拠にせず、署名検証に失敗したカタログやpackageはactiveにしない。鍵更新は旧鍵で署名された次期公開鍵と、有効期間を持つ段階的rotationで行う。

最後に検証済みのカタログを保持し、新しいカタログの署名、互換性、時刻条件に失敗した場合は置き換えない。未知の`moduleType`や`experienceType`、新しすぎるschemaはそのpackだけを非互換とし、他packの利用を継続する。

## 安全なインストールとrollback

```text
download to a unique temporary directory
-> signature / expected size / SHA-256 validation
-> safe unzip (absolute path、..、symlink、展開量超過を拒否)
-> manifest schema / experience compatibility / item count validation
-> file flush and fsync
-> move into Content/Packs/{packID}/{contentVersion}
-> atomic active.json replacement
-> open and smoke-test active package
-> retain previous verified version for rollback
```

一時directoryと最終directoryは同一volumeに置き、activationはrenameまたはatomic pointer replacementで行う。途中失敗時は旧active packageを維持する。起動時にactive pointerとpackageの整合性を確認し、不整合なら直前の検証済みversion、同梱sample、Safe Fallbackの順で復旧する。同一packへのinstall、activate、removeはstore actor内で直列化する。

## UI状態

インストールUIは次を明示的な状態として持つ。

- 未インストール
- ダウンロード中（進捗、停止、再試行）
- 検証中
- インストール済み
- 更新あり
- 非互換（アプリ更新が必要）
- 失敗（理由と安全な再試行）

教材の販売状態はインストール状態と分離する。`availableFrom`前は公開前、`saleReady == false`は新規購入不可、`retiredAt`後は未所有者に販売終了として表示する。販売終了済みでも所有者は利用と再インストールができる。`supersedesPackID`が示す後継教材は案内に使うが、自動的に購入権や学習履歴を移さない。

## オフライン保証

通信できない場合は次の順序で利用する。

1. 最後に検証済みのカタログ
2. 最後に正常起動したインストール済みpackage
3. アプリ同梱の無料sample
4. Safe Fallback

ロック解除、安全解除、管理コードはネットワークや有料権利に依存させない。有料権利をオンラインで再検証できない場合は有効期限付きcache policyを適用するが、教材ファイルを即時削除しない。

## ストレージと削除

ダウンロード教材は再取得可能なcacheとしてiCloud／端末バックアップ対象外にする。画面には教材別容量、合計容量、削除、再ダウンロードを表示する。active versionの削除は新versionへの切替または同梱sampleへのfallbackが確立してから行う。購入権の失効・期限切れではアクセスだけを無料範囲へ戻し、package削除は容量管理policyまたはユーザー操作で行う。

## 進捗互換性

履歴の主キーは`packID + itemID`を維持する。content更新のmigration documentは`preserve`、`resetItem`、`migrate`を明示する。誤字修正は`preserve`、正解や論点変更は`resetItem`、ID置換は`migrate`とする。migrationは署名対象に含め、適用前backup、冪等な適用、適用済みversion記録、失敗時rollbackを必須とする。年度資格教材は原則として別pack IDにする。

## JSONからSQLiteへの移行

教材の執筆・校閲元はJSONを維持し、1教材が1万〜2万項目、複数大型教材、全文検索が必要になる前にbuild工程で読み取り専用SQLiteへcompileする。`ContentAssetSource`とRepositoryの境界は変えず、package内部実装だけを差し替える。

学習データは現在JSON／月別NDJSONである。回答transactionには更新・完了日時を持たせ、未完了transactionをpruneせず、重複確認はsubmission ID cacheを使う。数年分・数万回答・多数教材の横断reportへ進む前にSQLiteへ移行し、少なくとも次のindexを設ける。

- `(packID, itemID)`
- `answeredAt`
- `sessionID`
- `submissionID UNIQUE`
- `(experienceID, packID)`
- `conceptID`

移行は旧storeの読み取り専用backupを作成し、transaction内でimport、件数・checksum検証、切替marker保存を行う。再実行しても重複しない冪等設計にし、完了前は旧storeを正本として維持する。

## Phase 1の実装入口

1. `RemoteCatalogSource`と署名検証器を追加する。
2. `ContentPackageInstaller`を追加し、上記のtemp downloadからatomic activationまでを実装する。
3. `BundledContentSource`と`InstalledContentSource`を優先順位付きで合成するsourceを追加する。
4. インストール状態machineと容量管理UIを教材カタログへ接続する。
5. 同梱無料sampleを常にfallbackとして残したまま、有料全量データを段階的にpackageへ移す。

URLSession、CDN、差分更新はPhase 1で導入する。Phase 0のBundle ID、App Group、Family Controls Extension構成には変更を加えない。
