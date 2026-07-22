# Platform Foundation v9

## 完成した境界

Catalog v2はCategory、Series、Pack、Componentを開いたID型で表現する。Packは`experienceID`とcomponentの`contentSchemaID`を宣言し、Registryが対応Factoryを解決する。英単語・宅建というpack ID一覧でFactoryを選ばない。

共通基盤が担当するのはCatalog、権利、配信、永続化、解除sessionの状態遷移である。教材固有のUI、質問decode、回答記録変換、復習時間、preview、レポートはExperienceが担当する。

```text
Category -> Series -> Pack -> Component
                         |        |
                         |        +-> contentSchemaID + files
                         +-> experienceID -> StudyExperienceFactory
```

## データだけでの追加実証

`LockAndStudyTests/Fixtures/PlatformV9`は本番Releaseから隔離したテストカタログである。

- `language.japanese`／四字熟語6項目を`flashcard.v1`でロードする。
- `takken2027.fixture.v1`を2026とは別pack・別商品として`certification.v1`でロードする。
- 未知theme tokenを持つ`life.manners`／ビジネスマナーを既存`certification.v1`でロードする。
- 四字熟語packageをApplication Support相当へstage／activateし、破損拒否、Bundle fallback、rollbackを確認する。

fixture追加のために本番Factory、カテゴリーenum、StoreKit商品enumを変更していない。`scripts/verify_platform_v9`はfixtureの関係、template、schema、hash、件数、本番カタログへの非混入を検証する。

## 状態移行

`PlatformMigrationV9`は従来のselected packをactive unlock／opened／last studiedへ分離し、既存Experience単位のfirst-runと設定を既存packへ一度だけコピーする。完了flagにより冪等である。回答・進捗の主キー`pack ID + item ID`と既存IDは維持する。

旧解除bundleはopaque engine payloadを持つ共通envelopeへ冪等に移行する。期限切れ、未対応schema、proof不一致はabortし、解除を作らない。旧形式の質問enumは互換decode層だけに残す。

## リリース不変条件

- Bundle ID、App Group、Family Controls extensions／entitlementsを維持する。
- `english3000.v1`と`takken2026.v1`のpack、item、product IDを維持する。
- 英単語3,000語／無料250語、宅建Release 100問の件数とhashを維持する。
- Pass商品は固定、買い切り商品と過去商品mappingはCatalog駆動で解決する。
- ロック、管理コード、緊急解除、Safe Fallbackを購入や通信へ依存させない。
- DraftとfixtureをReleaseへ含めない。
