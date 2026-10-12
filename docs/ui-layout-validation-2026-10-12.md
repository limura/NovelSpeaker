# 上部操作配置の検証と保留課題（2026-10-12）

## 今回の機能変更

本棚・Normal/Web本文の上部customViewを、同じwindow/navigationBar座標で実測した左右境界から配分する。右端の有限再試行とlate-valid回復、左境界の3回一致、所有leading groupの左anchorを採用する。ボタン配分の縮小結果を最大予算へ戻さない。

Duoの閉じたLandscape Rightでは生候補3件（戻る606,0,48,48、タブ608,150,44,58が2件）が一意性判定を妨げていた。完全探索後に同じボタン行が観測できた場合だけ別行controlを一意性判定から外し、同一世代で安定した右端より完全に右側のcontrolを`observedOutsideRight`として扱う。これは「戻るなし」と別状態。候補0件、不完全探索、未安定、境界との交差、曖昧な複数の同一行候補は従来予約へfallbackする。別行の戻るが単独で観測された場合の既存判定も維持する。

27.1 RC / Duo Closed Landscape Right / XL / 間隔8pt / 14ボタンで、右端590pt、非占有矩形606..654pt、利用幅574pt、fallback=falseをNormalとWebで確認した。以前は左予約88pt、利用幅502pt、fallback=trueだった。少ないボタンと多数ボタン、portrait/landscape/open/closed、戻る、アプリ所有ellipsisを代表検証した。全設定の直積検査ではない。

## ビルド・テストと差分範囲

- 作業ツリー（確認用ログあり）：関連57件、失敗0。Release simulator build成功。
- 一時DEBUGサンプラー・overlay・ボタン制限引数・NSBoundary console・NSUpperBoundary/v1 Releaseログ・その4テストを除いた独立ソース：関連53件、失敗0。署名付きDebug通常起動もSE2で確認。
- commit対象は機能変更、関連テスト、この課題文書。確認用診断は作業ツリーに未commitで保持。UpdateMemo、ReleaseMemo、SpeakerTest、既存未追跡メモは対象外。pushしない。

テストログ：`/Users/limura/Documents/Codex/2026-10-11/task/measured-boundary-change/duo-exclusion-tests.log`、`independent-commit-tests.log`、`duo-exclusion-release.log`。

## 代表実操作と既知R1/R2/R3

RC版Device Hubで対象名・画像・姿勢を再確認した。Duoはユーザー操作によりNormal/開閉姿勢が変わっていたため、以前のWeb条件と同一と扱っていない。遷移中に空canvas/横倒し画像が出たものや、ファイル名と実姿勢が一致しない初回画像は安定配置の証拠から除外する。

| 条件 | 結果と限界 |
|---|---|
| R1 iPad上部タブ縦・Web9操作 | 6枠（menu+5）を中央タブの右へ配置。ellipsisに4項目。詳細ボタンが小説詳細へ遷移し、設定タブへの誤遷移なし。戻る成功。今回画像`ipad-upper-P*`（`-toc`という試行名の実内容は詳細画面） |
| iPad上部タブ横 | 9操作、本棚5操作、短/長検索の省略表示、検索解除後の非空本棚の編集成功。今回`ipad-upper-L*` |
| iPad下部タブ横/縦 | 両方9操作と独立した戻るを維持。縦の本文空白は別課題。今回`ipad-lower-*` |
| R2 Duo開縦・14操作 | menu+11枠。Webのellipsisに他小説追加/事前生成/目次が表示。戻るは独立。本修正以前の左右実測版では目次選択・Cancelまで成功。本修正後はメニュー表示と開横/閉横の戻るを再確認 |
| Duo閉横の両方向 | 14操作。Landscape RightでNormal/Webとも非占有を安定採用。ページ送りと戻る成功。Landscape Leftの別行戻るも操作成功 |
| Duo少数操作 | 一時Debugの3操作が開縦で全表示。Releaseへ戻した通常14操作で再確認。起動引数は解除。少数/多数の純粋配分テストも成功 |
| SE2 Normal/Web | 一時診断を除いた独立commit候補を通常起動。元7操作の縦横表示、両方式の戻る成功。以前の左右実測版では追加3項目をONにした10操作・ellipsisの目次選択まで成功。今回は保存された元7操作が代表条件 |
| R3 iPad最大文字サイズで本棚がellipsisのみ | 左右実測版でAccessibilityXXXLの上部タブ、省略メニュー・戻るの実操作成功を記録済み（`measured-boundary-change/ipad-v2-huge-upper-*`）。アプリ所有ellipsisは幅に応じた省略であり、システム空ellipsisとは別。本修正後の最大文字GUIは再反復していない |

今回の画像・AX記録：`/Users/limura/Documents/Codex/2026-10-11/task/duo-exclusion-check/`。`duo-closed-LR-initial`は実際にはClosed Portrait、`duo-open-LR-web`と`duo-open-LR-settled`は実際にはOpen Portraitであり横成功に数えない。開横の有効画像は`duo-open-rotated-web`。保存境界JSONは`duo-boundary.json`。
以前のGUI証拠：`/Users/limura/Documents/Codex/2026-10-11/task/measured-boundary-change/REPORT.md`と`right-edge-change/RECOVERY-final-report.md`。修正前のR1/R2/R3記録は`repro-evidence/README.md`。

設定復元：iPad下部タブOFF・通常Portrait・検索解除・編集終了。SE2 WebViewHorizontal・回転追従OFF・Portrait。Duoは開始時に実観測したNormalへ戻し、通常起動引数なし。ボタン保存設定・データは保持。

## 6s Plus実機ログ

ユーザーが最新ログ入りIPAを操作し、見た目・操作の不具合なしと報告。IPA SHA256 `fd40f9120536d916a6359e6f335a13896a8797115c1b2340c2fd41efc01944a4`、iOS15.8.8。Libraryの指定ログをこのMacに取得・読み取り確認済み。原本255223bytes、SHA256 `b6f403324d5b6386d9c731476dec81df6284f017426bf1636a22bc4f2c56bc8b`、JSON全68件を解析。

原本：`/Users/limura/Documents/Codex/2026-10-11/task/library-6s-85Vn5F/テキスト-B92DE86FFD34-1.txt`。Library ID `libfile_ede5d20b4fc88191af2f5b9f775d9c60`。古い発話診断等も含むため原本全体はこの文書やcommitへ転載しない。

`NSUpperBoundary/v1`は45件（本棚28、Normal7、Web10）、09:37:07Z〜09:41:11Z。安定非fallback21件、fallback24件。後者のうち17件は右端安定待ちで、全24件を描画不具合とは解釈しない。

- iOS15の本棚customView変換で(x20,y7,height30)を12件安定採用。所有幅は114/139/180ptと検索で変化してもanchorは維持。右端はPortrait394pt、Landscape716pt。利用幅は374/696pt（本棚全体配分のpoolであり、右群の幅そのものではない）。public frame APIを持たない旧OS経路が実機で成立した。
- 本文の安定戻るは9件。Normal縦で66x44ptを1件、その後Normal/Web縦横で44x44ptを8件採用。後者の利用幅はPortrait338pt、Landscape660pt。有限値・同一座標で安定している。
- 初期Normal横09:37:11Zは候補0件・left exhausted=true、右端716pt安定、従来予約で幅616pt。次のPortrait09:37:26Zで採用。その後09:39:25ZのNormal横とWeb横はfallback=false。この初回の同一条件での自発回復時刻はログだけでは証明できない。
- 本棚のinactiveOrTransition exhausted=trueを3件観測。09:40:56Zから09:40:58Zは同じ横寸法でowned採用へ回復。右bootstrapExhaustedは0件。NaN/Infinityや負の利用幅はなし。
- 45件は起動100件上限未満。上限停止が今回の欠落原因だという証拠はない。ログは全画面共有の2秒間隔・重複抑制・最新状態置換であり、操作全イベントやレイアウト全フレームを網羅しない。安定ログがあり「待ちが全て不足」とは言えないが、全操作で2〜3秒待ったことも証明しない。

## 保留：iPad Web縦書き本文の空白

未修正。2026-10-12のユーザー指定により、上部配置とは独立した課題として後回しにする。

再現環境：iPad Pro11-inch M5 / iPadOS26.5 / Xcode27.1 RC Device Hub、Light、Text Size3（trait Large）、下部タブON、Web縦書き、アプリ文字サイズ84.60474、行間3.00、白い文字/暗灰色背景、既存の「はじめに」1/17ページ。

手順：設定で「タブの表示を画面下部にする」をON、再起動で適用。Landscape Leftで本文を起動し、Rotate LeftでPortrait Upside Downへ回す。期待は回転後も本文文字が見え、選択位置に追従すること。実際は暗灰色領域に緑の選択highlightだけが残り、上部操作・ページUI・下部タブは見える。静止後も空白、設定タブ往復でも空白。本棚へ戻って同じ本文を開き直すと復旧。

通常Portraitで起動→横→縦の1回では再現しなかった。開始方向に依存した観測であり、全縦回転が失敗するとは断定しない。最新Releaseと、今回の左境界接続前の既存isolated Debugビルドの両方で同じ空白を実ピクセル確認。比較版は右復旧等も異なりDebug/Release差もあるため厳密な一変数比較ではない。少なくとも新しい左実測の導入以前から存在する。原因は未確定、DOM/CSS実状態やWebKit描画完了を新規計測していない。

証拠：`/Users/limura/Documents/Codex/2026-10-11/task/ipad-blank-regression-check/`内の`current-L-start-upside-P-blank-static.jpg`、`current-blank-tab-return.jpg`、`current-back-reopen.jpg`、`baseline-L-start-upside-P.jpg`、`builds.json`、`current-L-start-stdout.log`、`baseline-stdout.log`。旧観測は`left-boundary-evidence/LEFT-BOUNDARY-report.md`と`back-region-evidence/FRESH-BACKTREE-report.md`。再現後は最新Release・上部タブ・通常Portraitへ戻し本文表示を確認済み。

Library保存済み画像`ipad-lower-P-web.jpg`：`libfile_5bbbeda7506081918b727d664b4916db`。これは以前の確認用Debugで撮影した実画像。最新比較の画像ではない。

## 次の課題と優先順位

1. 次にNormal本文のページ選択スライダー下の余白を調査。DuoおよびiPad上部タブでユーザー報告あり。画像・view/frame/safe area/insets/constraintsを計測してから方針を報告し、実装は今回へ混ぜない。
2. Duo本文fullscreen時のタブ非表示と上下余白は後続課題。今回開始していない。
3. UIKit所有の空ellipsisは未再現。customView幅の適正化で避けられるという見立てと、実際に解消を確認したという主張は区別する。未解消確認のまま。
4. iPad Web本文空白は上記の通り保留・未修正。
5. 本文文字サイズと縦位置は上部操作配置の主目的外として保留。
6. iOS16実行環境での確認、全端末・全Dynamic Type・全設定の直積検査は未実施。経験的なcontrol形状guardが未知のUIKit形状を取得できなければ保守的fallbackを維持する。
