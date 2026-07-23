# 宅建Concept制作ワークフロー v18

## 目的と責務境界

v18はAIの再生成可能な草稿と、人間が法令・論点境界を確認したデータをファイル境界で分離する。公開中の100問、Lock Core、StoreKit、Shield、Unlock RuntimeのRelease経路は変更しない。

| 領域 | 書き手 | 内容 | 次へ進む条件 |
|---|---|---|---|
| `Generated` | 決定的スクリプト | AI Concept Master、1,000問棚卸し、Golden mapping/variants、出典queue、境界audit | 人間review batchへexport |
| `ReviewBatches` | export + 人間 | 50 Concept単位の境界・根拠・年度更新判断 | batch単体と全体のvalidation |
| `Reviewed` | importのみ | 人間校閲済みConcept Master / Inventory | 全1,000 ID一意所有、350〜450 Concept |
| `Drafts` | Reviewed起点generator | Inventory / Variant AI草稿 | 問題・誤答・出典校閲 |
| `ReleaseCandidates` | 明示コマンド | Free Sample / Full Pack候補 | promotion/release gateと人間承認 |
| 公開Release | 既存release処理 | ユーザーへ配布する100問 | v18は自動変更しない |

`prepare_takken_concept_assets_v17`は互換名を維持するが、書き込み先は`Generated`だけである。全出力は同一ディレクトリ上の一時ファイルを`fsync`後に`os.replace`する。処理前後で`Reviewed` tree digestを比較し、変更を検出した場合は失敗する。

## Review Batch往復

```sh
./scripts/export_takken_concept_review_batch 1
./scripts/validate_takken_concept_review_batch <batch.json>
./scripts/import_takken_concept_review_batches <completed-directory>
```

exportは既存ファイルを上書きしない。batchには元Master digest、元Concept ID、元legacy IDを封入する。人間は各Conceptへ具体的な`sourceNotes`、`reviewer`、`reviewedAt`、`reviewDecision`を記録する。

mergeでは代表Conceptへ`mergedFromConceptIDs` / `supersedesConceptIDs`を記録し、splitでは新Conceptへ`splitFromConceptID`を記録する。batch間を移るlegacy IDは、送り側`legacyTransfersOut`と受け側`legacyTransfersIn`に同一ID・相手batchを記録する。

importは次を全件検証してから一括反映する。

- batch番号・Concept IDに重複がない
- export元と同じGenerated Master digest
- 既存1,000問を過不足なく、ちょうど一つのConceptが所有
- orphan / duplicate legacy IDが0
- merge/split後も350〜450 Concept
- 全Conceptが人間review metadataと追跡可能な出典を持つ
- transferのin/outが一致
- `validate_concept_master`と再構築Inventoryが合格

検証失敗時は`Reviewed`を一切変更しない。成功時は既存Masterを`Backups`へdigest名で保存してatomic replaceする。同じbatch群の再importは同一内容となり冪等である。

## Reviewed Master起点生成

```sh
./scripts/build_takken_legacy_inventory \
  --concept-master ContentSource/TakkenConcepts/Reviewed/concept_master_reviewed.json

./scripts/generate_takken_variant_drafts \
  --concept-master ContentSource/TakkenConcepts/Reviewed/concept_master_reviewed.json
```

generatorは引数のMasterを検証し、人間が修正したConcept ID、title、canonicalRule、recommendedFormats、legacySourceIDsを使う。`Generated`へ暗黙に戻らない。出力には入力Master digestを記録し、同名の人間編集済みファイルを内容違いで上書きしない。

`number_choice`は`numericFacts`に`reviewStatus = reviewed`の数量事実がある場合だけ許可する。35条、37条書面、8種制限などの制度名・条番号は数量事実にしない。placeholderは`isPlaceholder = true`とし、Tierのvariant充足数に数えない。

## 現在の状態

- Generated Concept: 380（A 120 / B 180 / C 80）
- category: 宅建業法140 / 権利関係110 / 法令上の制限65 / 税・その他65
- legacy棚卸し: 1,000件を一意分類
- 本番Reviewed Master: なし
- 自動`reviewed` / `release`昇格: 0
- 未確認出典queue: 380

次の人間作業は、境界warningのdecision記録、全8 batchの法令校閲、1,000問ownership確認である。
