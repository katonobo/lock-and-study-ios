# Architecture

## 境界と依存方向

`Selected Study Experience → DependencyContainer → Core services → Apple frameworks or local storage` の一方向です。共通層はロック・権利・教材ラインナップ・全体データを担当し、教材固有画面や通常学習の問題選択を担当しません。

オンボーディング完了後は、選択したStudy Experienceをアプリの唯一のRootとして表示します。共通Platformタブは表示せず、教材ラインナップは各Experienceの設定画面にある「教材の選択」から全画面表示します。教材を選ぶとRootを置き換え、次回起動時もその教材へ直接入ります。

オンボーディングはScreen Time認可とロック対象選択を必須とし、Shieldの適用成功後にだけ完了状態を保存します。したがって「オンボーディング完了」と「基本ロック有効」は同じコミット境界です。

- `StudyExperienceRegistry`: manifestの開いた`experienceID`からFactoryを解決
- `StudyExperienceFactory`: 独自Root、First Run、進捗summary、`StudyExperienceSessionRuntime`、教材固有の解除完了hookを提供
- `StudyExperienceReportProviding`: 共通snapshotから教材固有の週次指標だけを生成
- `FlashcardExperience`: Profile、pack単位設定、SRS、予習、カード学習を提供。英単語と四字熟語で同じ本番Swift実装を使う
- `CertificationExperience`: Profile、分野、問題形式、誤答学び直しを提供。宅建とビジネスマナーで同じ本番Swift実装を使う

通常学習では教材型を共通`StudyPrompt`へ平坦化しません。解除の正本は`UnlockChallengeSessionEnvelope`であり、Lock Coreは`enginePayload`をdecodeしません。問題位置、選択肢、正誤、解説確認時間、再回答、SRSはExperience Runtimeが所有し、完了時だけ`ExperienceCompletionProof`を共通Coordinatorへ返します。旧`StudyModule`/`StudyPrompt`と旧問題snapshotは`Compatibility`と移行用途に限定され、新Experienceの可用性判定には使いません。

Flashcardの次回予習は解除成功後のRuntime hookでpack単位に作成します。作成時刻から120秒だけホームへ表示し、前面で2秒確認された候補は24時間以内なら次回解除問題の先頭へ一度だけ採用します。Certificationもpack単位の論点予習を保持します。hookはEnvelope IDで冪等であり、予習保存失敗は獲得済み解除を取り消しません。

- Lock Core: policy、session、弱化判定、Screen Time adapter
- Security: 管理コード、緊急解除、保護変更
- Content: strict catalog、階層Category、manifest、全contentFilesのhash/count検証、experience compatibility、access decision、Installed→Bundled→Safe Fallback
- Commerce: StoreKit 2、複合entitlement、表示モデル
- Learning: 教材別queue/SRS/feedback、回答snapshot、解除challenge
- Persistence: Application Supportのversioned JSON/NDJSON、submission ID、解除completion checkpoint、英単語予習の永続期限と一度だけの消費による再試行耐性
- Reporting: `LearningDataStore`を表示時に再読込し、Calendarベースの直近7暦日、共通指標、教材別section、共有要約を端末内で生成
- Migration: 専用App Groupの許可済みclaim/progressだけを取込

3拡張はメインアプリをリンクせず、`Shared/` の最小モデルとApp Groupだけを共有します。Shield Actionは解除せずpending requestを冪等作成します。解除はメインアプリが学習完了後に再ロック予約を先に成功させてから行います。Device Activity callbackが保存済み終了時刻より早い場合は終了時刻へ再予約し、再予約失敗時は直ちにShieldを再適用します。

## 保存先

- App Group: policy、選択token、解除session、拡張間request、最小診断状態
- Application Support: 学習進捗、回答NDJSON、event、opaque解除Envelope、検証済みInstalled package
- Keychain: salted PBKDF2管理コードcredential
- UserDefaults entitlement cache: 起動表示用。StoreKit 2検証を権利の正本とする
- Migration App Group: 旧アプリが生成する一時claim/progress

Releaseコードは外部通信、広告、分析SDKを持ちません。

## 週次レポート

英単語と宅建の各「記録」タブは、その教材の`NavigationStack`内から共通`LearningReportView`を開きます。グローバルTabViewは使用しません。画面内のスコープ切替だけで「この教材／すべての教材」を切り替え、他教材データがない場合は切替自体を表示しません。

`LearningReportService`は回答、event、進捗、released manifestを`LearningDataStore`とContent Repositoryから毎回取得します。共通層はShield起点の学習チャンス、実回答、実際に作成された解除sessionだけを集計し、`VocabularyReportProvider`と`TakkenReportProvider`が新出・復習、レベル進捗、分野成績などを追加します。サンプルレポートは固定メモリデータだけを使い、保存領域へ書き込みません。
# v11 final hardening

Unlock Challengeの復元は`UnlockSessionRestorationValidator`を通過した場合だけChallenge Viewを生成する。pack ID、Packの利用可否（現行または買い切り所有済みArchived）、normalized Experience ID、payload schema、content versionの完全一致が必要である。不一致時はEnvelopeを`aborted`にし、ロックを維持した回復画面から組み込みの安全問題だけを開始する。別Packのmanifestを復元に流用してはならない。

Catalog validationはGlobal fatalとPack-localを区別する。Category/Series/Packの重複ID、Category cycle、Catalog root/schema不正はCatalog全体を拒否する。Pack参照・component・商品ID等の局所エラーは該当Packだけを隔離する。Category/Seriesの曖昧な先勝ち・後勝ちは認めない。

検証済みCatalogは`ValidatedCatalogStore`がApplication Supportへ原子的に保存し、1世代のbackupを保持する。読込み優先順は、新Catalog、プロセス内LKG、永続LKG/backup、bundled、safe fallbackである。永続データも再decode・再validationしてから利用する。
