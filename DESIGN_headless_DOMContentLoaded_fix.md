# 実装メモ: headless取得のハング修正(erik.load の load待ち → DOMContentLoaded待ち)

対象コミット: 「headless取得: load イベント(didFinish)待ちをやめ DOMContentLoaded で進める(なろう長編のハング修正)」

このメモは **別リポジトリ(Realm+IceCream → CoreData 移行版)へ移植する際に、cherry-pick が綺麗に当たらなくても確実に再適用できるよう** 残すもの。
変更の「意図」と「最小の差分」を、周辺コード(特に Realm 周り)が書き換わっていても再現できる形で書く。

---

## 1. 何が問題だったか(調査結果・実測ベース)

- 小説家になろう(`ncode.syosetu.com` / `novel18.syosetu.com`)は SiteInfo で `isNeedHeadless=TRUE`。
  理由は「素のHTTPだと bot 扱いの User-Agent で **403**」を回避するため(headless の WKWebView は本物の Safari UA を送るので 200)。
- ところが **特定ページ(特に長編 例: くまクマ熊ベアー n4185ci)で headless 取得が間欠的にハング**し、
  最終的に `ErikError.noContent`(「何も読み込めませんでした」)で失敗する。短編は通るが長編は「途中で止まる/ローディングのまま」。
- 実測(Mac Catalyst CLI `--dump-rendered-html` / `--scrape-inspect-url` で再現):
  - 同じURLが **成功(~1.7秒)/ 失敗(タイムアウトまでハング)の二極化**。コールド時に失敗が偏る。フレーク。
  - タイムアウトを 10→120 秒に伸ばしても **失敗は「遅れて成功」にならず 120 秒丸ごとハング**(=遅いのではなく完了シグナルが来ない)。
  - 独立ポーリングで観測すると、ハング中でも **本文DOM は ~1.4 秒で完全に揃っている**(`document.readyState='interactive'`, 本文要素あり)。
    なのに `readyState` が **"complete" に永遠に到達しない**(=メイン文書内の広告/トラッカー等サブリソースが終わらず `load` イベントが発火しない)。

### 根本原因
- Erik(vendored Pod `Pods/Erik/Sources/LayoutEngine.swift`)の `WebKitLayoutEngine` は、ページ読み込み完了を
  **WKWebView の `didFinish`(= `load` イベント)** で判定する(`pageLoadedPolicy = .navigationDelegate`、`navigate` フラグ)。
- 完了待ちは `handleLoadRequestCompletion` の `while(navigate){...}` **ビジーウェイト**。
  iOS/Catalyst は `#if os(OSX)` の RunLoop を通らないので **タイトループ(1コア張り付き)** で `navigate` を監視する。
- `load` イベントが来ない(=広告サブリソースが終わらない)ページでは `navigate` が下りず、`pageLoadTimeout` まで
  スピンし続けた末に空(noContent)を返す。**本文は揃っているのに `load` を待って詰む**のが本質。
- User-Agent は無関係(403 は別問題。headless 経路では Safari UA なので 200 が返っている)。

---

## 2. 修正の考え方(これが移植時の本質)

**headless 取得の初回ロードを「`erik.load`(= `load`/`didFinish` 待ち=ビジーウェイト)」から
「`webView.load` 直接 + `DOMContentLoaded`(`readyState != 'loading'`)到達待ち」に置き換える。**

- 本文は DOMContentLoaded で揃うので、`load` イベント(全サブリソース完了)を待つ必要が無い。
- **`webView.load` を直接呼ぶと Erik の `navigate` フラグは立たない**ため、後段の `GetCurrentContent`
  (`erik.currentContent` も同じビジーウェイトを持つ)も **待たずに即返る**。つまり Erik のビジーウェイト経路を一切通らなくなる。
  → ハング解消 + CPU 張り付き解消。
- 本文出現の「本待ち」(SPA/JS描画やボタンクリック)は **既存の `headlessWaitThenContent`(smart-wait=MutationObserver+postMessage / forceClick dismiss / 固定待ち)をそのまま使う**。
  DOMContentLoaded はあくまで「watcher を仕掛けてよい安定した文書がコミットされた」ことの門番。
- **アプリ側のみ・SiteInfo シート変更なし=完全後方互換**(旧アプリは従来どおり headless で動く)。

---

## 3. 具体的な差分(移植時に再現するもの)

### (A) `NovelSpeaker/HeadlessHTTPClient.swift` に新メソッド追加
`HeadlessHttpClient` に `LoadUntilDOMContentLoaded(...)` を追加(`GetCurrentContent` の直前に置いた)。要点:

- `generateUrlRequest(...)`(既存・Cookie/UA は webView.customUserAgent 側で適用済み)で `URLRequest` を作る。
- `self.webView.load(request)` で **直接ロード**(`erik.load` は使わない)。
- `document.readyState` を **0.15秒間隔で非同期ポーリング**(ビジーウェイトではない)。
  `readyState in ('interactive','complete')` **かつ** `webView.url != "about:blank"`(コミット済み確認。about:blank も complete を返すため)になったら `completion(nil)`。
- 保険のハード上限 `timeoutInterval + 2.5`(従来 `pageLoadTimeout` と同値=待ち上限は悪化させない)。超過で
  `noContent` 相当の NSError を返す。
  - 既知の割り切り: ネットワーク失敗時、従来は `didFailProvisional` で早く失敗していたが、本経路は独自 delegate を
    持たないためこの上限まで待つ。早く失敗させたい場合は custom `WKNavigationDelegate`(`Navigable` 準拠で Erik に拾わせる)が要る=別課題。
- 同一ページ内アンカー(`#` のみ変更)は WKWebView がナビを起こさない事があるため、既存 `HttpRequest` と同様に
  `about:blank` を一旦挟む処理を踏襲。

> Realm 非依存。この変更はそのまま移植できる。

### (B) `NovelSpeaker/NiftyUtility.swift` の `httpHeadlessRequest` の差し替え
初回ロードを `client.HttpRequest(...)`(erik.load)から `client.LoadUntilDOMContentLoaded(...)` に変更。
- 旧 `successResultHandler:{ doc in ... }` の `doc` は元々未使用(待ち後に `GetCurrentContent` で取り直していた)。
- 新クロージャ `{ err in if err!=nil { failedAction } else { injectJavaScript→waitProcess } }`。
  `waitProcess()` の中身(`headlessWaitThenContent` 呼び出し)と `injectJavaScript`(scrollTo)処理は **そのまま**。

> ★Realm 接点はこの関数の冒頭にある `allowsCellularAccess` 算出のみ:
> ```
> let allowsCellularAccess = RealmUtil.RealmBlock { ... RealmGlobalState.GetInstanceWith(realm:)?.IsDisallowsCellularAccess ... }
> ```
> ここは **今回の修正では一切触っていない**(値を `LoadUntilDOMContentLoaded` にそのまま渡すだけ)。
> CoreData 移行版では、この `allowsCellularAccess` の取得が CoreData 版に書き換わっているはずなので、
> **その移行版の取得方法をそのまま使い、得た `allowsCellularAccess` を `LoadUntilDOMContentLoaded(... allowsCellularAccess: ...)` に渡す**だけでよい。
> （= 衝突するのはこの1行周辺だけ。修正の本体(A)(B)は Realm と無関係。）

### (C) 診断CLIの追加(任意・便利機能)
`NovelSpeaker/AppLaunchCoordinator.swift` の `--dump-rendered-html` に `--timeout <秒>`(Erik ロード待ちの上限)を追加し、
`NOVELSPEAKER_DUMP_TIMING`(ナビ開始→完了/失敗の実時間)を stderr に出す。移植は任意(無くても本修正は成立)。

---

## 4. 検証方法(移植先でも同じ手順で確認できる)

Mac Catalyst でビルド:
```
xcodebuild -workspace novelspeaker.xcworkspace -scheme NovelSpeaker \
  -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
本番パイプライン(StoryFetcher→fetchUrl→httpHeadlessRequest→新ロード)で、コールド間隔を空けて連続実行し、
**ハング(数十秒のタイムアウト)が出ず本文が取れる**ことを確認:
```
BIN=.../Debug-maccatalyst/NovelSpeaker.app/Contents/MacOS/NovelSpeaker
"$BIN" --scrape-inspect-url https://ncode.syosetu.com/n4185ci/1/   # content/title 等が非空で返ればOK
```
修正前は同URLが間欠的に ~42秒等でハング→ noContent。修正後は ~数秒で安定して content 取得(本リポジトリで実測)。

参考(headless 単体・SiteInfo非依存・タイムアウト可変で挙動を見る):
```
"$BIN" --dump-rendered-html https://ncode.syosetu.com/n4185ci/1/ --timeout 40
```

---

## 5. やっていないこと / 別課題(混同しないため)

- **syosetu の 403 自体**(素のHTTPの User-Agent が bot 扱い)は本修正では直していない。
  headless が ON のままなので 403 には当たらない。将来 headless を外したいなら、別途
  「httpRequest にブラウザ風 UA を付ける」修正が必要(後方互換のため SiteInfo シートで isNeedHeadless を OFF にするのは
  旧アプリを 403 で壊すので不可)。
- Erik 本体(Pods)のビジーウェイトは温存(vendored を patch せず、通らない実装にした)。
- 「1話目が最新話に書き換わる」というユーザ報告は **データ格納側の別バグ**の可能性が高く、本件とは切り分けて別途調査。
