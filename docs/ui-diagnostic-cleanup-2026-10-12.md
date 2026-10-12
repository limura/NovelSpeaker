# UI調査コードの除去と8pt全画面のコミット準備

今回の上部配置調査で追加した診断は、実際の幅測定・復旧処理と分離されていた。診断だけを削除しても製品動作に必要な処理は残る。

除去したもの:

- NSIPadUpperProbeの有限サンプラー、画面階層/hitTest/矩形の採取、診断用安定判定ゲート。
- SafeArea/layoutMarginsの可視化overlayと切替API、診断用タイトル/文字サイズ/ボタン数の起動引数。
- 本棚の配分説明用キャッシュ、readerの診断呼出し、NSBoundary出力。
- AppInformationLoggerへNSUpperBoundary/v1を記録する専用関数、BoundaryLogLimiterと画面種別。
- UpperProbeOverlayTest、BoundaryLogLimiterTestの診断専用テスト。

残したもの:

- 汎用AppInformationLoggerと従来からのDEBUG処理、過去のログデータ。
- LeadingProbe/RightEdgeProbeの実動作測定、候補探索、同一geometryでの安定確認、遷移/欠測時の再測定・復旧。
- 幅予算、上部タブ候補、Duoで画面外の戻る候補を非占有扱いにする処理、アイコンfallback。
- 上部配置の回帰53件、Web全画面8pt/解除/HTML余白復元/章再読込/可視アンカー処理。

一時診断は未コミットの追加だったので、除去後のUtility/本棚/Normal reader/幅予算/SpeakerTestはHEADと同一になった。SpeakerTestの追加差分はoverlay専用classだけと確認してその部分を除去し、従来のテストを変更していない。UpdateMemoと無関係な未追跡ファイルは保全した。既存indexも変更前に保存し、対象パスだけをstageする。

Web全画面の新規回帰3件は実際のWKWebViewを利用する。margin8→0→次章再読込後0→解除8、および縦/横書きで途中の同じ文字をviewport変更後に復元できることを確認する。テスト用WebViewも実際の全画面と同じinset=.never/0を使い、WebContentプロセスへのスクロール反映を待つ。読込直後のcontentSizeによる移動は不確定だったため、既存本文スクロールAPIで途中位置を準備する。

再調査が必要なら、製品の測定・復旧処理を入口とし、専用worktree/作業ツリーで一時的な読取計測を追加する。今回の元ソース、画像、geometry JSON、ビルド/テストログはローカルのui-diagnostic-cleanupとweb-fullscreen-8ptに保存した。削除したoverlay/ログに製品処理を依存させる必要はない。

検証の結果・手動範囲はコミット前の最終報告と、web-reader-fullscreen-8pt-2026-10-12.md末尾に記録する。過去のDuo全画面調査、Normal下部余白調査の文書は削除していない。


## 診断除去後の最終確認

調査専用コードを除去した最終ソースで通常Debugビルド成功。上部幅・復旧・候補・アイコンの関連53件、新規WKWebView全画面回帰3件がすべて成功（合計56件、失敗0）。新規テストは実WebViewでmarginの解除/章再読込と縦横の同一文字アンカー復元を確認する。

Device HubでDuo4姿勢の全画面・通常復帰、SE2横書きとiPad縦書きの通常/全画面/解除を実ピクセル確認。清掃後のDuoはユーザーが現在選んだ横書きと編集済み本文を使い、その設定/本文は変更していない。Normal readerの製品コードはHEADとバイト一致を確認した。今回の手動確認はWeb readerが対象で、Native Normalの全姿勢の追加操作確認、全ボタン押下、旧OS/実機、全ルビ/段組は未確認。iPad白紙問題の修正は対象外。

数値測定は前段の診断版の記録であり、清掃後に診断を再導入して採取したものではない。清掃後の画像・AX・ビルド/テストログは `/Users/limura/Documents/Codex/2026-10-11/task/ui-diagnostic-cleanup` に保存。既存のログデータ、調査文書、シミュレータデータは削除していない。UpdateMemoと無関係な未追跡ファイルをコミットへ含めない。
