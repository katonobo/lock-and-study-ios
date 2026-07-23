# 宅建Concept Mastery v17

## 履歴からの導出

新しい永続ストアは追加せず、`StudyAnswerRecord`からconcept単位の状態を純粋関数で決定する。旧v1回答でconceptIDがない場合はitemIDをfallbackとして使う。

状態:

- 未回答: `unlearned`
- 直近の初回答が誤答: `relearning`
- 初回正解1回: `learning`
- 異なる2セッションで正解: `stabilizing`
- 異なる2variant以上を異なる2セッション以上で初回正解し、直近2回も初回正解: `mastered`
- 復習期限到来: `due`

同一セッション内の誤答後の正解はmasteredへ数えない。

## 復習間隔

concept単位の連続初回正解に応じて1、3、7、14、30日を使用する。誤答は6時間後を初期復習期限とする。このpolicyは`TakkenConceptMasteryPolicy`へ隔離している。

## Concept-first選択

利用可能問題をconceptでグループ化し、preview、due、relearning、A未学習、B未学習、通常復習、C未学習の順でconceptを選ぶ。その後、最近使っていないvariant、直近と異なるformat、弱点misconceptionに合うformatを選ぶ。同一sessionでは同じconceptを重複させない。distinct conceptが要求問題数に満たない場合は、同じconceptで水増しせず短いsessionを返す。

unlockでは`unlockEligible = false`または30秒超の長文case studyを除外する。30秒以内の短いcase studyは既存教材との後方互換のため利用可能とする。preview後は同conceptの別variantを優先する。

## レポート

既存回答数・正答率を残しつつ、学んだ論点、定着済み、定着途中、学び直し中、期限到来、異なるvariantで正解、今週新しく定着した論点を追加した。同じ論点を4問解いても4個の知識とは表示しない。
