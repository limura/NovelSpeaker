# 本文の長押しメニュー(編集メニュー)項目の選別

「設定タブ」→「本文中の長押しメニュー項目を減らす」の実装メモ。

## 背景と、以前の方式の限界

以前は `canPerformAction(_:withSender:)` でセレクタ名を見て弾く方式だった。
この方式は「こちらが知っているセレクタ名の項目しか制御できない」ため、
OS が新しい項目を増やすとそれを取りこぼす(消せない)という問題が残っていた。
実際 iOS 18 で追加された「作文ツール(`showWritingTools:`)」などは消せていなかった。

## iOS 16 以降で使える方式

iOS 16 以降は編集メニューが `UIMenuElement` のツリーとして取得できる。
末端は `UICommand` で、実行される `Selector` がそのまま読めるので、
セレクタ名を推測せずに **「残すと指定された物以外を全部落とす」** 形で選別できる。
この方式なら将来 OS が項目を増やしても自動的に消えるため、取りこぼしが原理的に無くなる。

| 表示部 | 使うフック |
| --- | --- |
| `SpeechViewController` の `UITextView` | `UITextViewDelegate.textView(_:editMenuForTextIn:suggestedActions:)` |
| `WebSpeechViewController` の `WKWebView` | `UIResponder.buildMenu(with:)`(`builder.system == .context`) |

`WKWebView` には `editMenuForTextIn` 相当の物が無いが、iOS 16 以降は長押しの編集メニューも
`UIMenuBuilder`(`.context` システム)経由で組み立てられており、レスポンダである
`WKWebView` の `buildMenu(with:)` にそのツリーが渡ってくる。
`builder.menu(for: .root)` から辿れるので、メニュー識別子を決め打ちで並べる必要も無い。

実装は `NovelSpeaker/EditMenuFilter.swift` に集約してある。

### iOS 15 について

デプロイメントターゲットが iOS 15.0 なので、iOS 15 では従来通り `canPerformAction` 経路で判定する。
判定自体は iOS 16 以降と同じ `MenuItemsNotRemovedType.selectorNames` を使うので結果は一致する
(ただし iOS 15 では「知らない項目」は元々消えるだけで、新規項目の取りこぼしは起きない)。

なお、同じメニュー項目でも `canPerformAction` に飛んでくるセレクタ名とメニューツリー中の
`UICommand` のセレクタ名が食い違う物がある(例: `canPerformAction` は `_share:` だが
ツリー中は `share:`)ため、`selectorNames` には両方の綴りを列挙してある。

## 実測した編集メニューのツリー

iPhone SE(3rd gen) / iOS 18.1 と iPhone 17 Pro Max / iOS 26.5 のシミュレータで実測。
**両者で完全に同一**だった。

```
UIMenu com.apple.menu.standard-edit
  UICommand cut:                                  Cut
  UICommand copy:                                 Copy
  UICommand paste:                                Paste
  UICommand delete:                               Delete
  UICommand select:                               Select
  UICommand selectAll:                            Select All
UIMenu com.apple.menu.replace
  UICommand promptForReplace:                     Replace…
  UICommand transliterateChinese:                 简⇄繁
  UICommand _insertDrawing:                       Insert Drawing
  UICommand showWritingTools:                     Writing Tools      ← iOS 18 で追加
  UIMenu com.apple.menu.autofill                  AutoFill
    UIMenu com.apple.menu.insert-from-external-sources  (空)
    UICommand captureTextFromCamera:              Scan Text
UIMenu com.apple.menu.open                        (空)
UIMenu com.apple.menu.format                      Format
  UIMenu com.apple.menu.text-style                Text Style
    UICommand toggleBoldface:                     Bold
    UICommand toggleItalics:                      Italic
    UICommand toggleUnderline:                    Underline
  UIMenu com.apple.menu.writing-direction         Writing Direction
    UICommand makeTextWritingDirectionRightToLeft:  Right to Left
    UICommand makeTextWritingDirectionLeftToRight:  Left to Right
  UICommand _showTextFormattingOptions:           More…
UIMenu com.apple.menu.lookup
  UICommand findSelected:                         Find Selection
  UICommand _define:                              Look Up
  UICommand _translate:                           Translate
UIMenu com.apple.menu.learn
  UICommand addShortcut:                          Learn…(ユーザ辞書)
UIMenu com.apple.command.speech                   Speech
  UICommand _accessibilitySpeak:                  Speak
  UICommand _accessibilitySpeakLanguageSelection: Speak…
  UICommand _accessibilityPauseSpeaking:          Pause
UIMenu com.apple.menu.share
  UICommand share:                                Share…
UIMenu com.apple.menu.dynamic.<UUID>              ← UIMenuController 由来の ことせかい 独自項目
  UICommand setSpeechModSettingWithSender:            読み替え辞書へ登録
  UICommand setSpeechModForThisNovelSettingWithSender: この小説用の読み替え辞書へ登録
  UICommand checkSpeechTextWithSender:                読み替え後の文字列を確認する
  UICommand selectAllTextWithSender:                  全てを選択する
```

補足:

- ことせかい の独自項目は `com.apple.menu.dynamic.<UUID>` という識別子のメニューに入って渡ってくる。
  UUID は毎回変わるので識別子では判別できないが、セレクタ名で判別できる。
- `buildMenu(with:)`(WKWebView 側)には、この dynamic メニューは渡ってこない。
  独自項目の表示可否は従来通り ViewController 側の `canPerformAction` が担当する。
- `suggestedActions` に残しても、最終的な表示可否は `canPerformAction` でも判定される
  (両方で許可されないと出ない)。そのため両経路で同じ判定を使うようにしてある。
- 「作文ツール」は Apple Intelligence が使えない端末では `canPerformAction` が false を返すため、
  設定で残す指定をしても表示されない。

## 設定UI

`MenuItemsNotRemovedType` は上記の末端項目を一通り持っていて(`allCases`)、
「残される長押しメニュー項目」の選択肢はここから生成している。
項目数が多いのでメニューのまとまりごとにセクション分けして表示する。

Realm に保存される rawValue は互換性のため、既存の物
(`copy` / `define` / `translate` / `addShortcut` / `share` / `selectAll`)を変更していない。
