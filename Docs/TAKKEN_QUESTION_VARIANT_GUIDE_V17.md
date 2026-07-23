# 宅建問題Variant制作ガイド v17

## Variantの目的

variantは問題数を増やすための言い換えではない。同じconceptを、別の記憶経路でも再生できるか確認するために作る。

有効な経路:

- `judgment`: 正誤判断
- `number`: 期限・割合・金額の直接再生
- `actor-timing-wording`: 主体、事前／事後、義務／任意の識別
- `comparison`: 類似制度の比較
- `application-exception`: 具体的事例と例外適用

語尾変更、選択肢順変更、正誤反転だけの問題は別variantに数えない。同一concept内の`variantID`は経路を表す安定IDとする。

## 品質条件

- `correctChoiceID`を正本とし、`correctIndex`を一致させる
- choice IDを安定化する
- すべての誤答に具体的rationaleとmisconceptionCodeを付ける
- misconceptionCodeは`actor`、`timing`、`number`、`scope`、`exception`、`obligation`、`procedure`、`document`、`condition`、`terminology`
- 数値選択は短い数値・比率・期間・金額だけにし、単位を統一する
- A論点は3形式以上、C論点は無理に3形式以上へ増やさない
- 解除向けは30秒以内・単一論点とし、新規制作ではcase studyを原則使わない
- 複合問題は`integratedConceptIDs`を持ち、原則unlock対象外にする

Runtimeは既存教材との後方互換のため、`unlockEligible = true`かつ30秒以内の短いcase studyを許容する。30秒超の長文事例と複合問題は除外する。

## 解説と予習

shortExplanationは規則を直接1〜2文で示す。longExplanationは主体・時期・数字・適用条件・例外と誤答理由を追加し、短文の言い換えだけにしない。previewは問題文と答えの丸写しではなく、次に思い出す規則と混同対象を示す。

## AI草稿

現在のGolden variant 270件は既存素材から異なる形式を決定的に選んだAI草稿である。`ai_draft`、distractor `pending`、`sourceNote = null`を維持する。rationaleに示す分類は校閲済みの法的断定ではない。

人間校閲が完了するまで`check_takken_golden_candidate`は失敗し、`generate_takken_free_sample`は何も出力しない。
