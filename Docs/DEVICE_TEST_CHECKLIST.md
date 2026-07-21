# Device Test Checklist

## 端末とOS

- [ ] iOS 16のiPhone、現行iOSのiPhone、iPadでinstall/archive build
- [ ] portrait/landscape、Dynamic Type最大、VoiceOver、Reduce Motion
- [ ] timezone変更、深夜跨ぎ、夏時間地域、再起動、強制終了

## Screen Time

- [ ] `.individual` 認可、拒否、後から失効、再認可
- [ ] app/category/web domain選択と同数token差替
- [ ] shield主/副ボタン、通知許可/拒否、手動起動
- [ ] 解除完了までshield維持、5/10/20/30分、終了後再ロック
- [ ] monitor重複callback、予約失敗、期限切れsession復旧
- [ ] 管理コードの変更/削除/誤入力lockout/24時間reset
- [ ] 30秒active待機＋5秒holdの緊急解除、background停止、24時間境界

## 学習と購入

- [ ] 無料英単語250と無料宅建100だけで繰返し解除
- [ ] 誤答6/12/20秒、二重タップ、bundle再起動復元/30分失効
- [ ] 英単語解除成功直後だけ次回予習を表示し、前面2秒確認、120秒で完全非表示、再起動・タブ移動・backgroundで期限非延長
- [ ] 確認済み予習が24時間以内の次回解除で先頭へ一度だけ入り、版変更・レベル外・権利喪失では採用されない
- [ ] challenge期限切れを回答直前・正答保存直前・解除session作成直前に発生させてもShieldが解除されない
- [ ] Sandboxで月額、年額7日trial、2個別pack、Ask to Buy、restore
- [ ] Family Sharing、grace、billing retry、expiry、refund/revoke
- [ ] Pass＋個別所有、Pass終了後に個別所有だけ残る
- [ ] 宅建商品が`販売準備中`の間は購入できない

## データと移行

- [ ] export/share、履歴だけ削除、保護付き全初期化、破損backup
- [ ] 履歴削除直後に英単語・宅建の表示中モデルが0件へ更新され、予習ファイルも削除される
- [ ] 両旧アプリのverified購入・進捗、重複import、改変claim拒否
- [ ] Screen Time token/管理コード/緊急履歴が移行されない

## 週次レポート

- [ ] 無料ユーザーで英単語・宅建それぞれの記録タブから当週レポートを開ける
- [ ] Shield起点は学習チャンスへ入り、教材ホームの手動開始は入らない
- [ ] ロック無効時の問題完了で「解除できた回数」が増えない
- [ ] この教材／すべての教材を切り替えても教材データが混ざらない
- [ ] 家族共有シートが明示操作で開き、アプリ名・token・管理コード・緊急理由・個別問題が含まれない
- [ ] オンボーディングのサンプルが実回答、進捗、レポートへ混ざらない
- [ ] 学習履歴削除後、表示更新またはpull-to-refreshで全指標が0へ戻る
- [ ] 深夜跨ぎ、TimeZone変更、DST地域でも7暦日と日別グラフが正しい
- [ ] iPhone/iPad、最大Dynamic Type、VoiceOverでヒーロー・主要指標・共有が欠けない
