# Architecture

## 境界と依存方向

`Selected Study Experience → DependencyContainer → Core services → Apple frameworks or local storage` の一方向です。共通層はロック・権利・教材ラインナップ・全体データを担当し、教材固有画面や通常学習の問題選択を担当しません。

オンボーディング完了後は、選択したStudy Experienceをアプリの唯一のRootとして表示します。共通Platformタブは表示せず、教材ラインナップは各Experienceの設定画面にある「教材の選択」から全画面表示します。教材を選ぶとRootを置き換え、次回起動時もその教材へ直接入ります。

オンボーディングはScreen Time認可とロック対象選択を必須とし、Shieldの適用成功後にだけ完了状態を保存します。したがって「オンボーディング完了」と「基本ロック有効」は同じコミット境界です。

- `StudyExperienceRegistry`: pack IDからExperience factoryを解決
- `StudyExperienceFactory`: 独自Root、First Run、進捗summary、解除rendererを生成
- `UnlockChallengeProviding`: Lock Coreが教材へ解除問題を要求する唯一の境界
- `VocabularyExperience`: 独自AppModel、Router、Settings、5タブ、`VocabularyItem`による通常学習
- `TakkenExperience`: 独自AppModel、Router、Settings、5タブ、`TakkenQuestion`による通常学習

通常学習では教材型を共通`StudyPrompt`へ平坦化しません。共通Codable型は、プロセス再起動を越える解除challengeと回答履歴snapshotの境界に限定します。旧`StudyModule`/`StudyPrompt`経路は既存データ互換と移行のため残しますが、現行Experienceの通常学習には使いません。

- Lock Core: policy、session、弱化判定、Screen Time adapter
- Security: 管理コード、緊急解除、保護変更
- Content: manifest、全contentFilesのhash/count検証、experience registry、access decision
- Commerce: StoreKit 2、複合entitlement、表示モデル
- Learning: 教材別queue/SRS/feedback、回答snapshot、解除challenge
- Persistence: Application Supportのversioned JSON/NDJSON、submission IDとcompletion checkpointによる再試行耐性
- Migration: 専用App Groupの許可済みclaim/progressだけを取込

3拡張はメインアプリをリンクせず、`Shared/` の最小モデルとApp Groupだけを共有します。Shield Actionは解除せずpending requestを冪等作成します。解除はメインアプリが学習完了後に再ロック予約を先に成功させてから行います。Device Activity callbackが保存済み終了時刻より早い場合は終了時刻へ再予約し、再予約失敗時は直ちにShieldを再適用します。

## 保存先

- App Group: policy、選択token、解除session、拡張間request、最小診断状態
- Application Support: 学習進捗、回答NDJSON、event、解除bundle
- Keychain: salted PBKDF2管理コードcredential
- UserDefaults entitlement cache: 起動表示用。StoreKit 2検証を権利の正本とする
- Migration App Group: 旧アプリが生成する一時claim/progress

Releaseコードは外部通信、広告、分析SDKを持ちません。
