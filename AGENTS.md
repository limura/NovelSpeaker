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

## 既知のTODO（別途対応・コミット未追跡メモあり）

- `TODO_NFC正規化対応.md`: 本棚検索で濁点/半濁点タイトル(NFD)がヒットしない問題への対応。
