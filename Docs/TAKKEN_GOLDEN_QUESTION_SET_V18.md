# Golden Question Set / Concept Set v18

Golden Questionは公開中Releaseの品質基準100問、Golden Conceptはその100問が人間review後にmapされた論点集合である。両者を同数に固定しない。

```json
{
  "goldenQuestionIDs": ["公開Releaseの順序付き100 ID"],
  "conceptMappings": [
    {
      "questionID": "tl_...",
      "conceptID": "takken....",
      "mappingStatus": "ai_draft|human_reviewed"
    }
  ],
  "distinctConceptCount": 100
}
```

ゲートはQuestion IDが公開Release 100と順序・重複なしで一致すること、各Questionに一つのmappingがあること、ConceptがMasterに存在すること、`distinctConceptCount`がmappingから導出されることを検証する。複数Questionが同じConceptへmapすることを許可する。

現在のGenerated mappingは100 Question / 100 AI Conceptであり、校閲済みの数ではない。v18統合fixtureでは既知重複2 Conceptをmergeし、Release問題本文を変えず100 Question / 99 distinct Conceptとして検証に合格する。

Golden variant草稿は270件だが、全件`ai_draft`かつplaceholderであり公開候補ではない。形式はtrue/false 89、multiple choice 76、wording contrast 75、case study 30、number choice 0。未確認の条番号からnumber choiceを作らない。

## Public Free Sample

Golden quality benchmarkと商品上の無料体験を分離する。`Generated/free_sample_profiles_v18.json`には次を定義する。

- `current-gyoho-100`: 現行の商品方針を維持する宅建業法100問
- `all-fields-balanced-100`: 4分野を30/30/20/20で体験する100問

profileはQuestion数、distinct Concept目標、category/format/difficulty配分、Unlock eligible最低数、case study上限、同一Concept上限を指定できる。入力variantがreview済みでない、出典・誤答校閲が不足する、または配分を満たせない場合は候補ファイルを作らない。

## Full Pack

Concept Masterの現在計画はstandalone 920 + integrated case 80 = total 1,000。Full Pack gateは3集計の完全一致、350〜450 Concept、category/format/tier coverage、integrated caseの`integratedConceptIDs`を検証する。現在の270 AI placeholder草稿は不足500件を報告し、Full Packとして拒否される。
