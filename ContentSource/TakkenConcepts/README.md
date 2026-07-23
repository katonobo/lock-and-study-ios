# Takken Concept Authoring Workflow v18

このディレクトリは、公開中の宅建 Release 100問から隔離した制作領域です。AI生成物、人間校閲済みデータ、候補商品をディレクトリ境界で分けます。`Generated` の内容は法令校閲済みではなく、`Reviewed` や `ReleaseCandidates` へ自動昇格しません。

## ディレクトリ

- `Generated/`: 決定的に再生成できるAI分類・草稿・監査結果
- `ReviewBatches/`: 人間が編集するbatchと境界decision template
- `Reviewed/`: 全batch importゲートを通過した人間校閲済みConcept Master等
- `Drafts/`: Reviewed Masterを明示入力して生成する問題・棚卸し草稿
- `ReleaseCandidates/`: 校閲済み入力から明示的に作る候補。公開領域ではない
- `Backups/`: Reviewed Master置換時の自動バックアップ
- `Schemas/`: Concept、Inventory、Review Batch、Golden、Free SampleのJSON Schema

旧v17直下ファイルは`./scripts/migrate_takken_concept_layout_v18`で`Generated/`へ移行できます。互換用にAI Masterへ暗黙フォールバックする処理は設けません。

## 安全境界

- `Generated` は `reviewStatus = ai_draft`
- AIが`reviewer`、`reviewedAt`、`reviewDecision`、確認済み`numericFacts`を捏造しない
- placeholderは`isPlaceholder = true`で、通常のvariant充足数に含めない
- `Reviewed`へのimportは全batch、1,000旧問題IDの一意所有、350〜450 Concept、出典・校閲metadataを一括検証してからatomic replace
- `Reviewed`の既存ファイルは置換前に`Backups/`へ保存
- `Generated`再作成は`Reviewed`を読み書きしない
- `ReleaseCandidates`から公開Releaseへの昇格は、既存のpromotion/release gateを別途通す

## 標準フロー

```sh
# 1. AI草稿をGeneratedだけへ再生成
./scripts/prepare_takken_concept_assets_v17

# 2. 境界warningとdecision templateを生成（自動merge/splitなし）
./scripts/audit_takken_concept_boundaries

# 3. batchを書き出す（既定50 Concept、現在はbatch 1〜8）
./scripts/export_takken_concept_review_batch 1

# 4. 人間編集後に単体・全体ゲートを通す
./scripts/validate_takken_concept_review_batch ContentSource/TakkenConcepts/ReviewBatches/<file>.json
./scripts/import_takken_concept_review_batches ContentSource/TakkenConcepts/ReviewBatches

# 5. Reviewed Masterを明示して派生草稿を作る
./scripts/build_takken_legacy_inventory \
  --concept-master ContentSource/TakkenConcepts/Reviewed/concept_master_reviewed.json
./scripts/generate_takken_variant_drafts \
  --concept-master ContentSource/TakkenConcepts/Reviewed/concept_master_reviewed.json
```

`ReviewBatches/`に置く完成batchは、export時の`sourceMasterDigest`と元の所有範囲を維持し、merge/splitでbatchをまたぐ旧問題IDは`transferredLegacyQuestionIDsIn` / `transferredLegacyQuestionIDsOut`の両側に記録します。同じ完成batch群の再importは冪等です。

## 検証

```sh
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_platform_v14
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_platform_v17
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_platform_v18
LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 ./scripts/release_readiness
```

現時点でリポジトリに本番の`concept_master_reviewed.json`はありません。法令校閲者が全380 AI draft Conceptの境界、根拠、数字、年度更新理由を確認し、全batch importを完了するまで、Golden variant・無料候補・Full Packは公開可能ではありません。
