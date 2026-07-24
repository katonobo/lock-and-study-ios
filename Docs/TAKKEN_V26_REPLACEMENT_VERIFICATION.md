# 宅建2026 v26 差替え検証記録

実施日: 2026-07-24

対象コミット: `945f8c8ea63c886bb1b98ece7f30c0a4598d98b5`

パッケージ: `LockAndStudy_Takken2026_v26_Codex_Replacement_Package.zip`

## 結論

Payload、独立Validator、既存Python検証、Debug/Release Build、未署名Archiveまでは反映・確認済み。
ただし、現在のリポジトリはパッケージが前提とするv20実行基盤ではなくv18基盤であり、変更禁止対象の
Lock Coreが次の2点でv26候補を拒否する。このためUnit Test、UI Test、実機解除フローは完了しておらず、
実機テスト用候補としてはNo-Goである。

1. `CertificationQuestionPackagePolicy`は`checked`、`reviewed`、`release`だけを許可し、
   全1,000問の`ai_review_candidate`を拒否する。
2. `SampleIndexV1Validator`は配列または`levels[].questions`だけを許可し、
   v26無料100問の`questions`ラッパーを拒否する。

候補を動かすにはこの2箇所を変更するか、パッケージ形式・状態を変える必要がある。前者は今回の
「Lock Coreを変更しない」、後者は指定SHA、`ai_review_candidate`維持に反するため、どちらも実施していない。

## バックアップ

バックアップ先:

`ContentSource/TakkenWork/Backups/20260724T125310+0900`

パッケージが既存前提としていた次の2ファイルは、対象コミットには存在しなかった。

- `takken_2026_questions_v20.json`
- `takken_2026_free_sample_100_v20.json`

この事実を`BACKUP_MANIFEST.json`へ記録し、実際に存在した宅建Release資産4ファイルを
パスを維持してバックアップした。

- `study_pack_catalog.json`
- `takken2026_metadata_v1.json`
- `takken_2026_free_100_v1.json`
- `takken2026_credits_v1.txt`

バックアップ4件のSHA-256照合は成功している。

## データ検証

- 全問題: 1,000問
- 無料問題: 100問（全問が全問題の部分集合）
- 論点: 380、無料100問は100論点
- `reviewStatus`: 全1,000問が`ai_review_candidate`
- `distractorReviewStatus`: 全1,000問が`ai_candidate_checked`
- `legalReviewChecklist`: true 0件
- `saleReady`: catalog / metadataともにfalse
- 外部有資格者レビュー要求: true
- Unlock対象: 680問
- 事例問題のUnlock対象: 0問
- 問題SHA-256:
  `af7f5b6e27e964d3cf6485497e302cdefed79b56cb70690444bb8178ce5a3263`
- 無料SHA-256:
  `52021360421a97d68d66399c0423fa0809c8d620c4e240985e3f6792c04be34e`

形式分布:

- ○×: 300
- 文言比較: 260
- 数値選択: 60
- 四択: 300
- 事例問題: 80

英単語2ファイルのSHA-256とbyteCountは変更なし。catalog内の英単語packも意味上の差分なし。
Bundle ID、IAP product ID、App Group、Extension ID、StoreKit、Shield、Unlock Runtime、
Lock CoreのSwiftファイルに変更はない。Xcode projectの差分は新しい2つのJSONをResourcesへ追加するものだけである。

## 検証結果

成功:

- パッケージ17ファイルのmanifest SHA / byteCount
- パッケージ内独立Validator
- リポジトリ用独立Validator
- `verify_released_content`
- Platform v9〜v18 verification
- `release_readiness`
- `LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 release_readiness`
- Debug Build
- Release Build
- 未署名Archive

Archive:

- `/tmp/LockAndStudy-v26-20260724.xcarchive`
- Bundle ID: `com.ameneko.lockandstudy`
- Archive内のv26問題・無料100問SHAはパッケージ指定値と一致

Unit Test:

- iOS 18.4 / iPhone 16 Simulator
- 全171件
- 成功162件
- 失敗9件
- 失敗内訳:
  - 6件: `ai_review_candidate`を現行Coreが未校閲として拒否
  - 2件: 無料100問の`questions`ラッパーを現行Coreが解釈できない
  - 1件: 旧`contentVersion`を固定期待する既存テスト

UI Test:

- iOS 18.4とiOS 17.5で試行
- Xcode 26.5の`DebuggerLLDB.DebuggerVersionStore.StoreError` /
  `no debugger version`によりアプリ起動前に停止

実機:

- paired端末は検出されたが、Xcodeからはoffline
- さらに上記Coreの実行時拒否があるため、無料100問、購入/Pass 1,000問、5形式、
  Unlock、120秒予習、conceptID履歴の実機確認は未完了

## 販売・昇格禁止

外部有資格者の全問法令校閲は未完了。`saleReady=true`、`reviewed`、`release`、
`legalReviewChecklist=true`への変更は行っていない。販売はNo-Goのままとする。
