# ReviewBatches

`export_takken_concept_review_batch`が出力したbatchを人間が編集する作業領域です。`concept_boundary_decisions_v18.json`はwarningごとの`accept` / `merge` / `split`判断を記録するテンプレートであり、生成スクリプトが自動判断を入力することはありません。

完成batchは、Conceptごとの出典、reviewer、reviewedAt、reviewDecisionを記録します。merge/splitで旧問題IDを別batchへ移す場合、送り側と受け側のtransfer metadataを対で更新してください。
