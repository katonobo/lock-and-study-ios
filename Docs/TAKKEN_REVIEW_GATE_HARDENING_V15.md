# 宅建レビューゲート堅牢化 v15

実装日: 2026-07-23

## 受領した確認と承認境界

無料V2は実機で確認済みであり、表示された宅建問題についても、この問題内容・学習方向で問題ないとの確認を受領した。この確認は、無料V2の実機動作と教材方針の受け入れとして記録する。

一方、この確認だけから400件の候補それぞれに`reviewer`、`reviewedAt`、`reviewNote`、`sourceNote`、法令チェック結果を捏造しない。候補は引き続き`ai_draft` / distractor `pending`のまま隔離し、個別の人手校閲記録が揃ったbatchだけを既存の昇格コマンドへ渡す。

## v15で強化した拒否条件

`validate_takken_v2_review_batch`とRelease候補検証は、従来の人手校閲ゲートに加えて次をFail Closedで検査する。

- `true_false`は正規化後の集合が正確に`正しい` / `誤り`で、選択肢数が2件
- `number_choice`は数値、比率、期間、金額の短い回答だけ
- 数値選択肢で一つでも単位を使う場合は全選択肢に同一単位が必要
- 全角数字、`％`、日本語数字はNFKC正規化後に同じ規則で検証
- `reviewedAt`は書式だけでなく暦として実在する日付・日時
- `sourceNote`はNFKC正規化後8文字以上の具体的根拠
- prompt、choice本文・rationale、`wrongChoiceRationales`、短文・長文解説、`keyPoint`、preview全フィールド、`contrastNote`、`sourceNote`を草稿markerの対象にする
- `誤答候補`、`対照文候補`、`要校閲`、`要点候補`、`詳細解説候補`、`pending-human-review`、`人間が確認する`、角括弧内の入力placeholderを拒否

受理例:

- `正しい` / `誤り`
- `5日` / `7日` / `10日`
- `５％` / `七%` / `１０％`
- `reviewedAt = 2026-07-23`
- `reviewedAt = 2026-07-23T08:00:00+09:00`

拒否例:

- `正しい` / `正しいとは限らない`
- `はい` / `いいえ`
- `5日` / `7` / `10日`
- `5日` / `7年` / `10日`
- `reviewedAt = 2026-99-99`
- `reviewedAt = 2026-02-30`
- 空または短すぎる`sourceNote`

## Python cacheの抑止

教材監査、batch export、Reviewed昇格、Release候補確認、候補生成、v14/v15統合検証は、ローカルモジュールをimportする前に`sys.dont_write_bytecode = True`を設定する。`scripts`配下に`__pycache__`または`.pyc`が残っていれば統合検証を失敗させる。

## 凍結状態

`scripts/platform_freeze_v14.json`は更新していない。Lock Core、Catalog / Commerce、Experience Runtime、Content transaction、SwiftUI、unlock、commerce、reportingには変更を加えていない。

公開中の宅建100問、`expectedItemCount = 100`、`saleReady = false`、旧200問の隔離、400候補の未承認状態を維持する。
