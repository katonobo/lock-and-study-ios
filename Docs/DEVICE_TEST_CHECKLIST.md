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
- [ ] Sandboxで月額、年額7日trial、2個別pack、Ask to Buy、restore
- [ ] Family Sharing、grace、billing retry、expiry、refund/revoke
- [ ] Pass＋個別所有、Pass終了後に個別所有だけ残る
- [ ] 宅建商品が`販売準備中`の間は購入できない

## データと移行

- [ ] export/share、履歴だけ削除、保護付き全初期化、破損backup
- [ ] 両旧アプリのverified購入・進捗、重複import、改変claim拒否
- [ ] Screen Time token/管理コード/緊急履歴が移行されない
