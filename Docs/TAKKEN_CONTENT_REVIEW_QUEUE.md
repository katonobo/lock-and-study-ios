# 宅建コンテンツ v2 校閲キュー

> 候補JSONはすべてAI草稿です。法令内容を自動承認せず、Release Resourcesへコピーしません。

## 生成結果

- 元論点: 100
- 候補合計: 400（base 100 / 派生 300）
- reviewStatus: 全件 `ai_draft`
- distractorReviewStatus: 全件 `pending`
- Release targetへの収録: 0件

### 形式別

| 形式 | 件数 | 比率 |
|---|---:|---:|
| true_false | 115 | 28.7% |
| number_choice | 80 | 20.0% |
| wording_contrast | 80 | 20.0% |
| multiple_choice | 95 | 23.8% |
| case_study | 30 | 7.5% |

### 優先確認タグ

- 主体: 275候補
- 数字・期限・割合: 263候補
- 法令文言・正誤根拠: 28候補
- 義務/任意・前後・原則/例外: 128候補

## 人間校閲の完了条件

- [ ] 2026-04-01基準の法令・数字・主体・例外を確認
- [ ] 問題文をAI草稿表現から自然な本試験型表現へ修正
- [ ] correctChoiceIDとcorrectIndexを再確認
- [ ] 全誤答rationaleを法令根拠に基づき修正
- [ ] short/long explanationの役割を分離
- [ ] reviewer / reviewedAt / review notesを記録
- [ ] distractorReviewStatusを`checked`へ変更
- [ ] 最終承認後だけreviewStatusを`reviewed`へ変更

## 候補別キュー

| conceptID | variantID | 形式 | 確認する数字/主体/文言 | 正解候補 | 誤答根拠 | 法令基準日 | reviewer | reviewedAt | review notes |
|---|---|---|---|---|---|---|---|---|---|
| concept.tl_gyoho_license_001 | base.true_false | true_false | 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_002 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_003 | base.true_false | true_false | 法令文言・正誤根拠 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_004 | base.true_false | true_false | 法令文言・正誤根拠 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_005 | base.true_false | true_false | 法令文言・正誤根拠 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_007 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_019 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_020 | base.true_false | true_false | 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_021 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_001 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_002 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_003 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_004 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_005 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_007 | base.true_false | true_false | 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_019 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_020 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_021 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_001 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_002 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_003 | base.true_false | true_false | 数字・期限・割合 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_004 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_005 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_006 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_016 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_017 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_001 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_002 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_003 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_004 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_005 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_006 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_016 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_017 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_001 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_002 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_003 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_004 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_005 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_016 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_017 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_001 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_002 | base.true_false | true_false | 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_003 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_004 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_005 | base.true_false | true_false | 法令文言・正誤根拠 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_007 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_019 | base.true_false | true_false | 法令文言・正誤根拠 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_020 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_021 | base.true_false | true_false | 法令文言・正誤根拠 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_001 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_002 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_003 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_004 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_005 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_007 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_008 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_009 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_025 | base.true_false | true_false | 数字・期限・割合 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_026 | base.true_false | true_false | 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_027 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_028 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_039 | base.multiple_choice | multiple_choice | 法令文言・正誤根拠 | 建物状況調査に関する事項 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_001 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_002 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_003 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_004 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_005 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_007 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_019 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_020 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_030 | base.multiple_choice | multiple_choice | 数字・期限・割合 | 一定条件のもとで認められる | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_001 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_002 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_003 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_004 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_005 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_006 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_007 | base.true_false | true_false | 義務/任意・前後・原則/例外 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_008 | base.true_false | true_false | 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_022 | base.true_false | true_false | 法令文言・正誤根拠 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_023 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_024 | base.true_false | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_034 | base.multiple_choice | multiple_choice | 法令文言・正誤根拠 | 事務所等ではない喫茶店 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_001 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_002 | base.true_false | true_false | 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_003 | base.true_false | true_false | 法令文言・正誤根拠 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_010 | base.true_false | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_014 | base.multiple_choice | multiple_choice | 数字・期限・割合 | 5％ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_001 | base.true_false | true_false | 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_002 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_003 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_010 | base.true_false | true_false | 数字・期限・割合 / 主体 | 正しい | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_015 | base.multiple_choice | multiple_choice | 法令文言・正誤根拠 | 宅建業法上禁止される | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_001 | draft.true_false.001 | true_false | 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_006 | draft.true_false.002 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_003 | draft.true_false.003 | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_021 | draft.true_false.004 | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_003 | draft.true_false.005 | true_false | 法令文言・正誤根拠 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_027 | draft.true_false.006 | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_003 | draft.true_false.007 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_002 | draft.true_false.008 | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_007 | draft.true_false.009 | true_false | 義務/任意・前後・原則/例外 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_004 | draft.true_false.010 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_003 | draft.true_false.011 | true_false | 数字・期限・割合 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_004 | draft.true_false.012 | true_false | 法令文言・正誤根拠 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_020 | draft.true_false.013 | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_006 | draft.true_false.014 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_003 | draft.true_false.015 | true_false | 数字・期限・割合 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_001 | draft.true_false.016 | true_false | 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_001 | draft.true_false.017 | true_false | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_006 | draft.true_false.018 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_005 | draft.true_false.019 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_023 | draft.true_false.020 | true_false | 数字・期限・割合 / 主体 | 誤り | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_006 | draft.number_choice.001 | number_choice | 数字・期限・割合 / 主体 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_003 | draft.number_choice.002 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 3か月 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_027 | draft.number_choice.003 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_003 | draft.number_choice.004 | number_choice | 数字・期限・割合 / 主体 | 1人 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_004 | draft.number_choice.005 | number_choice | 数字・期限・割合 / 主体 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_003 | draft.number_choice.006 | number_choice | 数字・期限・割合 | 60 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_020 | draft.number_choice.007 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_006 | draft.number_choice.008 | number_choice | 数字・期限・割合 / 主体 | 2週間 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_003 | draft.number_choice.009 | number_choice | 数字・期限・割合 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_001 | draft.number_choice.010 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_006 | draft.number_choice.011 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_005 | draft.number_choice.012 | number_choice | 数字・期限・割合 / 主体 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_023 | draft.number_choice.013 | number_choice | 数字・期限・割合 / 主体 | 8 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_007 | draft.number_choice.014 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_007 | draft.number_choice.015 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_002 | draft.number_choice.016 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 8 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_020 | draft.number_choice.017 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_006 | draft.number_choice.018 | number_choice | 数字・期限・割合 | 500万円 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_010 | draft.number_choice.019 | number_choice | 数字・期限・割合 / 主体 | 1年 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_004 | draft.number_choice.020 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_025 | draft.number_choice.021 | number_choice | 数字・期限・割合 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_001 | draft.number_choice.022 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_021 | draft.number_choice.023 | number_choice | 数字・期限・割合 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_005 | draft.number_choice.024 | number_choice | 数字・期限・割合 / 主体 | 20％ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_002 | draft.number_choice.025 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_002 | draft.number_choice.026 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_007 | draft.number_choice.027 | number_choice | 数字・期限・割合 / 主体 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_004 | draft.number_choice.028 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 3か月 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_010 | draft.number_choice.029 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 1 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_004 | draft.number_choice.030 | number_choice | 数字・期限・割合 / 主体 | 1人 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_003 | draft.number_choice.031 | number_choice | 数字・期限・割合 / 主体 | 5年 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_005 | draft.number_choice.032 | number_choice | 数字・期限・割合 / 主体 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_004 | draft.number_choice.033 | number_choice | 数字・期限・割合 / 主体 | 60万円 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_030 | draft.number_choice.034 | number_choice | 数字・期限・割合 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_007 | draft.number_choice.035 | number_choice | 数字・期限・割合 / 主体 | 1週間 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_002 | draft.number_choice.036 | number_choice | 数字・期限・割合 / 主体 | 1年 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_002 | draft.number_choice.037 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_016 | draft.number_choice.038 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 10年 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_006 | draft.number_choice.039 | number_choice | 数字・期限・割合 / 主体 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_024 | draft.number_choice.040 | number_choice | 数字・期限・割合 / 主体 | 20％ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_008 | draft.number_choice.041 | number_choice | 数字・期限・割合 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_016 | draft.number_choice.042 | number_choice | 数字・期限・割合 / 主体 | 30万円 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_019 | draft.number_choice.043 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_003 | draft.number_choice.044 | number_choice | 数字・期限・割合 / 主体 | 8 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_005 | draft.number_choice.045 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_020 | draft.number_choice.046 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_002 | draft.number_choice.047 | number_choice | 数字・期限・割合 / 主体 | 5人 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_006 | draft.number_choice.048 | number_choice | 数字・期限・割合 / 主体 | 20％ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_019 | draft.number_choice.049 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_002 | draft.number_choice.050 | number_choice | 数字・期限・割合 | 1000 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_014 | draft.number_choice.051 | number_choice | 数字・期限・割合 | 200万円 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_005 | draft.number_choice.052 | number_choice | 数字・期限・割合 / 主体 | 2週間 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_004 | draft.number_choice.053 | number_choice | 数字・期限・割合 / 主体 | 5年 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_006 | draft.number_choice.054 | number_choice | 数字・期限・割合 / 主体 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_005 | draft.number_choice.055 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_006 | draft.number_choice.056 | number_choice | 数字・期限・割合 / 主体 | 2 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_001 | draft.number_choice.057 | number_choice | 数字・期限・割合 / 主体 | 8 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_003 | draft.number_choice.058 | number_choice | 数字・期限・割合 / 主体 | 一 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_003 | draft.number_choice.059 | number_choice | 数字・期限・割合 / 主体 | 37 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_009 | draft.number_choice.060 | number_choice | 数字・期限・割合 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_001 | draft.number_choice.061 | number_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_001 | draft.number_choice.062 | number_choice | 義務/任意・前後・原則/例外 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_021 | draft.number_choice.063 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_003 | draft.number_choice.064 | number_choice | 法令文言・正誤根拠 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_002 | draft.number_choice.065 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_007 | draft.number_choice.066 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_004 | draft.number_choice.067 | number_choice | 法令文言・正誤根拠 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_001 | draft.number_choice.068 | number_choice | 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_006 | draft.number_choice.069 | number_choice | 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_001 | draft.number_choice.070 | number_choice | 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_019 | draft.number_choice.071 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_001 | draft.number_choice.072 | number_choice | 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_001 | draft.number_choice.073 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_001 | draft.number_choice.074 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_028 | draft.number_choice.075 | number_choice | 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_008 | draft.number_choice.076 | number_choice | 義務/任意・前後・原則/例外 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_005 | draft.number_choice.077 | number_choice | 法令文言・正誤根拠 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_004 | draft.number_choice.078 | number_choice | 義務/任意・前後・原則/例外 / 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_021 | draft.number_choice.079 | number_choice | 法令文言・正誤根拠 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_016 | draft.number_choice.080 | number_choice | 主体 | ［正しい数値・期限を入力］ | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_001 | draft.wording_contrast.001 | wording_contrast | 義務/任意・前後・原則/例外 | 宅建業は免許制。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_006 | draft.wording_contrast.002 | wording_contrast | 数字・期限・割合 / 主体 | 媒介では双方に交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_003 | draft.wording_contrast.003 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 専任は最長3か月。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_021 | draft.wording_contrast.004 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 専任は常勤・専従。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_027 | draft.wording_contrast.005 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条と37条を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_003 | draft.wording_contrast.006 | wording_contrast | 数字・期限・割合 / 主体 | 契約行為ありの案内所は1人以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_002 | draft.wording_contrast.007 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 宅建士証が必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_007 | draft.wording_contrast.008 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 手付は解約手付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_004 | draft.wording_contrast.009 | wording_contrast | 数字・期限・割合 / 主体 | 35条説明時は士証提示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_020 | draft.wording_contrast.010 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 契約形式に注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_006 | draft.wording_contrast.011 | wording_contrast | 数字・期限・割合 / 主体 | 専任は2週間に1回以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_001 | draft.wording_contrast.012 | wording_contrast | 主体 | 業者処分は指示・業務停止・免許取消。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_001 | draft.wording_contrast.013 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37条は契約後。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_006 | draft.wording_contrast.014 | wording_contrast | 数字・期限・割合 / 主体 | 標識は外から分かる表示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_005 | draft.wording_contrast.015 | wording_contrast | 数字・期限・割合 / 主体 | 35条説明時は宅建士証提示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_023 | draft.wording_contrast.016 | wording_contrast | 数字・期限・割合 / 主体 | 8種制限は買主保護。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_007 | draft.wording_contrast.017 | wording_contrast | 数字・期限・割合 / 主体 | 業者間では説明省略に注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_006 | draft.wording_contrast.018 | wording_contrast | 主体 | 保証協会の業務は弁済だけではない。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_007 | draft.wording_contrast.019 | wording_contrast | 数字・期限・割合 / 主体 | 同一都道府県内なら知事免許。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_002 | draft.wording_contrast.020 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 業者間には原則適用なし。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_020 | draft.wording_contrast.021 | wording_contrast | 数字・期限・割合 / 主体 | 更新は依頼者申出。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_010 | draft.wording_contrast.022 | wording_contrast | 数字・期限・割合 / 主体 | 事務禁止は最長1年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_004 | draft.wording_contrast.023 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 37条は説明義務ではなく書面交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_001 | draft.wording_contrast.024 | wording_contrast | 主体 | 媒介契約書は遅滞なく交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_019 | draft.wording_contrast.025 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 提示と読み上げを区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_001 | draft.wording_contrast.026 | wording_contrast | 主体 | 報酬は上限規制。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_001 | draft.wording_contrast.027 | wording_contrast | 数字・期限・割合 / 主体 | 事務所には専任宅建士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_005 | draft.wording_contrast.028 | wording_contrast | 数字・期限・割合 / 主体 | 手付は20％まで。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_002 | draft.wording_contrast.029 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条は契約前。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_001 | draft.wording_contrast.030 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 保証協会加入で営業保証金に代替。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_002 | draft.wording_contrast.031 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 自ら貸主は原則として宅建業ではない。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_007 | draft.wording_contrast.032 | wording_contrast | 数字・期限・割合 / 主体 | 自ら売主でも37条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_004 | draft.wording_contrast.033 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 専属専任も最長3か月。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_001 | draft.wording_contrast.034 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 供託＋届出後に営業開始。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_010 | draft.wording_contrast.035 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 居住用貸借は片方1/2月分が原則。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_028 | draft.wording_contrast.036 | wording_contrast | 主体 | 現在は宅地建物取引士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_004 | draft.wording_contrast.037 | wording_contrast | 数字・期限・割合 / 主体 | 案内所でも契約行為があれば必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_003 | draft.wording_contrast.038 | wording_contrast | 数字・期限・割合 / 主体 | 宅建士証も5年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_008 | draft.wording_contrast.039 | wording_contrast | 義務/任意・前後・原則/例外 | 買主は手付放棄。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_005 | draft.wording_contrast.040 | wording_contrast | 数字・期限・割合 / 主体 | 35条書面には宅建士記名。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_004 | draft.wording_contrast.041 | wording_contrast | 数字・期限・割合 / 主体 | 営業保証金と保証協会分担金を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_007 | draft.wording_contrast.042 | wording_contrast | 数字・期限・割合 / 主体 | 専属専任は1週間に1回以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_004 | draft.wording_contrast.043 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 供託先は本店最寄り。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_002 | draft.wording_contrast.044 | wording_contrast | 数字・期限・割合 / 主体 | 業務停止は最長1年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_002 | draft.wording_contrast.045 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条と37条を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_016 | draft.wording_contrast.046 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 新築住宅売主の帳簿は10年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_006 | draft.wording_contrast.047 | wording_contrast | 数字・期限・割合 / 主体 | 37条書面も宅建士の記名。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_024 | draft.wording_contrast.048 | wording_contrast | 数字・期限・割合 / 主体 | 名称より実質。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_016 | draft.wording_contrast.049 | wording_contrast | 数字・期限・割合 / 主体 | 支店は30万円追加。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_019 | draft.wording_contrast.050 | wording_contrast | 数字・期限・割合 / 主体 | 廃業等にも届出がある。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_003 | draft.wording_contrast.051 | wording_contrast | 数字・期限・割合 / 主体 | 自ら売主が条件。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_016 | draft.wording_contrast.052 | wording_contrast | 主体 | 本店移転は供託所にも注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_005 | draft.wording_contrast.053 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 売買・交換・貸借で37条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_002 | draft.wording_contrast.054 | wording_contrast | 義務/任意・前後・原則/例外 | 媒介契約規制は売買・交換中心。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_020 | draft.wording_contrast.055 | wording_contrast | 数字・期限・割合 / 主体 | 宅建士と専任宅建士を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_002 | draft.wording_contrast.056 | wording_contrast | 主体 | 同意があっても上限超え不可。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_026 | draft.wording_contrast.057 | wording_contrast | 義務/任意・前後・原則/例外 | 契約前の判断材料。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_002 | draft.wording_contrast.058 | wording_contrast | 数字・期限・割合 / 主体 | 5人に1人。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_001 | draft.wording_contrast.059 | wording_contrast | 主体 | 合格と登録は別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_006 | draft.wording_contrast.060 | wording_contrast | 数字・期限・割合 / 主体 | 手付上限20％。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_003 | draft.wording_contrast.061 | wording_contrast | 主体 | 説明者は宅建士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_002 | draft.wording_contrast.062 | wording_contrast | 主体 | 加入時は分担金。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_019 | draft.wording_contrast.063 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37条は契約内容の確認。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_005 | draft.wording_contrast.064 | wording_contrast | 数字・期限・割合 / 主体 | 不足時は2週間以内。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_004 | draft.wording_contrast.065 | wording_contrast | 数字・期限・割合 / 主体 | 登録と宅建士証を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_006 | draft.wording_contrast.066 | wording_contrast | 数字・期限・割合 / 主体 | 貸借でも35条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_005 | draft.wording_contrast.067 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 保証協会は一つだけ。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_006 | draft.wording_contrast.068 | wording_contrast | 数字・期限・割合 / 主体 | 複数都道府県なら大臣免許。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_001 | draft.wording_contrast.069 | wording_contrast | 数字・期限・割合 / 主体 | 業者売主×非業者買主。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_005 | draft.wording_contrast.070 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 供託だけでは営業開始不可。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_003 | draft.wording_contrast.071 | wording_contrast | 数字・期限・割合 / 主体 | 免許取消は重い。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_003 | draft.wording_contrast.072 | wording_contrast | 数字・期限・割合 / 主体 | 37条書面には宅建士記名。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_017 | draft.wording_contrast.073 | wording_contrast | 主体 | 誇大広告は禁止。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_007 | draft.wording_contrast.074 | wording_contrast | 主体 | 登録事項変更は手続。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_017 | draft.wording_contrast.075 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 保証協会と専任宅建士義務は別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_020 | draft.wording_contrast.076 | wording_contrast | 主体 | 免許は当然承継されない。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_004 | draft.wording_contrast.077 | wording_contrast | 義務/任意・前後・原則/例外 / 主体 | 他人物売買の制限。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_001 | draft.wording_contrast.078 | wording_contrast | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条は契約前。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_017 | draft.wording_contrast.079 | wording_contrast | 主体 | 営業保証金と保証協会は比較。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_003 | draft.wording_contrast.080 | wording_contrast | 法令文言・正誤根拠 | 売買報酬は価格区分。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_001 | draft.multiple_choice.001 | multiple_choice | 義務/任意・前後・原則/例外 | 宅建業は免許制。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_006 | draft.multiple_choice.002 | multiple_choice | 数字・期限・割合 / 主体 | 媒介では双方に交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_003 | draft.multiple_choice.003 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 専任は最長3か月。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_021 | draft.multiple_choice.004 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 専任は常勤・専従。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_003 | draft.multiple_choice.005 | multiple_choice | 法令文言・正誤根拠 | 売買報酬は価格区分。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_027 | draft.multiple_choice.006 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条と37条を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_003 | draft.multiple_choice.007 | multiple_choice | 数字・期限・割合 / 主体 | 契約行為ありの案内所は1人以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_002 | draft.multiple_choice.008 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 宅建士証が必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_007 | draft.multiple_choice.009 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 手付は解約手付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_004 | draft.multiple_choice.010 | multiple_choice | 数字・期限・割合 / 主体 | 35条説明時は士証提示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_003 | draft.multiple_choice.011 | multiple_choice | 数字・期限・割合 | 本店60万、支店30万。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_004 | draft.multiple_choice.012 | multiple_choice | 法令文言・正誤根拠 | 売買を業として行うと免許が必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_020 | draft.multiple_choice.013 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 契約形式に注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_006 | draft.multiple_choice.014 | multiple_choice | 数字・期限・割合 / 主体 | 専任は2週間に1回以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_003 | draft.multiple_choice.015 | multiple_choice | 数字・期限・割合 | 金額の基本を暗記。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_001 | draft.multiple_choice.016 | multiple_choice | 主体 | 業者処分は指示・業務停止・免許取消。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_001 | draft.multiple_choice.017 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37条は契約後。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_006 | draft.multiple_choice.018 | multiple_choice | 数字・期限・割合 / 主体 | 標識は外から分かる表示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_005 | draft.multiple_choice.019 | multiple_choice | 数字・期限・割合 / 主体 | 35条説明時は宅建士証提示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_023 | draft.multiple_choice.020 | multiple_choice | 数字・期限・割合 / 主体 | 8種制限は買主保護。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_007 | draft.multiple_choice.021 | multiple_choice | 数字・期限・割合 / 主体 | 業者間では説明省略に注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_006 | draft.multiple_choice.022 | multiple_choice | 主体 | 保証協会の業務は弁済だけではない。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_007 | draft.multiple_choice.023 | multiple_choice | 数字・期限・割合 / 主体 | 同一都道府県内なら知事免許。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_002 | draft.multiple_choice.024 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 業者間には原則適用なし。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_020 | draft.multiple_choice.025 | multiple_choice | 数字・期限・割合 / 主体 | 更新は依頼者申出。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_006 | draft.multiple_choice.026 | multiple_choice | 数字・期限・割合 | 支店新設は500万円追加。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_010 | draft.multiple_choice.027 | multiple_choice | 数字・期限・割合 / 主体 | 事務禁止は最長1年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_004 | draft.multiple_choice.028 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 37条は説明義務ではなく書面交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_001 | draft.multiple_choice.029 | multiple_choice | 主体 | 媒介契約書は遅滞なく交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_019 | draft.multiple_choice.030 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 提示と読み上げを区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_001 | draft.multiple_choice.031 | multiple_choice | 主体 | 報酬は上限規制。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_025 | draft.multiple_choice.032 | multiple_choice | 数字・期限・割合 | 耐震診断の内容。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_001 | draft.multiple_choice.033 | multiple_choice | 数字・期限・割合 / 主体 | 事務所には専任宅建士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_021 | draft.multiple_choice.034 | multiple_choice | 数字・期限・割合 | 欠格事由は免許の入口。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_005 | draft.multiple_choice.035 | multiple_choice | 数字・期限・割合 / 主体 | 手付は20％まで。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_002 | draft.multiple_choice.036 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条は契約前。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_001 | draft.multiple_choice.037 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 保証協会加入で営業保証金に代替。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_002 | draft.multiple_choice.038 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 自ら貸主は原則として宅建業ではない。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_007 | draft.multiple_choice.039 | multiple_choice | 数字・期限・割合 / 主体 | 自ら売主でも37条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_004 | draft.multiple_choice.040 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 専属専任も最長3か月。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_001 | draft.multiple_choice.041 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 供託＋届出後に営業開始。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_010 | draft.multiple_choice.042 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 居住用貸借は片方1/2月分が原則。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_028 | draft.multiple_choice.043 | multiple_choice | 主体 | 現在は宅地建物取引士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_004 | draft.multiple_choice.044 | multiple_choice | 数字・期限・割合 / 主体 | 案内所でも契約行為があれば必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_003 | draft.multiple_choice.045 | multiple_choice | 数字・期限・割合 / 主体 | 宅建士証も5年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_008 | draft.multiple_choice.046 | multiple_choice | 義務/任意・前後・原則/例外 | 買主は手付放棄。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_005 | draft.multiple_choice.047 | multiple_choice | 数字・期限・割合 / 主体 | 35条書面には宅建士記名。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_004 | draft.multiple_choice.048 | multiple_choice | 数字・期限・割合 / 主体 | 営業保証金と保証協会分担金を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_005 | draft.multiple_choice.049 | multiple_choice | 法令文言・正誤根拠 | 管理業と取引業を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_030 | draft.multiple_choice.050 | multiple_choice | 数字・期限・割合 | 電子提供は条件付き。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_007 | draft.multiple_choice.051 | multiple_choice | 数字・期限・割合 / 主体 | 専属専任は1週間に1回以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_004 | draft.multiple_choice.052 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 供託先は本店最寄り。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_002 | draft.multiple_choice.053 | multiple_choice | 数字・期限・割合 / 主体 | 業務停止は最長1年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_002 | draft.multiple_choice.054 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 35条と37条を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_016 | draft.multiple_choice.055 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 新築住宅売主の帳簿は10年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_006 | draft.multiple_choice.056 | multiple_choice | 数字・期限・割合 / 主体 | 37条書面も宅建士の記名。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_024 | draft.multiple_choice.057 | multiple_choice | 数字・期限・割合 / 主体 | 名称より実質。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_008 | draft.multiple_choice.058 | multiple_choice | 数字・期限・割合 | 登記された権利は35条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_016 | draft.multiple_choice.059 | multiple_choice | 数字・期限・割合 / 主体 | 支店は30万円追加。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_019 | draft.multiple_choice.060 | multiple_choice | 数字・期限・割合 / 主体 | 廃業等にも届出がある。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_003 | draft.multiple_choice.061 | multiple_choice | 数字・期限・割合 / 主体 | 自ら売主が条件。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_021 | draft.multiple_choice.062 | multiple_choice | 法令文言・正誤根拠 | 書面化は紛争予防。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_016 | draft.multiple_choice.063 | multiple_choice | 主体 | 本店移転は供託所にも注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_015 | draft.multiple_choice.064 | multiple_choice | 法令文言・正誤根拠 | 無免許営業は禁止。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_005 | draft.multiple_choice.065 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 売買・交換・貸借で37条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_002 | draft.multiple_choice.066 | multiple_choice | 義務/任意・前後・原則/例外 | 媒介契約規制は売買・交換中心。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_020 | draft.multiple_choice.067 | multiple_choice | 数字・期限・割合 / 主体 | 宅建士と専任宅建士を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_002 | draft.multiple_choice.068 | multiple_choice | 主体 | 同意があっても上限超え不可。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_026 | draft.multiple_choice.069 | multiple_choice | 義務/任意・前後・原則/例外 | 契約前の判断材料。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_002 | draft.multiple_choice.070 | multiple_choice | 数字・期限・割合 / 主体 | 5人に1人。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_001 | draft.multiple_choice.071 | multiple_choice | 主体 | 合格と登録は別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_006 | draft.multiple_choice.072 | multiple_choice | 数字・期限・割合 / 主体 | 手付上限20％。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_003 | draft.multiple_choice.073 | multiple_choice | 主体 | 説明者は宅建士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_002 | draft.multiple_choice.074 | multiple_choice | 主体 | 加入時は分担金。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_003 | draft.multiple_choice.075 | multiple_choice | 法令文言・正誤根拠 | 媒介も宅建業。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_019 | draft.multiple_choice.076 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 | 37条は契約内容の確認。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_005 | draft.multiple_choice.077 | multiple_choice | 法令文言・正誤根拠 | 専任の自動更新は禁止。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_002 | draft.multiple_choice.078 | multiple_choice | 数字・期限・割合 | 本店1000万、支店500万。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_014 | draft.multiple_choice.079 | multiple_choice | 数字・期限・割合 | 200万円以下は5％。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_039 | draft.multiple_choice.080 | multiple_choice | 法令文言・正誤根拠 | 既存建物は状況調査。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_005 | draft.multiple_choice.081 | multiple_choice | 数字・期限・割合 / 主体 | 不足時は2週間以内。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_004 | draft.multiple_choice.082 | multiple_choice | 数字・期限・割合 / 主体 | 登録と宅建士証を区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_022 | draft.multiple_choice.083 | multiple_choice | 法令文言・正誤根拠 | 保全なしなら支払拒絶。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_006 | draft.multiple_choice.084 | multiple_choice | 数字・期限・割合 / 主体 | 貸借でも35条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_005 | draft.multiple_choice.085 | multiple_choice | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 保証協会は一つだけ。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_006 | draft.multiple_choice.086 | multiple_choice | 数字・期限・割合 / 主体 | 複数都道府県なら大臣免許。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_001 | draft.multiple_choice.087 | multiple_choice | 数字・期限・割合 / 主体 | 業者売主×非業者買主。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_019 | draft.multiple_choice.088 | multiple_choice | 法令文言・正誤根拠 | 専任の期間制限は依頼者保護。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_005 | draft.multiple_choice.089 | multiple_choice | 義務/任意・前後・原則/例外 / 主体 | 供託だけでは営業開始不可。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_003 | draft.multiple_choice.090 | multiple_choice | 数字・期限・割合 / 主体 | 免許取消は重い。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_006 | draft.case_study.001 | case_study | 数字・期限・割合 / 主体 | 媒介では双方に交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_021 | draft.case_study.002 | case_study | 義務/任意・前後・原則/例外 / 主体 | 専任は常勤・専従。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_003 | draft.case_study.003 | case_study | 数字・期限・割合 / 主体 | 契約行為ありの案内所は1人以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_002 | draft.case_study.004 | case_study | 義務/任意・前後・原則/例外 / 主体 | 宅建士証が必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_007 | draft.case_study.005 | case_study | 義務/任意・前後・原則/例外 / 主体 | 手付は解約手付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_004 | draft.case_study.006 | case_study | 数字・期限・割合 / 主体 | 35条説明時は士証提示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_006 | draft.case_study.007 | case_study | 数字・期限・割合 / 主体 | 専任は2週間に1回以上。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_001 | draft.case_study.008 | case_study | 主体 | 業者処分は指示・業務停止・免許取消。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_006 | draft.case_study.009 | case_study | 数字・期限・割合 / 主体 | 標識は外から分かる表示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_005 | draft.case_study.010 | case_study | 数字・期限・割合 / 主体 | 35条説明時は宅建士証提示。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_023 | draft.case_study.011 | case_study | 数字・期限・割合 / 主体 | 8種制限は買主保護。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_007 | draft.case_study.012 | case_study | 数字・期限・割合 / 主体 | 業者間では説明省略に注意。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_006 | draft.case_study.013 | case_study | 主体 | 保証協会の業務は弁済だけではない。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_license_007 | draft.case_study.014 | case_study | 数字・期限・割合 / 主体 | 同一都道府県内なら知事免許。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_002 | draft.case_study.015 | case_study | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 業者間には原則適用なし。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_020 | draft.case_study.016 | case_study | 数字・期限・割合 / 主体 | 更新は依頼者申出。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_supervision_010 | draft.case_study.017 | case_study | 数字・期限・割合 / 主体 | 事務禁止は最長1年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_004 | draft.case_study.018 | case_study | 数字・期限・割合 / 義務/任意・前後・原則/例外 / 主体 | 37条は説明義務ではなく書面交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_baikai_001 | draft.case_study.019 | case_study | 主体 | 媒介契約書は遅滞なく交付。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_019 | draft.case_study.020 | case_study | 義務/任意・前後・原則/例外 / 主体 | 提示と読み上げを区別。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_fee_001 | draft.case_study.021 | case_study | 主体 | 報酬は上限規制。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_001 | draft.case_study.022 | case_study | 数字・期限・割合 / 主体 | 事務所には専任宅建士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_8shu_005 | draft.case_study.023 | case_study | 数字・期限・割合 / 主体 | 手付は20％まで。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_hosho_kyokai_001 | draft.case_study.024 | case_study | 義務/任意・前後・原則/例外 / 主体 | 保証協会加入で営業保証金に代替。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_37_007 | draft.case_study.025 | case_study | 数字・期限・割合 / 主体 | 自ら売主でも37条。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_eigyo_hoshokin_001 | draft.case_study.026 | case_study | 義務/任意・前後・原則/例外 / 主体 | 供託＋届出後に営業開始。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_028 | draft.case_study.027 | case_study | 主体 | 現在は宅地建物取引士。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_office_004 | draft.case_study.028 | case_study | 数字・期限・割合 / 主体 | 案内所でも契約行為があれば必要。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_takkenshi_003 | draft.case_study.029 | case_study | 数字・期限・割合 / 主体 | 宅建士証も5年。 | 要校閲 | 2026-04-01 |  |  |  |
| concept.tl_gyoho_35_005 | draft.case_study.030 | case_study | 数字・期限・割合 / 主体 | 35条書面には宅建士記名。 | 要校閲 | 2026-04-01 |  |  |  |
