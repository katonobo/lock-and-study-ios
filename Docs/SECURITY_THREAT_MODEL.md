# Security Threat Model

| 脅威 | 対策 | 残余リスク |
|---|---|---|
| 管理コード推測/漏えい | random salt、PBKDF2-HMAC-SHA256、constant-time比較、5/10回lockout、Keychain ThisDeviceOnly | 端末所有者がiOS設定やアプリ削除を行うことは防げない |
| 時計巻き戻し | 最終失敗時刻を下限にし、sessionは絶対終了時刻で判定 | OS全体改変端末は範囲外 |
| 弱化操作の即時回避 | 管理コードまたは24時間＋二度目確認、同数token変更もdigest判定 | アプリ削除/Family Controls取消はOS権限 |
| App Group改変 | schema、allowlist、digest、複合ID、冪等merge | 同一Team署名の侵害にはサーバー署名がない |
| 拡張callback重複/順不同 | request/session/activity名を固定し、全操作を冪等化、`endsAt`確認 | OSが拡張を起動しない期間は次回アプリ起動で復旧 |
| StoreKit権利偽装 | verified transactionのみ、revoked/refunded/expired除外 | offline cacheは短期表示用で正本ではない |
| 旧claim偽造 | migration entitlement、verified旧transaction、source/product mapping、nonce/digest/consumedAt | digestは秘密署名ではなく破損検知 |
| content破損/差替 | manifest SHA-256、count/schema/placeholder検証 | バンドル自体の署名侵害はOS code signing境界 |
| 学習ファイル破損 | atomic write、schema version、corrupt backup、snapshot | backupから自動復元は行わずユーザーへ通知 |
| 解除不能 | 固定無料教材、権利snapshot bundle、緊急解除、再ロック予約前のshield維持 | Screen Time認可失効時は再認可が必要 |

ReleaseにはURLSession、広告/分析SDK、debug premium、master code、通常フローの`fatalError`を含めません。診断値にはtoken、コード、receipt、回答内容を保存しません。
