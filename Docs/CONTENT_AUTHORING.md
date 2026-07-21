# Content Authoring

教材はrelease manifest、data JSON、metadata/creditsで構成します。IDは安定した `packID + itemID` とし、同一pack内の重複を禁止します。prompt、2個以上のchoices、有効なcorrect index、短い/長い解説、content versionが必須です。

英単語はlevel、word、意味、例文、発音用テキストを持ち、無料250語のIDは固定します。宅建はexam year、law basis date、category/subcategory、format、review status、annual review/update metadata、source noteを保持します。placeholder、空文、未校閲AI草稿をreleasedへ変更してはいけません。

新教材は `StudyExperienceFactory` と `UnlockChallengeProviding` を実装し、通常学習では教材固有モデルを維持します。共通型への変換は解除challengeと回答履歴のCodable snapshot境界だけで行います。履歴には出題時の選択肢、正解、解説、難易度、形式、法令基準日、content/question versionを保存し、後の教材更新で過去履歴を書き換えません。

編集後は `./scripts/validate_content` と `./scripts/verify_released_content` を実行します。
