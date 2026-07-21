# Owner Actions

コード外の資格情報、契約、素材、実機が必要な作業です。すべて完了するまでApp Store提出可能とは判定しません。

- [ ] メインApp ID `com.ameneko.lockandstudy` を作成
- [ ] 3拡張App ID（`.shieldconfiguration`、`.shieldaction`、`.deviceactivitymonitor`）を作成
- [ ] App Group `group.com.ameneko.lockandstudy` を作成し全4targetへ付与
- [ ] migration App Group `group.com.ameneko.lockandstudy.migration` を新旧3アプリへ付与
- [ ] メインと3拡張のFamily Controls Distribution Entitlementを申請・承認
- [ ] Distribution provisioning profilesを作成・更新
- [ ] App Store ConnectでStudy Pass subscription groupを作成
- [ ] 月額Pass、年額Pass、英単語pack、宅建2026 packの4 IAPを作成
- [ ] 各地域の価格を決定
- [ ] 年額Passに7日無料体験を設定
- [ ] 4商品でFamily Sharingを有効化
- [ ] IAP審査画像と日本語/英語localizationを登録
- [ ] `https://katonobo.com/lockandstudy-privacy-policy/` に実装一致のPrivacy Policyを公開・確認
- [ ] App Store用Support URLとsupport mailboxを公開・確認
- [ ] 最終App Icon一式をAssetsへ追加
- [ ] iPhone/iPadのApp Storeスクリーンショットを作成
- [ ] 宅建追加200問を最終承認しreviewer/承認日を記録
- [ ] 宅建AI草稿700問を資格者/専門家が全問校閲
- [ ] 旧2アプリへmigration patchを適用してアップデートを配布
- [ ] Sandboxで4商品、trial、Ask to Buy、restore、expiry/refund、Family Sharingを試験
- [ ] 実機でScreen Time、3拡張、通知拒否、再起動、iPadを試験
- [ ] Distribution署名でArchive Validationを成功させる
- [ ] Review Notesと審査アカウント/手順を確認してApp Reviewへ提出

宅建packは200問と700問の人手工程が終わり、manifestのcount/hash/saleReadyと販売文言を更新するまで販売しません。
