# 宅建Legacy 1,000問棚卸し v17

## 対象

- 公開無料100問
- 追加宅建業法200問
- 法令上の制限200問
- 権利関係300問
- 税・その他200問

各旧問題を一度だけ`takken_2026_legacy_question_inventory_v1.json`へ登録し、元ファイル、digest、mappedConceptID、disposition、理由を保持した。旧問題そのものは削除していない。

## 初期AI分類

| disposition | 件数 |
|---|---:|
| `base_variant_candidate` | 325 |
| `additional_variant_candidate` | 506 |
| `duplicate` | 1 |
| `requires_legal_research` | 130 |
| `integrated_case_material` | 38 |
| 合計 | 1,000 |

orphanは0件。同じ旧IDの複数concept登録も0件。`duplicate`は参照先旧IDを必須とし、廃止・outdatedを使用する場合は具体的な学習価値・法改正理由を必須にする。

## 追跡方法

Concept Masterの`legacySourceIDs`から旧問題へ、Inventoryの`mappedConceptID`から新conceptへ双方向に追跡できる。年度更新で文章を修正しても旧IDとdigestを残し、素材の由来を失わない。

全分類は`status = ai_draft`で、旧`checked`を新v2の人間校閲へ流用していない。再生成は`./scripts/build_takken_legacy_inventory`、完全性確認は`./scripts/audit_takken_concept_coverage`で行う。
