# Architecture

## 境界と依存方向

`Features → AppModel/DependencyContainer → Core protocols/services → Apple frameworks or local storage` の一方向です。教材固有コードは `StudyModule` を実装し、Lock、Commerce、Persistenceから参照されません。AppModelは画面間調停だけを行い、巨大な全機能クラスにはしません。

- Lock Core: policy、session、弱化判定、Screen Time adapter
- Security: 管理コード、緊急解除、保護変更
- Content: manifest、hash検証、module registry、access decision
- Commerce: StoreKit 2、複合entitlement、表示モデル
- Learning: prompt snapshot、SRS、解除bundle planner
- Persistence: Application Supportのversioned JSON/NDJSON
- Migration: 専用App Groupの許可済みclaim/progressだけを取込

3拡張はメインアプリをリンクせず、`Shared/` の最小モデルとApp Groupだけを共有します。Shield Actionは解除せずpending requestを冪等作成します。解除はメインアプリが学習完了後に再ロック予約を先に成功させてから行います。

## 保存先

- App Group: policy、選択token、解除session、拡張間request、最小診断状態
- Application Support: 学習進捗、回答NDJSON、event、解除bundle
- Keychain: salted PBKDF2管理コードcredential
- UserDefaults entitlement cache: 起動表示用。StoreKit 2検証を権利の正本とする
- Migration App Group: 旧アプリが生成する一時claim/progress

Releaseコードは外部通信、広告、分析SDKを持ちません。
