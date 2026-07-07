//
//  PhoneSessionManager.swift
//  NovelSpeakerWatch
//
//  iPhone 側 ことせかい との WCSession 通信(Watch 側)。
//  - コマンド送信(接続中表示・タイムアウト・エラーの管理込み)
//  - applicationContext(再生状態・小説一覧)の受信
//  - 本文ファイル(transferFile)の受信と保存
//

import Foundation
import WatchConnectivity
import Combine

final class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    @Published var playState: WatchPlayState?
    @Published var novels: [WatchNovelSummary] = []
    @Published var isReachable = false
    @Published var isActivated = false
    /// コマンド送信中(「接続中…」表示用)。iPhone 側がコールドスタートだと6〜7秒かかることがある
    @Published var isSending = false
    @Published var lastErrorMessage: String?
    /// 本文を受信済みの小説ID
    @Published var storedNovelIDs: Set<String> = []
    /// 受信済み本文の章数(novelID → 章数)。メタデータの章数と比較して「転送が古い」判定に使う
    @Published var storedChapterCounts: [String: Int] = [:]
    /// 受信済み本文のタイトル(novelID → タイトル)。キャッシュ管理画面用
    @Published var storedTitles: [String: String] = [:]
    /// 特急転送を依頼中の小説ID(受信完了で消える)
    @Published var transferRequestedNovelIDs: Set<String> = []

    private override init() {
        super.init()
        refreshStoredNovels()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func refreshStoredNovels() {
        DispatchQueue.global(qos: .utility).async {
            var counts: [String: Int] = [:]
            var titles: [String: String] = [:]
            for novelID in NovelStorage.storedNovelIDs() {
                if let novel = NovelStorage.loadNovel(novelID: novelID) {
                    counts[novelID] = novel.stories.count
                    titles[novelID] = novel.title
                } else {
                    counts[novelID] = 0
                }
            }
            DispatchQueue.main.async {
                self.storedChapterCounts = counts
                self.storedTitles = titles
                self.storedNovelIDs = Set(counts.keys)
            }
        }
    }

    func removeStoredNovel(novelID: String) {
        NovelStorage.remove(novelID: novelID)
        refreshStoredNovels()
    }

    /// 転送済みの小説が iPhone 側で更新されて古くなっていたら、自動で転送し直しを依頼する。
    /// 「Watchに転送済み = 自動同期ON」というモデル(削除すれば同期も止まる)。
    private func autoRefreshStaleStoredNovels() {
        guard WCSession.default.isReachable else { return }
        for novel in novels {
            guard let storedCount = storedChapterCounts[novel.novelID],
                  novel.chapterCount > storedCount,
                  !transferRequestedNovelIDs.contains(novel.novelID) else { continue }
            requestTransfer(novelID: novel.novelID, quiet: true)
        }
    }

    // MARK: - コマンド送信

    /// quiet: バックグラウンド用途(自動再転送等)では「接続中…」やエラーを UI に出さない
    func send(_ command: WatchMessage.Command, args: [String: Any] = [:], quiet: Bool = false, completion: ((Bool) -> Void)? = nil) {
        if !quiet {
            DispatchQueue.main.async {
                self.isSending = true
                self.lastErrorMessage = nil
            }
        }
        sendOnce(command, args: args, quiet: quiet, retriesLeft: 1, completion: completion)
    }

    /// 未接続状態からの1回目の sendMessage は「接続の起動」に化けて失敗しがちなので、
    /// 少し待って1回だけ再送する
    private func sendOnce(_ command: WatchMessage.Command, args: [String: Any], quiet: Bool, retriesLeft: Int, completion: ((Bool) -> Void)?) {
        var message: [String: Any] = args
        message[WatchMessage.commandKey] = command.rawValue
        WCSession.default.sendMessage(message, replyHandler: { reply in
            DispatchQueue.main.async {
                if !quiet {
                    self.isSending = false
                }
                if let stateDictionary = reply[WatchMessage.Reply.playState] as? [String: Any],
                   let state = WatchPlayState.from(dictionary: stateDictionary) {
                    self.applyPlayStateIfNewer(state)
                }
                let ok = reply[WatchMessage.Reply.ok] as? Bool ?? false
                if !ok && !quiet {
                    self.lastErrorMessage = reply[WatchMessage.Reply.errorMessage] as? String ?? "操作に失敗しました"
                }
                completion?(ok)
            }
        }, errorHandler: { error in
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.sendOnce(command, args: args, quiet: quiet, retriesLeft: retriesLeft - 1, completion: completion)
                }
                return
            }
            DispatchQueue.main.async {
                if !quiet {
                    self.isSending = false
                    self.lastErrorMessage = "iPhoneと通信できません。iPhoneを再起動した後は、一度ロック解除が必要です。"
                }
                completion?(false)
            }
        })
    }

    /// quiet: 自動再転送などバックグラウンド用途では「接続中…」表示やエラー表示を出さない
    func requestTransfer(novelID: String, quiet: Bool = false) {
        DispatchQueue.main.async {
            self.transferRequestedNovelIDs.insert(novelID)
        }
        send(.requestTransfer, args: [WatchMessage.Arg.novelID: novelID], quiet: quiet) { ok in
            if !ok {
                self.transferRequestedNovelIDs.remove(novelID)
            }
        }
    }

    // MARK: - 受信データの反映

    private func applyContext(_ context: [String: Any]) {
        let state: WatchPlayState?
        if let stateDictionary = context[WatchMessage.Context.playState] as? [String: Any] {
            state = WatchPlayState.from(dictionary: stateDictionary)
        } else {
            state = nil
        }
        let novelList: [WatchNovelSummary]
        if let listArray = context[WatchMessage.Context.novelList] as? [[String: Any]] {
            novelList = listArray.compactMap { WatchNovelSummary.from(dictionary: $0) }
        } else {
            novelList = []
        }
        DispatchQueue.main.async {
            if let state = state, !state.novelID.isEmpty {
                self.applyPlayStateIfNewer(state)
            }
            if !novelList.isEmpty {
                self.novels = novelList
            }
            self.autoRefreshStaleStoredNovels()
        }
    }

    /// 返信と applicationContext が前後しても、iPhone 側での生成時刻が新しい方だけを採用する
    private func applyPlayStateIfNewer(_ state: WatchPlayState) {
        if playState == nil || state.updatedAt >= (playState?.updatedAt ?? Date(timeIntervalSince1970: 0)) {
            playState = state
        }
    }
}

// MARK: - WCSessionDelegate
extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isActivated = (activationState == .activated)
            self.isReachable = session.isReachable
        }
        // 前回 iPhone 側が送った applicationContext は再起動後も残っているので初期表示に使う
        applyContext(session.receivedApplicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let novelID = file.metadata?["novelID"] as? String else { return }
        do {
            try NovelStorage.store(fileURL: file.fileURL, novelID: novelID)
            DispatchQueue.main.async {
                self.transferRequestedNovelIDs.remove(novelID)
            }
            refreshStoredNovels()
        } catch {
            DispatchQueue.main.async {
                self.lastErrorMessage = "本文の保存に失敗しました: \(error.localizedDescription)"
                self.transferRequestedNovelIDs.remove(novelID)
            }
        }
    }
}

/// 受信した小説本文(JSON)の保存と読み出し
enum NovelStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Novels", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func fileURL(novelID: String) -> URL {
        // novelID は URL 文字列なのでファイル名に使えるようエンコードする
        let name = novelID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? novelID
        return directory.appendingPathComponent("\(name).json")
    }

    static func storedNovelIDs() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0.deletingPathExtension().lastPathComponent.removingPercentEncoding }
    }

    static func store(fileURL: URL, novelID: String) throws {
        let destination = self.fileURL(novelID: novelID)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: fileURL, to: destination)
    }

    struct StoredChapter {
        let subtitle: String
        let content: String
    }

    /// 章番号 → 章タイトル・本文 の辞書として読み出す
    static func loadNovel(novelID: String) -> (title: String, stories: [Int: StoredChapter])? {
        guard let data = try? Data(contentsOf: fileURL(novelID: novelID)),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let storyArray = payload["stories"] as? [[String: Any]] else { return nil }
        var stories: [Int: StoredChapter] = [:]
        for storyDictionary in storyArray {
            if let chapter = storyDictionary["chapter"] as? Int,
               let content = storyDictionary["content"] as? String {
                stories[chapter] = StoredChapter(
                    subtitle: storyDictionary["subtitle"] as? String ?? "",
                    content: content
                )
            }
        }
        return (payload["title"] as? String ?? "", stories)
    }

    static func remove(novelID: String) {
        try? FileManager.default.removeItem(at: fileURL(novelID: novelID))
    }
}
