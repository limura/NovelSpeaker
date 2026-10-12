# Web読書画面・画面端8ptの全画面版（2026-10-12）

## 試せる状態

作業ツリーに通常操作で使える8pt版を実装した。計測専用コードは除去し、起動引数なしのDebugアプリをDuo/SE2/iPadへ導入済み。コミット・プッシュ・実機更新は行っていない。HEADは16c4d09eのまま。

Xcode 27.1 RCで `/Users/limura/Documents/git/Codex_Work/NovelSpeaker/novelspeaker.xcworkspace` を開き、scheme `NovelSpeaker`、実行先 `iPhone Duo (iOS 27.1)` を選んで Run。`.xcodeproj`単体やbetaを選ばない。Schemeに以前の調査用 `-NSDuo…` 引数が残っていれば外す。今回の機能には特別な起動引数は不要。

Duoは設定のDebug欄「小説本文画面の表示方式」が `WebViewVertical` に戻っている。`WebViewHorizontal`でも利用可能。iPhoneで回転を試す場合は設定の「画面の回転に追従する」をONにする（Duoは既存のONを維持、SE2のOFFは変更していない）。本棚で本文を開き、本文右下付近の青い下向き矢印入りの枠アイコン（アクセシビリティ名「全画面表示」）を押す。全画面では上向きアイコン／「ボタン表示」になり、同じボタンで解除する。

DuoはTest Novel 1-17の1ページ目・縦書き・閉じた右向き横・全画面で試せる状態。SE2/iPadは元の1ページ目の通常表示へ戻した。文字サイズやテーマは変更していない。Duoの一時的な横書き設定も縦書きへ復元済み。

## 実装と対象範囲

変更ファイルは `WebSpeechViewController.swift`、`WebSpeechViewTool.swift`、`Resources/WebSpeechViewTool_Inject.js` の3ファイル。

- 全画面ではWebViewの上下左右をroot viewの8pt内側へ固定する。safeArea外も利用するが、本文を物理windowの4辺から最低8pt離す。root view/windowの一致はDuo4状態、SE2、iPadで実測した。
- WebView側で8ptを持つため、アプリが生成した `body.NovelSpeakerBody` のmargin/paddingだけを全画面時0にする。通常のbody margin8pxを二重に加算しない。外部サイトのCSSには適用しない。新しい章の生成HTMLにも現在の全画面状態を反映する。
- readerの `prefersStatusBarHidden` と更新要求で時計/Wi-Fiを隠す。既存のtab→selected navigation→readerへの委譲を利用し、nav/tab controllerの追加overrideは導入しなかった。
- iOS18以降は `setTabBarHidden(_:animated:)` でactive tabを隠す。iOS15〜17は従来の `tabBar.isHidden` を使用。最低OSはiOS15のまま。iOS15〜17での実行検証は行っていない。
- `prefersHomeIndicatorAutoHidden` と更新要求を利用。OSへの自動非表示の希望であり、常時消える保証やジェスチャー無効化ではない。画面キャプチャにバーが残る場合がある。下safe34を削除する実装ではない。
- 解除では元の制約、scroll inset/adjustment、元のtab表示状態を復元し、所有する全画面CSSを取り除く。通常の上部配置と下部操作列の制約は保持した。
- 全画面のサイズ変更、および全画面の出入りでは、生成本文の可視文字アンカーを一時保存し、DOM再配置後の同じ文字の矩形差分をnative scrollViewへ適用する。縦書きは横軸、横書きは縦軸だけ調整。保存済み発話位置・本文・selectionとは別の状態で、章が変わった場合には復元しない。

Normal readerの `SpeechViewController.swift` は今回変更していない。既存の上部配置診断等を含む他9ファイルのSHA256が調査開始前と一致した（preserved-existing-hashes.json）。UpdateMemo/SpeakerTest/UpperButtonBarBudget等の既存変更は保全した。私有APIや私有クラス名による分岐はない。

## 測定値

矩形は `(x,y,width,height)`、単位pt。DOM viewportもWebViewのwidth/heightと一致。全画面のnative scrollContentInset/adjustedContentInsetは0、HTML body margin/paddingも0。通常表示は元のbody margin8pxへ戻る。

| 条件 | window | 通常WebView | 8pt全画面WebView／viewport | 解除後 |
|---|---|---|---|---|
| Duo開いた縦 | 669×951 | (8,90,653,726) | (8,8,653,935)／653×935 | 通常制約へ復元 |
| Duo開いた横 | 951×669 | (8,90,851,493) | (8,8,935,653)／935×653 | 通常値へ復元を実測 |
| Duo閉じた縦 | 466×678 | (8,90,366,502) | (8,8,450,662)／450×662 | 通常値へ復元を実測 |
| Duo閉じた横 | 678×466 | (8,90,578,290) | (8,8,662,450)／662×450 | 通常値へ復元を実測 |
| SE2縦・iOS26.5 | 375×667 | (8,82,359,452) | (8,8,359,651)／359×651 | (8,82,359,452) |
| iPad縦・iPadOS26.5 | 834×1210 | (8,148,818,992) | (8,8,818,1194)／818×1194 | (8,148,818,992) |

Duoの開いた縦は最終的に上下反転portraitも確認している。閉じたportraitの上下反転はアプリが対応しないため、deviceの物理向きとinterfaceOrientationが一時的に一致しない。主表はinterfaceOrientationが通常portrait/landscapeへ落ち着いた記録を使用。

角丸/カメラ穴は物理マスクとして残り、ユーザーの許容範囲に従って本文をその背後まで描画する。8ptのWebView境界を超える途中の文字矩形はscrollView内でクリップされる。DOMのRange矩形は字面の実ピクセルとは異なり、部分表示の矩形がviewport外へ続く場合がある。

## 画像下部の隙間の切り分け

以前の代表画像 `combined-open-L-full.jpg` はviewport/bodyとも951×669、margin/padding0、scrollContentInset/adjustedInset0だった。body rectは(-5075.421875,0,6026.421875,669)。同じ本文4542 UTF-16文字、同じfont-size17.942528px/line-height27.024313px、同じviewportで一時診断iframeを作り、文字Rangeの下端を測定した。元画像と同じbody rectを再現し、文字下端は611.5625px、残り57.4375pxだった。

縦書きのLatin単語は横倒しで単語単位に折り返される。次の単語が残りの領域に収まらないため下部に空きが残る。viewport高さを669→653へ16px縮めても文字下端611.5625は変わらず、空きは41.4375pxになる。一方、同じ653px高さの日本語4500文字では文字下端645.53125px、空き7.46875pxとなった。column-count/widthはauto、padding/margin0で、固定列幅やsafeAreaの追加余白ではない。

8pt版のDuo縦書き長文の例:

| 条件 | viewport高さ | 非空白文字Rangeの最大下端 | viewport内の残り | 画面端までの残り（8ptを加算） |
|---|---:|---:|---:|---:|
| 開いた縦 | 935 | 919.875 | 15.125 | 23.125 |
| 開いた横 | 653 | 611.5625 | 41.4375 | 49.4375 |
| 閉じた縦 | 662 | 611.5625 | 50.4375 | 58.4375 |
| 閉じた横 | 450 | 442.890625 | 7.109375 | 15.109375 |

これは最低8ptより大きい空きが自然に残ることを示す。文字や行間を伸ばして下端まで埋める変更は行っていない。

横書き長文では閉じた横viewport450pxに対し、見える文字Rangeの下端428.875px、残り21.125pxだった。次の行/空行/段落の配置により空きが変わる。途中スクロールでは上下端の行がクリップされ、Rangeがviewport外へ続くこともあるため、それを負のCSS余白と扱わない。

実際のTest Novelの2ページ目は短文 `dummy 2`。縦書きでは文字下端72.046875px、横書きでは23.5pxで、残りは本文終了後の領域。章送り後も8ptフレームとbody margin0を確認した。synthetic短文7文字の縦書き下端123px、横書き下端23.5pxも別に測定した。短文の末尾空白を、長文の折り返し残りやCSS paddingと混同しない。

診断iframeのscroll200はsmooth scroll直後でscroll値0のままだったため、途中位置の成功根拠には使っていない。途中スクロールの評価は実際のWKWebView.scrollViewを公開APIで200pt動かした記録だけを使用。Device Hubのdrag/wheelで実タッチのスクロール成功は確認できなかった。設定一覧は公開AXのScroll Down操作で移動できた。

## 可視位置とアンカー

追加処理前: 閉じた横のnative offset5986→5786に200pt動かすと最初に完全に見える文字は226。portraitへ回転するとoffset5376・最初の文字267となった。以前の「右端中央の文字が変わった」所見とは区別し、今回は実際に最初の可視文字とその矩形を計測した。この結果を根拠に一時可視アンカーの保存/復元を追加した。

追加後のDuo途中位置: 開いた横offset4891で最初の完全可視文字267、折り畳みportraitでoffset5376・同267、そこから閉じた横へ回転してoffset5750.6667・同267を確認。viewport変更に対してoffset自体は変わる。全画面解除後は行長の変化により、その文字より前の文字が同じ列内に入る場合があり、最初の完全可視文字は138になった。サンプル文字やoffsetの数値だけでアンカー喪失と断定しない。

SE2横書きでは全画面offset200、可視アンカーindex92、yRatio約0.029186。解除後はoffset214、最初の可視アンカーindex91（折り返しにより1文字前も同じ行に入る）、yRatio約0.028761で、近い画面内位置を維持。iPad縦書きは途中のアンカーindex13が全画面/解除で共通、offset10022→12278、xRatio約0.8594→0.8496だった。

保存readLocationとselectionは既存発話位置（今回のchapter1では0/{0,1}）に対応し、手動スクロールの可視アンカーとは別。中央の文字、最初の完全可視文字、保存発話位置、復元対象indexを区別する。ここで確認した本文/フォント/姿勢での回帰を超えて、あらゆるルビ/巨大文字/2段組/外部サイトで厳密なピクセル位置保持を保証するものではない。アンカーが取得できない外部サイト等は従来の可視位置取得方式を使う。

## 検証・証拠

最終ソースで通常scheme `NovelSpeaker` のDebugビルド成功。`NovelSpeakerTests/UpperButtonBarBudgetTest`をDuoで直列実行し20件・失敗0。`git diff --check`成功。初回の診断除去で残った参照を除去し、その後の最終ビルド/テストが成功している。

数値は一時的な読取診断版で測定し、診断を除去した同じ機能の最終版で引数なしの操作・実ピクセルを再確認した。最終画像:

- final-duo-open-P-full.jpg / final-duo-open-L-full.jpg
- final-duo-closed-P-full.jpg / final-duo-closed-L-full.jpg
- final-duo-closed-L-normal.jpg / final-duo-ready-to-try.jpg
- final-se2-normal.jpg / final-se2-full.jpg
- final-ipad-normal.jpg / final-ipad-full.jpg

証拠ディレクトリ: `/Users/limura/Documents/Codex/2026-10-11/task/web-fullscreen-8pt`。各画像とAXテキスト、各条件のgeometry.json、all-measurements.json、fixtures.json、3ファイルのimplementation.patch、preserved-existing-hashes.json、build-final.log、test-upper-layout-final.logを保存した。初期helperのログ閉包で誤対応したoffset200/portraitのJSONはrawログから訂正済み。疑わしい瞬間の記録を現在状態の根拠には使用しない。

今回のiPadでは通常/全画面とも本文を表示できたが、以前のWeb白紙問題の修正や原因調査は行っていない。iOS15〜17と実機は未検証。SE2/iPadの設定は変更せず、Duoの表示方式は元のWebViewVerticalへ戻した。


## 診断除去後の最終確認

調査専用コードを除去した最終ソースで通常Debugビルド成功。上部幅・復旧・候補・アイコンの関連53件、新規WKWebView全画面回帰3件がすべて成功（合計56件、失敗0）。新規テストは実WebViewでmarginの解除/章再読込と縦横の同一文字アンカー復元を確認する。

Device HubでDuo4姿勢の全画面・通常復帰、SE2横書きとiPad縦書きの通常/全画面/解除を実ピクセル確認。清掃後のDuoはユーザーが現在選んだ横書きと編集済み本文を使い、その設定/本文は変更していない。Normal readerの製品コードはHEADとバイト一致を確認した。今回の手動確認はWeb readerが対象で、Native Normalの全姿勢の追加操作確認、全ボタン押下、旧OS/実機、全ルビ/段組は未確認。iPad白紙問題の修正は対象外。

数値測定は前段の診断版の記録であり、清掃後に診断を再導入して採取したものではない。清掃後の画像・AX・ビルド/テストログは `/Users/limura/Documents/Codex/2026-10-11/task/ui-diagnostic-cleanup` に保存。既存のログデータ、調査文書、シミュレータデータは削除していない。UpdateMemoと無関係な未追跡ファイルをコミットへ含めない。
