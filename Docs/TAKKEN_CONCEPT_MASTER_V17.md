# 宅建論点マスター v17

## 問題数と論点数を分ける理由

1,000問を1,000個の知識として扱うと、同じ規則の○×・数値・主体違いが別々の学習進捗になり、暗記できた文章数を理解した知識数と誤認する。v17では、覚える核を安定した`conceptID`へまとめ、問題はその知識を異なる経路から再想起するvariantとして扱う。

初期AIドラフトは380論点である。

| 分野 | 論点数 |
|---|---:|
| 宅建業法 | 140 |
| 権利関係 | 110 |
| 法令上の制限 | 65 |
| 税・その他 | 65 |
| 合計 | 380 |

重要度はA 120、B 180、C 80。Aは3〜5形式、Bは2〜3形式、Cは1〜2形式を上限目安とする。これはAIによる初期提案で、試験頻度や法的正確性の人間確認前である。

## 安定ID

`takken.<domain>.<subdomain>.<meaningful-slug>`を基本とする。年度や旧問題IDを正本へ含めず、旧IDは`legacySourceIDs`で追跡する。文章修正や年度更新ではconceptIDを維持し、制度の意味自体が変わる場合だけ新IDまたはsupersedes関係を使う。

## AIクラスタリング

既存1,000問を分野・subCategoryで分け、keyPoint、問題文、解説の意味類似度から最大4素材を一つのconcept候補へまとめた。現在の無料100問はGolden seedであるため、seed同士を同一conceptへ自動統合しない。

この処理は論点境界を法的に確定しない。全conceptは次の状態を維持する。

- `reviewStatus = ai_draft`
- `sourceNotes = []`
- `requiresSourceResearch = true`
- `reviewer = null`
- `reviewedAt = null`

## 人間校閲

校閲担当者は、同じ正しい規則か、期限・主体・効果を独立学習すべきかを確認する。Reviewedへ進めるには、法令名＋条項、公的資料名＋URL・公開日、判例情報など追跡可能な根拠が必要である。「公式サイトを確認」「担当者が確認」だけでは受理しない。

データはv18の責務分離により`ContentSource/TakkenConcepts/Generated/concept_master_ai_draft.json`へ移行した。検証は`./scripts/validate_takken_concept_master`で行う。
