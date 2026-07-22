# Commerce and Entitlements

権利は `activePass + ownedPacks + familySharedProductIDs + verifiedLegacyGrants` の複合snapshotです。UIの価格は常にStoreKitの `displayPrice` を使います。

| 状態 | Pass教材 | 所有パック | 無料sample |
|---|---:|---:|---:|
| 無料 / expired / revoked / refunded | × | 所有分のみ | ○ |
| active / grace period | ○ | ○ | ○ |
| billing retry | 新規権利としては不可 | ○ | ○ |
| Family Shared | 有効なら○ | 共有パック○ | ○ |
| Ask to Buy pending | 未確定 | 既存分のみ | ○ |
| verified legacy | 期限内Passまたはmapped pack | mapped分 | ○ |

`Transaction.currentEntitlements` と `Transaction.updates` はverifiedだけを受け入れます。revoked、upgraded、期限切れは除外します。購入はverified transactionを権利へ反映した後にfinishします。復元は `AppStore.sync()` 後に再解決します。

Passと個別所有は共存し、Pass終了後も個別所有を残します。Pass中の個別購入は「Passに含まれています」を先に示し、買い切り希望者向け操作は別の明示操作にします。宅建パックはStoreKit商品を定義済みですが、manifest `saleReady=false` の間は販売可能と表示しません。

年度版は必ず別`pack ID`・別`oneTimeProductID`で販売します。旧年度の買い切り権は新年度へ自動継承せず、新年度の買い切りまたは有効なPassが有料範囲に必要です。旧年度を`archivedOwnedOnly`へ移すと新規販売とPass対象から外れますが、既存所有者は引き続き開けます。Catalogの重複商品ID、年度・後継参照、販売状態はstrict validationとテストで確認します。
# Archived edition policy (v11)

年度版の権利方針は次に固定する。

- 最新の`forSale`版は個別買い切りまたはStudy Passの対象にできる。
- `archivedOwnedOnly`へ移行した過去年度版は、そのPackの買い切り権利（App Store、Family Sharing、検証済み旧版移行）を持つ利用者だけが開ける。
- Study PassはArchived版を開かない。旧Catalogの`activeAndArchived`はdecode互換のため残すが、`forSale`以外ではアクセスを許可しない。
- Pack availabilityと問題単位の`ContentAccessService`は同じ方針を使う。
