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
    /// Watch で最後に再生した日時(novelID → Date)。キャッシュ整理の並び順に使う
    @Published var lastPlayedDates: [String: Date] = PhoneSessionManager.loadLastPlayedDates()
    /// iPhone 側の読み上げ位置(本文ページの購読中に届く)。表示文字ベースの位置
    @Published var phoneReadingPoint: PhoneReadingPoint?

    struct PhoneReadingPoint: Equatable {
        let novelID: String
        let chapter: Int
        let location: Int
    }

    private var didVerifyStoredNovels = false
    /// 本文ページが購読を望んでいるか(reachable 復帰時の再購読に使う)
    private var wantsReadingPointSubscription = false

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
                self.pushWatchContext()
            }
        }
    }

    /// Watch→iPhone 方向の applicationContext を送る。
    /// updateApplicationContext は「最新の1つだけが残る」方式なので、
    /// 転送済み一覧と読み上げ位置をまとめた全量を毎回作って送る(キー単位の差分更新はできない)
    func pushWatchContext() {
        guard WCSession.default.activationState == .activated else { return }
        var context: [String: Any] = [
            // iPhone 側の本棚(Apple Watch転送状況別・絞り込み)が参照する転送済み一覧
            WatchMessage.Context.watchStoredNovelIDs: Array(storedChapterCounts.keys),
        ]
        // Watch 単体再生の読み上げ位置(最新の1件)。iPhone 側はこれで栞を更新する
        if let latest = WatchReadingPositionStore.latest() {
            context[WatchMessage.Context.watchReadingPosition] = [
                "novelID": latest.novelID,
                "chapter": latest.position.chapter,
                "location": latest.position.location,
                "updatedAt": latest.position.updatedAt.timeIntervalSince1970,
            ]
        }
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("PhoneSessionManager: updateApplicationContext(Watch→iPhone) 失敗: \(error)")
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

    /// 返信辞書そのものが欲しい場合用(UI表示なし・リトライなし)。
    /// 失敗時は nil を返す。発話直前の設定同期(syncSpeechSettings)などが使う
    func sendForReply(_ command: WatchMessage.Command, args: [String: Any] = [:], completion: @escaping ([String: Any]?) -> Void) {
        var message: [String: Any] = args
        message[WatchMessage.commandKey] = command.rawValue
        WCSession.default.sendMessage(message, replyHandler: { reply in
            completion(reply)
        }, errorHandler: { error in
            print("PhoneSessionManager: sendForReply(\(command.rawValue)) 失敗: \(error)")
            completion(nil)
        })
    }

    /// 本文ページの表示中だけ iPhone の読み上げ位置(readingPoint)の購読を ON にする。
    /// 手首を下ろす等で unreachable になった場合は iPhone 側が自動で購読を解除するので、
    /// reachable 復帰時にはこちらから購読し直す(sessionReachabilityDidChange 参照)
    func setReadingPointSubscription(_ wants: Bool) {
        guard wants != wantsReadingPointSubscription else { return }
        wantsReadingPointSubscription = wants
        guard WCSession.default.activationState == .activated else { return }
        send(wants ? .subscribeSpeechBlock : .unsubscribeSpeechBlock, quiet: true)
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
        // 転送依頼は通ったのにファイルが届かない場合(iPhone側の転送失敗等)に
        // スピナーが回りっぱなしにならないよう、5分で依頼中表示を諦める
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            self.transferRequestedNovelIDs.remove(novelID)
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
            // セッション中に一度だけ、本棚から消えた小説の孤児キャッシュを掃除する
            if !self.didVerifyStoredNovels, WCSession.default.isReachable {
                self.didVerifyStoredNovels = true
                self.verifyStoredNovelsAgainstBookshelf()
            }
        }
    }

    /// 返信と applicationContext が前後しても、iPhone 側での生成時刻が新しい方だけを採用する
    private func applyPlayStateIfNewer(_ state: WatchPlayState) {
        if playState == nil || state.updatedAt >= (playState?.updatedAt ?? Date(timeIntervalSince1970: 0)) {
            playState = state
            if state.isPlaying {
                recordLastPlayed(novelID: state.novelID)
            }
        }
    }

    // MARK: - 最終再生日時の記録(キャッシュ整理用)

    private static let lastPlayedDatesKey = "NovelLastPlayedDates"

    private static func loadLastPlayedDates() -> [String: Date] {
        guard let raw = UserDefaults.standard.dictionary(forKey: lastPlayedDatesKey) as? [String: Double] else { return [:] }
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Watch 単体再生(WatchSpeechPlayer)からも記録するので private にしない
    func recordLastPlayed(novelID: String) {
        guard !novelID.isEmpty else { return }
        // 高頻度で来るので、1時間単位でしか更新しない(UserDefaults 書き込みの節約)
        if let last = lastPlayedDates[novelID], Date().timeIntervalSince(last) < 3600 { return }
        lastPlayedDates[novelID] = Date()
        UserDefaults.standard.set(lastPlayedDates.mapValues { $0.timeIntervalSince1970 },
                                  forKey: PhoneSessionManager.lastPlayedDatesKey)
    }

    // MARK: - 孤児キャッシュの掃除

    /// Watch に本文がある小説が iPhone の本棚から削除されていないか確認し、
    /// 削除されていたらキャッシュも消す(本棚から消した=意思表示済みなので自動でよい)。
    /// 小説一覧は件数制限付きで送られてくるため「一覧に居ない」では判定できず、明示的に問い合わせる。
    func verifyStoredNovelsAgainstBookshelf() {
        let novelIDs = Array(storedNovelIDs)
        guard !novelIDs.isEmpty, WCSession.default.isReachable else { return }
        var message: [String: Any] = [WatchMessage.commandKey: WatchMessage.Command.checkNovelExistence.rawValue]
        message[WatchMessage.Arg.novelIDs] = novelIDs
        WCSession.default.sendMessage(message, replyHandler: { reply in
            guard let missing = reply[WatchMessage.Reply.missingNovelIDs] as? [String], !missing.isEmpty else { return }
            for novelID in missing {
                NovelStorage.remove(novelID: novelID)
            }
            self.refreshStoredNovels()
        }, errorHandler: nil)
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
        requestStatusIfNovelUnknown()
    }

    /// 小説が未選択(前回の applicationContext も無い)のに iPhone と繋がっているなら、
    /// iPhone に現在の状態(=最後に読んでいた小説)を教えてもらう。
    /// デバッグ実行での再インストール等で受信済み context が消えた直後の「初回未選択」対策。
    private func requestStatusIfNovelUnknown() {
        guard playState?.novelID.isEmpty != false, WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        send(.requestStatus, quiet: true)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            // unreachable の間に iPhone 側で自動解除された購読を購読し直す
            if session.isReachable && self.wantsReadingPointSubscription {
                self.send(.subscribeSpeechBlock, quiet: true)
            }
            // 繋がったタイミングで小説が未選択なら状態を聞く
            self.requestStatusIfNovelUnknown()
        }
    }

    /// iPhone からの片方向プッシュ(replyHandler なしの sendMessage)。
    /// 現状は本文ページ購読中の読み上げ位置(readingPoint)のみ
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let point = message[WatchMessage.Push.readingPoint] as? [String: Any],
              let novelID = point["novelID"] as? String,
              let chapter = point["chapter"] as? Int,
              let location = point["location"] as? Int else { return }
        DispatchQueue.main.async {
            self.phoneReadingPoint = PhoneReadingPoint(novelID: novelID, chapter: chapter, location: location)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Watch 単体再生用の発話設定ファイル
        if (file.metadata?[WatchSpeechSettings.transferTypeKey] as? String) == WatchSpeechSettings.transferTypeValue {
            do {
                try WatchSpeechSettingsStorage.store(
                    receivedFileURL: file.fileURL,
                    fingerprint: file.metadata?[WatchSpeechSettings.transferFingerprintKey] as? String)
                print("PhoneSessionManager: 発話設定を受信・保存")
                // 停止中なら現在の章を新しい設定で組み直す(再生中は次の章から反映)
                WatchSpeechPlayer.shared.applyReceivedSettingsIfIdle()
            } catch {
                print("PhoneSessionManager: 発話設定の保存に失敗: \(error)")
            }
            return
        }
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
