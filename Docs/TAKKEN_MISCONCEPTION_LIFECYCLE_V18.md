# Unlock誤概念ライフサイクル v18

## 記録

`CertificationChallengeQuestion`は、出題時のchoice IDから`misconceptionCode`へのsnapshotを保持する。選択肢shuffle後は元choiceのrationaleとcodeを、提示後choice IDへ同時に写すため、表示順と記録tagがずれない。

Unlockで誤答した`StudyAnswerRecord.tags`には通常演習と同じ`TakkenMisconceptionTagger`を使い、`misconception:number`、`misconception:timing`等を保存する。codeがない誤答は従来どおり一般weaknessとして扱う。

## active / resolved

`TakkenConceptMasteryPolicy`は履歴を入力するpure functionとして、codeごとの最新誤答を起点にactive weaknessを算出する。

弱点は次のいずれかで解消する。

1. 最新誤答後、同じcodeの克服に適した形式で、異なるvariantかつ異なるsessionの初回正解を2回得る。
2. 最新誤答後にConceptがmasteredへ到達し、異なるvariant・sessionの初回正解を2回得る。

解消後に同じcodeで新たに誤答した場合、その時点を新しい起点としてactiveへ戻る。全履歴に一度でも存在したcodeを永久に弱点扱いしない。

形式適合例:

- `number`: `number_choice`
- `timing`: timing route
- `exception`: wording contrast / case study
- `scope` / `condition`: multiple choice / case study
- `obligation` / `procedure` / `document`: wording contrast / multiple choice

## 回帰テスト

`TakkenConceptWorkflowV18Tests`で次を検証する。

- choice shuffle後も選択した提示IDが元のmisconception codeへ一致
- Unlock誤答と通常演習が同じtagを保存
- 異なるvariant/sessionの2回正解で解消
- 解消後の再誤答でactiveへ戻る
- mastery後に古い誤概念が残らない
