# Lock and Study v18 最終検証

## 実装範囲

- Generated / ReviewBatches / Reviewed / Drafts / ReleaseCandidates / Backupsの分離
- atomic write、Reviewed backup、Generated再作成時のReviewed不変検査
- 50 Concept batchのexport / validate / import、merge/split、batch間transfer、冪等性
- Golden Question 100とdistinct Concept数の分離
- 468件の境界warningと人間decision template
- Reviewed Masterを明示入力するInventory / Variant生成
- human-reviewed `numericFacts`だけを使うnumber choice
- Free Sample profileとFull Pack 920/80/1,000 gate
- Unlock choiceのmisconception snapshot、通常演習と共通tagger、解消・再発

## データ監査

- Concept: 380（A 120 / B 180 / C 80）
- category: 宅建業法140 / 権利関係110 / 法令上の制限65 / 税・その他65
- 旧1,000問: base 325 / additional 506 / integrated 38 / duplicate 1 / source research 130
- Golden: Question 100 / Generated distinct Concept 100
- AI Golden variants: 270（TF 89 / MC 76 / wording 75 / case 30 / number 0）
- Reviewed Concept / Variant: 0
- source research未確認: 380
- full-pack variant不足: 500
- 境界warning: 468

merge/split統合fixtureでは、既知35条候補の2 Conceptをmergeし、別Conceptをsplitした後も380 Concept・旧1,000 IDの一意所有を維持する。Golden 100 Questionは99 distinct Conceptへmapできる。orphan、duplicate ownership、不一致transferは拒否する。

## Release保護

公開Release 100問、catalog content SHA、`saleReady = false`、platform freezeは変更していない。

- 公開100問SHA-256: `6d4ce62f86a2a0b7805ec39442e3b01968c9f11947b9c2dd7fbbf8055e00d6af`
- catalog SHA-256: `05571a3a05926f1c2ef28caef70f9991a3b2a4df550737345b8a47ff74e44685`
- 公開問題数 / expectedItemCount: 100 / 100
- `saleReady`: `false`
- AI処理による`reviewed` / `release`昇格: 0
- 本番Reviewed Master: 人間校閲未完了のため未作成

## 独立ゲート

2026-07-23の独立実行結果:

```sh
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_platform_v14
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_platform_v17
PYTHONDONTWRITEBYTECODE=1 ./scripts/verify_platform_v18
LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 ./scripts/release_readiness
```

- v9〜v18 `platform_verifications`: passed
- `release_readiness`: passed
- `audit_takken_content_v18`: passed
- Swift parse: 97ファイル passed
- v18対象XCTest: 4 passed / 0 failed
- 全Unit: 171 passed / 0 failed / 0 skipped
- Unit xcresult: `.build/V18UnitAll.xcresult`
- Debug Simulator build: passed
- Release Simulator build: passed
- Release Archive: passed
- Archive: `/tmp/LockAndStudy-v18-verified.xcarchive`
- Archive構成: arm64、Bundle ID `com.ameneko.lockandstudy`、App Extension 3件

全UIテストはビルドまで成功したが、Xcode 26.5の`DebuggerLLDB.DebuggerVersionStore.StoreError: no debugger version`によりテスト対象アプリの起動前で停止した。iOS 18.4、26.2、26.5、Simulator再起動、Xcode first-launch再初期化でも同じで、テスト失敗やアプリcrashには到達していない。v17時点のUIテストは合格済みであり、v18ではUI画面を変更していないが、今回の環境では新しいUI合格結果を確定できていない。

## 未解決の人間作業

- 468 boundary warningのaccept/merge/split判断
- 380 Conceptの具体的法令・公的資料確認
- numericFactsと年度更新要否のConcept単位確認
- 1,000問の問題文・誤答理由・出典校閲
- 全review batch import後のGolden mapping確定
- Free Sample / Full Packの商品承認
