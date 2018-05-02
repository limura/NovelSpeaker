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

* 自作小説の登録
設定タブの下の方の「新規自作小説の追加」を選択することで、自分で書いた文章を小説としてことせかいに登録することができます。
ここで作成した自作小説を再度編集したい場合、自作小説を表示している時に編集ボタン(小説家になろうの小説の場合は「詳細」ボタンがあった位置にあります)を押すことで再度編集できます。
なお、この自作小説の登録機能は、ちょっと汚い形で組み込んでしまっているので、今後のアップデートでもう少し違った形(EPUB形式での取り込みとか)での実装に変更するかもしれません。その場合はもしかすると自作小説自体を新形式に移行出来ない可能性があります(できるだけ残そうと努力はするつもりですけれども)。もしそうなってしまった場合はご容赦お願いしつつ、自作小説は別途バックアップを取っておいていただきますようお願い致します。

小説のダウンロードが失敗してしまった場合：
小説家になろうのサイトが高負荷になっていたり、Web認証の必要なWiFi接続を行っている時などに小説をダウンロードした場合、小説ではない文字列が読み込まれることがあります。その場合は、ホームボタン二度押しで出てくるマルチタスク画面にて ことせかい を終了させて、再度起動の後、本棚メニューの右上にある矢印が回転しているボタンを押して再読み込みをさせてください。しばらく待つと再読み込みが読み込みが終わり、その後であれば正しい小説が読み込めているはずです。

起動時に落ちてしまう場合：
アップデート後、起動時に落ちてしまう場合には、誠に申し訳ありませんが一旦アプリを削除してから、もう一度インストールすることで起動するようになります。ただ、アンインストールしてしまうとダウンロードした小説や読み替え辞書などの情報が全て消えてしまいます。すみません。


「小説家になろう」は株式会社ヒナプロジェクト様の登録商標です。
本アプリは株式会社ヒナプロジェクト様が提供するものではありません。

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

・なろう検索のタブで、検索時の順位付けの部分を、タップしてから選択するタイプに変更しました。(検索開始ボタンがスクロールしないと見えない状態だったのを解消しました)
・設定タブに更新履歴の情報を追加しました。
・アプリの更新があった時に、一回だけダイアログを表示するようにしました。

追伸：
評価やレビュー、ありがとうございます。今回はほとんど更新はありません。
やはり、検索タブの所の PickerView(検索の順位付けのくるくる回るUI)が入ってしまって「検索開始」ボタンが見えなくなってしまっていて、スクロールしないと駄目になっていたのが原因(?)で検索出来ない人がおられるようでしたので、ちょっとUIを変えました。
あと、ことせかいをアップデートしたのが気づいてもらえないかもしれないなぁ、と思って、バージョン番号が変わった時には一回だけダイアログを出すようにしました。ということで、ちょっとウザくなってしまいます。すみません。

# Version 1.1.2

Interface change

- in Search tab, "Search order" is now show after tap.
- Add "Update log" in Settings tab.
- Update Notice dialog added. This is displayed first time only.


# Ver 1.1.3

問題の修正

・なろう検索のタブで、検索用文字列を入力できなくなっていた問題を修正しました。

追伸：
評価やレビュー、ありがとうございます。今回は検索が無意味になってしまうようなバグを入れたままリリースしてしまって申し訳ありませんでした。
焦って提出して安心したままじゃ駄目ですね…… 本当にすみませんでした。

# Version 1.1.3

Bug fix

- in Search tab, Search string is now can editable.


# Ver 1.1.4

インタフェースの変更

・文章上で長押しした時に出るメニューに、「読み替え辞書へ登録」を追加しました。コピーしてペーストする手間が少しだけ減ります。
・設定タブの下の方に「新規自作小説の追加」が増えます。自分で書いた文章を読み上げさせる時などにご利用ください。
作成した自作小説を再度編集したい場合、自作小説を表示している時に編集ボタン(小説家になろうの小説の場合は「詳細」ボタンがあった位置にあります)を押すことで再度編集できます。
なお、この自作小説の登録機能は、ちょっと汚い形で組み込んでしまったので、今後のアップデートでもう少し違った形での実装に変更するかもしれません。その場合はもしかすると自作小説自体を新形式に移行出来ない可能性があります(できるだけ残そうと努力はするつもりですけれども)。もしそうなってしまった場合はご容赦お願いしつつ、自作小説は別途バックアップを取っておいていただきますようお願い致します。

問題の修正

・読み上げが勝手に停止する問題を修正しました(多分これで根本的な対応になると思います)

追伸
評価やレビュー、ありがとうございます。長いことおまたせしてしまって申し訳ありません。自作小説の登録機能を追加してみました。自作小説だけでなく、小説家になろう以外の小説を読み上げさせることもできるようになったかと思います。ただ、小説家になろう以外からの小説を読み込ませる機能、と考えるとちょっと面倒臭いと思われるので、もう少し楽に登録できる方法(EPUBを読み込みとか)を考察中です。
それでは、今後とも ことせかい をよろしくお願い致します。


# Version 1.1.4

Interface change

- Add "Add default correction of the reading" menu on text long tap menu.
- Add "Add own created book" feature at Settings page. You can write yourself book now!

Bug fix.

- Reading aloud revises a problem to stop without permission.



# Ver 1.1.5

インタフェースの変更

・iOS 9 以上で、発音される音声データを選択できるようになります。設定タブの声質の設定に項目が増えます。
利用可能な音声データは初期状態では一つだけですので、音声データを増やしたい場合は
設定アプリ > 一般 > アクセシビリティ > スピーチ > 声 > 日本語
と手繰っていった所で音声データをダウンロードしてください。
(なお、Siriさんの音声データは O-ren(拡張) という名前になっているもののようです）
・Voice Over が有効になっている場合、読み上げ開始時に警告を発するようになります。
・本棚の並び順を変更できるようになります。本棚タブの右上にボタンが増えます。
・小説の更新分を自動で取得させることができるようになります。設定タブに設定項目が増えます。

問題の修正

・小説の更新分を読み込むなどをした時に、読み上げ位置が初期化される問題を修正
・電話がかかってきた時など、ことせかい 以外のアプリで音が使われる時に再生を停止しなかった問題を修正
・アプリ名が NovelSpeaker になっていたのを ことせかい になるように修正
・iPhone 6 Plus 等で上下に黒帯が入る事がある問題を修正
・内部DBへのアクセス時に落ちる問題を修正

追伸

評価やレビュー、ありがとうございます。かなり長いこと放置してしまっていてすみません。iOS 10 になって標準の音声データがしょぼくなりすぎたのを受けて、取り急ぎ標準の音声以外のデータを使えるようにしたものに更新致します。これで本物のSiriさんに読み上げてもらえるようになるはずです。ただ、これが出来るのに気づいたのが手元の端末を iOS 10 に上げた後でなので、iOS 9 では試しておらず、もしかすると利用できないかもしれません(なお、iOS 8 ではAppleの提供しているAPIに音声選択の項目が無いため利用できません)。もし、問題がありましたら恐れ入りますが最新の iOS へ更新するなどで対応していただけるとうれしいです。
なお、次回以降の更新時の話になりますが、ことせかい の対応OSバージョンを iOS 8 以上にすることを計画しています(現在は iOS 7 以上の対応です)。どうしても iOS 7 で動作して欲しいという方がおられましたら、サポートサイトの下の方に用意致しましたご意見ご要望フォームから思いの丈を送っていただけると対応できるようになるかもしれません。
それでは、今後とも ことせかい をよろしくお願い致します。

# Version 1.1.5

Interface change

- Can select speaker data. You need download sepaker data from:
  Settings > General > Accessibility > Speech > Voices > Japanese
- If VoiceOver enabled, alert dialog is open when speak start.
- Bookshelf sort type selector now available.
- Auto download for updated novel mode added. Add enable/disable this mode settings at Settings page.

Bug fix

- I read it aloud at the time of the re-reading of the novel, and a position revised an initialized problem.
- When it had a telephone, It come to stop reproduction.
- I revise the problem that a black belt holder may begin up and down in 6 iPhone Plus.
- Application revised a bug to be finished at the time of access to internal DB.

metadata rejected に返信した奴
"AAA"という単語はサイト名です。"AAA"は http://syosetu.com/ というWebサイトの名前です。

本アプリは”AAA"にある小説を読み上げるためのものです。従って、ユーザは”AAA"という単語で検索をすることが有り得ます。そのため、我々はメタデータには”AAA"が含まれるべきだと考えています。

メタデータ”AAA"はこのまま残しておいて良いでしょうか？

アプリ名については日本語の言い回し上紛らわしい事を確認致しましたので”BBB"と修正致します。

The word "小説家になろう" is the site name. "小説家になろう" is the name of the Web site called http://syosetu.com/.

This application is intended to read a novel in "小説家になろう" aloud. Therefore, the user may have that I search it by a word "小説家になろう". Therefore we think that "小説家になろう" should be included in meta data.

May meta data "小説家になろう" leave it as it is?

Because I confirmed a confusing thing in a Japanese expression about the application name, I make modifications with "ことせかい".

# Ver 1.1.6

インタフェースの変更

- 再生中にイヤホンジャックからイヤホンが引き抜かれた場合、再生が停止するようになります

問題の修正

- 「なろう検索」からのダウンロード等が失敗する問題を修正
- ある本の読み上げを停止した後、別の本を開いて読み上げを開始しようとした時に、読み上げ開始位置が先程停止した読み上げ位置にズレてしまう問題を修正
- 連続再生時間で指定した時間が経つ前にページ切り替えが起こると連続再生時間での自動停止が効かなくなる問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。また、小説家になろう様側の仕様変更でダウンロードができなくなるという不都合でご迷惑とご心配をおかけしましたことをお詫びいたします。これからも宜しくお願い致します。
今回は小説家になろうのサイトのメンテナンス以降、ダウンロードができなくなってしまった問題への対応が主となります。
また、作りかけの機能も一応入っているのですが、この作りかけの機能については使い勝手があんまりよくないのと、"表示されているページを読み込む"ために混乱を招く形式になっていると思いますので、分かる人だけ使ってくださいといった形で提供致します。ですので、この機能については将来的には別の形で実装しなおす可能性があります(特にUI周りは変えたいと思っているので「こうしたらもっと使いやすいor混乱しにくいんじゃないか？」といった提案等はお気軽にサポートサイト側のご意見ご要望フォームにお送りください)。また、リリース後に出てくるダイアログでは言及せず、AppStore側でのアップデートノートを読んだ人だけが気づける機能としています。機能の説明としては、

- Safariで利用できるシェアボタン(上向きの矢印のボタン)から利用できる「ことせかいへ読み込む」機能を追加しました。Safariで "小説の本文が表示されている状態"(小説のタイトルページではなくて本文が表示されているページです) で、シェアボタン(四角から上向きの矢印が出ているボタン)を押して、「ことせかいへ読み込む」を選択すると利用できます。(OFFになっていて表示されていない場合には、シェアボタンを押した後、「その他」の中で「ことせかいへ読み込む」をONにしてからご利用ください)

という物になります。なお、この「ことせかいへ読み込む」機能は、Webページを取り込む時の補佐、程度の性能となっております。複数ページがある場合には続きのページも出来る限り読み込むようにはしましたが、全てのWebページで動作するようには作られておりませんし、本来は続きのページでない記事などを続きのページと誤認して読み込んでしまったりすることもあるようなものなので、あまり期待せずに うまく動いたらラッキー、位で思っておいていただけると嬉しいです(実際、いくつかのWebサイトでは動かないのを確認しています。その場合はお手数ですが今まで通りコピーしてから自作小説としてペーストするなどで対応していただければ嬉しいです。なお、サポートサイト側などから「このサイト(できればURLまで書いていただけるとありがたいです)がうまく動きませんでした」と報告していただけると嬉しいですが、すぐには対応できないかもしれません)。また、読み込まれた文章に本文と関係の無いもの(例えば「次のページへ」のリンクの文字など)が混じることが結構あります。そのため、これらを修正できるように、Webページから読み込まれた文章は自作小説と同じ扱いをしていますので、編集して取り除いて頂ければと思います。

次に、「********」といった文字がある文章を読み上げさせようとすると高確率でアプリが終了してしまうという問題を確認しています。原因を究明中なのですが、開明には至っていません。一応、例に上げた「*******」というものであれば「*」という文字列を「　」(全角スペース)として読み替え辞書に登録することでアプリが終了するという問題からは回避できることが確認できていますので、この問題が起きた時にはそのような手法で回避して頂ければと思います。

また、今回のアップデートから ことせかい の対応OSバージョンを iOS 8 以上に致しました。ダウンロードできている方には問題ないと思いますが、古い iOS を利用している場合にはアップデートはできなくなっているものと思われます。

それでは、今後とも ことせかい を宜しくお願い致します。


# Version 1.1.6

Interface change

- When an headphone is pulled up when an headphone sticks in headphone Jack, speech comes to stop.

Bug fix

- Fixed problem that download from Let's becom novelist site failed.
- Fixed a problem in which the reading start position shifted to the reading position stopped earlier when reading of a book was stopped and when opening another book and starting reading aloud.
- Fixed a problem that automatic stop at continuous playback time does not work if page switching occurs before the specified time in continuous playback time.


レビュワー向け

Interface change

- When an headphone is pulled up when an headphone sticks in headphone Jack, speech comes to stop.
- Add "download with NovelSpeaker" Action Extension for Safari. It's use http://* connection.

Bug fix

- Fixed problem that download from Let's becom novelist site failed.
- Fixed a problem in which the reading start position shifted to the reading position stopped earlier when reading of a book was stopped and when opening another book and starting reading aloud.
- Fixed a problem that automatic stop at continuous playback time does not work if page switching occurs before the specified time in continuous playback time.

レビュワー向け reject された後の追記

I updated the App Archive because Metadata is wrong.

> We noticed the app icon displayed on the device and the large icon displayed on the App Store do not sufficiently match, which makes it difficult for users to find the app they just downloaded.

However, in this explanation, I was not sure what exactly is wrong.
I did not know whether the color of the application icon is a problem or whether the size is a problem.
In the Xcode project, the icon of the part of the image to be attached will be blank, so it will correspond to newly setting 1024px.
If there is still a problem, I am glad that you can specifically tell me what is the problem.

----
In japanese.
Metadataがおかしいという事で、App Archiveを更新しました。

> We noticed the app icon displayed on the device and the large icon displayed on the App Store do not sufficiently match, which makes it difficult for users to find the app they just downloaded.

しかし、この説明では具体的に何がおかしいのかがよくわかりませんでした。
アプリアイコンの色が問題なのか、大きさが問題なのかがわかりませんでした。
Xcode projectでは、添付致します画像の部分のアイコンが空白でしたので、新たに1024pxのものを設定した、という対応になります。
まだ問題があるのであれば、具体的に、何が問題なのかを指示していただけると嬉しいです。


# Ver 1.1.7

インタフェースの変更

・設定タブに、「ルビをルビだけ読むようにする」のON/OFF設定を追加
・「設定」->「再ダウンロード用URLの取得」、を「再ダウンロード用データの生成」に変更します。小説家になろうのものだけでなく、自作小説、Safariから ことせかい に読み込ませたもの、読みの修正用辞書のバックアップが可能となります
・Safari から「ことせかい に読み込む」機能を使って読み込ませた時、タイトルが確定した時点でタイトルをダイアログで表示するようになります

問題の修正

・小説を読み上げ中に設定タブなどへ移動して戻ってくると、読み上げ位置が過去のものに戻されてしまう問題を修正
・全ての小説を再ダウンロードする時に、更新が無いものについてはダウンロードキューに追加しないようになります

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回の修正は細かい改良やバグ修正が主となります。
小説の読み上げ中にタブを移動すると読み上げ位置が巻き戻る問題はご迷惑をおかけしました。申し訳ありません。
今回は再ダウンロード用のURLの取得機能を変更して、自作小説のバックアップや読みの修正用辞書のバックアップもできるようにしてみました。ファイルの拡張子を .novelspeaker-backup-json にしていだだいて、正しいJSON形式で記述していただければ、外部から読み替え辞書の登録もできるようになります(読み替え辞書のみの記載だけでも問題ありませんので、読み替え辞書を登録するために利用していただいても構いません)。これらのデータは上書き保存されます。古いもので上書きされなかったものは削除されませんのでご注意ください。なお、JSONの形式は一度「再ダウンロード用データの生成」でバックアップ用データを生成して頂いて、その中身を真似る形で理解して頂ければと思います。

それでは、今後とも ことせかい を宜しくお願い致します。

# Ver 1.1.7

Interface change

- Add "Speech ruby only" setting feature on Settings page.
- Change "Create re-download URL" feature to "Create NovelSpeaker Backup file" on Settings page.
- When loading with Safari using the "download with NovelSpeaker" extension, title will be displayed in the dialog when the title is confirmed.

Bug fix

- Fixed a problem that when you move to the setting tab etc. while reading a novel and return it, the reading-out position is returned to the past one.
- When all the novels are re-downloaded, those that do not update will not be added to the download queue.


Appleのレビュアー向けの補足情報


In this update, files with the file extension .novelspeaker-backup-json are associated with the application.
This function is intended for backup purposes of downloaded novels etc.
This file is generated using "Create re-download URL" in SettingsPage of the application.
The user can download the generated novelspeaker-backup-json file into the application, and you can re-download the backed up novel again.

.novelspeaker-backup-json The contents of the file are in JSON format and are roughly as follows.

{
  "data_version" : "1.0.0",
  "word_replacement_dictionary": {
    "from word": "to word", ...
  },
  "bookshelf": [
  {
    "type": "url" or "ncode" or "user",
    "ncode": ..., "title": ..., "id": ..., ...
  }, ...
  ]
}

In the above. Novelskeaker-backup-json, a place to save data using encryption has been added.
For that reason, we decided to use the encryption function "Yes" when submitting the review of the application.
This encryption function uses sha 256 (CC_SHA 256 () function) prepared by OS side.



# Ver 1.1.8

インタフェースの変更

・設定タブのUIを少し作り直し(機能は変わりません)
・設定タブの「ルビをルビだけ読むようにする」をONにした時に、ルビとして認識しない文字を指定できるように
・設定タブの読みの修正内にて、修正項目の検索ができるように

問題の修正

・iPhone SE等の画面の小さい端末で、文字が見切れていた問題を一部修正
・「ルビをルビだけ読むようにする」機能で、ルビ以外の部分を読み飛ばしてしまう問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回の修正も細かい改良やバグ修正が主となります。
設定タブで文字が見切れていた問題やルビをルビだけ読むようにする機能の不都合は気づいておりませんでした。皆様からの不都合報告には重ねてお礼申し上げます。
今回のバージョンから、UI周りを外部のライブラリに変更して作り直していっています。以前と動作が少し異なる所も出てきてしまうと思いますが、機能的には同じものを提供できるようにしているつもりです。何か問題などありましたらお気軽にご意見ご要望フォーム等から指摘して頂けると嬉しいです。

それでは、今後とも ことせかい をよろしくお願いいたします。


# Ver 1.1.8

Interface change

- Redo some UI of setting tab (function does not change)
- To enable you to designate characters that you do not recognize as ruby when turning on "Speech ruby only" on setting tab
- In order to search for correction items within correction of reading on setting tab

- bug fix

- Fixed a part of the problem that letters were not seen on small terminal of screen of iPhone SE etc
- Fixed a problem that "Speech ruby only" skipping skipping parts other than ruby


# Ver 1.1.9

問題の修正

・新規ユーザー小説の登録が必ず失敗するようになっていた問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回はバグ修正のみの更新になります。
新規UIに変更したあたりでバグを作り込んでいました。申し訳ありません。

今後とも ことせかい をよろしくお願いいたします。

# Ver 1.1.9

bug fix

- Fixed an issue where registration of new user novels always failed.

# Ver 1.1.10

インタフェースの変更

・「ダウンロード状態」タブを潰して「Web取込」タブを新設。Web取込では表示されているWebPageの文字を取り込む事ができるようになるはずです。使い方の詳しい説明はサポートサイトを参照してください
・Safariから取り込む 機能でも、タイトルや内容を確認してから取り込む事ができるように
・小説を読んでいる画面にて、左右へのスワイプで章の切り替えができるように

問題の修正

・小説のタイトルやあらすじに&quot;等があった時にそのまま表示されてしまっていた問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回は「Web取込」機能のリリースが主たる目的の更新となります。この機能は少し前から使えるようになっていた、Safariで表示しているWebページを取り込む機能を少し使いやすくしようとしたものです。大まかな使い方としては、

1. Web取込タブに内蔵されているWebブラウザで、ことせかい に取り込みたい小説を表示させる
2. 右下にある「取り込み」ボタンを押す
3. そのページを取り込むとどのような内容となるのかがダイアログで表示されるので、確認の上「このまま取り込む」ボタンを押す事で取り込みを開始する

という形になります。なお、3. のシーンで「続ページ：有り」となっている場合、複数ページに分かれている文書を最大100ページまで読み込みます(それ以降は本棚ページでリロードボタンを押す事でダウンロードを続行します)。
より詳しい使い方をサポートサイト側に書いておきますのでそちらもご参照ください。

また、このWeb取込の機能は個々のWebページ毎に「本文」「タイトル」「作者名」「続くページへのリンク」等といった情報を取り出す必要があるため、それらの情報をデータベース化して利用しています。という事で、この情報が登録されていないWebサイトでは取り込みがうまく動かない事になるため、このデータベースの内容が充実していないと寂しい事になるわけです。ただ、世の中には沢山のWebサイトがあり、それに対して ことせかい の開発者は一人ですので正直全く人手が足りません。ですので、このデータベースのメンテナンスを手伝って頂ける方を募集します(なお、お手伝い頂いても報酬は何も出ません事をご承知ください)。データベースのメンテナンスについての詳しい情報も使い方同様にサポートサイト側に書いておきますのでお手伝いして頂ける方はぜひお手伝いをお願いします。

また、次回以降のアップデート時に、対応の iOS バージョンを 9 (か、もしかすると10) 以上にしたいと考えています。iOS のバージョンが古いもので動かしているなどで、対応バージョンの上昇が困るという方がおられましたら、サポートサイト側のご意見ご要望フォーム等からお知らせして頂ければ、対応バージョンを上げないような努力をしてみようと考えます。逆に言うと、お知らせ頂けなければ気兼ねなく対応の iOS バージョンを上げてしまうと思われますので、重ねて申し上げますが、上げてほしくない方がおられましたらお知らせください。

それでは、今後とも ことせかい をよろしくお願いいたします。


# Ver 1.1.10

Interface change

- New Web Import tab added.
- Even for functions to be imported from Safari, you can check the title and contents and then import it.
- On the screen reading the novel, let's switch chapters with swipe left and right.

bug fix

- Fixed problem which was displayed as it was when &quot; etc was in the title and the outline of the novel.

# Version 1.1.11

インタフェースの変更

・Web取込タブにて、Googleのような検索サイトへのアクセスを閉じました(「無制限のWebアクセス」によるレーティング17+を回避する方策です)

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

さて、今回の修正はちょっと残念な修正になります。Version 1.1.10 にした時に追加した Web取込 タブなのですが、これは所謂普通のWebブラウザのようなものとして実装されていました。この場合、Apple側に提出する年齢制限指定の部分にある「無制限のWebアクセス」をONにしないといけないのですが、これをONにしてしまうとアプリのレーティングが17+になります。ということで Version 1.1.10 はレーティングが 9+ から 17+ になってしまいました。
当方、年齢制限をされている人が使っておられることを完全に失念しておりましたので、特に何の警告もなく、レーティングを上げた状態でリリース致しました。
なのですが、おそらくはこの変更によって年齢制限に引っかかってしまった利用者の方から残念だというレビューがつきまして、なるほど使いたい方が使えないのは寂しいなぁということで、少し知恵を絞ってこんな形ならどうだろう、というリリースとなります。

変更箇所は

- Web取込タブのURLバーへのURLや検索文字列の入力をできなくした
- Web取込タブのホームページ(ブックマークリスト)の標準値に設定してある Google へのリンクを削除した

という二点となります。つまり、通常の方法ではGoogle検索のようなものに移動できなくなりますので、アプリ側では「無制限のWebアクセス」ができないという事になる……という目論見です(この状態でリリースされているということはおそらくはその解釈で良いということでしょう)。

で、です。Google検索が使えないと初期値以外のWebサイトを読み込めないじゃないか、というお話があると思います。その場合はお手数ですが Safari 経由で ことせかい を呼び出す機能がありますので、そちらをお使い頂ければと思います。
使い方としては、

- Safari アプリを起動
- ことせかい に取り込みたい本文が表示されている状態にする
- シェアボタン(四角から上向き矢印が出ているボタン)を押し、下段(白黒のアイコンが並んでいる所)にある「ことせかい へ読み込む」を選択して ことせかい へ取り込む(「ことせかい へ読み込む」ボタンが無い場合は右にスクロールしていって「その他」を押し、「ことせかい へ読み込む」をONにしてください)

で、任意のWebページを取り込むことができます。
アプリひとつで完結している方が煩雑さは少なくなるのはわかるのですが、小説を楽しもうと思っている年齢制限に引っかかってしまう方のために、少し涙を飲んで頂ければと思います。

ということで、一応回避策は無い事は無いのですが、使い勝手が悪くなることは否めません。ということで、「やっぱりWeb取込タブでGoogle検索したい！17+で使えない人は涙を飲んでくれ！」という熱い思いを唱える方がおられましたら、その熱い思いをご意見ご要望フォームにぶつけていただければと思います。その熱い思いによっては Version 1.1.10 の形式に戻すことも吝かではありません。なお、返信用のe-mailアドレスを書いておいて頂けると、何らかの対策的なお話ができるかもしれません。

また、余談ですが Version 1.1.10 からはバックアップデータを生成していただくと、ブックマークもバックアップされるようになっています。バックアップされたデータを ことせかい に読み込ませることで、バックアップされたブックマークで ことせかい のブックマークを上書きすることができます。以上余談でした。

また、次回以降のアップデート時に、対応の iOS バージョンを 9 以上にしたいと考えています(お一方 iOSバージョン 10 は勘弁してくださいとの投書がありましたので少なくともこの先1年位は上げても 9 までにする予定です)。iOS のバージョンが古いもので動かしているなどで、対応バージョンの上昇が困るという方がおられましたら、サポートサイト側のご意見ご要望フォーム等からお知らせして頂ければ、対応バージョンを上げないような努力をしてみようと考えます。逆に言うと、お知らせ頂けなければ気兼ねなく対応の iOS バージョンを上げてしまうと思われますので、重ねて申し上げますが、上げてほしくない方がおられましたらお知らせください。

それでは、今後とも ことせかい をよろしくお願いいたします。


# Version 1.1.11

Interface change

- We closed access to the search site like Google on the Web import tab (a way to avoid Rating 17+ by 'Unlimited Web Access')


for review

In this update, we made an update aimed at removing "unrestricted web access" specified by age restriction.
I am cited below as to what I fixed.

- Invalid entry of URL and search string into URL bar of "Web import" tab.
- Deleted the link to Google set to the standard value of the homepage (bookmark list) of "Web import" tab.

With the above fixes, you can not enter URL, Google search, etc from "Web import" tab. Therefore, we think that it will become possible to browse only the site saved as the initial value.
We believe that this means that it can not be said as "unlimited Web access".
I made the above fix, but please let me know what is the problem if I can not remove "unrestricted web access" with this.


# Version 1.1.12

インタフェースの変更

- ユーザ自作小説等を編集しようとした時に、読み上げ位置から編集が開始されるように変更

問題の修正

- iPhone X で本の内容の表示の最初の1,2行が隠れてしまう問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回は細かい修正のみのリリースとなります。iPhone X は当方は所持しておりませんでしたので、ユーザ様からのバグ報告がなければ対応しないといけないと気づけもしませんでしたので、とても助かります。その他にも「これは全然直らないんだけどどうなんだろう……」といった何かは単に気づいていないだけの可能性もありますので、気になる点はお手数ですがサポートサイト側に用意してあります、ご意見ご要望フォームから投稿して頂けるとありがたいです(気づいてはいるけれど実装がまだという物もありますので、github側のissueに同様の項目が無いかどうかを確認してから投稿して頂けますと、とてもありがたいです)。

また、再度のご連絡になりますが、次回以降のアップデート時に、対応の iOS バージョンを 9 以上にしたいと考えています。iOS のバージョンが古いもので動かしているなどで、対応バージョンの上昇が困るという方がおられましたら、サポートサイト側のご意見ご要望フォーム等からお知らせして頂ければ、対応バージョンを上げないような努力をしてみようと考えます。逆に言うと、お知らせ頂けなければ気兼ねなく対応の iOS バージョンを上げてしまうと思われますので、重ねて申し上げますが、上げてほしくない方がおられましたらお知らせください。

それでは、今後とも ことせかい をよろしくお願いいたします。


# Version 1.1.12

Interface change

- When editing a user's own novel etc, change so that editing starts from the reading-out position.

bug fix

- Fixed problem that iPhone X hides the first and second lines of the contents of the book.


# Version 1.1.13

インタフェースの変更

- テキストファイルを自作小説として取り込めるように
- PDFファイルを自作小説として取り込めるように(iOS 11以上のみ)
- 設定タブに「不都合報告をメールで開発者に送る」機能を追加

問題の修正

- Web取込機能で取り込んだ小説について、取り込んだ時間で更新日時を更新するように
- Web取込機能で、HTTP 400 BadRequest でエラーしていた問題の一部を解消

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回はテキストファイルを取り込む事ができるようにしました。SafariからのWebページの取り込みと似ている形で、シェアボタンから利用します。「ことせかいへ読み込む」(アイコンが灰色な)側がSafariからのWebページ取り込みで、「ことせかいにコピー」(アイコンがカラー)のものが今回追加されたテキストファイルの取り込みですのでちょっと混乱する形になっています(どうしたらわかりやすくなりますかね……？)。
テキストファイルが取り込めるようにした仕組みと同じ形で、PDFも取り込めるようにしてみました。ただ、これは iOS 11 から使えるようになった PDFKit というものを使っておりますので、iOS 11 以降でないと動きません。また、PDF の中に書かれている文字列を取り出す仕組みをその PDFKit のものに全ておまかせしておりまして、どうやら二段組のPDF文書などの複雑な構造の文書ですと、めちゃくちゃな内容で取り込まれたりするようです。あと、文字として保存されていないもの(文字が画像として入っている場合等)は取り込めません。なので、PDF取り込み機能はあんまり使い物にならないかもわかりません。
これらのファイル取り込み機能は、シェアボタン経由で「ことせかいにコピー」を選択することで動作します。ただ、SafariとiOS11からのファイルアプリからのシェアボタンでの動作は確認できたのですが、Dropboxアプリからのシェアボタンでは選択肢に出てこないようでした(シェアボタン(エクスポート)->別のアプリで開く->ことせかいへコピー、でなら動くみたいですが、タップ回数が多いですね)。何故そうなるのかの原因がよくわからないので詳しい方がおられましたら教えてください。
また、アプリ内にサポートサイトへのリンクをつけた後あたりから不都合の報告をサポートサイト側から報告して頂ける事が多くなったのですが、残念なことに不都合報告に書かれている情報が少なくて対応できない事が多いです(例えば「しばらく使っていると落ちます」みたいな情報だけですと、何が原因で落ちたのかもわかりませんのでどうにもこうにも対応できません)。開発者の手元で再現のできない問題は再現可能になるような調査を行う必要があり、時間がかかるため、(例に挙げたような)情報量の少ない不都合報告への対応はほぼできないと考えて欲しいです。といっても、再現可能となるような詳細な手順を書いて頂くのも大変だろうというのもわかりますので、ことせかい の操作ログを保存しておいて、不都合報告の時にそれを送信できるようにしてみました。この操作ログと不都合の発生した日時を突き合わせる事で、実際に操作した状況を開発者の手元で再現しやすくなるだろう、という目論見です。ただ、操作ログには ことせかい に取り込んだ小説のURLといった情報も含まれておりますので、この操作ログを送信していただくと、それらの情報が開発者に公開されてしまうことになります。ですので、開発者に知られては困るような情報を ことせかい で扱っている場合には操作ログを送信しないでください(守秘義務的な法律を全然理解していない開発者になりますので、公開されてはいけない情報を扱っている場合は本当に送らないでください。困ります)。なお、アプリが落ちてしまうような時にもログは残るようにしたつもりですので、アプリが落ちた後すぐに操作ログを含めての不都合報告をして頂けると、アプリが落ちた状況も開発者の手元で再現しやすくなりそうです。

以上となります。それでは、これからも ことせかい をよろしくお願い致します。


# Version 1.1.13

Interface change

- Now can import .txt file.
- Now can import .PDF file.
- Add Problem report feature in Settings tab.

Bug fix

- As for the novel imported by the "Web import" function, update the update date and time in the captured time.
- Fixed some of the problems with HTTP 400 BadRequest with "Web import" function


# Version 1.1.14

インタフェースの変更

- なろう検索で観られる小説の詳細ページのレイアウトを変更(画面の小さいデバイスで表示が崩れるため)

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回は軽微な修正となります。具体的には iPhone 5s で表示が崩れているという不都合報告を受けたことで発覚した問題への対応となります。つまり、ユーザの皆様からの不都合報告には本当に助かっています。これからもよろしくお願い致します。

それでは、これからも ことせかい をよろしくお願い致します。

# Version 1.1.14

Interface change

- Novel information page layout changed (for small display device).


# Version 1.1.15

インタフェースの変更

- Web取込機能を使って取り込んだ小説について、個々の章を表示している画面に再ダウンロード用のボタン(回転している矢印)を追加

問題の修正

- バックアップファイルで小説等を読み込み直す時に、画面が凍りついたり ことせかい が落ちやすくなっていた問題を(一部)修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回の修正も細かい改良やバグ修正が主となっております。今回のバグ修正などもユーザ様からのご指摘があって気づいた問題になります。いつもありがとうございます。最近は問題のご指摘だけでなく、かなりしっかりとした状況の再現方法まで伝えて頂けていて、手元での問題の再現が楽になることで問題の修正がやりやすく、とても助かっています。ありがとうございます。

以上手短になりますが、今後共 ことせかい をよろしくお願い致します。

# Version 1.1.15

interface change

- Added a button for re-downloading (rotating arrow) to the screen displaying individual chapters for the novel captured using the "Web import" function.

bug fix

- Corrected (some) the problem that the screen froze or NovelSpeaker fell easily when reloading the novel etc in the backup file.


# Version 1.1.16

問題の修正

- 「ルビはルビのまま読む」がONになっていても最初の1章分は効いていなかった問題を修正
- "*" が連続している部分を読み上げようとすると落ちるので、無害な文字へと読み替える読み替え辞書として追加するように

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

前々からお問い合せのありました、ルビはルビのまま読むが効いていない、という問題の一つが手元の端末で再現するのを確認致しましたので、修正しました。ご迷惑をおかけてしまって申し訳ありませんでした。
ここ最近はバグ修正のアップデートばかりになっているんですが、これらのバグ修正は全部ユーザ様からの不都合報告から発覚しているように思います。単に私のテストがしょぼすぎる(マトモなunit testが書かれていないとか)のが原因の一つではあるのですが、ユーザ様達からの不都合報告には本当に助かっています。ありがとうございます。

それでは、今後共 ことせかい をよろしくお願い致します。


# Version 1.1.16

bug fix

- fixed: Even if "Speech ruby only" is ON, the first chapter was not working
- Since it falls when trying to read a part where "*" is consecutive, it is added as a replacement dictionary to read as harmless characters


# Version 1.1.17

問題の修正

- 文字入力が必要な部分で、Enterを押さないと保存されなかった問題を画面外タップ等でキーボードを消しても反映されるように修正
- Bluetooth機器が外れた時に再生が停止しなかった問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

サポート周りを充実させたことで、不都合報告などでとても助かっているのですが、逆にお問い合わせの件数が増えてしまってちょっと大変になっています。どうすればいいんでしょうかね……(´・ω・`)

あ、問い合わせをしないで欲しいと言いいたいわけではなくて、逆にお問い合わせがあるのはありがたいというか問題もみつかりますしたまに褒めてもらったりして元気も貰えますし利点が多いんですけれど、単純に数が多いと一人で対応するのには限界があるなぁという感じです。かといって、定型文などのそっけない返事とかを返せばいいのかというとそれだと問い合わせ窓口を設けている意味がなくなっちゃいますし、問い合わせ窓口を減らせば昨年末あたりからの怒涛の不都合修正リリースみたいなこともできなくなりますし、といっても問い合わせの量が増えるとそればっかりに時間が使われてしまって……うーん……(´・ω・`)
せっかくお問い合わせの話題を書いたのでついでになりますが、不都合報告をされる時は、「〜が動きません」みたいな簡潔な表現ですと、開発者側の手元で再現できない事が多いので、不都合報告をされる場合は「ことせかい を一回も使ったことが無い人でも同じ操作ができて、問題を認識できるくらいの情報」をつけてくださいますようお願いします。情報が少ないと開発者側の手元で再現できず、再現できない問題は直そうにも直せませんので対応できないことになり、「そちらでは動かないんですね……こちらの手元では動いてるんですけどね……(´・ω・`)」という気持ちだけが残る後味の悪いお問い合わせになってしまいます。お返事ができる場合には「もうちょっと具体的にどのWebサイトのどの小説の何ページ目のどんな文章の辺りでそれが起こるかを教えて頂けますか？」といったような形で開発者側の手元でも再現できそうな情報を引き出すためのお返事を出しているのですが、お返事が必要ないと書かれているとそれもできずに残念な気持ちだけが残る感じになってしまっています。といっても、お返事を書くのはそれはそれで大変なのですけれども……本当にどうしたものか……(´・ω・`)
ついでついでに、お問い合わせで「〜は〜ですか？」と疑問形で終わっているのに返信は必要ないとなっていたりすると、「はい、〜は〜ですね」と思いながら返信できないというなんともモニョモニョする感じになっておりますので疑問形で投稿される場合は返信を許可にして頂く事を考慮してみてくださいね(´・ω・`)

うーん、こんな泣き言を書いて何がしてもらいたいかというのは特に何をしてもらおうという気もないのですけれど、現状ではそのような事になっておりまして、何か新しい機能の実装をお待ち頂いている方々にはとても残念なのですけれどあんまり新しい機能向けの開発の時間が取れていませんというお知らせになっていたり、簡潔で内容の薄い不都合報告を送って頂いている方にはわざわざ不都合報告を書く時間を取って頂いたにもかかわらず(開発者の手元で再現できないという理由で)対応もできずに申し訳ないという気持ちを伝えたいというか、お問い合わせの枕などでお褒めの言葉を添えてくれている方にはとても元気をもらっていていつも本当にありがとうございますと厚く御礼申し上げたいというか……うーん……(´・ω・`)

と、いうわけで、特に何の結論もないただの泣き言のリリースノートになってしまいましたけれども、これからも ことせかい をよろしくお願いいたします。



# Version 1.1.17

bug fix

- Corrected so that even if you erase the keyboard by tapping off the screen etc., the problem which was not saved unless you press Enter is reflected in the part where character input is necessary
- Fixed an issue where playback did not stop when Bluetooth device was disconnected


# Version 1.1.18

問題の修正

- 読み上げ時に別のタブに切り替えたりするなどをすると読み上げ位置がズレたりと色々問題が多かったため、読み上げ中に別タブに移動するなどした場合には読み上げを停止するように
- 最後まで読み上げた後の終了時のアナウンスが発声されない場合があった問題を修正
- 小説の本文を表示している状態から本棚等に戻った時に、読み上げている小説の情報が壊れる可能性があった問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回も問題の修正のみのリリースとなります。問題への対応のため一部仕様が変更されています。今までは読み上げをさせながら別の小説を探すなどの操作ができていたのですが、状態管理周りが大変になってしまっていたのでこれをやめました(小説の本文が表示されている状態から抜けようとすると読み上げが停止するようになります)。
また、恐らくはかなり前から潜んでいた問題を修正しました(開いている小説を別の小説に切り替えた後に読み上げを開始すると変な動作になる等の現象として観測できていたと思われます)。この問題が発生した後は色々な動作が不安定になっていたと思われます(分かる人にはわかるように書くと delegate が開放されたはずの object を呼び出していました)。

ということで、特に何の新機能もないリリースばかりになっておりますが、これからも ことせかい をよろしくお願いいたします。


# Version 1.1.18

bug fix.

- Speech stopped when moving to another tab during speech reading. This was the cause of causing various problems.
- Fixed an issue where announcement at the end after speaking to the end might not be uttered
- When returning to the bookshelf etc from the state displaying the novel text, we fix the problem that there was a possibility that the information of the novel being read might be broken.


# Version 1.1.19

問題の修正

- 小説を開いた時(又は別の章に移動した時)に表示位置が変化しなかった問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回も問題の修正のみのリリースとなります。

立て続けの問題修正のみのリリースで書くことがなくなってきました！(ﾟ∀ﾟ)b
ということで、余談というかご提案を頂いたものへの返信などをしてみようかと思います。

読み上げ時にコントロールセンター(画面の下から引き出すと出て来たり、ロック画面に出てくるアレです)に表示される情報で時間が出るといいなぁというご意見を頂いたのですけれど、ざっと実装の実験をしてみた限りでは色々と面倒くさい問題を解かないと駄目そうなのでお蔵入りにすることにしました。簡単に説明致しますと、「読み上げる時間が推測しにくいが登録するのは時間」という事と、「再生位置の更新をアプリ側から伝えられない(勝手に更新される)ので『今はだいたいこの辺り』という情報を反映できない」ためです。まぁ、だいたいこの文章量なら3分位なんじゃない？って当てずっぽうで3分と宣言しておいて、2分半で読み終わっちゃったり、3分過ぎても読み終わってなかったりしてもいいのならそれはそれでいいのですが、多分、コントロールセンターで表示されている情報と一致しないとかいう不都合報告が飛んでくるんじゃないかと思いますのでそういうツッコミどころを増やすようなものになるのであれば実装はできないなぁという判断になりました。何かこういうことをしたらいいんじゃない？といったご提案があれば教えていただければと思います。

それでは、これからも ことせかい をよろしくお願いいたします。



# Version 1.1.19

bug fix

- Fixed an issue where the display position did not change when opening a novel (or moving to another chapter)


# Version 1.1.20

インタフェースの変更

- 設定タブにある「開発者へ問い合わせる」機能に新機能等の提案用のフォームを追加
- 小説の本文を表示している時、上部に追加された地球のアイコンからその小説のWebPageをSafariで開けるように

問題の修正

- 自作小説の編集中に登録を押さずに戻っても、内容が保存されるように

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回もお問い合わせについての回答をしていきます。
なお、ここに回答が書かれるということは、実装しないと決めた事などのものが多くなります(実装するのであれば実装して上部の更新情報に乗せることになります)ので、基本的にはユーザ様方には寂しい話となります。

まず一つ目は、読み替え辞書をクラウド的なものでユーザ間で共有して編集できないかというご提案です。
これは実現したらとても良いものになるとは思うのですが、そのクラウド的な物を維持するのにはお金がかかるので、ことせかい の開発者側としては対応できない案件となります。ことせかい が何らかの形で定常的にお金を生むような形にしていればよかったのかもしれませんがそうはなっていませんし、今から何らかのお金を生む要素を入れるのは多くの人が望まない事ですよね。なので、やる気はありません。ただ、数年間分のサーバ費用にオマケもつけるからやってくれという人が現れたり、自分がサーバ側を管理運営するのでアプリ側はなんとかしてくれという人が現れたり、この無料のサービスをこうやって使うと実現できるんじゃね？というウルトラCを考えついたりしたらあるいは、という気もしなくもありません。(もちろん、その費用が尽きたりサーバ運営をしてくれている人が諦めたりその無料サービスから想定外の使い方しちゃ駄目と怒られたらそこでそのクラウド読み替え辞書共有サービスは終了になりますので、不安定なサービスであるといえます)

二つ目は何らかの問題で期待しないデータがダウンロードされてしまった場合の話です。
これは、例えば小説ではなく、「アクセス数が多いのでエラー」といったものがダウンロードされてしまった、というような場合の事です。
現状では、既にダウンロードして登録されてしまった部分(章)を再ダウンロードする方法はありません。
内部的には HTTP のステータスコードでエラーを返してくれている(200 OK ではない場合、例えば 429 Too many requests を返している)場合であれば、ダウンロードが失敗したとみなして保存せずにダウンロードを終了しています(していない例がありましたら不都合になりますのでお問い合わせフォーム等から教えてください)。逆に、HTTPのステータスコードによるエラー以外で「アクセス数が多いのでエラー」という文字列が取得できてしまう場合(200 OK で取得したデータの場合)には、ダウンロードが失敗したかどうかを判定するのは難しいため、そのままの文字列が保存されてしまいます。これをユーザ様の側で「この章だけ再ダウンロードせよ」という指示を出せるようにしたらよいか、とも思ったのですが、現在の内部データベース仕様ですと「その章」がどんなURLであったのかの情報が不足しており、再ダウンロードすることができないために実現できませんでした(現状では最初にダウンロードしようとした章のURLと、最後にダウンロードしようとした章のURLしか保存されていませんので、10章分読み込んでいた場合には2章から9章までは再ダウンロードすることができない、という状態です)。
なので、「アクセス数が多いのでエラー」といったようなエラーメッセージそのものが保存されてしまっている場合は一旦小説を本棚から削除して、通信環境の良い所で再度ダウンロードしていただく必要があります。
この問題については将来的には対応しようとは思っているのですが、現在の内部データベース形式では上記の理由で無理となります。また、将来的に対応できたとしても、現在既にダウンロード済みのものについて(上記の例だと2章から9章について)はURLを推測できない関係上、対応が不可能な問題となります。予めご了承ください。

三つ目は縦書き表示について。
まず、ことせかい は「読み上げ」アプリですので「目で読む」ための機能については真面目にサポートするつもりはありません。
また、縦書き表示についてのお問い合わせは何度か受けておりますので少し調査してみたことがあるのですが、残念なことに簡単には縦書き表示はできそうにありませんでした。
グダグタと調査したものを書き下しますと、NSAttributedString に NSVerticalGlyphFormAttributeName 辺りを設定すると縦書き表示ができそうなのですが、1行分しか縦書き表示してくれないようであったり、TTTAttributedLabel というライブラリを公開してくれている人が居てそれを使うと良さそうだと思ったら、Label であって TextView ではないのでスクロールできなかったり、UIWebView に CSS で writing-mode: vertical-rl; 辺りを含ませた物を表示させれば綺麗な縦書き表示ができるかと思ったけれど、現在の読み上げ位置をハイライトする方法が一筋縄ではいかなくて断念したり、といった感じです。最後の UIWebView 辺りの仕組みがうまく動くのであれば表示している WebPage をそのまま読み上げさせる事や、挿絵を表示しながらの閲覧もできるようになりそうでいいかなぁとも思ったんですけれども、読み上げアプリとしては読み上げ位置が見えないのはなぁということでお蔵入りになりました。なお、これらは 2,3年前 に調査したものになりますので、今ではもっと良い方法があるかもしれません(その辺りの知識のある方がおられましたら教えていただければ嬉しいです)。

蛇足的にもう一つ。ことせかい の中の色んな所にあるスライダー(左右にスライドして値を入力する奴)なんですけれど、これ、微妙な値を指示したい場合にはちょっと面倒ですよね。そんな時は、スライダーのつまむ所(丸い奴)をタップしたまま(つまむ所が見える状態になるまで)指を下にずらして、そこで指を左右に傾けるような形で位置を調整すると微妙な値もなんとなく入力できます。まぁ正確に0.1づつ動かしたい、みたいなのには使えないのですけれど、覚えておくとちょっと便利な感じです。あ、これは左右への0.1づつとかのボタンを配置するのが面倒だから言っているのではなくてですね、ボタンを配置てしまうとiPhone SEとかの幅の狭い端末だとレイアウトが崩れちゃってちゃんと操作できなくなっちゃうのでボタンを配置できない所があったりするのです。

以上となります。
それでは、これからも ことせかい をよろしくお願いいたします。


# Version 1.1.20

Interface change

- Add a form for suggesting new functions etc. to "query to developers" function on setting tab
- When displaying the text of the novel so that the novel's WebPage can be opened in Safari from the icon of the earth added to the top

Bug fix

- Even if you go back without pressing registration while editing your own novel, so that the contents are saved


# Version 1.1.21

インタフェースの変更

- 設定タブに「本棚に栞の位置を表示する」のON/OFFの設定を追加

問題の修正

- Web取込機能にて取込を行った小説を開いた時に、読み込まれた章の数がうまく表示できていなかった問題を修正
- ダウンロード中に本棚から小説を削除した時に、ダウンロードが継続することで壊れた小説ができてしまう問題を修正

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助かっています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

今回のアップデートでは、読んでいる位置をプログレスバーで表示してほしいという要望に対応してみたのですが、どうにも本棚ページの雑然としている感じが強くなってしまったようにみえましたので、標準ではOFFにしておいて、設定タブの所からON/OFFを切り替えて利用して頂く形にしました。
その他の問題の修正に関しましては、これもユーザ様からのお問い合わせからの修正になっています。いつもありがとうございます。

また、前回までにリリースノートで告知しておりましたQ&A的なものを、サポートサイトの1ページとして纏めておきました。ご利用ください。

それでは、これからも ことせかい をよろしくお願いいたします。

# Version 1.1.21

Interface change

- Add "Display bookmark position on Bookshelf" toggle switch on Settings tab.

Bug fix

- Fixed an issue where the number of chapters loaded could not be displayed well when opening a novel that was imported by the web import function
- Fixed a problem that broken novels will be created when downloading continues when downloading novels from bookshelf during downloading

# Version 1.1.22

インタフェースの変更

- 小説の本文を長押しした時に出るメニューを「読み替え辞書へ登録」のみにするかどうかの指定を設定タブに追加
- 小説の本文を表示する字体を選択するボタンを設定タブの「表示文字サイズの設定」上部に追加

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助けられています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。

ゴールデンウィークは何をやろうかなぁと思いながら、結局 ことせかい の改良をしている私です。今回も不採用となりましたお問い合わせについて回答していきます。

ルビを文字の上に表示して欲しいというお問い合わせについて。
まず、ことせかい は「読み上げ」アプリですので「目で読む」ための機能については真面目にサポートするつもりはありません。
なのですが、簡単に実現できるのに実装しないのだとすると悪い気もしますので、調査してみました。しかし、残念なことにルビの表示を簡単に実現するのは難しいという結論に達しましたため、この機能については見送りました。
とはいえ、調査している所で小説の本文を表示している部分の字体を変えるのはそれほど大変でもなさそうでしたので、字体を変える機能を実装しました。選べる字体は多いのに日本語の文字の字体が変わるものは少なそうなのが気になりますが、選択できないよりはいいのかなぁと思っています。

それでは、これからも ことせかい をよろしくお願いいたします。


# Version 1.1.22

Interface change

- Add to the setting tab whether to set only the menu to be displayed when long-pressed the novel's body "Add correction of the reading"
- Add a button to select the font that displays the novel's body to the upper part of "Setting the display character size" on the setting tab


# Version 1.1.23

インタフェースの変更

- 本棚での栞の位置表示ゲージについて、読み終わっている場合はゲージの色を変えた

追伸

評価やレビュー、ありがとうございます。特にサポートサイト側からのご意見ご要望フォームからの詳細なバグ報告には本当に助けられています。アプリのレビュー欄でのお褒めの言葉もとても嬉しいです。これからも宜しくお願い致します。


----
in Japaneze.

今回のアップデートでは、年齢制限指定の「無制限のWebアクセス」を外すことを目的としたアップデートを行いました。
修正した事を以下に挙げます。

- "Web import"タブのURLバーへのURLや検索文字列の入力をできなくした。
- "Web import"タブのホームページ(ブックマークリスト)の標準値に設定してある Google へのリンクを削除した。

以上の修正により、"Web import"タブからはURLの入力やGoogle検索などができなくなります。そのため、初期値として保存されているサイトのみの閲覧ができるようになると考えています。
私達はこれによって、「無制限のWebアクセス」とは言えない状態になると考えております。
以上の修正をしましたが、これでは「無制限のWebアクセス」を外すことができないのであれば何が問題なのかを教えてください。
以上よろしくお願いします。

----
in Japanese.

今回のアップデートでは、ファイル拡張子が .novelspeaker-backup-json となっているファイルについて、アプリとの関連付けを行いました。
この機能はダウンロードされた小説等のバックアップ用途が目的です。
このファイルはアプリのSettingsPageにおいて"Create re-download URL"を用いて生成されます。
ユーザは生成された .novelspeaker-backup-json ファイルをアプリに読み込ませる事で、バックアップされた小説をもう一度ダウンロードし直す事ができるようになります。

.novelspeaker-backup-json ファイルの中身は JSON 形式となっており、おおよそ以下のような形式です。

{
"data_version" : "1.0.0",
"word_replacement_dictionary": {
"from word": "to word", ...
},
"bookshelf": [
{
"type": "url" or "ncode" or "user",
"ncode": ..., "title": ..., "id": ..., ...
]
}

上記の .novelskeaker-backup-json の中で、暗号化を使用してデータを保存する箇所が追加されました。
そのため、アプリのレビュー提出の際に暗号化機能の利用を「はい」にしました。
この暗号化機能はOS側で用意しているsha256(CC_SHA256()関数)を利用しています。

expedited app review に出した時の文言
---begin---
なろう検索のタブで、検索用文字列を入力できなくなっていた問題を修正しています。
この部分が入力できないと、検索で好みの小説を探すことができないため、あまり小説が選べないアプリになってしまっています。

問題の再現手順：

1. なろう検索 タブを開く
2. 一番上の「検索文字列」のテキストボックスを選択
3. 文字を入力する

3. のステップで、旧バージョンでは文字が入力できませんでした。

In English

In Search tab, Search string is now can editable.


The reproduction procedure of the problem:

1. Open the search tab
2. Choose the text box of a top "search string"
3. Input a letter

In 3. steppe, It was not able to input a letter in the old version.
----end----

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

284話 たいがとの接触
