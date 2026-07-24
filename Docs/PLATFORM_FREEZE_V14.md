# Lock and Study プラットフォーム凍結 v14

## 凍結対象

v14以降の宅建教材改善では、次の基盤を教材追加の都合だけで変更しない。

- Lock Core
- Catalog / Commerce
- Experience Runtime
- v13 Content Delivery transaction、Activation Journal、進捗移行

`scripts/platform_freeze_v14.json`は対象ファイル集合、件数、内容SHA-256をfreeze hashとして保持する。`./scripts/verify_platform_v14`は現在の内容を再計算し、不一致を検出する。凍結対象を意図的に変更する場合は、具体的な本番不具合、回帰テスト、監査理由を記録してからmanifestを更新する。

## v14で許可した変更

- Certification教材のschema別package-level validator
- StageとRuntimeで共有する複数ファイル一括ポリシー
- 宅建v2の人手校閲、batch昇格、Release候補検証
- 上記のXCTest、静的検証、運用文書

英単語・宅建の画面、学習セッション、ロック・解除、購入権、レポートには変更を加えていない。

## Fail Closed条件

複数ファイル資格教材は、個別ファイルのhash・件数・schemaが正しくても、結合後にID重複、公開件数不一致、placeholder、未校閲status、無料sample不整合があればStageを拒否する。既存active packageは切り替えない。

AI草稿は、人手校閲メタデータを欠く限りReviewedへ昇格できず、Reviewedにある旧形式200問もv2ゲートを満たさない限りRelease候補にならない。

## v27で許可した信頼境界変更

宅建v26候補をProductionへ公開せず実機校閲するため、次の凍結対象だけを監査付きで更新した。

- `StudyPackManifest`が候補quality profileを欠落させずdecodeする一般互換修正
- `ContentRepository` / `BundledContentSource`へ同一`ContentTrustMode`を注入する変更
- Production defaultを`.production`のまま維持し、専用compile flagがあるReview targetだけ`.internalReviewCandidate`を使う変更

根拠は`LockAndStudy_V26_Implementation_Audit_v27.md`で確認されたProduction Runtime不一致と、未校閲候補がProduction Archiveへ混入していたP0問題である。公開済みロック、Shield、Device Activity、再ロック、管理コード、緊急解除、共通Unlock Runtimeには変更を加えていない。Productionが許可する資格問題statusも`checked/reviewed/release`のままであり、回帰テストと`release_readiness`、Production/Review双方のbundle scanを追加したうえでfreeze hashを更新した。
