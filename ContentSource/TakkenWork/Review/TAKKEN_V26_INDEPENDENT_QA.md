# 宅建2026 v26 差替候補・独立QA報告

作成日: 2026-07-24

法令基準日: 2026-04-01

状態: **外部法令校閲前の差替レビュー候補（saleReady=false）**

## 完成物

- 全問題: 1,000問
- 無料 / 有料: 100 / 900
- distinct Concept: 380
- 無料100問のdistinct Concept: 100
- 問題SHA-256: `af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263`
- 無料100問SHA-256: `52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e`

## 配分

- 分野: {'宅建業法': 400, '権利関係': 280, '法令上の制限': 160, '税・その他': 160}
- 形式: {'wording_contrast': 260, 'multiple_choice': 300, 'case_study': 80, 'true_false': 300, 'number_choice': 60}
- 用途: {'unlock_micro': 680, 'standard_practice': 240, 'integrated_mock': 80}
- 難易度: {'標準': 450, '応用': 150, '基礎': 400}
- 無料分野: {'宅建業法': 40, '権利関係': 28, '法令上の制限': 16, '税・その他': 16}
- 無料形式: {'wording_contrast': 18, 'true_false': 26, 'multiple_choice': 32, 'case_study': 8, 'number_choice': 16}

## 自動検査で確認済み

- 問題ID・問題ルート重複: 0
- 正解choice IDとindexの不一致: 0
- 選択肢重複: 0
- 誤答理由欠落: 0
- 無料100問が本体の部分集合でない問題: 0
- 生成崩れ・placeholder・内部管理コード: 0
- `なければなります`等の既知の不自然文: 0
- 全問題のreviewStatus: `ai_review_candidate`
- legalReviewChecklistの自動承認: 0
- catalog / metadataのsaleReady: false

## 旧v20からの主な是正

- 管理番号だけを変えた同一問題の水増しを禁止
- 1 Conceptにつき同一形式は1問まで
- 4択・事例の誤答を、同一分野の具体的な誤命題から構成
- 各誤答に固有の訂正文とmisconception分類を保存
- 無料100問を100の異なるConceptから選定
- 公式過去問100% Coverageを未検証のまま主張しない
- document-levelの公式出典候補と、問題単位の外部校閲を明確に分離

## 未完了・販売禁止理由

この成果物は、**問題データとして実装可能な1,000問を作成したもの**ですが、宅建有資格者または法律専門家による全問の条文・施行日・例外・誤答肢確認は未完了です。そのため、Releasedフォルダへテスト差替えできるPayloadを含めていますが、`saleReady=false`を維持します。

特に次を問題単位で承認するまで有料販売しないでください。

1. 正解の一意性
2. 2026年4月1日施行法令との一致
3. 各誤答肢が確実に誤りで、かつ不自然なダミーでないこと
4. 短解説・詳細解説・混同ポイントの妥当性
5. 統計・税制・軽減措置・経過措置
6. document-level出典から具体的条項への確定

## 判定

- Codexによるローカル差替え・Build/Test: **Go**
- 実機での学習UX評価: **Go**
- App Storeの有料教材として販売: **No-Go（外部全問校閲後）**
