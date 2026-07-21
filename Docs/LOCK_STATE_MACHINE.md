# Lock State Machine

## 状態

| 状態 | 意味 | 主な遷移 |
|---|---|---|
| `notConfigured` | 未設定 | 認可・対象選択・開始で`active` |
| `active` | shield適用中 | 学習完了で`temporarilyUnlocked` |
| `temporarilyUnlocked` | 終了時刻付き解除 | monitor/復旧で`active` |
| `authorizationLost` | Screen Time認可失効 | 再認可で前状態を復旧 |
| `exitPending` | 終了の待機中 | 管理コード承認または24時間後の二度目確認 |
| `ended` | 利用終了 | 明示的な再設定まで解除 |

Shieldの主ボタンはApp Groupにpending requestを1件だけ作成して閉じます。通知許可時は案内通知を出し、拒否時はユーザーが手動でアプリを開きます。

解除学習完了時は、DeviceActivityの再ロック予約成功、解除session保存、shield解除の順です。予約失敗時はshieldを解除しません。拡張callbackが早ければ保存済み`endsAt`へ再予約し、失敗すれば即時再ロックします。アプリ起動・前面復帰時もactive sessionのmonitorを再構築し、再構築失敗または期限切れならShieldを再適用します。保存済み`endsAt`とbundle reason codeを正本として冪等に復旧します。

解除challengeは回答送信前、正答記録後のbundle保存前、一時解除session作成直前に期限を再確認します。どの境界でも期限切れならbundleを`aborted`として保存し、画面を閉じ、Shieldを解除しません。回答送信結果は正答・誤答・期限切れ・保存失敗を分離し、保存失敗時は回答ボタンを再度有効にします。

ロック対象変更は、通常設定、管理コード承認、24時間待機後の二度目確認のすべてが`LockControlling.saveSelection`を通ります。基本ロック中かつ一時解除中でなければ、新しいtokenで即座にShieldを再適用します。一時解除中は保存だけ行い、次回再ロック時に新しい対象を使います。適用失敗時は以前の選択とpolicyへ戻し、明示エラーを表示します。

対象削減、同数でもdigestが変わる選択変更、解除量増加、復習量減少、commitment短縮、ロック終了、管理コード削除は弱化です。管理コードがなければ24時間待機後の二度目確認、設定済みならコード承認が必要です。緊急解除はrolling 24時間に1回、30秒active待機、5秒hold、15分解除です。
