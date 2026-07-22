# 新しいExperienceを追加する

## まず新教材か新しい学び方かを判定する

既存の回答方法と学習ライフサイクルで扱える教材は、新Experienceではなく新しいStudy Packとして追加する。

- 四字熟語、漢字、古語、TOEIC単語：`flashcard.v1`
- FP、ITパスポート、行政書士、マナー検定：`certification.v1`
- 仕訳入力、リスニング、記述添削：必要な場合のみCustom Experience

既存Templateへ追加する場合、本番Swiftの変更は不要である。Category、Series、Pack、Component、教材ファイルに加え、manifestの`presentation.flashcard`または`presentation.certification`を追加し、検証スクリプトと教材テストを通す。固定レベル、教材名、単位、検索文言、年度表示をSwiftへ追加しない。

## Factory契約

Custom Experienceは`StudyExperienceFactory`を実装し、`StudyExperienceRegistry`へ1回登録する。Factoryはpack IDを列挙せず、manifestの`experienceID`とcomponentの`contentSchemaID`で互換性を判定する。

必須契約は次のとおりである。

1. 一意で開いた`StudyExperienceID`と、対応する`ContentSchemaID`集合
2. manifest compatibility validator
3. content decoderと、件数・ID・回答・説明・schemaのvalidator
4. 通常学習のroot UIと、必要ならpack単位のfirst-run UI
5. `StudyExperienceSessionRuntime.createSession`とversion付きopaque payload
6. 解除challenge UI、`StudyAnswerValue`の検証、回答遷移、active review tick、完了証明
7. Experience内部の型から回答snapshotを含む`StudyAnswerRecord`への変換
8. 誤答時に必要なactive review exposureの計算
9. completion hookと120秒preview等のpack単位pending state
10. 一時状態のcleanup
11. pack別・全体レポート用provider
12. 通常、解除、復旧、期限切れ、冪等性、履歴分離のテスト

Factoryは教材固有の質問型、正解判定、解説時間、SRS、法令基準日を所有する。`AppModel`、`UnlockChallengeSessionCoordinator`、`ScreenTimeLockManager`へ教材固有のswitchを追加しない。

## Unlock Runtimeの境界

Lock Coreへ返すものは`ExperienceCompletionProof`であり、質問内容や正解Choice IDではない。共通envelopeには次だけを保存する。

- session、request、pack、experience ID
- content versionとpolicy version
- 開始・期限
- completion stateと一意なcompletion event ID
- engine payload schema IDとopaque payload

Factory／Experience側だけがopaque payloadをdecodeして学習を再開する。新しすぎるschema、破損、期限切れ、pack不一致はfail closedでabortし、解除を作らない。完了証明は冪等に受理し、同じ完了で複数の解除sessionやイベントを作らない。旧`ExperienceUnlockBundleSnapshot`を扱うコードは`Compatibility`以外へ追加しない。

## Content packageの要件

- IDは既存と衝突せず、未知値をdecodeできる文字列にする。
- descriptor pathはpackage root相対で、絶対path、`..`、symlink逸脱を禁止する。
- SHA-256とitem countをカタログへ記録する。
- minimum app versionとschema versionを宣言する。
- 無料sampleを明示し、解除不能時はBundleのSafe Fallbackを利用できるようにする。
- Draft、`ai_draft`、未校閲問題をReleaseへ含めない。

## 状態とCommerce

設定、first-run、preview、進捗、回答、レポートは必ず`pack ID`でscopeする。同じExperienceと同じitem IDを複数packで使用しても混ざらないことをテストする。

買い切り商品はmanifestの`oneTimeProductID`で解決する。Pass商品だけが固定設定である。年度版は別pack／別商品にし、旧年度の所有権を自動継承させない。`archivedOwnedOnly`は新規購入不可だが既存所有者は利用できる。

## 登録手順

1. Experience ID、content schema、payload schemaのversioning方針を決める。
2. decoder／validatorとFactoryを実装する。
3. root UI、解除UI、回答記録変換、completion／cleanup／report hookを実装する。
4. RegistryへFactoryを登録する。
5. DEBUG／Unit Test用のCategory、Series、Pack、Component fixtureを追加する。
6. 同一item IDの別pack分離、再起動復旧、期限切れ、破損payload、Safe Fallbackをテストする。
7. Fake Factoryと同じく、Registry登録だけでAppModelの開始、opaque復元、回答、完了一回性、期限切れFail Closedが通るテストを追加する。
8. Catalog／Commerce／Content検証を追加し、`./scripts/verify`、Release Archiveを通す。

Custom Experience登録で変更してよい共通箇所はRegistryのcomposition rootだけである。Lock Core、Commerce Core、Catalog UIへ分岐を追加する必要が生じた場合は、Factory契約またはmanifestモデルの不足として先に境界を見直す。
