# 宅建Concept境界監査 v18

## 実行

```sh
./scripts/audit_takken_concept_boundaries
```

出力:

- `ContentSource/TakkenConcepts/Generated/concept_boundary_audit_v18.json`
- `ContentSource/TakkenConcepts/Generated/concept_boundary_audit_v18.md`
- `ContentSource/TakkenConcepts/ReviewBatches/concept_boundary_decisions_v18.json`

監査は候補をwarningとして提示するだけで、Conceptを自動merge/splitしない。decision templateの`decision`と`reviewNote`は人間が入力する。

## 現在のwarning

全468件:

- canonicalRule完全一致: 1
- title完全一致: 1
- normalized keyPoint一致: 3
- prompt高類似: 1
- cluster内低類似: 9
- titleに複数ruleの可能性: 274
- 3件以上の異なるruleを含む可能性: 176
- 既知semantic duplicate候補: 3

既知fixture:

- `tl_gyoho_takkenshi_006` / `tl_gyoho_37_003`
- `tl_gyoho_35_027` / `tl_gyoho_37_002`
- `tl_gyoho_35_001` / `tl_gyoho_35_002`

同一条項の複数Concept参照、または一Conceptによる複数条項包含は、人間が具体的な`sourceNotes`を入力したReviewed Masterで追加検出される。AI draftは具体的根拠を捏造しないため、この2種の監査はReviewed出典が揃うまで確定できない。

## 判断原則

- `accept`: 一つの記憶目標として妥当
- `merge`: 同じ記憶目標。代表Conceptへ全legacy IDと`mergedFromConceptIDs`を集約
- `split`: 異なる主体、数字、時期、義務・任意、原則・例外などに分ける。新Conceptへ`splitFromConceptID`
- `rename`: 境界は維持し、title/canonicalRuleを明確化
- `retire`: 旧問題素材は追跡を残したまま出題対象外判断
- `integrated_case`: 単独暗記でなく複数Concept横断事例として使用

言い換えだけでConceptやVariantを増やさず、異なる記憶経路がある場合だけ分離する。
