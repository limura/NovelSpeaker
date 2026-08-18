# 発話追従スクロールの一時停止と、画面下部ボタン群

ユーザ要望(2026-08-18 受信のサポートメール)への調査・設計メモ。

## 要望と、今回の対象範囲

要望の骨子:
- 読み上げを止めずに、自分でスクロールして先を読んだり読み飛ばしたりしたい
- 目で読んでいる場所へ「読み上げ位置」を引っ張って行きたい
- (別件)操作ボタンが画面右上だけなのは片手だと押しにくい。画面下部にも欲しい

**対象外(非対応)**: 「閑話を飛ばして結末だけ読む」のような**別ページを読みながらの発話継続**。
発話中の本文と表示中の本文が一致している前提のコードが多く(`storySpeakerStoryChanged` が
表示側を強制的に追従させる等)、崩すと影響範囲が大きすぎる。
今回対象とするのは **同じページ内での先読み・読み戻し** のみ。

## 設計方針(ことせかい流)

capti の再現はしない。以下は capti にはあるが**入れない**:

- ハイライトのグレーアウト → 数秒止まるだけなのに色が変わる意味がない
- 射的マーク(追従 ON/OFF の常設トグル) → ユーザに「今どちらの状態か」を管理させることになる
- 停止中インジケータ / 「読み上げ位置へ戻る」フローティングボタン → 同上
- 「無期限に止める」 → 代わりに `0 = 機能OFF(常に追従)`

**基本の体験は「発話中はスクロールするもの」のまま変えない。**
ちょっと自分で動かすと止まるが、ほったらかせばすぐ再開する。ユーザが状態を意識する必要はない。
長く止めたい人は秒数設定を伸ばす(設定が唯一の逃げ道であり、モード状態は増えない)。

## 1. 追従の一時停止

### 止める場所

強制スクロールと強制範囲選択は1箇所に集約されている。

`SpeechViewController.swift:1569` `storySpeakerUpdateReadingPoint(storyID:range:)`
- `textView.select(self)` + `textView.selectedRange = newRange` … 強制範囲選択
- `textViewScrollTo(readLocation:)` … 強制スクロール

一時停止中はこの関数の中身をまるごと skip する。それだけで両方止まる。
(呼び元は `StorySpeaker.willSpeakRange()` = `StorySpeaker.swift:1389`)

WebView 版は `WebSpeechViewController.swift:1745` の同名メソッドだが、**skip するのは
`scrollToIndex()` だけ**にする。`highlightSpeechLocation()` は止めない(下記)。

### 手動スクロールの検出

`UIScrollViewDelegate.scrollViewWillBeginDragging(_:)` を使う。

- `UITextView` は `UIScrollView` のサブクラスなので `textView.delegate = self` でよい。
  **`textView.delegate` は現在未使用**(storyboard にも outlet 無し)。
- `willBeginDragging` は指/トラックパッドのドラッグ開始でのみ呼ばれ、
  `scrollRectToVisible(animated:)` 等のプログラム由来では呼ばれない。判定として素直に使える。
  (`scrollViewDidScroll` はプログラム由来でも呼ばれるので使ってはいけない)
- 自前のジェスチャは足さない。既存の左右スワイプ章送り(`panRecgnizer`, `SpeechViewController.swift:322`)と競合する。
- WebView 版は `webView.scrollView` の delegate を **`ScrollPullAndFireHandler` が握っている**
  (`ScrollPullAndFireHandler.swift:37`)。ここにコールバックを1つ足して横流しする。

タイマーは **指を離した時(`scrollViewDidEndDragging` / `scrollViewDidEndDecelerating`)起点**で開始し、
スクロールのたびにリセットする。

### 停止秒数の設定

`RealmGlobalState` に Int で持つ(端末間で共有・バックアップされるべき値のため)。

- 範囲 0〜60秒、**既定 5秒**、`0 = 機能OFF(従来どおり常に追従)`
- 既定を短くするのは、今まで常に動いていたので「誤タップで動かなくなった」と誤解されるのを避けるため。
  頻繁に先読みしたい人は自分で60秒まで伸ばす。

`RealmGlobalState` にプロパティを増やすと、**自動では入らない手書きの3箇所**への追記が必要:
- `NovelSpeakerUtility.swift:2348` 付近 — バックアップ辞書への出力
- `NovelSpeakerUtility.swift:1665` 付近 — バックアップからの復元
- `RealmToRealmCopyTool.swift:195` 付近 — ローカル↔iCloud Realm 間コピー

CloudKit 同期は `RealmGlobalState` が既に SyncObject なので自動で乗る。

⚠️ **復元時、キーが無ければ現在値を放置する**(既定値5で上書きしない)。
キーが無い = この設定がまだ無かった頃の古いバックアップ、という意味なので、
そこに書かれていない設定を初期値で潰してはいけない。
既存の復元処理は `if let x = dic.object(forKey: "...") as? NSNumber { globalState.x = ... }` の形で
**キーが無ければ何もしない**イディオム になっている(復元対象は `RealmGlobalState.GetInstanceWith()` で得た
生きているインスタンス、`NovelSpeakerUtility.swift:1535`)ので、この書き方をそのまま踏襲すればよい。

### 「読み上げ位置が画面内に入ってきたら自動再開」は採用しない

`textViewScrollTo()` は `targetY = caretY - visibleHeight * 0.7` なので、
**読み上げ位置が画面の70%の位置に来る**ようにスクロールする(WebView 側の `ScrollToElement` も
margin 0.3 で同じ結果)。「画面内に入った」時点で再開すると必ずそこまで飛ぶので、突然のスクロールになる。
数秒待てば通常のタイマーで再開するので、それでよい。

### WebView 版のハイライトは止めない(ただし selection だけは止める)

通常版では「ハイライト = 選択範囲」そのものなので、止めれば両方止まる。
WebView 版は **canvas を重ねたハイライトと、本物の `selection` が別物**なので、
ハイライト(canvas)は動かし続けてよい。読み上げ位置が画面内にあれば見えるだけで、
スクロールはしないので支障はない。

ただし1点だけ注意がある。`HighlightSpeechSentence()`(`WebSpeechViewTool_Inject.js:112` 付近)は
canvas を動かした後に

```javascript
let selection = window.getSelection();
selection.removeAllRanges();
selection.addRange(range);
```

も実行していて、この `selection` は**飾りではなく機能している**:
- WebView 版の再生ボタン `CheckFolderAndStartSpeech()`(`WebSpeechViewController.swift:1491`)は
  `getSelectedLocation()`(= `window.getSelection()`)を読み位置にしている
- `prevSearchByText` / `nextSearchByText`(`WebSpeechViewController.swift:1382`, `1410`)も検索起点に使う

このまま一時停止中も動かすと、**ユーザが長押しで作った選択範囲を1ブロックごとに奪ってしまい**、
「ここから発話開始」が位置を取れなくなる。

→ **一時停止中は canvas の更新だけ行い、`selection` の張り替えはしない**ように
`HighlightSpeechSentence()` を分ける(フラグ1つ)。これで:
- 読み上げ位置は見え続ける
- ユーザの長押し選択は生き残り、`getSelectedLocation()` がそのまま「ここから発話開始」に使える
- 一時停止が終われば selection も読み上げ位置に戻る

通常版の textView 側に同等の「選択とは別の独立ハイライト」を作る案(背景色属性を付ける等)は、
`attributedText` の差し替えがスクロール中に怪しい挙動をする既知の問題(`SpeechViewController.swift:846` のコメント)
があるので**採らない**。通常版は最後の選択範囲が固まったまま残る、でよい。

### 一時停止中にページが変わったら

`setStoryWithoutSetToStorySpeaker()`(`SpeechViewController.swift:816`)が先頭にスクロールし直すので、
一時停止中に章が変わったら**強制スクロールを再開する**(= 一時停止を解除する)。
別ページを見ながらの発話継続を非対応にしたのと同じ理由で、そこは追いようがない。

## 2. 「ここから発話開始」

### 実機実測(2026-08-18, iPhone SE 3rd gen = 375pt, iOS 18.1)

検証用の最小アプリ(非編集 `UITextView` + `UIMenuController`)を作って長押しメニューを実測した。

| 条件 | 結果 |
|---|---|
| `canPerformAction` 素通し + 自前4項目(= ことせかいの発話停止中) | 1頁目 `Copy / Look Up / Translate` → `>` → `Search Web / Learn...` → `>` → `Share... / 読み替え辞書へ登録`。**自前項目に到達するのに `>` 2回** |
| 自前4項目のみ許可(`isMenuItemIsAddNovelSpeakerItemsOnly` 相当) | **システム項目は全部消えた**。ただし自前項目もタイトルが長く1頁1項目でページ送りが出る |
| 「ここから発話開始」1項目のみ許可 | **1項目だけが表示され、ページ送りなし。長押ししてそのまま押せる** |
| iOS16+ `textView(_:editMenuForTextIn:suggestedActions:)` で自前1項目を返す | 同じく1項目のみ。`suggestedActions` は `Menu()[6] / Menu()[5] / Menu()[0] / Menu(Format)[3] / Menu()[3] / Menu()[1] / Menu(Speech)[3] / Menu()[1]` の8グループとして渡ってくる |

結論:
- **狭い端末でのページ送り問題は「発話中は1項目だけ許可する」ことで回避できる**(実測確認済み)。
  逆に、既存の項目を残したまま足すとページ送りの奥に沈むので駄目。
- `canPerformAction` で `false` を返せば、`Copy` / `Look Up` / `Translate` / `Search Web` /
  `Learn...` / `Share...` といったシステム項目は**消える**(少なくとも iOS 18.1 では)。
- iOS16+ の `editMenuForTextIn` なら `suggestedActions` を**列挙して選別できる**ので、
  「本文中の長押しメニュー項目を減らす」で取りこぼしている項目も指定できる可能性がある。
  ただしデプロイメントターゲットが **iOS 15.0** なので `#available` ゲート + 旧経路の維持が必要。
  (これは今回のスコープ外だが、別途やる価値がある)

### `canPerformAction` を触る時の注意

`CustomUITextView.canPerformAction`(`CustomUITextView.swift:16`)が発話中に無条件で `false` を
返しているのは、**過去に OS のメジャーバージョンアップ後、`selectedRange` を代入したタイミングで
勝手にメニューのバルーンが出るようになり、消費電力が激増した**のを塞いだ経緯があるため。

今回 iOS 18.1 で「`selectedRange` を 0.7 秒ごとに更新し続ける」再現を試したが、
素通しモードでもバルーンは自動で出なかった = **現行OSでは再現せず、判断材料にならない**。
将来の OS で再発する可能性は否定できないので、安全側に倒す:

> **`canPerformAction` を緩めるのは「追従が一時停止している間」だけにする。**
> 一時停止中はアプリが `selectedRange` を代入していないので、そもそも当時の発火条件が成立しない。

つまり条件は「発話中 **かつ** 追従一時停止中」のときだけ「ここから発話開始」を通す。

### 位置の指定と発話の移動

- 長押しで選択が起きるので、その `textView.selectedRange.location` をそのまま使う
  (既存の「選択して再生ボタン」= `CheckFolderAndStartSpeech()` と同じ経路)
- 長押し開始で一時停止タイマーをキックする必要がある(でないと選択位置が次の発話更新で上書きされる)。
  `UILongPressGestureRecognizer` を `cancelsTouchesInView = false` で足して `.began` でキックする。
- 発話を止めずに位置だけ移すのは、既存の「少し戻す」ボタン(`SpeechViewController.swift:1446`)と同じ型:
  `StopSpeech(realm:stopAudioSession: false)` → `setReadLocationWith` → `StartSpeech`。
  連打対策の `scheduleSpeechRestartAfterSeek()`(`StorySpeaker.swift:1334`, 0.3秒デバウンス)を経由させる。

### 駄目だった場合の代案

もし実アプリで長押しメニューがうまく制御できなければ、
**長押しした位置のすぐ近くに「ここから発話開始」のフローティングを出す**方式に切り替える。
トリガーが長押しなので誤爆しにくく、1ボタンなのでページ送りも起きない。
`SearchFloatingView` / `FloatingButton` が雛形になる。

### WebView 版

- タップ/長押し座標→文字位置は **既にある**。`WebSpeechViewTool_Inject.js:385` の
  `GetCurrentDisplayLocation(xRatio, yRatio)` が `document.caretRangeFromPoint()` →
  `SelectionRangeToIndex()` で index を返している。実運用中(`RedisplayWebView()` が
  バックグラウンド復帰時の表示位置復元に使用、`WebSpeechViewController.swift:227`)で、
  縦書き/2段組向けの ratio 調整も済んでいる。
- 比率でなく px を受ける版を1つ足すだけでよい:
  ```javascript
  function GetIndexFromPoint(x, y) {
      const range = document.caretRangeFromPoint(x, y);
      if (range) { const d = SelectionRangeToIndex(range); if (d && "startIndex" in d) return d.startIndex; }
      return undefined;
  }
  ```
- 長押しメニューは WebView 版も `UIMenuController` ベース(`WebSpeechViewController.swift:1775` 付近)
  なので同じ手が使える。

## 3. 画面下部ボタン群

- 右上とは**独立した設定**にする。既定は**全部 OFF**(= 表示されない)。
  今まで無かったものを押し付けない。「全部 OFF なら非表示」なので `表示しない` 専用の設定は不要。
- 実装はフローティング。本文画面の下部は既に `◀ [スライダ] ?/? ▶` の行が safeArea 下端にあり、
  iPhone ではさらにタブバーも出る(`hidesBottomBarWhenPushed` は未使用)ので、
  行を差し込むと本文が狭くなる。`SearchFloatingView` / `FloatingButton` が雛形。
  `FloatingButton.layoutBottom(parentView:bottomConstraintAppend:)` が縦オフセットを引数で取る。
- 表示位置は2択: **下部バーに重ねる / 下部バーの上に出す**。
  (将来オフセットのスライダに育てられるが、まずは2択)
- つまんで移動はやらない(実装コストが高く、移動先でも邪魔になるだけ)。

`SpeechViewButtonTypes`(`Realm/RealmModels.swift:2619`)に case を足す場合、
`ValidateAndFixSettingArray()` が新 type を自動で足すので移行処理は不要。
ただし `SpeechViewButtonTypes` は素の `Codable` なので、**新 type を含む設定が iCloud 経由で
古いバージョンに渡ると配列全体のデコードに失敗して既定値に戻る**。既存の作りの話だが、
新旧混在期間に起こり得る点は認識しておく。

## 4. 実装対象(確定版)

1. 手動スクロール検知で、強制スクロールと強制範囲選択を N 秒止める。スクロールのたびにリセット。
   一時停止中に章が変わったら一時停止を解除する
2. N は `RealmGlobalState`(0〜60秒、既定5秒、0で機能OFF)。バックアップ/復元/Realm間コピーの3箇所に追記
3. 「発話中 かつ 追従一時停止中」のときだけ、長押しメニューに「ここから発話開始」を**1項目だけ**出す
4. 画面下部ボタン群(右上と独立設定、既定全OFF、位置2択)
5. 1〜3 を WebView 版にも同じ形で

ハイライト色の変更なし。インジケータなし。トグルなし。フローティングの「戻る」ボタンなし。

## 5. 実機で確かめたいこと

1. 実アプリ(`CustomUITextView` + 既存の長押しメニュー削減設定)でも1項目だけになるか
2. 一時停止中に長押し → 選択 → メニュー という流れで、選択位置が保持されるか
3. `scrollRectToVisible(animated: true)` のアニメーション中にドラッグを始めた時、引き戻されないか
   → `willBeginDragging` で `setContentOffset(scrollView.contentOffset, animated: false)` で打ち切る
4. VoiceOver 使用時


---

# 実装時に判明したこと(2026-08-18 実装)

## 1. `UIMenuController.shared.menuItems` が長押し時には空になっている

`viewDidLoad` で `setCustomUIMenu()` を呼んで設定した `UIMenuController.shared.menuItems` が、
実際に長押しした時点では **空配列になっている**(iOS 18.1 の実機相当環境でログ確認)。
空だと独自項目が一切 `canPerformAction` に問い合わされず、メニュー自体が表示されない。

→ 長押しのたびに `setCustomUIMenu()` を呼び直すようにした(通常版・WebView版とも)。

⚠️ これは今回の機能に限った話ではなく、**現行OSでは「読み替え辞書へ登録」等の既存の独自項目も
出なくなっている可能性がある**(要確認)。`UIMenuController` が非推奨になった影響と思われる。
`editMenuForTextIn`(iOS16+)へ移行する際に併せて解消するのが筋。

## 2. 一時停止が切れるとメニューが引っ込む

`canPerformAction` が `isScrollFollowSuspended` を見ている以上、一時停止が切れた瞬間に
メニュー項目が消える。5秒だとメニューを読んで選ぶ前に消えるので、
長押し起点の一時停止だけは `speakFromHereSuspendSecondMinimum = 15` 秒を下限にした。
(手動スクロール起点の秒数設定とは別物)

## 3. Realm の schemaVersion を上げる必要があった

`RealmGlobalState` にメンバを追加しただけでもスキーマ変更なので、
`RealmUtil.currentSchemaVersion` を 18 → 19 に上げないと既存の Realm が開けず、
`CoreDataToRealmTool.IsNeedMigration()` の中で trap して**起動時にクラッシュする**。
(`deleteRealmIfMigrationNeeded = false` のため)

さらに、メンバを追加しただけだと既存 Realm では新メンバに Swift 側の初期値ではなく
**0 が入る**。`scrollFollowSuspendSecond` は 0 が「機能を使わない」の意味になってしまい、
既存ユーザだけ機能OFFで始まってしまうので、`Migrate_18_To_19` で明示的に既定値(5)を入れている。

## 4. 画面下部ボタン群は作り直しにガードが要る

`assignBottomButtons()` は `forceUpdateUpperButtons()` 経由で `viewDidLayoutSubviews` からも
呼ばれるため、毎回作り直すと「作り直す→レイアウトが走る→また呼ばれる」で無限に回る。
設定内容+再生状態から作った signature が同じなら何もしないようにしてある。

## 実装した内容

- 手動スクロール検知で強制スクロール/強制範囲選択を N 秒止める(通常版・WebView版)
- N は `RealmGlobalState.scrollFollowSuspendSecond`(0〜60秒、既定5秒、0で機能OFF)
  - バックアップ出力/復元(キーが無ければ現在値を放置)/Realm間コピーに追記済み
- 発話中かつ一時停止中のみ、長押しメニューに「ここから発話開始」を1項目だけ表示
- WebView版はハイライト(canvas)は止めず、`SetKeepUserSelection()` で selection の張り替えだけ止める
- 一時停止中にページが変わったら一時停止を取り消す
- 画面下部ボタン群(右上と独立設定、既定全OFF、表示位置は2択)

## まだ目視確認できていないもの

- 長押しメニューに「ここから発話開始」が1項目だけ描画される様子
  (`canPerformAction` が true を返すところまではログで確認済み)
- 画面下部ボタン群のバーそのものの見た目
  (設定画面の描画と、既定で全OFF=非表示になることは確認済み)
