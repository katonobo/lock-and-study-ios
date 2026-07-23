# 宅建教材改善ワークフロー v14

## 現在の安全な状態

v14ではプラットフォームを再設計せず、教材作成・人手校閲・配布前検証だけを強化した。現時点で人間による法令校閲結果は新たに提供されていないため、AI草稿を承認済みとみなしていない。

- Release無料版: 100問（○×95、4択5）、`checked`
- 旧形式の追加宅建業法: 200問、`ContentSource/Reviewed`に隔離
- 法令上の制限・権利関係・税その他: 合計700問、全件`ai_draft`
- 無料100論点のv2候補: 400問、全件`ai_draft` / distractor `pending`
- `takken2026.v1`の`expectedItemCount`: 100のまま
- `saleReady`: `false`のまま

`./scripts/audit_takken_content_v14`は上記の件数、形式、status、Release非混入を毎回検証する。

## 50問単位の人手校閲

400候補は決定的な8 batchに分ける。コマンドは既存ファイルを上書きしない。

```sh
./scripts/export_takken_review_batch 1
```

出力したJSONでは、法令内容と教材表現を人間が確認して次を満たす。

- `reviewer`: 校閲担当者を識別できる値
- `reviewedAt`: ISO-8601の日付または日時
- `reviewNote`: 修正・確認内容を具体的に記録
- `legalReviewChecklist`: `lawBasis`、`subject`、`timing`、`numbers`、`exceptions`をすべて確認済みにする
- `distractorReviewStatus`: `checked`
- `reviewStatus`: `reviewed`（最終配布物だけ`release`も可）
- `correctChoiceID`と`correctIndex`: 同一の正解を指す
- 全誤答: choice内の`rationale`と`wrongChoiceRationales`へ同じ具体的理由を記録
- `shortExplanation`: 解答直後に規則を短く確認する内容
- `longExplanation`: 主体・時期・数字・例外と誤答理由まで学び直す内容
- `preview.title` / `preview.rule`: 次回予習で意味が通る内容
- `examYear = 2026` / `lawBasisDate = 2026-04-01`
- `【AI草稿】`、入力欄、AI誤答根拠候補などの草稿markerをゼロにする

校閲済みbatchは次のコマンドで`ContentSource/Reviewed`へ移す。1〜100問のbatchだけを受け付け、上記の項目が一つでも欠ければ拒否する。Release Resourcesは変更しない。

```sh
./scripts/promote_takken_reviewed ContentSource/Drafts/takken_2026_v2_review_batch_01.json
```

## 無料v2の配布前ゲート

採用する校閲済みファイルをまとめて指定する。ファイル単位ではなく、結合した一つのpackとして検証する。

```sh
./scripts/check_takken_release_candidate \
  ContentSource/Reviewed/takken_2026_v2_review_batch_01.json \
  ContentSource/Reviewed/takken_2026_v2_review_batch_02.json
```

最終候補には次を要求する。

- 合計250〜300問、ID重複ゼロ、100 conceptを維持
- ○×25〜30%、数値選択20〜25%、文言比較20〜25%、4択20〜25%、事例5〜10%
- ○×の正解比率40〜60%
- placeholder・AI草稿・未校閲statusがゼロ
- 全問が人手校閲メタデータと2026-04-01法令チェックを持つ

このコマンドは検証専用であり、Releaseやcatalogを自動変更しない。合格後に限り、採用JSONをReleaseへ配置してdescriptorの`sha256`、`byteCount`、`itemCount`、manifestの`expectedItemCount`、`conceptCount`、`variantCount`、`sampleDefinition`を実データと一致させ、`contentQualityProfile = takken-v2`を設定する。無料v2の完成だけでは有料全範囲の校閲完了を意味しないため、`saleReady`は残り教材の人手校閲と購入フロー確認が終わるまで`false`を維持する。

## アプリ内package検証

このpackage-level validationは、ファイル単独では見えない不整合をactive化前に検出する。

資格教材を複数JSONへ分割しても、Stage時に全ファイルを結合して以下を確認する。

- 全ファイル横断のitem ID重複
- active問題数と`expectedItemCount`
- placeholderゼロ
- `checked` / `reviewed` / `release`以外のstatusゼロ
- 無料sample IDと件数

この処理はRuntimeの`TakkenQuestionRepository`と`CertificationQuestionPackagePolicy`を共有する。Stageで通りRuntimeで失敗する検証差を残さない。

## 次の教材作業

無料v2の人手校閲後、旧200問をconcept/variantへ再構成する。旧`checked`は最終承認に流用しない。その後、法令上の制限200、権利関係300、税その他200を50〜100問ずつ同じゲートへ通す。全件が人手校閲済みになる前に有料packへ混在させない。
