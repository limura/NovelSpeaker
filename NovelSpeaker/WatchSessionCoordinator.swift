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
import CryptoKit
import UIKit
import AVFoundation

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
        transferSpeechSettingsIfNeeded()
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
        // サスペンド中に Watch から届いた applicationContext は delegate が呼ばれないまま
        // 受信済みプロパティにだけ入っていることがあるので、フォアグラウンド復帰時に必ず処理する
        // (updatedAt のガードがあるので何度呼んでも冪等)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let session = WCSession.default
            guard session.activationState == .activated else { return }
            let received = session.receivedApplicationContext
            if !received.isEmpty {
                self.session(session, didReceiveApplicationContext: received)
            }
        }
        // 「iPhone側で発話設定を変える → iPhoneをしまう → Watchで再生」という典型フローで
        // Watch 側の発話直前同期(最大2秒待ち)を待たずに済むよう、バックグラウンドに入る時に
        // 設定の変更があれば先回りで送っておく(変更が無ければ指紋が一致して何も送らない)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.transferSpeechSettingsIfNeeded()
        }
    }

    // MARK: - Watch への状態送信

    /// 現在の再生状態と小説一覧を applicationContext で送る。
    /// 高頻度で呼ばれても実際の送信は1秒に1回に抑える。
    /// force: 内容が前回と同じでも必ず送る。Watch が requestStatus で「状態が欲しい」と
    /// 言ってきた時に使う(Watch を再インストールすると受信済み context が消えるが、
    /// iPhone 側の指紋は残っているので、通常の重複抑止だと二度と送られなくなるため)
    func pushContextSoon(force: Bool = false) {
        DispatchQueue.main.async {
            if force { self.forceNextContextPush = true }
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
    private var forceNextContextPush = false

    private func pushContextNow() {
        let session = WCSession.default
        // isWatchAppInstalled は開発時のインストール経路によっては false のままになるが、
        // sendMessage が通る状態なら updateApplicationContext も通ることが多いので条件にしない
        guard isStarted, session.activationState == .activated, session.isPaired else { return }
        let force = forceNextContextPush
        forceNextContextPush = false
        var fullContext: [String: Any] = [:]
        fullContext[WatchMessage.Context.playState] = currentPlayState().toDictionary()
        let novelList = currentNovelList().map { $0.toDictionary() }
        fullContext[WatchMessage.Context.novelList] = novelList
        // 内容が前回送信時と同じなら送らない(Bluetooth 送信を減らして電池を守る)。
        // updatedAt は毎回変わるので比較から除外する。force 指定時はこの抑止を飛ばす。
        let fingerprint = WatchSessionCoordinator.fingerprint(of: fullContext)
        if !force && fingerprint != nil && fingerprint == lastContextFingerprint { return }
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
        // StorySpeaker にまだ小説がセットされていない(アプリ起動直後など)場合でも、
        // Watch 側が「初回は未選択」にならないよう、iPhone が最後に読んでいた小説を報告する。
        // その場合は発話コアには触れず(isPlaying=false)、栞の位置だけを進捗として載せる。
        if storyID.isEmpty {
            RealmUtil.RealmBlock { realm in
                guard let story = RealmGlobalState.GetLastReadStory(realm: realm) else { return }
                state.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: story.storyID)
                state.chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: story.storyID)
                state.chapterSubtitle = story.subtitle
                if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: state.novelID) {
                    state.title = novel.title
                    state.chapterCount = novel.lastChapterNumber ?? 0
                    let length = max(story.content.count, 1)
                    state.progress = min(1.0, Double(novel.m_readingChapterReadingPoint) / Double(length))
                    state.readingLocation = novel.m_readingChapterReadingPoint
                    state.bookmarkUpdatedAt = novel.lastReadDate
                }
            }
            return state
        }
        state.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        state.chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
        state.isPlaying = StorySpeaker.shared.isPlayng
        RealmUtil.RealmBlock { realm in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: state.novelID) {
                state.title = novel.title
                state.chapterCount = novel.lastChapterNumber ?? 0
                state.bookmarkUpdatedAt = novel.lastReadDate
            }
            if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) {
                state.chapterSubtitle = story.subtitle
                let length = max(story.content.count, 1)
                state.progress = min(1.0, Double(StorySpeaker.shared.readLocation) / Double(length))
            }
        }
        state.readingLocation = StorySpeaker.shared.readLocation
        return state
    }

    private func currentNovelList() -> [WatchNovelSummary] {
        return RealmUtil.RealmBlock { realm -> [WatchNovelSummary] in
            guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return [] }
            let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
            let sorted = WatchSessionCoordinator.sortNovelsForWatch(
                novels: novels,
                sortType: globalState?.bookShelfSortType ?? .LastReadDate,
                globalState: globalState)
            var result: [WatchNovelSummary] = []
            for novel in sorted {
                if result.count >= WatchSessionCoordinator.novelListLimit { break }
                var summary = WatchNovelSummary()
                summary.novelID = novel.novelID
                summary.title = novel.title
                summary.chapterCount = novel.lastChapterNumber ?? 0
                summary.readingChapterNumber = novel.readingChapterNumber ?? 0
                summary.isLiked = (globalState?.calcLikeLevel(novelID: novel.novelID) ?? 0) > 0
                summary.writer = novel.writer
                result.append(summary)
            }
            return result
        }
    }

    /// Watch の本棚に載せる並び順。iPhone の本棚の並び順設定(bookShelfSortType)に追従する。
    /// フォルダ分け系の並び順は Watch では平坦なリストにしか出せないので、
    /// 「iPhone のフォルダ内と同じ整列キー」で平坦に並べた近似にする
    /// (整列キーの昇順/降順は BookShelfTreeViewController.getNovelArray と揃えること)
    private static func sortNovelsForWatch(novels: Results<RealmNovel>, sortType: NarouContentSortType, globalState: RealmGlobalState?) -> [RealmNovel] {
        switch sortType {
        case .Ncode:
            return Array(novels.sorted(byKeyPath: "novelID", ascending: true))
        case .WebSite:
            // iPhone ではサイト別フォルダ分け。novelID は URL なので昇順で並べると同一サイトが固まる
            return Array(novels.sorted(byKeyPath: "novelID", ascending: true))
        case .NovelUpdatedAt, .NovelUpdatedAtWithFolder:
            return Array(novels.sorted(byKeyPath: "lastDownloadDate", ascending: false))
        case .Writer:
            return Array(novels.sorted(byKeyPath: "writer", ascending: false))
        case .LikeLevel:
            var likeLevelMap: [String: Int] = [:]
            if let globalState = globalState {
                let likeCount = globalState.novelLikeOrder.count
                for (index, novelID) in globalState.novelLikeOrder.enumerated() {
                    likeLevelMap[novelID] = likeCount - index
                }
            }
            return novels.sorted { likeLevelMap[$0.novelID] ?? 0 > likeLevelMap[$1.novelID] ?? 0 }
        case .CreatedDate:
            return Array(novels.sorted(byKeyPath: "createdDate", ascending: false))
        case .PageCount:
            return novels.sorted { a, b in
                let aCount = RealmStoryBulk.StoryIDToChapterNumber(storyID: a.m_lastChapterStoryID)
                let bCount = RealmStoryBulk.StoryIDToChapterNumber(storyID: b.m_lastChapterStoryID)
                return aCount < bCount
            }
        case .UnreadChapterCount:
            return novels.map { ($0, BookShelfTreeViewController.unreadChapterCount(novel: $0)) }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        case .Title, .SelfCreatedFolder, .KeywordTag:
            return Array(novels.sorted(byKeyPath: "title", ascending: false))
        case .LastReadDate, .LastReadDateWithFolder, .AppleWatchTransferState:
            return Array(novels.sorted(byKeyPath: "lastReadDate", ascending: false))
        @unknown default:
            return Array(novels.sorted(byKeyPath: "lastReadDate", ascending: false))
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
            replyHandler?([WatchMessage.Reply.ok: false, WatchMessage.Reply.errorMessage: NSLocalizedString("WatchSessionCoordinator_ErrorUnknownCommand", comment: "対応していない操作です。iPhone側の ことせかい が古い可能性があります。")])
            return
        }
        // syncSpeechSettings は返信の形が特殊(settingsUpToDate)なので独立して処理する。
        // Watch が発話直前に「手元の発話設定の指紋」を送ってくるので、最新なら即返信、
        // 古ければ transferFile を積んでから返信する(Watch 側はファイル到着を少しだけ待つ)
        if command == .syncSpeechSettings {
            let watchFingerprint = message[WatchMessage.Arg.fingerprint] as? String ?? ""
            DispatchQueue.global(qos: .userInitiated).async {
                guard let encoded = self.encodeSpeechSettings() else {
                    replyHandler?([WatchMessage.Reply.ok: false, WatchMessage.Reply.errorMessage: NSLocalizedString("WatchSessionCoordinator_ErrorSpeechSettingsEncodeFailed", comment: "発話設定の生成に失敗しました")])
                    return
                }
                let upToDate = (encoded.fingerprint == watchFingerprint)
                if !upToDate {
                    self.enqueueSpeechSettingsTransfer(data: encoded.data, fingerprint: encoded.fingerprint)
                }
                replyHandler?([
                    WatchMessage.Reply.ok: true,
                    WatchMessage.Reply.speechSettingsUpToDate: upToDate,
                ])
            }
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
                    finish((false, NSLocalizedString("WatchSessionCoordinator_ErrorNoNovelSelected", comment: "小説が選ばれていません")))
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
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorNovelIDMissing", comment: "novelID がありません")))
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
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorNovelIDMissing", comment: "novelID がありません")))
                return
            }
            NovelDownloadQueue.shared.addQueue(novelID: novelID)
            completion((true, nil))
        case .setLike:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String,
                  let enabled = message[WatchMessage.Arg.enabled] as? Bool else {
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorInvalidArguments", comment: "引数が不正です")))
                return
            }
            completion(setLike(novelID: novelID, enabled: enabled))
        case .requestTransfer:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String else {
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorNovelIDMissing", comment: "novelID がありません")))
                return
            }
            // sendMessage は届いているのに isWatchAppInstalled が false になり
            // transferFile だけ WCErrorDomain 7006 で失敗する状態が観測されている
            // (Watch アプリを Xcode から直接インストールすると companion の関連付けが
            // 壊れてこうなることがある)。転送を積まずにエラーを返してスピナーを止めさせる。
            guard WCSession.default.isWatchAppInstalled else {
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorWatchAppNotInstalled", comment: "Watchアプリが未インストール扱いになっています。Watch側の ことせかい を一度削除して、iPhoneのWatchアプリの「利用可能なApp」からインストールし直すと直ることがあります。")))
                return
            }
            transferNovel(novelID: novelID)
            // Watch 単体再生用の発話設定も(変わっていれば)一緒に送っておく
            transferSpeechSettingsIfNeeded()
            completion((true, nil))
        case .requestStatus:
            // Watch アプリが開かれたタイミングなので、発話設定の変更もここで拾って送る
            transferSpeechSettingsIfNeeded()
            // Watch は「状態が無いから欲しい」と言ってきている。再インストール直後などは内容が
            // 前回と同じでも Watch 側は空なので、重複抑止を飛ばして必ず小説一覧を送る
            pushContextSoon(force: true)
            completion((true, nil))  // 返信とpushContextSoon()で状態が送られる
        case .checkNovelExistence, .syncSpeechSettings:
            completion((true, nil))  // handleCommand で処理済み(ここには来ない)
        case .setDefaultSpeakerConfig:
            guard let rate = message[WatchMessage.Arg.rate] as? Double,
                  let volume = message[WatchMessage.Arg.volume] as? Double else {
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorInvalidArguments", comment: "引数が不正です")))
                return
            }
            let clampedRate = min(max(Float(rate), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
            let clampedVolume = min(max(Float(volume), 0.0), 1.0)
            RealmUtil.RealmBlock { realm in
                guard let speakerSetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) else { return }
                RealmUtil.WriteWith(realm: realm) { _ in
                    speakerSetting.rate = clampedRate
                    speakerSetting.volume = clampedVolume
                }
            }
            // 発話中なら次のブロックから反映させる(保存だけだと次の再生開始まで反映されない)
            StorySpeaker.shared.applyLiveDefaultSpeakerConfig(rate: clampedRate, volume: clampedVolume)
            // アナウンス音声(「次の章はありません」等)も新しい速度・音量に合わせる
            StorySpeaker.shared.ApplyDefaultSpeakerSettingToAnnounceSpeaker()
            // Watch 単体再生用の設定ファイルも新しい値で送り直す(指紋が変わるので実際に送られる)
            transferSpeechSettingsIfNeeded()
            completion((true, nil))
        case .subscribeSpeechBlock:
            isSpeechBlockSubscribed = true
            // 購読直後は次のブロック境界を待たずに現在位置を即送る(本文ページのハイライト初期表示用)
            lastReadingPointSentDate = Date(timeIntervalSince1970: 0)
            let storyID = StorySpeaker.shared.storyID
            if !storyID.isEmpty {
                sendReadingPoint(storyID: storyID, location: StorySpeaker.shared.readLocation)
            }
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
        return (ok, ok ? nil : NSLocalizedString("WatchSessionCoordinator_ErrorNoNovelSelected", comment: "小説が選ばれていません"))
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
                    completion((false, isNext
                        ? NSLocalizedString("WatchSessionCoordinator_ErrorNoNextChapter", comment: "次の章はありません")
                        : NSLocalizedString("WatchSessionCoordinator_ErrorNoPreviousChapter", comment: "前の章はありません")))
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
            completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorNovelNotFound", comment: "小説が見つかりません")))
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

    // MARK: - 発話設定の転送(Watch 単体再生用)

    private static let lastSpeechSettingsFingerprintKey = "WatchSessionCoordinator_LastSpeechSettingsFingerprint"

    /// Watch 単体再生用の発話設定を transferFile で送る。内容が前回送信時と同じなら送らない。
    /// 呼び出しは activation 時と Watch からの requestStatus / requestTransfer 時
    /// (= Watch アプリを開いた・転送を頼んだ時)に限られるので、Realm 全読みのコストは許容範囲。
    func transferSpeechSettingsIfNeeded() {
        let session = WCSession.default
        guard isStarted, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let encoded = self.encodeSpeechSettings() else { return }
            if UserDefaults.standard.string(forKey: WatchSessionCoordinator.lastSpeechSettingsFingerprintKey) == encoded.fingerprint { return }
            self.enqueueSpeechSettingsTransfer(data: encoded.data, fingerprint: encoded.fingerprint)
        }
    }

    /// 現在の発話設定を JSON に変換して指紋付きで返す(重いので background queue で呼ぶこと)
    private func encodeSpeechSettings() -> (fingerprint: String, data: Data)? {
        var settings = buildSpeechSettings()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // 指紋は毎回変わる updatedAt を除いて(固定して)計算する
        settings.updatedAt = Date(timeIntervalSince1970: 0)
        guard let fingerprintSource = try? encoder.encode(settings) else { return nil }
        let fingerprint = SHA256.hash(data: fingerprintSource).map { String(format: "%02x", $0) }.joined()
        settings.updatedAt = Date()
        guard let data = try? encoder.encode(settings) else { return nil }
        return (fingerprint, data)
    }

    private func enqueueSpeechSettingsTransfer(data: Data, fingerprint: String) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchSpeechSettings-\(UUID().uuidString).json")
        do {
            try data.write(to: fileURL)
        } catch {
            print("WatchSessionCoordinator: 発話設定の一時ファイル書き込み失敗: \(error)")
            return
        }
        WCSession.default.transferFile(fileURL, metadata: [
            WatchSpeechSettings.transferTypeKey: WatchSpeechSettings.transferTypeValue,
            WatchSpeechSettings.transferFingerprintKey: fingerprint,
        ])
        // transferFile はキュー式で OS が再試行してくれるので、積めた時点で送信済み扱いにする。
        // 転送がエラーで終わった場合は didFinish 側で指紋を消して次回再送させる
        UserDefaults.standard.set(fingerprint, forKey: WatchSessionCoordinator.lastSpeechSettingsFingerprintKey)
        print("WatchSessionCoordinator: 発話設定を転送キューに追加 (\(data.count) bytes)")
    }

    /// Realm 上の発話設定を WatchSpeechSettings に変換する。
    /// v1.5 は「全小説対象(anyTarget)のグローバル設定のみ」(小説別の話者・読み替えは未対応)。
    private func buildSpeechSettings() -> WatchSpeechSettings {
        // SearchSettingsFor は「anyTarget + 指定 novelID」を返すので、
        // 存在しない novelID を渡して anyTarget(全小説対象)の設定だけを拾う
        let globalOnlyNovelID = "novelspeakerdata://watch-global-settings"
        return RealmUtil.RealmBlock { realm -> WatchSpeechSettings in
            var settings = WatchSpeechSettings()
            func convertSpeaker(_ speaker: RealmSpeakerSetting) -> WatchSpeechSettings.Speaker {
                // VOICEVOX は Watch では動かないので既定の AVSpeechSynthesizer 話者に読み替える
                // (rate 等の値もエンジン毎にスケールが違うので引き継がない)
                guard speaker.type != "VOICEVOX" else { return WatchSpeechSettings.Speaker() }
                var result = WatchSpeechSettings.Speaker()
                result.pitch = speaker.pitch
                result.rate = speaker.rate
                result.volume = speaker.volume
                result.type = speaker.type
                result.voiceIdentifier = speaker.voiceIdentifier
                result.locale = speaker.locale
                return result
            }
            let defaultSpeaker: RealmSpeakerSetting
            if let globalDefaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) {
                defaultSpeaker = globalDefaultSpeaker
            } else {
                defaultSpeaker = RealmSpeakerSetting()
            }
            settings.defaultSpeaker = convertSpeaker(defaultSpeaker)
            if let sectionConfigs = RealmSpeechSectionConfig.SearchSettingsFor(realm: realm, novelID: globalOnlyNovelID) {
                for sectionConfig in sectionConfigs {
                    let speaker = sectionConfig.speakerWith(realm: realm) ?? defaultSpeaker
                    settings.sectionConfigs.append(WatchSpeechSettings.SectionConfig(startText: sectionConfig.startText, endText: sectionConfig.endText, speaker: convertSpeaker(speaker)))
                }
            }
            var waitConfigs: [WatchSpeechSettings.WaitConfig] = []
            if let allWaitConfigList = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm) {
                for waitConfig in allWaitConfigList {
                    waitConfigs.append(WatchSpeechSettings.WaitConfig(targetText: waitConfig.targetText, delayTimeInSec: waitConfig.delayTimeInSec))
                }
            }
            // 「間の仕組み」が非推奨型なら読み替え辞書へ変換する
            // (StoryTextClassifier.CategorizeStoryText(story:) と同じ変換)
            if RealmGlobalState.GetInstanceWith(realm: realm)?.isSpeechWaitSettingUseExperimentalWait == true {
                for waitConfig in waitConfigs {
                    let count = Int(waitConfig.delayTimeInSec * 10)
                    if count <= 0 { continue }
                    settings.speechMods.append(WatchSpeechSettings.Mod(before: waitConfig.targetText, after: "。" + String(repeating: "_。", count: count), isRegexp: false, targetEngines: []))
                }
                waitConfigs = []
            }
            settings.waitConfigs = waitConfigs
            // 読み替え辞書。標準辞書由来のエントリは AVSpeechSynthesizer 専用マークを引き継ぐ
            let defaultSpeechModKeySet = NovelSpeakerUtility.GetDefaultSpeechModKeySet()
            if let modSettings = RealmSpeechModSetting.SearchSettingsFor(realm: realm, novelID: globalOnlyNovelID) {
                for modSetting in modSettings {
                    let key = NovelSpeakerUtility.DefaultSpeechModKey(before: modSetting.before, after: modSetting.after, isRegexp: modSetting.isUseRegularExpression)
                    let targetEngines: [String] = defaultSpeechModKeySet.contains(key) ? ["AVSpeechSynthesizer"] : []
                    settings.speechMods.append(WatchSpeechSettings.Mod(before: modSetting.before, after: modSetting.after, isRegexp: modSetting.isUseRegularExpression, targetEngines: targetEngines))
                }
            }
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled {
                    settings.speechMods.append(WatchSpeechSettings.Mod(before: "\\s+", after: "α", isRegexp: true, targetEngines: []))
                }
                settings.isIgnoreURIStringSpeechEnabled = globalState.isIgnoreURIStringSpeechEnabled
                settings.isOverrideRubyEnabled = globalState.isOverrideRubyIsEnabled
                settings.notRubyCharactorStringArray = globalState.notRubyCharactorStringArray
                settings.isDisableNarouRuby = globalState.isDisableNarouRuby
                // 「再生が末尾に達した時の動作」。Watch 単体再生の末尾到達時に使う
                settings.repeatSpeechTypeRawValue = globalState.repeatSpeechType.rawValue
                settings.isRepeatSpeechLoopNoCheckReadingPoint = (globalState.repeatSpeechLoopType == .noCheckReadingPoint)
                settings.isAnnounceAtRepatSpeechTime = globalState.isAnnounceAtRepatSpeechTime
                settings.novelLikeOrder = Array(globalState.novelLikeOrder)
            }
            // フォルダ一覧(「同じ/指定フォルダの小説を再生」の候補選び用)
            if let folders = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) {
                settings.novelFolders = folders.map {
                    WatchSpeechSettings.Folder(name: $0.name, novelIDs: Array($0.targetNovelIDArray))
                }
            }
            return settings
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
            transferSpeechSettingsIfNeeded()
            // Watch→iPhone の applicationContext はアプリがサスペンド中に届いた場合
            // delegate が呼ばれないまま受信済みプロパティにだけ入っていることがあるので、
            // アクティベート時に必ず一度処理する(updatedAt のガードがあるので冪等)
            let received = session.receivedApplicationContext
            if !received.isEmpty {
                self.session(session, didReceiveApplicationContext: received)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // 手首を下ろす等で Watch が unreachable になったら本文ページの購読は切れたものとみなす
        // (Watch 側からの明示的な unsubscribe が届かなかった場合の保険。無駄な位置送信を残さない)
        if !session.isReachable {
            isSpeechBlockSubscribed = false
        }
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
        // Watch 単体再生の読み上げ位置。iPhone 側の栞より新しければ反映する。
        // 新形式(直近の複数件)があればそちらを、無ければ旧形式(最新1件)を使う
        let positionDictionaryArray: [[String: Any]]
        if let array = applicationContext[WatchMessage.Context.watchReadingPositions] as? [[String: Any]] {
            positionDictionaryArray = array
        } else if let single = applicationContext[WatchMessage.Context.watchReadingPosition] as? [String: Any] {
            positionDictionaryArray = [single]
        } else {
            positionDictionaryArray = []
        }
        for positionDictionary in positionDictionaryArray {
            guard let novelID = positionDictionary["novelID"] as? String,
                  let chapter = positionDictionary["chapter"] as? Int,
                  let location = positionDictionary["location"] as? Int,
                  let updatedAtInterval = positionDictionary["updatedAt"] as? TimeInterval else { continue }
            applyWatchReadingPosition(novelID: novelID, chapter: chapter, location: location, updatedAt: Date(timeIntervalSince1970: updatedAtInterval))
        }
    }

    /// Watch 単体再生の読み上げ位置を iPhone 側の栞に反映する。
    /// 「新しい方優先」: iPhone 側でその後に読んでいたら(lastReadDate の方が新しければ)何もしない
    private func applyWatchReadingPosition(novelID: String, chapter: Int, location: Int, updatedAt: Date) {
        DispatchQueue.main.async {
            // Watch で聴く小説は直前に iPhone 側でも開いている(openNovel 等で StorySpeaker が
            // 保持している)のが普通なので、「開いているから反映しない」にすると同期したい小説ほど
            // 反映されなくなってしまう。iPhone 側でまさに発話中の場合だけ諦める(発話側の位置が正)
            let currentStoryID = StorySpeaker.shared.storyID
            let isCurrentNovel = !currentStoryID.isEmpty && RealmStoryBulk.StoryIDToNovelID(storyID: currentStoryID) == novelID
            if isCurrentNovel && StorySpeaker.shared.isPlayng {
                print("WatchSessionCoordinator: Watchの読み上げ位置は iPhone 側が発話中のため反映しない novelID=\(novelID)")
                return
            }
            var appliedStory: Story? = nil
            // withoutNotifying: StorySpeaker.updateReadDate と同じ作法で、画面側(SpeechViewController等)の
            // novel オブザーバに通知しない。素の Write で書くと iCloud 同期用の
            // 「他端末で更新された n章 へ移動」フローティングボタンが誤って出てしまう
            // (あちらの仕組みは触らず、Watch 直通での更新はこちらで直接反映するので不要)
            RealmUtil.Write(withoutNotifying: StorySpeaker.shared.updateDateWithoutNotifyingTokens) { realm in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
                guard updatedAt > novel.lastReadDate else {
                    print("WatchSessionCoordinator: Watchの読み上げ位置は iPhone 側の栞の方が新しいため反映しない novelID=\(novelID) watch=\(updatedAt) iPhone=\(novel.lastReadDate)")
                    return
                }
                guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapter) else { return }
                let contentCount = story.content.count
                let clampedLocation = min(max(0, location), max(0, contentCount - 1))
                story.SetCurrentReadLocationWith(realm: realm, location: clampedLocation)
                novel.lastReadDate = updatedAt
                novel.m_readingChapterStoryID = story.storyID
                novel.m_readingChapterContentCount = contentCount
                print("WatchSessionCoordinator: Watchの読み上げ位置を栞に反映 novelID=\(novelID) chapter=\(chapter) location=\(clampedLocation)")
                appliedStory = story
            }
            guard let story = appliedStory else { return }
            // StorySpeaker が同じ小説を(停止状態で)保持している場合は開き直して追従させる。
            // Realm の栞だけ動かすと画面と StorySpeaker 内部の位置が古いまま残り、
            // 再生開始や updateReadDate で古い位置に巻き戻されてしまう。
            // (SetStory は栞から readLocation を読み直す)
            if isCurrentNovel {
                StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: false)
            }
            self.pushContextSoon()
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        if let error = error {
            print("WatchSessionCoordinator: transferFile 失敗: \(error)")
            // 発話設定の転送に失敗した場合は「送信済み」の指紋を消して、次の機会に再送させる
            if (fileTransfer.file.metadata?[WatchSpeechSettings.transferTypeKey] as? String) == WatchSpeechSettings.transferTypeValue {
                UserDefaults.standard.removeObject(forKey: WatchSessionCoordinator.lastSpeechSettingsFingerprintKey)
            }
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
        // 本文表示の購読中のみ、2秒に1回まで読み上げ位置を送る(本文ページのハイライト用)
        guard isSpeechBlockSubscribed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReadingPointSentDate) >= 2.0 else { return }
        lastReadingPointSentDate = now
        sendReadingPoint(storyID: storyID, location: range.location)
    }

    /// 現在の読み上げ位置(表示文字ベース)を Watch へプッシュする(スロットルは呼び出し側)
    func sendReadingPoint(storyID: String, location: Int) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([
            WatchMessage.Push.readingPoint: [
                "novelID": RealmStoryBulk.StoryIDToNovelID(storyID: storyID),
                "chapter": RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID),
                "location": location,
            ],
        ], replyHandler: nil, errorHandler: nil)
    }

    func storySpeakerStoryChanged(story: Story) {
        pushContextSoon()
    }
}
