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
ダウンロード中のもも「本棚」に登録されますので、ダウンロードの終わったものを選択して、右上の「Speak」を選択することで読み上げを開始します。 

読み上げ開始位置を指定したい場合は、一旦読み上げを停止させて、読み上げを開始させたい位置を長押しして選択状態にしてから「Speak」ボタンを押すと良いです。

読み上げ速度などの変更方法： 
「設定」タブの「声質の設定」から通常時の読み上げ設定(声質と速度)、会話文の時の設定(声質のみ)が、 
「読みの修正」から「異世界」を「ことせかい」と読み上げさせないための設定ができます。 
ただ、「読みの修正」に大量に修正項目を設定すると読み上げ開始時に結構かなりいっぱい待たされるようになります。すみません。

* 英語
NovelSpeaker is application to read the shown novel which is "Let's become a novelist" aloud.
"listen" hears a novel when I do walking time and housework.
Because I cope with background reproduction, I can continue hearing a novel even when carrying out other activities with iPhone.


# キーワード

* 日本語
小説家になろう, 読み上げ, 小説

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
・読み上げ時に「……」や「、」「。」等でも読み上げの間をつけられるような設定項目を設定ページに追加しました。ただ、今までの手法で間を開かせると間が長すぎる感じでしたので、ちょっとあやしい方法での間を開けることもできるようにしました。「読上げ時の間の設定」ページの一番上の「読み上げの間の仕組み」の部分をタップして「非推奨型」にすると少し良くなる気がしますが、この手法は間を「_。_。_。」といった文字列を読み上げさせることで作っているので、将来のiOSのアップデートでうまく動かなくなる可能性があります。
・小説の詳細ページの作者名を押すと、その作者の小説を検索するようになります。
・小説を読むページにシェアボタンを追加しました。今読んでいるページへのURLやことせかいのアプリへのリンクなどをTwitterやmailでシェアすることができます。
・URLスキーム novelspeaker://downloadncode/ncode-ncode-ncode... という形式で、ncode を指定して小説をダウンロードさせる事ができるようになります。

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

# レビュー用メモ

修正項目以下の通りです。

Change of the interface

- I attached a button for the front and the movement to a later chapter with the screen which read a novel. By the right and left flick cannot move now.

Correction of the problem

- I revise the problem that the latest thing which I reloaded was not able to download.
- When I moved a chapter during background reproduction, I revise the problem that reproduction might stop.
- I revise the problem that the indication of the novel is fogged in a status bar and navigation bar, and it may not seem that it is displayed.
- I revise a reproduction start and the problem that I am replaced, and nothing sometimes reacts to for a long time of the chapter when I increase the setting of the reading substitute. (if the number increases, it becomes late)




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
