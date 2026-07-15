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

    // MARK: - 接続診断の記録(設定タブのデバッグメニュー「Apple Watch連携の診断情報」用)
    // Watch と半接続(isWatchAppInstalled=false / WCErrorDomain 7006 等)になると Xcode からも
    // 観測しづらいことが多いので、アプリ内から確認できるように主要イベントの時刻を残しておく。
    // デバッグ表示専用の best-effort な記録なのでスレッド保護はしない
    private var lastCommandReceivedDate: Date?
    private var lastCommandReceivedName: String?
    private var lastWatchContextReceivedDate: Date?
    private var lastContextPushSuccessDate: Date?
    private var lastContextPushErrorDate: Date?
    private var lastContextPushErrorMessage: String?
    private var lastFileTransferFinishDate: Date?
    private var lastFileTransferFinishDescription: String?

    /// Apple Watch 連携の状態レポート。設定タブのデバッグメニューから表示・コピーする
    func diagnosticsReport() -> String {
        guard WCSession.isSupported() else { return "WCSession: not supported" }
        let session = WCSession.default
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        func dateText(_ date: Date?) -> String {
            guard let date = date else { return "-" }
            return formatter.string(from: date)
        }
        let activationStateName: String
        switch session.activationState {
        case .activated: activationStateName = "activated"
        case .inactive: activationStateName = "inactive"
        case .notActivated: activationStateName = "notActivated"
        @unknown default: activationStateName = "unknown(\(session.activationState.rawValue))"
        }
        var lines: [String] = []
        lines.append("== WCSession (iPhone側) ==")
        lines.append("activationState: \(activationStateName)")
        lines.append("isPaired: \(session.isPaired)")
        lines.append("isWatchAppInstalled: \(session.isWatchAppInstalled)")
        lines.append("isReachable: \(session.isReachable)")
        lines.append("isComplicationEnabled: \(session.isComplicationEnabled)")
        lines.append("未完了のファイル転送: \(session.outstandingFileTransfers.count)件")
        lines.append("Watchからの受信済みcontext: \(session.receivedApplicationContext.isEmpty ? "なし" : "あり")")
        lines.append("")
        lines.append("== 最終イベント ==")
        lines.append("context送信成功: \(dateText(lastContextPushSuccessDate))")
        if let errorDate = lastContextPushErrorDate {
            lines.append("context送信失敗: \(dateText(errorDate)) \(lastContextPushErrorMessage ?? "")")
        }
        lines.append("Watchからのコマンド受信: \(dateText(lastCommandReceivedDate)) \(lastCommandReceivedName ?? "")")
        lines.append("Watchからのcontext受信: \(dateText(lastWatchContextReceivedDate))")
        lines.append("ファイル転送完了: \(dateText(lastFileTransferFinishDate)) \(lastFileTransferFinishDescription ?? "")")
        lines.append("")
        lines.append("isWatchAppInstalled が false のまま届かない場合は、iPhone の Watch アプリで ことせかい が「インストール済み」欄に居るかを確認してください(「利用可能なAPP」側に落ちていたら、Watch側のことせかいを削除して Watch アプリから再インストールすると直ることが多いです)。")
        return lines.joined(separator: "\n")
    }

    private static let watchStoredNovelIDsKey = "WatchSessionCoordinator_WatchStoredNovelIDs"

    /// 本文(RealmStoryBulk)が最後に変化した時刻。context の bulkChangeToken として Watch へ届き、
    /// 章数が変わらない内容だけの更新の同期トリガになる(アプリ再起動を跨いでも進み続けるよう永続化)
    private static let lastBulkChangeTokenKey = "WatchSessionCoordinator_LastBulkChangeToken"

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
        observeSettingsChangesForWatch()
    }

    // MARK: - 発話設定の変更監視(変更されたらすぐ Watch へ送る)

    private var settingsObserverTokens: [NotificationToken] = []
    private var settingsTransferDebounceWorkItem: DispatchWorkItem?

    /// Watch へ送る発話設定(WatchSpeechSettings)の材料になる Realm オブジェクト群を監視して、
    /// 変更されたらデバウンス付きで設定ファイルを送り直す。内容が変わっていなければ指紋が一致して
    /// 実際には送られないので、多少過剰に発火しても害はない(iCloud同期由来の変更でも同じ)。
    /// これで「iPhone 側で設定を変えた時も、Watch 側の変更と同じようにすぐ相手へ伝わる」になる
    private func observeSettingsChangesForWatch() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { realm in
                if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                    self.settingsObserverTokens.append(globalState.observe { [weak self] _ in
                        self?.scheduleSettingsTransferSoon()
                    })
                }
                if let speakerSettings = RealmSpeakerSetting.GetAllObjectsWith(realm: realm) {
                    self.settingsObserverTokens.append(speakerSettings.observe { [weak self] _ in
                        self?.scheduleSettingsTransferSoon()
                    })
                }
                if let sectionConfigs = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) {
                    self.settingsObserverTokens.append(sectionConfigs.observe { [weak self] _ in
                        self?.scheduleSettingsTransferSoon()
                    })
                }
                if let waitConfigs = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm) {
                    self.settingsObserverTokens.append(waitConfigs.observe { [weak self] _ in
                        self?.scheduleSettingsTransferSoon()
                    })
                }
                if let modSettings = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) {
                    self.settingsObserverTokens.append(modSettings.observe { [weak self] _ in
                        self?.scheduleSettingsTransferSoon()
                    })
                }
                if let novelTags = RealmNovelTag.GetAllObjectsWith(realm: realm) {
                    self.settingsObserverTokens.append(novelTags.observe { [weak self] _ in
                        self?.scheduleSettingsTransferSoon()
                    })
                }
                // 本文の変化(ダウンロード・自作小説の編集・削除)は RealmStoryBulk に必ず現れるので
                // これを監視して context+小説一覧を送り直す。Watch 側は届いた一覧で章数の差に気づき、
                // 転送済み小説なら自動で差分転送を依頼してくる(=iPhone 側で本文が変われば
                // Watch を操作しなくても同期される)。RealmNovel は栞の更新等でも高頻度に変わるので
                // 監視対象にしない。一覧は指紋で dedup されるので過剰発火しても実転送は起きない。
                // また、章数が変わらない内容だけの更新(誤字修正等)は章数比較では検知できないため、
                // 変更トークン(時刻)を永続化して context に載せる(Watch 側の再検証トリガ)。
                // どの小説が変わったかを Realm 通知のインデックスから特定するのは
                // (deletions/modifications が旧状態のインデックスで誤対応しうるため)やらない
                self.settingsObserverTokens.append(realm.objects(RealmStoryBulk.self).observe { [weak self] changes in
                    guard case .update(_, let deletions, let insertions, let modifications) = changes,
                          !(deletions.isEmpty && insertions.isEmpty && modifications.isEmpty) else { return }
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WatchSessionCoordinator.lastBulkChangeTokenKey)
                    self?.scheduleContextPushForNovelChanges()
                })
            }
        }
    }

    /// 設定変更の連打(スライダー操作や iCloud 同期のバースト)をまとめるためのデバウンス
    private func scheduleSettingsTransferSoon() {
        settingsTransferDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.transferSpeechSettingsIfNeeded()
        }
        settingsTransferDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private var novelChangesPushDebounceWorkItem: DispatchWorkItem?

    /// 本文変更の連打(全小説の更新確認で次々ダウンロードされる等)をまとめるためのデバウンス。
    /// pushContextNow は小説一覧の全量構築を伴うので、設定より長めに取る
    private func scheduleContextPushForNovelChanges() {
        novelChangesPushDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pushContextSoon()
        }
        novelChangesPushDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
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
        // 小説一覧の全量(ファイル)も内容が変わっていれば送り直す(指紋で dedup される)
        transferNovelListIfNeeded()
        var fullContext: [String: Any] = [:]
        fullContext[WatchMessage.Context.playState] = currentPlayState().toDictionary()
        let novelList = currentNovelList().map { $0.toDictionary() }
        fullContext[WatchMessage.Context.novelList] = novelList
        // iPhone の並び順のグループ種別(Watch の「iPhoneと同じ」がフォルダ分けを再現するのに使う)
        let sortType = RealmUtil.RealmBlock { realm in
            RealmGlobalState.GetInstanceWith(realm: realm)?.bookShelfSortType ?? .LastReadDate
        }
        fullContext[WatchMessage.Context.phoneSortGrouping] = WatchSessionCoordinator.groupingKind(sortType: sortType)
        // 最後に転送キューへ積んだ小説一覧の指紋(Watch 側の「同期中…」表示用)
        if let novelListFingerprint = UserDefaults.standard.string(forKey: WatchSessionCoordinator.lastNovelListFingerprintKey) {
            fullContext[WatchMessage.Context.novelListFingerprint] = novelListFingerprint
        }
        // 本文の変更トークン(章数が変わらない内容だけの更新を Watch に検知させる)。
        // この値が変わると context の指紋も変わるので、内容だけの更新でも dedup を抜けて必ず届く
        let bulkChangeToken = UserDefaults.standard.double(forKey: WatchSessionCoordinator.lastBulkChangeTokenKey)
        if bulkChangeToken > 0 {
            fullContext[WatchMessage.Context.bulkChangeToken] = bulkChangeToken
        }
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
                lastContextPushSuccessDate = Date()
                contextPushCount += 1
                if limit < novelList.count {
                    print("WatchSessionCoordinator: pushContext #\(contextPushCount) (小説一覧を\(limit)件に削減して送信)")
                } else {
                    print("WatchSessionCoordinator: pushContext #\(contextPushCount)")
                }
                return
            } catch {
                lastContextPushErrorDate = Date()
                lastContextPushErrorMessage = "\(error)"
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

    private func currentNovelList(limit: Int = WatchSessionCoordinator.novelListLimit) -> [WatchNovelSummary] {
        return RealmUtil.RealmBlock { realm -> [WatchNovelSummary] in
            guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return [] }
            let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
            let sorted = WatchSessionCoordinator.sortNovelsForWatch(
                novels: novels,
                sortType: globalState?.bookShelfSortType ?? .LastReadDate,
                globalState: globalState)
            var result: [WatchNovelSummary] = []
            for novel in sorted {
                if result.count >= limit { break }
                var summary = WatchNovelSummary()
                summary.novelID = novel.novelID
                summary.title = novel.title
                summary.chapterCount = novel.lastChapterNumber ?? 0
                summary.readingChapterNumber = novel.readingChapterNumber ?? 0
                summary.isLiked = (globalState?.calcLikeLevel(novelID: novel.novelID) ?? 0) > 0
                summary.writer = novel.writer
                summary.lastReadDate = novel.lastReadDate
                summary.lastDownloadDate = novel.lastDownloadDate
                summary.createdDate = novel.createdDate
                summary.readingChapterReadingPoint = novel.m_readingChapterReadingPoint
                summary.readingChapterContentCount = novel.m_readingChapterContentCount
                result.append(summary)
            }
            return result
        }
    }

    /// iPhone の並び順のグループ種別。Watch はこれを見て「iPhoneと同じ」表示のフォルダ分けを再現する。
    /// タグ名順はタグ情報が Watch に無く再現できないので、専用値 "keywordTag" を送って
    /// Watch 側に「非対応のため小説名順で表示」の案内を出させる(並び自体は小説名降順で送っている)
    private static func groupingKind(sortType: NarouContentSortType) -> String {
        switch sortType {
        case .KeywordTag:
            return "keywordTag"
        case .SelfCreatedFolder:
            return "folder"
        case .Writer:
            return "writer"
        case .WebSite:
            return "website"
        case .LastReadDateWithFolder:
            return "readDateBuckets"
        case .NovelUpdatedAtWithFolder:
            return "downloadDateBuckets"
        case .UnreadChapterCount:
            return "unreadBuckets"
        case .AppleWatchTransferState:
            return "watchTransferState"
        default:
            return "flat"
        }
    }

    /// Watch の本棚に載せる並び順。iPhone の本棚の並び順設定(bookShelfSortType)に追従する。
    /// フォルダ分け系の並び順は Watch では平坦なリストにしか出せないので、
    /// 「iPhone のフォルダを開いた時と同じ順」で平坦に並べた近似にする。
    /// 注意: 揃える相手は getNovelArray ではなく「実際の画面表示を作る」
    /// BookShelfTreeViewController.create*CellDataTree 側(表示側で並べ直すケースがある)
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
            // iPhone の表示は「作者名(昇順)のフォルダ+フォルダ内は小説名(昇順)」
            return Array(novels.sorted(by: [
                RealmSwift.SortDescriptor(keyPath: "writer", ascending: true),
                RealmSwift.SortDescriptor(keyPath: "title", ascending: true),
            ]))
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
            // iPhone の表示側は「章の数が多い順」(getNovelArray とは逆)
            return novels.sorted { a, b in
                let aCount = RealmStoryBulk.StoryIDToChapterNumber(storyID: a.m_lastChapterStoryID)
                let bCount = RealmStoryBulk.StoryIDToChapterNumber(storyID: b.m_lastChapterStoryID)
                return aCount > bCount
            }
        case .UnreadChapterCount:
            return novels.map { ($0, BookShelfTreeViewController.unreadChapterCount(novel: $0)) }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        case .SelfCreatedFolder:
            // iPhone の表示は「フォルダ(名前昇順)→フォルダ内は登録順→未分類はタイトル降順」。
            // 同じ順で平坦化する(複数フォルダに属する小説は最初の一回だけ)
            var novelMap: [String: RealmNovel] = [:]
            for novel in novels {
                novelMap[novel.novelID] = novel
            }
            var result: [RealmNovel] = []
            var listed = Set<String>()
            if let realm = novels.realm, let folders = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) {
                for folder in folders.sorted(by: { $0.name < $1.name }) {
                    for novelID in folder.targetNovelIDArray {
                        guard !listed.contains(novelID), let novel = novelMap[novelID] else { continue }
                        listed.insert(novelID)
                        result.append(novel)
                    }
                }
            }
            for novel in novels.sorted(byKeyPath: "title", ascending: false) where !listed.contains(novel.novelID) {
                result.append(novel)
            }
            return result
        case .Title, .KeywordTag:
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
        .togglePlayPause, .startSpeech, .skipBackward, .skipForward, .previousChapter, .nextChapter,
    ]

    private func handleCommand(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let commandString = message[WatchMessage.commandKey] as? String,
              let command = WatchMessage.Command(rawValue: commandString) else {
            replyHandler?([WatchMessage.Reply.ok: false, WatchMessage.Reply.errorMessage: NSLocalizedString("WatchSessionCoordinator_ErrorUnknownCommand", comment: "対応していない操作です。iPhone側の ことせかい が古い可能性があります。")])
            return
        }
        lastCommandReceivedDate = Date()
        lastCommandReceivedName = commandString
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
            // togglePlayPauseEvent() は使わない: あれは isNeedRepeatSpeech の「現在値」を引き継ぐため、
            // Watch からの背面起動などで一度も UI の再生ボタンを押していないと false のままになり、
            // 章末で次章へ進まず「読み上げが最後に達しました」で止まってしまう。
            // Watch の再生ボタンは UI の再生ボタンと同じ「連続再生の開始」なので true を明示する
            RealmUtil.RealmBlock { realm in
                if StorySpeaker.shared.isPlayng {
                    StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
                } else {
                    StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "Watchからの再生・停止.\(#function)", isNeedRepeatSpeech: true)
                }
            }
            completeAfterSettle(completion)
        case .startSpeech:
            // 「再生開始のみ」(ウィジェット「iPhoneで再生」用)。既に再生中なら何もしない。
            // isNeedRepeatSpeech: true の理由は togglePlayPause の項と同じ
            RealmUtil.RealmBlock { realm in
                guard !StorySpeaker.shared.isPlayng else { return }
                StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "Watchからの再生開始.\(#function)", isNeedRepeatSpeech: true)
            }
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
            openNovel(novelID: novelID, thenPlay: false, completion: completion)
        case .playNovel:
            guard let novelID = message[WatchMessage.Arg.novelID] as? String else {
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorNovelIDMissing", comment: "novelID がありません")))
                return
            }
            openNovel(novelID: novelID, thenPlay: true, completion: completion)
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
            transferNovel(novelID: novelID,
                          knownBulkFingerprints: message[WatchMessage.Arg.bulkFingerprints] as? [String: String] ?? [:])
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
        case .setRepeatSpeechConfig:
            guard let repeatTypeRawValue = message[WatchMessage.Arg.repeatType] as? Int,
                  let isLoopNoCheck = message[WatchMessage.Arg.loopNoCheckReadingPoint] as? Bool,
                  let repeatType = RepeatSpeechType(rawValue: repeatTypeRawValue) else {
                completion((false, NSLocalizedString("WatchSessionCoordinator_ErrorInvalidArguments", comment: "引数が不正です")))
                return
            }
            RealmUtil.RealmBlock { realm in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                RealmUtil.WriteWith(realm: realm) { _ in
                    globalState.repeatSpeechType = repeatType
                    globalState.repeatSpeechLoopType = isLoopNoCheck ? .noCheckReadingPoint : .normal
                }
            }
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

    /// 指定小説を StorySpeaker にセットする(thenPlay=true なら続けて再生も開始する)。
    /// 再生は「その小説の栞の続きから」。ウィジェット「この小説を再生」が thenPlay=true で使う
    private func openNovel(novelID: String, thenPlay: Bool, completion: @escaping ((ok: Bool, errorMessage: String?)) -> Void) {
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
                if thenPlay, !StorySpeaker.shared.isPlayng {
                    // SetStory 後に停止中なら再生を開始する。UI の再生ボタンと同じ「連続再生」として
                    // 開始する(isNeedRepeatSpeech: true。false だと章末で次章へ進まない。toggle の項参照)
                    RealmUtil.RealmBlock { realm in
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "Watchウィジェット「この小説を再生」.\(#function)", isNeedRepeatSpeech: true)
                    }
                    self.completeAfterSettle(completion)
                } else {
                    completion((true, nil))
                }
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

    /// 小説の本文を RealmStoryBulk のバイナリ(LZFSE 圧縮の [Story] JSON)のまま、バルク単位で
    /// Watch へ送る。knownBulkFingerprints(Watch が保存済みのバルクの指紋)と一致するバルクは
    /// 送信を省略し、最後に manifest(全バルクの指紋一覧)を送る。
    /// iPhone 側は送信状態を持たない(毎回 Watch 申告の指紋と突き合わせる)ので、
    /// 転送失敗や Watch 再インストール後も次の依頼で自然に回復する
    private func transferNovel(novelID: String, knownBulkFingerprints: [String: String] = [:]) {
        DispatchQueue.global(qos: .utility).async {
            var title = ""
            var chapterCount = 0
            // data が nil のバルクは Watch 側が同じ物を保存済みなので送らない
            var bulks: [(chapter: Int, fingerprint: String, data: Data?)] = []
            RealmUtil.RealmBlock { realm in
                if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                    title = novel.title
                    chapterCount = novel.lastChapterNumber ?? 0
                }
                guard let bulkList = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: novelID) else { return }
                for bulk in bulkList {
                    guard let binary = bulk.LoadCreamAssetBinary() else { continue }
                    let fingerprint = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
                    let needsSend = knownBulkFingerprints["\(bulk.chapterNumber)"] != fingerprint
                    bulks.append((bulk.chapterNumber, fingerprint, needsSend ? binary : nil))
                }
            }
            guard !bulks.isEmpty else {
                print("WatchSessionCoordinator: transferNovel バルクがありません novelID=\(novelID)")
                return
            }
            let session = WCSession.default
            // 既に転送キューに積まれている同一バルクは重複して積まない
            // (自動再転送依頼が転送完了前に再発火した時のため)
            let outstanding = Set(session.outstandingFileTransfers.compactMap { transfer -> String? in
                guard let metadata = transfer.file.metadata,
                      (metadata[WatchNovelBulkFile.transferTypeKey] as? String) == WatchNovelBulkFile.bulkTypeValue,
                      let outstandingNovelID = metadata[WatchNovelBulkFile.novelIDKey] as? String,
                      let fingerprint = metadata[WatchNovelBulkFile.fingerprintKey] as? String else { return nil }
                return "\(outstandingNovelID)#\(fingerprint)"
            })
            // 実際に送るバルクを確定してから積む(何個目/全何個 の進捗情報を metadata に載せるため)
            let sendList = bulks.filter { $0.data != nil && !outstanding.contains("\(novelID)#\($0.fingerprint)") }
            var queuedCount = 0
            for (queueIndex, bulk) in sendList.enumerated() {
                guard let data = bulk.data else { continue }
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WatchNovelBulk-\(UUID().uuidString).bin")
                do {
                    try data.write(to: fileURL)
                } catch {
                    print("WatchSessionCoordinator: transferNovel 一時ファイル書き込み失敗: \(error)")
                    return
                }
                session.transferFile(fileURL, metadata: [
                    WatchNovelBulkFile.transferTypeKey: WatchNovelBulkFile.bulkTypeValue,
                    WatchNovelBulkFile.novelIDKey: novelID,
                    WatchNovelBulkFile.bulkChapterKey: bulk.chapter,
                    WatchNovelBulkFile.fingerprintKey: bulk.fingerprint,
                    WatchNovelBulkFile.queueIndexKey: queueIndex,
                    WatchNovelBulkFile.queueTotalKey: sendList.count,
                ])
                queuedCount += 1
            }
            // manifest は毎回送る(バルクを全部持っていた場合も、これが Watch 側の
            // 「転送完了」判定と依頼中スピナーの停止条件になる)
            let manifest: [String: Any] = [
                WatchNovelBulkFile.novelIDKey: novelID,
                WatchNovelBulkFile.manifestTitleKey: title,
                WatchNovelBulkFile.manifestChapterCountKey: chapterCount,
                WatchNovelBulkFile.manifestBulksKey: bulks.map {
                    ["chapter": $0.chapter, "fingerprint": $0.fingerprint]
                },
            ]
            guard let manifestData = try? JSONSerialization.data(withJSONObject: manifest) else {
                print("WatchSessionCoordinator: transferNovel manifest 生成失敗 novelID=\(novelID)")
                return
            }
            let manifestURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WatchNovelManifest-\(UUID().uuidString).json")
            do {
                try manifestData.write(to: manifestURL)
            } catch {
                print("WatchSessionCoordinator: transferNovel manifest 書き込み失敗: \(error)")
                return
            }
            session.transferFile(manifestURL, metadata: [
                WatchNovelBulkFile.transferTypeKey: WatchNovelBulkFile.manifestTypeValue,
                WatchNovelBulkFile.novelIDKey: novelID,
            ])
            print("WatchSessionCoordinator: 本文を転送キューに追加 novelID=\(novelID) バルク \(queuedCount)/\(bulks.count) 個")
        }
    }

    // MARK: - 小説一覧の転送(本棚の全量)

    private static let lastNovelListFingerprintKey = "WatchSessionCoordinator_LastNovelListFingerprint"

    /// 小説一覧の全量を transferFile で送る。内容が前回送信時と同じなら送らない。
    /// applicationContext の novelList は先頭 novelListLimit 冊しか入らない(サイズ上限)ため、
    /// 本棚が大きい場合のフォルダ表示や並び替えはこちらの全量が正になる
    private func transferNovelListIfNeeded() {
        let session = WCSession.default
        guard isStarted, session.activationState == .activated, session.isPaired else { return }
        DispatchQueue.global(qos: .utility).async {
            let novels = self.currentNovelList(limit: Int.max).map { $0.toDictionary() }
            guard !novels.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: [WatchNovelListFile.novelsKey: novels], options: [.sortedKeys]) else { return }
            let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if UserDefaults.standard.string(forKey: WatchSessionCoordinator.lastNovelListFingerprintKey) == fingerprint { return }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WatchNovelList-\(UUID().uuidString).json")
            do {
                try data.write(to: fileURL)
            } catch {
                print("WatchSessionCoordinator: 小説一覧の一時ファイル書き込み失敗: \(error)")
                return
            }
            session.transferFile(fileURL, metadata: [
                WatchNovelListFile.transferTypeKey: WatchNovelListFile.transferTypeValue,
                WatchNovelListFile.transferFingerprintKey: fingerprint,
            ])
            // transferFile はキュー式で OS が再試行してくれるので、積めた時点で送信済み扱いにする。
            // 転送がエラーで終わった場合は didFinish 側で指紋を消して次回再送させる
            UserDefaults.standard.set(fingerprint, forKey: WatchSessionCoordinator.lastNovelListFingerprintKey)
            print("WatchSessionCoordinator: 小説一覧を転送キューに追加 (\(data.count) bytes)")
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
            // フォルダ一覧(「同じ/指定フォルダの小説を再生」の候補選びと本棚のフォルダ表示用)。
            // iPhone の本棚(自作フォルダ順)のフォルダの並びと同じく名前順で送る
            if let folders = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) {
                settings.novelFolders = folders.sorted(by: { $0.name < $1.name }).map {
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
        lastWatchContextReceivedDate = Date()
        // Watch 側から「Watch に本文がある小説の一覧」が送られてくる
        if let storedNovelIDs = applicationContext[WatchMessage.Context.watchStoredNovelIDs] as? [String] {
            UserDefaults.standard.set(storedNovelIDs, forKey: WatchSessionCoordinator.watchStoredNovelIDsKey)
        }
        // Watch が受信済みの小説一覧の指紋。こちらが最後に送った物と違うなら送り直す
        // (Watch の再インストール等でファイルが消えていても「送信済み」の dedup で
        //  二度と送られなくならないように)
        if let receivedFingerprint = applicationContext[WatchMessage.Context.watchNovelListReceivedFingerprint] as? String,
           receivedFingerprint != (UserDefaults.standard.string(forKey: WatchSessionCoordinator.lastNovelListFingerprintKey) ?? "") {
            // 一覧ファイルが転送待ちのうちは積み直さない(転送中に Watch から context が
            // 届くたびに同じファイルを重複キューしないため)
            let hasOutstandingNovelListTransfer = session.outstandingFileTransfers.contains {
                ($0.file.metadata?[WatchNovelListFile.transferTypeKey] as? String) == WatchNovelListFile.transferTypeValue
            }
            if !hasOutstandingNovelListTransfer {
                UserDefaults.standard.removeObject(forKey: WatchSessionCoordinator.lastNovelListFingerprintKey)
                transferNovelListIfNeeded()
            }
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
        // 診断用の記録(発話設定・小説一覧・本文バルク/manifest のどれも metadata の "type" に種別が入る)
        let transferType = fileTransfer.file.metadata?[WatchNovelBulkFile.transferTypeKey] as? String ?? "unknown"
        lastFileTransferFinishDate = Date()
        lastFileTransferFinishDescription = error == nil ? "\(transferType) 成功" : "\(transferType) 失敗: \(error!.localizedDescription)"
        if let error = error {
            print("WatchSessionCoordinator: transferFile 失敗: \(error)")
            // 発話設定・小説一覧の転送に失敗した場合は「送信済み」の指紋を消して、次の機会に再送させる
            if (fileTransfer.file.metadata?[WatchSpeechSettings.transferTypeKey] as? String) == WatchSpeechSettings.transferTypeValue {
                UserDefaults.standard.removeObject(forKey: WatchSessionCoordinator.lastSpeechSettingsFingerprintKey)
            }
            if (fileTransfer.file.metadata?[WatchNovelListFile.transferTypeKey] as? String) == WatchNovelListFile.transferTypeValue {
                UserDefaults.standard.removeObject(forKey: WatchSessionCoordinator.lastNovelListFingerprintKey)
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
