# リリース時に使ういろんなメモ。

# アイコン

http://www.flaticon.com/

# アプリの名前

* 日本語
ことせかい: 小説家になろう読み上げアプリ

* 英語
NovelSpeaker: "Let's become a novelist" reading aloud application

# アプリの説明

小説家になろう で公開されている小説を読み上げるアプリです。
歩いている時や家事をしている時などに小説を "聞く" ことができます。
バックグラウンド再生に対応していますので、iPhone で他の作業をしながらでも小説を聞き続ける事ができます。

「ことせかい」という名前は、小説家になろうの小説を iPhone の読み上げさせてみたときに、
「異世界」を「ことせかい」と発音したことから来ています。
ということで、残念ながら現在アプリから使える読み上げ機能では異世界のような単語を間違えて読むことが案外多いです。
そのような場合を少しでも軽減させるために読み替えの機能もつけてありますが、あまり期待しないでください。(´・ω・`)

使い方：
「なろう検索」で小説家になろうのサイトから読みたい小説を検索して、右上のdownloadボタンでダウンロードを開始させます。
ダウンロード中のものも「本棚」に登録されますので、ダウンロードの終わったものを選択して、右上の「Speak」を選択することで読み上げを開始します。

読み上げ開始位置を指定したい場合は、一旦読み上げを停止させて、読み上げを開始させたい位置を長押しして選択状態にしてから「Speak」ボタンを押す事で指定できます。
読み上げ位置は小説ごとに保存されます。


設定項目について

読み上げ速度などの変更方法：
「設定」タブの「声質の設定」から通常時の読み上げ設定(声質と速度)、会話文の時の設定(声質のみ)が、
「読みの修正」から「異世界」を「ことせかい」と読み上げさせないための設定ができます。
ただ、「読みの修正」に大量に修正項目を設定すると読み上げ開始時に結構かなりいっぱい待たされるようになります。すみません。

表示文字の大きさ：
「設定」タブの「表示文字サイズの設定」から、小説本文の表示に使われる文字の大きさを指定できます。

読み上げ時の間の設定：
「設定」タブの「読上げ時の間の設定」から、句読点や三点リーダーなどといったものについて、読み上げ時に間を開ける設定が可能です。

再生の自動停止：
「設定」タブの「最大連続再生時間」の項目で、再生を開始した後に自動的に停止するまでの時間を設定できます。標準では23時間55分になっていますので、概ね停止せずに読み上げがなされるように見えるはずです。

注意：
バックグラウンドで再生を行っている場合、画面が消えていたとしてもバッテリーの消費が増えますのでご注意ください。

小説のダウンロードが失敗してしまった場合：
小説家になろうのサイトが高負荷になっていたり、Web認証の必要なWiFi接続を行っている時などに小説をダウンロードした場合、小説ではない文字列が読み込まれることがあります。その場合は、ホームボタン二度押しで出てくるマルチタスク画面にて ことせかい を終了させて、再度起動の後、本棚メニューの右上にある矢印が回転しているボタンを押して再読み込みをさせてください。しばらく待つと再読み込みが読み込みが終わり、その後であれば正しい小説が読み込めているはずです。

高度な使い方：
* URLスキームによる小説のダウンロード
URLスキーム novelspeaker://downloadncode/ncode-ncode-ncode... という形式で ncode を指定することで、対象の小説をダウンロードキューに追加する事ができます。ncode とは、小説家になろうでの個々の小説のIDで、小説のページのURL(例えば http://ncode.syosetu.com/n0537ci/)の最後の部分(この例の場合は n0537ci)です。URLスキームでは ncode-ncode-ncode... と、複数の ncode を - (ハイフン) を使って繋げて記述できます。パソコン等で読んでいる小説を ことせかい でも読もうと思った時にこのURLスキームをiPhoneに送信して開くことでダウンロードを楽にできるようになる…… かもしれません。(単にアプリ内で検索してもいいような気がしますが)
なお、「設定」タブの「再ダウンロード用URLの取得」を用いることで、本棚に登録されている小説についてのダウンロードリストを取得することができます。機種変更をする時などにご利用ください。

* 英語
NovelSpeaker is application to read the shown novel which is "Let's become a novelist" aloud.
"listen" hears a novel when I do walking time and housework.
Because I cope with background reproduction, I can continue hearing a novel even when carrying out other activities with iPhone.


# キーワード

* 日本語
小説家になろう, 読み上げ, 小説, なろう

* 英語
Let's become a novelist, novel, reading aloud

# サポートURL

http://limura.github.io/NovelSpeaker



# github pages で Autogenerate したら出てきたのでメモ

### Welcome to GitHub Pages.
This automatic page generator is the easiest way to create beautiful pages for all of your projects. Author your page content here using GitHub Flavored Markdown, select a template crafted by a designer, and publish. After your page is generated, you can check out the new branch:

```
$ cd your_repo_root/repo_name
$ git fetch origin
$ git checkout gh-pages
```

If you're using the GitHub for Mac, simply sync your repository and you'll see the new branch.

### Designer Templates
We've crafted some handsome templates for you to use. Go ahead and continue to layouts to browse through them. You can easily go back to edit your page before publishing. After publishing your page, you can revisit the page generator and switch to another theme. Your Page content will be preserved if it remained markdown format.

### Rather Drive Stick?
If you prefer to not use the automatic generator, push a branch named `gh-pages` to your repository to create a page manually. In addition to supporting regular HTML content, GitHub Pages support Jekyll, a simple, blog aware static site generator written by our own Tom Preston-Werner. Jekyll makes it easy to create site-wide headers and footers without having to copy them across every page. It also offers intelligent blog support and other advanced templating features.

### Authors and Contributors
You can @mention a GitHub username to generate a link to their profile. The resulting `<a>` element will link to the contributor's GitHub Profile. For example: In 2007, Chris Wanstrath (@defunkt), PJ Hyett (@pjhyett), and Tom Preston-Werner (@mojombo) founded GitHub.

### Support or Contact
Having trouble with Pages? Check out the documentation at http://help.github.com/pages or contact support@github.com and we’ll help you sort it out.




# Ver 1.0.2 リリースノート

インタフェースの変更
・小説を読んでいる画面で前と後の章への移動用にボタンをつけました。左右フリックでの移動はできなくなります。

問題の修正
・リロードした最新のものがダウンロードできなかった問題を修正
・バックグラウンド再生中に章を移動した時、再生が停止する可能性があった問題を修正
・小説の表示がステータスバーやナビゲーションバーにかぶって表示されて見えなくなることがある問題を修正
・読み替えの設定を増やすと再生開始や章の切り替わり時に長時間無反応になる問題を"ある程度"修正。(件数が増えれば遅くはなります)
・大量の小説をダウンロードした状態だと動作が遅くなっていた問題を修正

# Version 1.0.2 release note

Change of the interface

- I attached a button for the front and the movement to a later chapter with the screen which read a novel. By the right and left flick cannot move now.

Correction of the problem

- I revise the problem that the latest thing which I reloaded was not able to download.
- When I moved a chapter during background reproduction, I revise the problem that reproduction might stop.
- I revise the problem that the indication of the novel is fogged in a status bar and navigation bar, and it may not seem that it is displayed.
- I revise a reproduction start and the problem that I am replaced, and nothing sometimes reacts to for a long time of the chapter when I increase the setting of the reading substitute. (if the number increases, it becomes late)
- Movement revises the problem that became slow if in condition to have downloaded a large quantity of novels.

# Ver 1.1 リリースノート

インタフェースの変更
・本棚、なろう検索、ダウンロード状態 のアイコンを変更しました。
・小説の表示用の文字サイズを変更できるようにしました。「設定」に項目が増えます。
・iPadでも表示できるようにしました(ユニバーサルアプリとなります)。
・読み上げ中に最後の章を読みきった時に、「読み上げが最後に達しました」とアナウンスするようになります。
・起動時に最後に読んでいた小説を表示するようになります。
・最大連続再生時間の指定を設定ページに入れました。標準では23時間55分になっています。再生を開始してから、ここで設定された時間が経つと再生が停止します。
・読み上げ時に「……」や「、」「。」等でも読み上げの間をつけられるような設定項目を設定ページに追加しました。
・小説の詳細ページの作者名を押すと、その作者の小説を検索するようになります。
・小説を読むページにシェアボタンを追加しました。今読んでいるページへのURLやことせかいのアプリへのリンクなどをTwitterやmailでシェアすることができます。
・URLスキーム novelspeaker://downloadncode/ncode-ncode-ncode... という形式で、ncode を指定して小説をダウンロードさせる事ができるようになります。「設定」タブの「再ダウンロード用URLの取得」で本棚に登録されている小説についてのダウンロード用URLを取得できますので、機種変更等の際にご利用ください。

追伸：
レビューありがとうございます。不都合の報告や機能追加などの提案、本当にありがたいです。

読みの修正用の読み替え辞書をサーバにアップロードしてユーザ間で共有する事についてなのですが、サーバの管理が発生する(24時間365日起動し続けているサーバを管理するのはちょっと大変な)のと(無いとは思いますが)意図しない読み替え(例えば「あ」を「くぁｗせｄｒｆｔｇｙふじこ」に読み替えるとか)を行う読み替え辞書の登録がなされた場合の排除方法といった、複数ユーザによる登録にまつわる問題を考えるのが大変そうだなぁ、と思ったのでとりあえず良い案が浮かぶまでは実装はしないことにしました。

読み上げ時の間の設定については、標準の方法ですととても短い「間」の指定が(おそらく)できません。今回のリリースでは非推奨の方式を選択することができるようにすることでいろいろな文字に対しても「間」の設定ができるようにしています。ただ、非推奨の方式は Siriさん の読み上げ方式の穴を突いているような所がありまして、将来的には意図した通りには使えなくなる可能性がありそうです(具体的には指定された間の長さに応じた回数「_。」という文字列を読み上げさせています)。ですので、非推奨型での間の設定の使用はあまりおすすめしないことにしておきます。ご了承ください。

Interface change
- Icon changed.
- Text size change configuration is now on settings page.
- iPad mode. NovelSpeaker is universal application now.
- If reached at the end of a book then announce messsage: "Because it reached at the end of a book, I stopped reading aloud."
- First open view is now "Last read page".
- "Max continuation reproduction time" configuration is now on settings page.
- "Speak wait config" configuration is now on settings page.
- Can search same writer novel, in novel details page.
- Share button added for novel read page.
- Custom URL scheme is now available. It can download with NCODE. Use novelspeaker://downloadncode/ncode-ncode-ncode...
  "ncode" is "Let's become a novelist"'s novel-code. "ncode" can found "Let's become a novelist" web page ( http://syosetu.com ). example ncode found at last of url  like http://ncode.syosetu.com/n9669bk/ (this example include ncode "n9669bk")

# Version 1.1.1

# TODO

- アップデートをダウンロードすると読み上げ位置(栞)が吹き飛んで一番最初になってしまう問題のfix

# リリースノート
インタフェースの変更
・読み上げの間の設定に 0.1刻み で変化させるボタンを追加しました。また、簡単な文を使っての読み上げテストができるようになります。
・小説の詳細ページの右上に、作者のマイページをSafariで表示するためのボタンを追加しました。
・なろう検索のタブで、検索時の順位付けを「総合評価の高い順」などから選べるようにしました。ただ、「検索開始」ボタンが画面外に押し出されてちょっと使いづらくなっています。すみません。

問題の修正
・読み上げの間の設定を「非推奨型」にした場合に文末の単語を2回読み上げる事がある問題を修正
・読み上げ対象の文字列に "@" が含まれている章を選択すると落ちる問題を修正
・読み上げ開始時に読み上げが失敗すると、アプリを落とさないと読み上げができなくなる問題を一部修正(再度再生させようとした時に読み上げられない問題を解決しただけで、読み上げが勝手に停止する問題については直せていません。すみません)

追伸：
評価やレビュー、ありがとうございます。回避方法がなく落ちてしまう不都合の報告がありましたので、主に不都合対応のリリースをさせていただきます。
その他、提案していただいた機能で、簡単に追加できそうなものについては追加してみました。ご確認ください。

本棚周り、コピー＆ペーストでの新規本の登録、他サイトの小説の読み込み等は実装するのに結構時間がかかりますので今回のリリースには含めることができませんでした。すみません。なお、これらの対応については結構かなりいっぱいたくさん時間がかかってしまいそうですので、気長に待っていただければ嬉しいです。



# Version 1.1.1 release note
Interface update
- "Speak wait config" page inploved.
- "Go to writer page" button added at novel detail page.

Bug fix
- Duplicate word speech about "Experimental" speak setting is fixed.
- I revise a problem to come off when I choose the chapter which "@" is included in for character string for the reading aloud.
- Speech start fail bug fixed.

# レビュー用メモ

修正項目以下の通りです。

Change of the interface

- I attached a button for the front and the movement to a later chapter with the screen which read a novel. By the right and left flick cannot move now.

Correction of the problem

- I revise the problem that the latest thing which I reloaded was not able to download.
- When I moved a chapter during background reproduction, I revise the problem that reproduction might stop.
- I revise the problem that the indication of the novel is fogged in a status bar and navigation bar, and it may not seem that it is displayed.
- I revise a reproduction start and the problem that I am replaced, and nothing sometimes reacts to for a long time of the chapter when I increase the setting of the reading substitute. (if the number increases, it becomes late)


# Ver 1.1.2

インタフェースの変更

・なろう検索のタブで、検索時の順位付けの部分を、タップしてから選択するタイプに変更しました。
・設定タブに更新履歴の情報を追加しました。
・アプリの更新があった時に、一回だけダイアログを表示するようにしました。



# メモ

## ナビゲーションバー(上に出てくる「戻る」ボタンとかタイトルとかが表示される領域)に埋まる問題を解消するには、
インタフェースビルダの Adjust Scroll View Insets っていうチェックボックスを off にするといいっぽい。(理由理解してない)
http://qiita.com/yimajo/items/7c7372e284e13827c989

## iCloud で同期するには
CoreData を使う時の初期化に
NSPersistentStoreUbiquitousContentNameKey と NSPersistentStoreUbiquitousContentURLKey
というのを使うらしい？

Key-Value store とか Document Storage ってのでもできるっぽい。
http://blog.gentlesoft.net/article/56456255.html


http://d.hatena.ne.jp/glass-_-onion/20120728/1343471940
