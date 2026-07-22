# Content Release Process

1. 原稿を `ContentSource/Drafts` またはreview領域で編集する。
2. 人手で正答、選択肢、解説、出典、年度、法令基準日を確認する。
3. reviewerと承認日をmetadataへ記録し、`releaseStatus=released` にする。
4. data fileのSHA-256、byte count、expected count、固定sample IDを更新する。
5. `Release/Resources/Content` に承認済みファイルだけを配置する。
6. 全scriptsとUnit/UI Test、Release buildを通す。

`./scripts/check_unreviewed_content` はreviewed/draftがReleaseへ入っていないこと、`release_readiness` はcount/hash/placeholder/販売表現/商品/Privacy設定に加え、共通runnerからv9、v10、v11、v12のPlatform検査を確認します。提出前の正本コマンドは`LOCKANDSTUDY_REQUIRE_FINAL_ICON=1 ./scripts/release_readiness`です。

現在の判定：英単語3,000語はrelease、無料250語は固定sample、宅建100問は無料release、宅建追加200問は最終承認前、宅建700問は人手校閲前です。200問・700問のstatusだけを機械的に変えて公開してはいけません。
