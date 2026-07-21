# Baseline Audit

## 英単語側

添付ソースで `validate_content`、`check_legacy_strings`、`release_safety_check` は成功しました。正式3,000語と固定無料250語を確認しました。`verify_production_content` と `release_readiness` は、ZIPに日本語名の指示書ファイルが欠けていたことだけで失敗しました。製品実行時にそのファイルへ依存しない形へ変更しています。

採用したものは、Screen Time 3拡張の分離、学習で解除する基本フロー、正式英単語データ、固定無料sample、SRS/履歴snapshot、PBKDF2管理コードです。旧Premiumモデル、旧Bundle ID、旧App Group、単一教材前提は廃止しました。

Device Activity Monitorの既存実装には、強制再ロックcallbackが保存済み終了時刻より早く来てもshieldを適用できる経路がありました。新実装は全callbackで `endsAt` を確認して早期再ロックを防ぎます。

## 宅建側

公開設定の品質確認済み100問、最終承認前のreviewed 200問、3ファイル合計700問のAI草稿を確認しました。採用したものは品質確認済み100問、年度・法令基準日・カテゴリ・解説・review metadata、true/falseと4択の出題形です。

200問と700問は `ContentSource/` にのみ置き、app targetから除外しました。旧Premium、旧Bundle ID/App Group、全問利用可能という販売表現は採用していません。

## 新規統合

複合pack/item ID、権利と教材状態の中央access decision、固定解除snapshot、原子的ローカル保存、4商品StoreKit catalog、旧アプリの検証済みclaim移行を新規設計しました。その後、Platform Shellと独立したVocabulary/Takken Study Experienceへ分離し、通常学習は教材固有型、解除境界だけは共通Codable snapshotを使う構造へ更新しました。
