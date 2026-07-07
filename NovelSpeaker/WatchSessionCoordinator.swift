//
//  WatchSessionCoordinator.swift
//  NovelSpeaker
//
//  Apple Watch アプリとの WCSession 連携(iOS 側)。
//  - Watch からのコマンド受信 → StorySpeaker 等へ転送
//  - 再生状態・小説一覧を applicationContext で Watch へ送信
//  - 小説本文の転送(transferFile)
//

import Foundation
import WatchConnectivity
import RealmSwift

class WatchSessionCoordinator: NSObject {
    static let shared = WatchSessionCoordinator()

    private var isStarted = false
    /// 本文表示ページが Watch 側で表示されている間だけ true(購読制)
    private var isSpeechBlockSubscribed = false
    private var lastReadingPointSentDate = Date(timeIntervalSince1970: 0)
    private var lastContextPushDate = Date(timeIntervalSince1970: 0)
    private var contextPushScheduled = false

    /// applicationContext に載せる小説一覧の上限(サイズ制限対策)
    static let novelListLimit = 300

    private static let watchStoredNovelIDsKey = "WatchSessionCoordinator_WatchStoredNovelIDs"

    /// Watch 側に本文が転送されている小説の novelID 集合。
    /// Watch から applicationContext(Watch→iPhone 方向)で送られてきたものを保持している。
    /// 本棚の「Apple Watch転送状況別」フォルダ分類や検索絞り込みが O(1) 判定に使う
    static func WatchStoredNovelIDs() -> Set<String> {
        return Set(UserDefaults.standard.stringArray(forKey: watchStoredNovelIDsKey) ?? [])
    }

    /// Apple Watch とペアリングされているか(複数選択メニューの表示条件などに使う)
    static var isWatchPaired: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired
    }

    /// Watch へファイル転送が積める状態か(転送実行前の確認に使う)
    static var isWatchTransferReady: Bool {
        return isWatchPaired && WCSession.default.isWatchAppInstalled
    }

    /// 複数の小説をまとめて Watch へ転送する(本棚の複数選択操作用)。
    /// transferFile はキュー式なので順に積むだけでよい
    func TransferNovels(novelIDArray: [String]) {
        for novelID in novelIDArray {
            transferNovel(novelID: novelID)
        }
    }

    private override init() {
        super.init()
    }

    /// AppLaunchCoordinator.runPostLaunch() から呼ぶ
    func start() {
        guard WCSession.isSupported(), !isStarted else { return }
        isStarted = true
        WCSession.default.delegate = self
        WCSession.default.activate()
        StorySpeaker.shared.AddDelegate(delegate: self)
    }

    // MARK: - Watch への状態送信

    /// 現在の再生状態と小説一覧を applicationContext で送る。
    /// 高頻度で呼ばれても実際の送信は1秒に1回に抑える。
    func pushContextSoon() {
        DispatchQueue.main.async {
            if self.contextPushScheduled { return }
            let interval = Date().timeIntervalSince(self.lastContextPushDate)
            let delay = max(0, 1.0 - interval)
            self.contextPushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.contextPushScheduled = false
                self.lastContextPushDate = Date()
                self.pushContextNow()
            }
        }
    }

    private var lastContextFingerprint: Data? = nil
    private var contextPushCount = 0

    private func pushContextNow() {
        let session = WCSession.default
        // isWatchAppInstalled は開発時のインストール経路によっては false のままになるが、
        // sendMessage が通る状態なら updateApplicationContext も通ることが多いので条件にしない
        guard isStarted, session.activationState == .activated, session.isPaired else { return }
        var fullContext: [String: Any] = [:]
        fullContext[WatchMessage.Context.playState] = currentPlayState().toDictionary()
        let novelList = currentNovelList().map { $0.toDictionary() }
        fullContext[WatchMessage.Context.novelList] = novelList
        // 内容が前回送信時と同じなら送らない(Bluetooth 送信を減らして電池を守る)。
        // updatedAt は毎回変わるので比較から除外する。
        let fingerprint = WatchSessionCoordinator.fingerprint(of: fullContext)
        if fingerprint != nil && fingerprint == lastContextFingerprint { return }
        // applicationContext にはサイズ上限があるため、失敗したら小説一覧を減らして再試行する
        for limit in [novelList.count, 50, 10] {
            var context = fullContext
            if limit < novelList.count {
                context[WatchMessage.Context.novelList] = Array(novelList.prefix(limit))
            }
            context[WatchMessage.Context.sentAt] = Date().timeIntervalSince1970
            do {
                try session.updateApplicationContext(context)
                // 指紋は「送信に成功した時だけ」保存する。失敗時に保存すると
                // 以後同じ内容が dedup されて二度と送られなくなる
                lastContextFingerprint = fingerprint
                contextPushCount += 1
                if limit < novelList.count {
                    print("WatchSessionCoordinator: pushContext #\(contextPushCount) (小説一覧を\(limit)件に削減して送信)")
                } else {
                    print("WatchSessionCoordinator: pushContext #\(contextPushCount)")
                }
                return
            } catch {
                print("WatchSessionCoordinator: updateApplicationContext error (novelList=\(limit)件): \(error)")
            }
        }
    }

    /// 比較用の指紋。時刻など毎回変わるフィールドを除いた上で、キー順を安定させて比較する
    private static func fingerprint(of context: [String: Any]) -> Data? {
        var copy = context
        if var playState = copy[WatchMessage.Context.playState] as? [String: Any] {
            playState.removeValue(forKey: "updatedAt")
            copy[WatchMessage.Context.playState] = playState
        }
        return try? JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys])
    }

    private func currentPlayState() -> WatchPlayState {
        var state = WatchPlayState()
        state.updatedAt = Date()
        let storyID = StorySpeaker.shared.storyID
        guard !storyID.isEmpty else { return state }
        state.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        state.chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
        state.isPlaying = StorySpeaker.shared.isPlayng
        RealmUtil.RealmBlock { realm in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: state.novelID) {
                state.title = novel.title
                state.chapterCount = novel.lastChapterNumber ?? 0
            }
            if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) {
                let length = max(story.content.count, 1)
                state.progress = min(1.0, Double(StorySpeaker.shared.readLocation) / Double(length))
            }
        }
        return state
    }

    private func currentNovelList() -> [WatchNovelSummary] {
        return RealmUtil.RealmBlock { realm -> [WatchNovelSummary] in
            guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return [] }
            let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
            let sorted = novels.sorted(byKeyPath: "lastReadDate", ascending: false)
            var result: [WatchNovelSummary] = []
            for novel in sorted {
                if result.count >= WatchSessionCoordinator.novelListLimit { break }
                var summary = WatchNovelSummary()
                summary.novelID = novel.novelID
                summary.title = novel.title
                summary.chapterCount = novel.lastChapterNumber ?? 0
                summary.readingChapterNumber = novel.readingChapterNumber ?? 0
                summary.isLiked = (globalState?.calcLikeLevel(novelID: novel.novelID) ?? 0) > 0
                result.append(summary)
            }
            return result
        }
    }

    // MARK: - コマンド処理

    /// 実行前に StorySpeaker へ小説がセットされている必要があるコマンド
    private static let commandsNeedingStory: Set<WatchMessage.Command> = [
        .togglePlayPause, .skipBackward, .skipForward, .previousChapter, .nextChapter,
    ]

    private func handleCommand(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let commandString = message[WatchMessage.commandKey] as? String,
              let command = WatchMessage.Command(rawValue: commandString) else {
            replyHandler?([WatchMessage.Reply.ok: false, WatchMessage.Reply.errorMessage: "unknown command"])
            return
        }
        // checkNovelExistence だけは返信の形が特殊(missing リスト)なので独立して処理する
        if command == .checkNovelExistence {
            let novelIDs = message[WatchMessage.Arg.novelIDs] as? [String] ?? []
            DispatchQueue.main.async {
                let missing = RealmUtil.RealmBlock { realm -> [String] in
                    return novelIDs.filter { RealmNovel.SearchNovelWith(realm: realm, novelID: $0) == nil }
                }
                replyHandler?([
                    WatchMessage.Reply.ok: true,
                    WatchMessage.Reply.missingNovelIDs: missing,
                ])
            }
            return
        }
        DispatchQueue.main.async {
            let finish: ((ok: Bool, errorMessage: String?)) -> Void = { result in
                var reply: [String: Any] = [WatchMessage.Reply.ok: result.ok]
                if let errorMessage = result.errorMessage {
                    reply[WatchMessage.Reply.errorMessage] = errorMessage
                }
                reply[WatchMessage.Reply.playState] = self.currentPlayState().toDictionary()
                replyHandler?(reply)
                self.pushContextSoon()
                // 章移動やスキップの後は isSpeaking 等が落ち着くのに時間がかかるので、
                // 少し置いてからもう一度状態を送る
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.pushContextSoon()
                }
            }
            // WCSession の背面起動直後などで小説が未セットなら、前回読んでいた小説をセットしてから実行する
            if WatchSessionCoordinator.commandsNeedingStory.contains(command), StorySpeaker.shared.storyID.isEmpty {
                let story = RealmUtil.RealmBlock { realm -> Story? in
                    return RealmGlobalState.GetLastReadStory(realm: realm)
                }
                guard let story = story else {
                    finish((false, "小説が選ばれていません"))
                    return
                }
                StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { _ in
                    DispatchQueue.main.async {
                        self.executeCommand(command, message: message, completion: finish)
                    }
                }
                return
            }
            self.executeCommand(command, message: message, completion: finish)
        }
    }

    private func executeCommand(_ command: WatchMessage.Command, message: [String: Any], completion: @escaping ((ok: Bool, errorMessage: String?)) -> Void) {
        switch command {
        case .togglePlayPause:
            RealmUtil.RealmBlock { _ in StorySpeaker.shared.togglePlayPauseEvent() }
            completeAfterSettle(completion)
        case .skipBackward:
            if StorySpeaker.shared.isPlayng {
                RealmUtil.RealmBlock { _ in StorySpeaker.shared.skipBackwardEvent() }
                completeAfterSettle(completion)
            } else {
                completion(skipWhileStopped(length: -100))
            }
        case .skipForward:
            if StorySpeaker.shared.isPlayng {
                RealmUtil.RealmBlock { _ in StorySpeaker.shared.skipForwardEvent() }
                completeAfterSettle(completion)
            } else {
                completion(skipWhileStopped(length: 100))
            }
        case .previousChapter:
            moveChapter(isNext: false, completion: completion)
        case .nextChapter:
            moveChapter(isNext: true, completion: completion)
        case .openNovel:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String else {
                completion((false, "novelID がありません"))
                return
            }
            openNovel(novelID: novelID, completion: completion)
        case .checkUpdatesAll:
            let novelIDArray = RealmUtil.RealmBlock { realm -> [String] in
                guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return [] }
                return novels.map { $0.novelID }
            }
            NovelDownloadQueue.shared.addQueueArray(novelIDArray: novelIDArray)
            completion((true, nil))
        case .checkUpdates:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String else {
                completion((false, "novelID がありません"))
                return
            }
            NovelDownloadQueue.shared.addQueue(novelID: novelID)
            completion((true, nil))
        case .setLike:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String,
                  let enabled = message[WatchMessage.Arg.enabled] as? Bool else {
                completion((false, "引数が不正です"))
                return
            }
            completion(setLike(novelID: novelID, enabled: enabled))
        case .requestTransfer:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String else {
                completion((false, "novelID がありません"))
                return
            }
            // sendMessage は届いているのに isWatchAppInstalled が false になり
            // transferFile だけ WCErrorDomain 7006 で失敗する状態が観測されている
            // (Watch アプリを Xcode から直接インストールすると companion の関連付けが
            // 壊れてこうなることがある)。転送を積まずにエラーを返してスピナーを止めさせる。
            guard WCSession.default.isWatchAppInstalled else {
                completion((false, "Watchアプリが未インストール扱いになっています。Watch側のことせかいを一度削除して、iPhoneのWatchアプリの「利用可能なApp」からインストールし直すと直ることがあります。"))
                return
            }
            transferNovel(novelID: novelID)
            completion((true, nil))
        case .requestStatus:
            completion((true, nil))  // 返信とpushContextSoon()で状態が送られる
        case .checkNovelExistence:
            completion((true, nil))  // handleCommand で処理済み(ここには来ない)
        case .subscribeSpeechBlock:
            isSpeechBlockSubscribed = true
            completion((true, nil))
        case .unsubscribeSpeechBlock:
            isSpeechBlockSubscribed = false
            completion((true, nil))
        }
    }

    /// 停止中のスキップ。skipForwardEvent() 等は StopSpeech の completion が
    /// 発話中でないと呼ばれない作りのため停止中は機能しない。
    /// 停止中は「停止したまま読み上げ位置だけ動かす」(章は跨がず章内でクランプ)。
    private func skipWhileStopped(length: Int) -> (ok: Bool, errorMessage: String?) {
        let ok = RealmUtil.RealmBlock { realm -> Bool in
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID) else { return false }
            let contentLength = story.content.unicodeScalars.count
            let newLocation = min(max(0, StorySpeaker.shared.readLocation + length), max(0, contentLength - 1))
            StorySpeaker.shared.setReadLocationWith(realm: realm, location: newLocation)
            return true
        }
        return (ok, ok ? nil : "小説が選ばれていません")
    }

    /// 発話の開始/停止直後は isSpeaking がまだ切り替わっていないことがあるので、
    /// 少し待ってから返信を作らせる
    private func completeAfterSettle(_ completion: @escaping ((ok: Bool, errorMessage: String?)) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            completion((true, nil))
        }
    }

    /// Watch からの章移動。nextTrackEvent()/previousTrackEvent() と違い、
    /// 停止中なら停止のまま章だけ移動し、章読込完了後に completion を呼ぶ
    /// (返信に正しい章番号と再生状態を載せるため)
    private func moveChapter(isNext: Bool, completion: @escaping ((ok: Bool, errorMessage: String?)) -> Void) {
        let wasPlaying = StorySpeaker.shared.isPlayng
        let loadCompletion: (Bool) -> Void = { result in
            DispatchQueue.main.async {
                guard result else {
                    completion((false, isNext ? "次の章はありません" : "前の章はありません"))
                    return
                }
                if wasPlaying {
                    RealmUtil.RealmBlock { realm in
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "Watchからの章移動", isNeedRepeatSpeech: StorySpeaker.shared.isNeedRepeatSpeech)
                    }
                    self.completeAfterSettle(completion)
                } else {
                    completion((true, nil))
                }
            }
        }
        RealmUtil.RealmBlock { realm in
            StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: false)
            if isNext {
                StorySpeaker.shared.LoadNextChapter(realm: realm, completion: loadCompletion)
            } else {
                StorySpeaker.shared.LoadPreviousChapter(realm: realm, completion: loadCompletion)
            }
        }
    }

    private func openNovel(novelID: String, completion: @escaping ((ok: Bool, errorMessage: String?)) -> Void) {
        let story = RealmUtil.RealmBlock { realm -> Story? in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return nil }
            let chapterNumber = novel.readingChapterNumber ?? 1
            return RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber)
        }
        guard let story = story else {
            completion((false, "小説が見つかりません"))
            return
        }
        // SetStory は非同期で重い(章のブロック分割等)ので、完了してから返信を作らせる。
        // でないと返信に切替前の小説の状態が載ってしまう
        StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { _ in
            DispatchQueue.main.async {
                completion((true, nil))
            }
        }
    }

    private func setLike(novelID: String, enabled: Bool) -> (ok: Bool, errorMessage: String?) {
        RealmUtil.RealmBlock { realm in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            RealmUtil.WriteWith(realm: realm) { realm in
                if enabled {
                    if globalState.novelLikeOrder.index(of: novelID) == nil {
                        globalState.novelLikeOrder.append(novelID)
                    }
                } else {
                    if let index = globalState.novelLikeOrder.index(of: novelID) {
                        globalState.novelLikeOrder.remove(at: index)
                    }
                }
            }
        }
        return (true, nil)
    }

    // MARK: - 本文転送

    /// 小説の全章テキストを JSON にまとめて transferFile で Watch へ送る
    private func transferNovel(novelID: String) {
        DispatchQueue.global(qos: .utility).async {
            var payload: [String: Any] = ["novelID": novelID]
            var stories: [[String: Any]] = []
            RealmUtil.RealmBlock { realm in
                if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                    payload["title"] = novel.title
                }
                RealmStoryBulk.SearchAllStoryFor(realm: realm, novelID: novelID) { story in
                    stories.append([
                        "chapter": story.chapterNumber,
                        "subtitle": story.subtitle,
                        "content": story.content,
                    ])
                }
            }
            payload["stories"] = stories
            guard stories.count > 0,
                  let data = try? JSONSerialization.data(withJSONObject: payload) else {
                print("WatchSessionCoordinator: transferNovel payload 生成失敗 novelID=\(novelID)")
                return
            }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WatchTransfer-\(UUID().uuidString).json")
            do {
                try data.write(to: fileURL)
            } catch {
                print("WatchSessionCoordinator: transferNovel 一時ファイル書き込み失敗: \(error)")
                return
            }
            WCSession.default.transferFile(fileURL, metadata: [
                "novelID": novelID,
                "title": (payload["title"] as? String) ?? "",
            ])
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchSessionCoordinator: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            print("WatchSessionCoordinator: activated isPaired=\(session.isPaired) isWatchAppInstalled=\(session.isWatchAppInstalled) isReachable=\(session.isReachable)")
            // 完了しない転送が残っていると OS が再試行を繰り返して電池を消費するので観測しておく
            let outstanding = session.outstandingFileTransfers.count
            if outstanding > 0 {
                print("WatchSessionCoordinator: 未完了のファイル転送が \(outstanding) 件残っています")
            }
            pushContextSoon()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Apple Watch の切り替え時など。再アクティベートが作法
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleCommand(message: message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleCommand(message: message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Watch 側から「Watch に本文がある小説の一覧」が送られてくる
        if let storedNovelIDs = applicationContext[WatchMessage.Context.watchStoredNovelIDs] as? [String] {
            UserDefaults.standard.set(storedNovelIDs, forKey: WatchSessionCoordinator.watchStoredNovelIDsKey)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        if let error = error {
            print("WatchSessionCoordinator: transferFile 失敗: \(error)")
        }
    }
}

// MARK: - StorySpeakerDeletgate
extension WatchSessionCoordinator: StorySpeakerDeletgate {
    func storySpeakerStartSpeechEvent(storyID: String) {
        pushContextSoon()
    }

    func storySpeakerStopSpeechEvent(storyID: String) {
        pushContextSoon()
    }

    func storySpeakerUpdateReadingPoint(storyID: String, range: NSRange) {
        // 本文表示の購読中のみ、2秒に1回まで読み上げ位置を送る(v1.5 の本文ページ用)
        guard isSpeechBlockSubscribed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReadingPointSentDate) >= 2.0 else { return }
        lastReadingPointSentDate = now
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([
            "readingPoint": [
                "storyID": storyID,
                "location": range.location,
            ],
        ], replyHandler: nil, errorHandler: nil)
    }

    func storySpeakerStoryChanged(story: Story) {
        pushContextSoon()
    }
}
