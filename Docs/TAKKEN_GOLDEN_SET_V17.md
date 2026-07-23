# 宅建Golden Set v17

## 三つの集合

Golden 100 Conceptsは、現在の無料100問を種にした重要100論点である。Golden Variantsは、この100論点を異なる記憶経路で確認する品質基準候補である。Public Free Sampleは、校閲済みGolden Variantsから原則1concept 1問を決定的に選ぶ100問である。

問題数と論点数は同じ意味ではない。270問のGolden Variantsを解いても、学習した知識は最大100論点として数える。

## 現在のAIドラフト

- Golden concepts: 100
- Golden variants: 270
- reviewed/release: 0
- source research pending: 100 conceptを含む全380 concept

| format | 件数 | 比率 |
|---|---:|---:|
| true_false | 73 | 27.0% |
| number_choice | 59 | 21.9% |
| wording_contrast | 59 | 21.9% |
| multiple_choice | 60 | 22.2% |
| case_study | 19 | 7.0% |

## 公開100問の保護

現在の`takken_2026_free_100_v1.json`は変更していない。SHA-256は`6d4ce62f86a2a0b7805ec39442e3b01968c9f11947b9c2dd7fbbf8055e00d6af`、`expectedItemCount = 100`、`saleReady = false`を維持する。

`generate_takken_free_sample`は人間校閲済み270候補だけを入力として受理し、出力先を`ContentSource/ReleaseCandidates`に限定する。現在は全件AI草稿のためFail Closedし、ReleaseもReleaseCandidateも生成しない。
