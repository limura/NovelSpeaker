# AGENTS.md

このリポジトリでエージェント(Claude Code 等)が作業する際のルール・メモ。
ツール標準のファイル名として `AGENTS.md` に実体を置き、`CLAUDE.md` はこれを取り込むだけにする。

## コミット運用

- `git add` はパス指定で明示する。`git add -A` / `git add .` は使わない。
- `NovelSpeaker/UpdateMemo.txt` は、明示的な指示がない限りコミットに含めない。
  （リリース直前までユーザーが頻繁に書き換える作業ファイルのため）
- 未追跡の作業メモ（`TODO_*.md` など）や手元用スクリプト（`fetch_SiteInfo_tsv.sh` 等）はコミットに巻き込まない。
- コミットメッセージは日本語で書く。
- ブランチは普段どおり master に直接コミットする運用。

## clone した直後にすること

- **`scripts/fetch_voicevox_vendor.sh` を実行する。**
  VOICEVOX 関連の大きなバイナリ（XCFramework / Open JTalk 辞書 / テスト用の `0.vvm`、合わせて約200MB）は
  git に入れていないため、これを実行しないと VOICEVOX 周りがビルドできない。
  - VVM を git に入れないのは、入れると ことせかい が VVM の**再配布者**になるため。
    利用者には公式から直接取得してもらう方針（`DESIGN_VOICEVOXの音声モデル取得.md`）。
    同じ理由で **`0.vvm` はアプリ本体にも同梱していない**（テストターゲットにだけ入れてある）。
    アプリを入れた直後は音声モデルが1つも無いのが正しい状態。
  - 辞書と XCFramework は再配布可能だが、合計145MBあり GitHub の LFS 無料枠（1GB/月）を圧迫するため外した。
  - 配布物には手を入れないと使えない箇所が3つあり、スクリプトが自動で直す（消さないこと）:
    ヘッダの enum 宣言（Swift から列挙型として見えるようにする）、
    onnxruntime の `CFBundleIdentifier` のアンダースコア（バンドルIDに使えない）、
    そして書き換えで壊れた署名のアドホック署名での付け直し。
    最後のは、外すだけだとシミュレータが未署名 dylib を読まないため必要
    （onnxruntime は 1.23.2 から署名付きで配られるようになった）。
  - `--check` で手元と公式の差だけ調べられる。`0.vvm` が公式より古くなったらここで分かる。

## ビルド / テスト

- Xcode の **ワークスペース**を使う（`novelspeaker.xcworkspace`）。`.xcodeproj` 単体ではない。
- ビルド例:
  `xcodebuild -workspace novelspeaker.xcworkspace -scheme NovelSpeaker -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- 単体テストのスキームは `NovelSpeakerTests`（`NovelSpeaker` スキームはテストアクション未設定）。
  `-only-testing:NovelSpeakerTests/StoryFetcherTest` のように絞れる。
- `NovelSpeakerTests/DownloadTest.swift` の pixiv 系テストは pixiv.net への実ネットワークアクセスを伴う統合テストで、
  オフライン/CI 環境では落ちる（コード変更とは無関係なことが多い）。

## 設計メモ

- `StoryState.CreateNextState()` が `document` / 各ボタン(`nextButton` 等)を次状態に引き継ぐのは**意図的**。
  ボタン送り(ボタンをクリックしないと次ページに行けない)サイトのために必要（commit 4494851）。
  URL送りのサイトではデコード時に `transientDOMRetainedIfNeeded()` が既に document を捨てているため、
  引き継いでも実質 nil で、重いDOMは「ボタンが必要なときだけ」保持される。ここを安易に「破棄」に変えないこと。
