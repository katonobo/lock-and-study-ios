# Takken Concept Authoring v17

このディレクトリは、公開中の宅建Releaseとは分離された制作領域です。内容はすべてAIによる初期分類・草稿であり、法令校閲済みではありません。

## ファイル

- `takken_2026_concept_master_draft_v1.json`: 380論点のAIドラフト
- `takken_2026_legacy_question_inventory_v1.json`: 既存1,000問の完全な棚卸し
- `takken_2026_golden_100_concepts_draft_v1.json`: 現在の無料100問を種にしたGolden 100
- `takken_2026_golden_variants_draft_v1.json`: 異なる記憶経路から選定した270問のAI草稿
- `takken_2026_source_research_queue_v1.json`: 全380論点の未確認出典キュー
- `Schemas/`: 制作データの機械可読スキーマ

## 安全境界

- `reviewStatus = ai_draft`
- `distractorReviewStatus = pending`
- `sourceNote = null`または`sourceNotes = []`
- `reviewer`、`reviewedAt`、`reviewNote`を自動入力しない
- `LockAndStudy/Resources/Content/Released`へ自動コピーしない
- 具体的な条文・公的資料を確認するまでsource research queueを完了扱いにしない

生成:

```sh
./scripts/prepare_takken_concept_assets_v17
```

監査:

```sh
./scripts/validate_takken_concept_master
./scripts/audit_takken_concept_coverage
./scripts/audit_takken_content_v17
```

Concept review batchは38論点×10batchです。既存batchを上書きしません。

```sh
./scripts/export_takken_concept_review_batch 1
```

AI分類は完成品ではありません。concept境界、重要度、法令根拠、誤答理由を人間が確認した後でも、Reviewedへの昇格にはv16/v17ゲートの全条件を満たす必要があります。
