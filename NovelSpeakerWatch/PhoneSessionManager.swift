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
import Compression
import WidgetKit

final class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    @Published var playState: WatchPlayState?
    @Published var novels: [WatchNovelSummary] = [] {
        didSet {
            novelsByID = Dictionary(novels.map { ($0.novelID, $0) }, uniquingKeysWith: { first, _ in first })
            updateWidgetNovelSummaries()
        }
    }
    /// novelID → 最新の summary。NavigationLink で push 済みの一覧(push 時のスナップショット)でも
    /// 行の表示内容(章数など)を最新にできるよう、描画時にこちらで引き直す
    private(set) var novelsByID: [String: WatchNovelSummary] = [:]
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
    /// 転送の進捗(novelID → 受信済み/今回送られるバルク数)。バルクの metadata から数える。
    /// 最初のバルクが届くまでは entry が無い(進捗不明のままスピナーだけ出す)
    @Published var transferProgress: [String: TransferProgress] = [:]

    struct TransferProgress: Equatable {
        let received: Int
        let total: Int
    }
    /// Watch で最後に再生した日時(novelID → Date)。キャッシュ整理の並び順に使う
    @Published var lastPlayedDates: [String: Date] = PhoneSessionManager.loadLastPlayedDates()
    /// iPhone 側の読み上げ位置(本文ページの購読中に届く)。表示文字ベースの位置
    @Published var phoneReadingPoint: PhoneReadingPoint?
    /// iPhone の本棚の並び順のグループ種別(WatchMessage.Context.phoneSortGrouping の値)。
    /// 本棚の「iPhoneと同じ」が iPhone と同じフォルダ分けを再現するのに使う
    @Published var phoneSortGrouping = "flat"
    /// 小説一覧(全量ファイル)が iPhone 側の最新とズレている(=転送待ち)か。本棚の「同期中…」表示用
    @Published var isNovelListSyncing = false

    /// 受信済みの小説一覧ファイルの指紋
    private static let receivedNovelListFingerprintKey = "WatchNovelListReceivedFingerprint"
    /// iPhone が最後に知らせてきた小説一覧の指紋(applicationContext 経由)
    private var lastContextNovelListFingerprint: String?

    private func updateNovelListSyncingState() {
        let received = UserDefaults.standard.string(forKey: PhoneSessionManager.receivedNovelListFingerprintKey)
        isNovelListSyncing = (lastContextNovelListFingerprint != nil && lastContextNovelListFingerprint != received)
    }

    struct PhoneReadingPoint: Equatable {
        let novelID: String
        let chapter: Int
        let location: Int
    }

    private var didVerifyStoredNovels = false
    /// 本文ページが購読を望んでいるか(reachable 復帰時の再購読に使う)
    private var wantsReadingPointSubscription = false

    // MARK: - 接続診断の記録(便利機能の隠しデバッグメニュー「接続診断」用)
    // 半接続状態(WCErrorDomain 7006 等)の再現時は Xcode からも観測しづらいので、
    // 主要イベントの時刻を残して Watch 単体で確認できるようにする。
    // デバッグ表示専用の best-effort な記録(@Published にはせず、診断画面側がタイマーで読む)
    private(set) var lastContextReceivedDate: Date?
    private(set) var lastFileReceivedDate: Date?
    private(set) var lastFileReceivedDescription: String?
    private(set) var lastCommandSentDate: Date?
    private(set) var lastCommandSentDescription: String?

    private override init() {
        super.init()
        refreshStoredNovels()
        // 受信済みの小説一覧(全量ファイル)があれば初期表示に使う
        if let storedList = WatchNovelListStorage.load() {
            novels = storedList
            // init 中の代入ではプロパティオブザーバ(didSet)が呼ばれないため、辞書は明示的に作る
            novelsByID = Dictionary(storedList.map { ($0.novelID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func refreshStoredNovels() {
        DispatchQueue.global(qos: .utility).async {
            // manifest(小さい JSON)を読むだけで、本文バルクの展開はしない
            var counts: [String: Int] = [:]
            var titles: [String: String] = [:]
            for novelID in NovelStorage.storedNovelIDs() {
                let count = NovelStorage.storedChapterCount(novelID: novelID)
                guard count > 0 else { continue }  // manifest だけあってバルク未着(先頭すら無い)は未転送扱い
                counts[novelID] = count
                titles[novelID] = NovelStorage.manifest(novelID: novelID)?.title ?? ""
            }
            DispatchQueue.main.async {
                self.storedChapterCounts = counts
                self.storedTitles = titles
                self.storedNovelIDs = Set(counts.keys)
                self.updateWidgetNovelSummaries()
                self.pushWatchContext()
            }
        }
    }

    /// 設定可能ウィジェット(「この小説を再生」)の小説選択肢・読了ゲージ用の要約(App Group)を
    /// 更新する。内容が変わった時だけウィジェットを再読込する。
    /// 候補 = 「Watch に本文転送済みの小説」+「最近読んだ順の上位(未転送でも)」。
    /// 未転送の小説も候補に入れるのは、Watch を iPhone のリモコンとしてだけ使う人でも
    /// ウィジェットからその小説を再生できるようにするため(単体モードで押した場合は
    /// 「本文が転送されていません」のエラーになるだけ)。全冊(数千冊)を入れると
    /// 選択 UI が使い物にならないので、未転送ぶんは最近読んだ上位に絞る
    private func updateWidgetNovelSummaries() {
        let transferred = storedChapterCounts
        var candidateIDs = Set(transferred.keys)
        let recentLimit = 30
        for novel in novels.sorted(by: { $0.lastReadDate > $1.lastReadDate }).prefix(recentLimit) {
            candidateIDs.insert(novel.novelID)
        }
        // 候補が空でも、直前まで有った物を消すために一度は空で保存させる
        guard !candidateIDs.isEmpty || !WatchNovelSummaryStore.load().isEmpty else { return }
        let summaries: [WatchWidgetNovelSummary] = candidateIDs.compactMap { novelID in
            let title = novelsByID[novelID]?.title ?? storedTitles[novelID] ?? ""
            guard !title.isEmpty else { return nil }
            let chapterCount = max(novelsByID[novelID]?.chapterCount ?? 0, transferred[novelID] ?? 0)
            var progress = 0.0
            if let s = novelsByID[novelID] {
                let inChapter = s.readingChapterContentCount > 0
                    ? Double(s.readingChapterReadingPoint) / Double(s.readingChapterContentCount) : 0
                progress = WatchNovelSummaryStore.overallProgress(
                    chapterNumber: s.readingChapterNumber, chapterCount: chapterCount, inChapter: inChapter)
            }
            // 進捗の微小変化での再読込を避けるため 1% 単位に丸める
            progress = (progress * 100).rounded() / 100
            return WatchWidgetNovelSummary(novelID: novelID, title: title,
                                           chapterCount: chapterCount, overallProgress: progress)
        }
        // 「最近読んだ/再生した順」に並べる(同時刻はタイトル順)。文字盤の一覧に出る
        // 「この小説を再生」のプリセットは先頭から数冊しか出せないので、
        // よく聴いている小説が先頭に来るようにする
        .sorted { a, b in
            func recency(_ novelID: String) -> Date {
                return max(novelsByID[novelID]?.lastReadDate ?? Date(timeIntervalSince1970: 0),
                           lastPlayedDates[novelID] ?? Date(timeIntervalSince1970: 0))
            }
            let aDate = recency(a.novelID)
            let bDate = recency(b.novelID)
            if aDate != bDate { return aDate > bDate }
            return a.title < b.title
        }
        if WatchNovelSummaryStore.save(summaries) {
            WidgetCenter.shared.reloadAllTimelines()
            // 文字盤の一覧に出る「この小説を再生」のプリセット(recommendations)も作り直させる
            WidgetCenter.shared.invalidateConfigurationRecommendations()
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
            // 受信済みの小説一覧の指紋。iPhone 側と食い違っていたら一覧ファイルが再送される
            // (再インストール直後など、ファイルが無いのに iPhone が「送信済み」と思っている場合の回復用)
            WatchMessage.Context.watchNovelListReceivedFingerprint:
                UserDefaults.standard.string(forKey: PhoneSessionManager.receivedNovelListFingerprintKey) ?? "",
        ]
        // Watch 単体再生の読み上げ位置。iPhone 側はこれで栞を更新する。
        // 毎回「保存している位置の全量」を送る(applicationContext は最新の1つに差し替わる方式で
        // ACK も無いので、全量+iPhone 側の「新しい方優先」で冪等に反映するのが取りこぼしが無い)。
        // 件数制限は updateApplicationContext のペイロード上限に引っかかって全滅しないための
        // 安全弁で、Watch で再生した小説の数しか増えないため実際に届くことはまず無い
        func positionDictionary(novelID: String, position: WatchReadingPositionStore.Position) -> [String: Any] {
            return [
                "novelID": novelID,
                "chapter": position.chapter,
                "location": position.location,
                "updatedAt": position.updatedAt.timeIntervalSince1970,
            ]
        }
        let recentPositions = WatchReadingPositionStore.recent(limit: 200)
        if let latest = recentPositions.first {
            context[WatchMessage.Context.watchReadingPosition] = positionDictionary(novelID: latest.novelID, position: latest.position)
            context[WatchMessage.Context.watchReadingPositions] = recentPositions.map {
                positionDictionary(novelID: $0.novelID, position: $0.position)
            }
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
    /// 章数の差だけでなく指紋の不一致(章数が同じで内容だけ変わった・バルクの取りこぼし)も
    /// 依頼の対象にする(依頼は指紋の突き合わせによる差分転送なので過剰に頼んでも実転送は最小)
    private func autoRefreshStaleStoredNovels() {
        guard WCSession.default.isReachable else { return }
        for novel in novels {
            guard let storedCount = storedChapterCounts[novel.novelID],
                  !transferRequestedNovelIDs.contains(novel.novelID) else { continue }
            guard novel.chapterCount > storedCount || !NovelStorage.isComplete(novelID: novel.novelID) else { continue }
            requestTransfer(novelID: novel.novelID, quiet: true)
        }
    }

    /// 確認済みの本文変更トークン(iPhone 側で最後に本文が変化した時刻)
    private static let verifiedBulkChangeTokenKey = "WatchVerifiedBulkChangeToken"

    /// iPhone 側で本文(RealmStoryBulk)が変化した印。章数の変わらない内容だけの更新
    /// (誤字修正等)は章数比較(autoRefreshStaleStoredNovels)では検知できないため、
    /// トークンが前回確認時より進んでいたら転送済みの全小説を指紋付きで再依頼する。
    /// 変わっていない小説は iPhone がマニフェスト1個を返すだけで済む(差分転送)ので、
    /// 転送済み冊数が現実的な範囲なら過剰なコストにはならない
    private func handleBulkChangeToken(_ token: Double) {
        let verified = UserDefaults.standard.double(forKey: PhoneSessionManager.verifiedBulkChangeTokenKey)
        if verified <= 0 {
            // 初回(またはアプリ再インストール後)は現在のトークンを既知として採用するだけにする。
            // 過去分の取りこぼしは isComplete 判定(autoRefresh)側の自己修復に任せる
            UserDefaults.standard.set(token, forKey: PhoneSessionManager.verifiedBulkChangeTokenKey)
            return
        }
        guard token > verified else { return }
        // iPhone に届く時にだけトークンを消費する(届かない時に消費すると変更を取りこぼす)
        guard WCSession.default.isReachable else { return }
        UserDefaults.standard.set(token, forKey: PhoneSessionManager.verifiedBulkChangeTokenKey)
        for novelID in storedNovelIDs {
            guard !transferRequestedNovelIDs.contains(novelID) else { continue }
            requestTransfer(novelID: novelID, quiet: true)
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
                self.lastCommandSentDate = Date()
                self.lastCommandSentDescription = "\(command.rawValue) ok=\(ok)"
                if !ok && !quiet {
                    self.lastErrorMessage = reply[WatchMessage.Reply.errorMessage] as? String ?? NSLocalizedString("Watch_Session_CommandFailed", comment: "操作に失敗しました")
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
                self.lastCommandSentDate = Date()
                self.lastCommandSentDescription = "\(command.rawValue) 失敗: \(error.localizedDescription)"
                if !quiet {
                    self.isSending = false
                    self.lastErrorMessage = NSLocalizedString("Watch_Session_NotReachable", comment: "iPhoneと通信できません。iPhoneを再起動した後は、一度ロック解除が必要です。")
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
            self.transferProgress.removeValue(forKey: novelID)  // 前回の依頼の進捗を持ち越さない
        }
        // 手持ちバルクの指紋を添えて、iPhone 側に「変わったバルクだけ」を送らせる(差分転送)
        let args: [String: Any] = [
            WatchMessage.Arg.novelID: novelID,
            WatchMessage.Arg.bulkFingerprints: NovelStorage.storedBulkFingerprints(novelID: novelID),
        ]
        send(.requestTransfer, args: args, quiet: quiet) { ok in
            if !ok {
                self.transferRequestedNovelIDs.remove(novelID)
            }
        }
        // 転送依頼は通ったのにファイルが届かない場合(iPhone側の転送失敗等)に
        // スピナーが回りっぱなしにならないよう、5分で依頼中表示を諦める
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            self.transferRequestedNovelIDs.remove(novelID)
            self.transferProgress.removeValue(forKey: novelID)
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
            // 全量ファイル(WatchNovelListStorage)を受信済みならそちらが正。
            // context の novelList は先頭300冊までしか入らないので、ファイル未着時だけ使う
            if !novelList.isEmpty, !WatchNovelListStorage.exists {
                self.novels = novelList
            }
            if let grouping = context[WatchMessage.Context.phoneSortGrouping] as? String {
                if grouping != self.phoneSortGrouping {
                    self.phoneSortGrouping = grouping
                }
            }
            if let fingerprint = context[WatchMessage.Context.novelListFingerprint] as? String {
                self.lastContextNovelListFingerprint = fingerprint
                self.updateNovelListSyncingState()
            }
            self.autoRefreshStaleStoredNovels()
            if let bulkChangeToken = context[WatchMessage.Context.bulkChangeToken] as? Double, bulkChangeToken > 0 {
                self.handleBulkChangeToken(bulkChangeToken)
            }
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
            // Watch 単体再生が発話元の時はそちらがコンプリケーションを更新するので、ここでは触らない
            // (playState には章タイトルが無く、単体側の subtitle 表示を上書きしてしまうため)
            if !WatchSpeechPlayer.shared.isSelectedAsSource, !state.novelID.isEmpty {
                WatchComplicationUpdater.update(
                    novelID: state.novelID, title: state.title, chapterSubtitle: state.chapterSubtitle,
                    chapterNumber: state.chapterNumber, chapterCount: state.chapterCount,
                    progressInChapter: state.progress)
            }
            // 単体再生で開いている小説の栞が iPhone 側の方が新しければ位置を追従させる
            WatchSpeechPlayer.shared.adoptPhoneBookmarkIfNewer(state)
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
        // 「この小説を再生」プリセットの並び(最近再生した順)にも反映する(変化時のみ保存される)
        updateWidgetNovelSummaries()
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
            // オフライン中に変更した速度・音量/連続再生モードがあれば iPhone へ書き戻す
            if session.isReachable {
                WatchSpeechPlayer.shared.sendPendingSpeechConfigIfPossible()
                WatchSpeechPlayer.shared.sendPendingRepeatConfigIfPossible()
            }
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
        DispatchQueue.main.async {
            self.lastContextReceivedDate = Date()
        }
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // 診断用の記録(発話設定・小説一覧・本文バルク/manifest のどれも metadata の "type" に種別が入る)
        let receivedType = file.metadata?[WatchNovelBulkFile.transferTypeKey] as? String ?? "unknown"
        DispatchQueue.main.async {
            self.lastFileReceivedDate = Date()
            self.lastFileReceivedDescription = receivedType
        }
        // Watch 単体再生用の発話設定ファイル
        if (file.metadata?[WatchSpeechSettings.transferTypeKey] as? String) == WatchSpeechSettings.transferTypeValue {
            do {
                try WatchSpeechSettingsStorage.store(
                    receivedFileURL: file.fileURL,
                    fingerprint: file.metadata?[WatchSpeechSettings.transferFingerprintKey] as? String)
                print("PhoneSessionManager: 発話設定を受信・保存")
                // Watch 側で変更した速度・音量/連続再生モードが iPhone に反映済みなら、ローカル差分を解消する
                WatchSpeechPlayer.shared.reconcileSpeechConfigAfterSettingsReceived()
                WatchSpeechPlayer.shared.reconcileRepeatConfigAfterSettingsReceived()
                // 停止中なら現在の章を新しい設定で組み直す(再生中は次の章から反映)
                WatchSpeechPlayer.shared.applyReceivedSettingsIfIdle()
            } catch {
                print("PhoneSessionManager: 発話設定の保存に失敗: \(error)")
            }
            return
        }
        // 小説一覧(全量)ファイル
        if (file.metadata?[WatchNovelListFile.transferTypeKey] as? String) == WatchNovelListFile.transferTypeValue {
            do {
                try WatchNovelListStorage.store(receivedFileURL: file.fileURL)
                let fingerprint = file.metadata?[WatchNovelListFile.transferFingerprintKey] as? String
                if let fingerprint = fingerprint {
                    UserDefaults.standard.set(fingerprint, forKey: PhoneSessionManager.receivedNovelListFingerprintKey)
                }
                if let novels = WatchNovelListStorage.load() {
                    DispatchQueue.main.async {
                        self.novels = novels
                        // context の指紋は「ファイルを積む前の値」のことがある(iPhone 側は
                        // context 送信後に指紋を更新するため)ので、届いたファイルを最新とみなして
                        // 揃える。これをしないと「同期中…」が次の context まで消えない
                        if let fingerprint = fingerprint {
                            self.lastContextNovelListFingerprint = fingerprint
                        }
                        self.updateNovelListSyncingState()
                        self.autoRefreshStaleStoredNovels()
                        // 受信済み指紋が変わったことを iPhone へ知らせる(再送ループの停止条件)
                        self.pushWatchContext()
                    }
                }
                print("PhoneSessionManager: 小説一覧(全量)を受信・保存")
            } catch {
                print("PhoneSessionManager: 小説一覧の保存に失敗: \(error)")
            }
            return
        }
        // 小説本文(バルク/manifest)
        let fileType = file.metadata?[WatchNovelBulkFile.transferTypeKey] as? String
        guard fileType == WatchNovelBulkFile.bulkTypeValue || fileType == WatchNovelBulkFile.manifestTypeValue,
              let novelID = file.metadata?[WatchNovelBulkFile.novelIDKey] as? String else { return }
        do {
            var notificationUserInfo: [String: Any] = ["novelID": novelID]
            if fileType == WatchNovelBulkFile.bulkTypeValue {
                guard let bulkChapter = file.metadata?[WatchNovelBulkFile.bulkChapterKey] as? Int,
                      let fingerprint = file.metadata?[WatchNovelBulkFile.fingerprintKey] as? String else { return }
                try NovelStorage.storeBulk(fileURL: file.fileURL, novelID: novelID,
                                           bulkChapter: bulkChapter, fingerprint: fingerprint)
                notificationUserInfo["bulkChapter"] = bulkChapter
                // 「転送中 (n/m)」の進捗。到着順は保証しないので受信済み数は単調増加にする
                if let queueIndex = file.metadata?[WatchNovelBulkFile.queueIndexKey] as? Int,
                   let queueTotal = file.metadata?[WatchNovelBulkFile.queueTotalKey] as? Int, queueTotal > 0 {
                    DispatchQueue.main.async {
                        let received = max(self.transferProgress[novelID]?.received ?? 0, queueIndex + 1)
                        self.transferProgress[novelID] = TransferProgress(received: received, total: queueTotal)
                    }
                }
            } else {
                try NovelStorage.storeManifest(fileURL: file.fileURL, novelID: novelID)
            }
            // manifest の全バルクが揃ったら転送完了(依頼中スピナーを止める)。
            // バルクと manifest の到着順は保証を仮定しない(どちらが最後でも判定できる)
            if NovelStorage.isComplete(novelID: novelID) {
                DispatchQueue.main.async {
                    self.transferRequestedNovelIDs.remove(novelID)
                    self.transferProgress.removeValue(forKey: novelID)
                }
            }
            refreshStoredNovels()
            // 本文ページ等に「この小説の本文が変わった/届いた」を知らせる(表示の読み直し用)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NovelStorage.didUpdateNotification, object: nil,
                                                userInfo: notificationUserInfo)
            }
        } catch {
            DispatchQueue.main.async {
                self.lastErrorMessage = String(format: NSLocalizedString("Watch_Session_SaveBodyFailed", comment: "本文の保存に失敗しました: %@"), error.localizedDescription)
                self.transferRequestedNovelIDs.remove(novelID)
                self.transferProgress.removeValue(forKey: novelID)
            }
        }
    }
}

/// iPhone から transferFile で届く小説一覧(全量)の保存と読み出し。
/// applicationContext の novelList(先頭300冊)はこのファイルが届くまでのフォールバック
enum WatchNovelListStorage {
    static var fileURL: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovelList.json")
    }

    static var exists: Bool {
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func store(receivedFileURL: URL) throws {
        let destination = fileURL
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: receivedFileURL, to: destination)
    }

    static func load() -> [WatchNovelSummary]? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let novelArray = payload[WatchNovelListFile.novelsKey] as? [[String: Any]] else { return nil }
        let novels = novelArray.compactMap { WatchNovelSummary.from(dictionary: $0) }
        return novels.isEmpty ? nil : novels
    }
}

/// 受信した小説本文の保存と読み出し。
/// iPhone の RealmStoryBulk のバイナリ(最大100章ぶんの [Story] JSON を LZFSE 圧縮した物)を
/// 無加工のまま「バルク」としてファイル保存し、読む時にバルク単位でオンデマンドに展開する。
/// 小説全体を一度にメモリへ載せない(1000章級の小説でも常に1〜2バルク分しか展開しない)。
///
/// レイアウト: Documents/Novels/<エンコード済みnovelID>/
///   - manifest.json                    … タイトル・最終章番号・全バルクの指紋一覧(iPhone 発行)
///   - bulk_<開始章>_<指紋>.bin          … バルクバイナリ(LZFSE 圧縮のまま保存)
enum NovelStorage {
    /// バルク/manifest の受信・保存が完了した時に post される(object: nil)。
    /// userInfo: "novelID" (String)、バルクの場合は "bulkChapter" (Int) も入る。
    /// 本文ページが「表示中の章の内容が変わった/表示できるようになった」を検知して読み直すのに使う
    static let didUpdateNotification = Notification.Name("NovelStorageDidUpdate")

    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Novels", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func novelDirectory(novelID: String) -> URL {
        // novelID は URL 文字列なのでファイル名に使えるようエンコードする
        let name = novelID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? novelID
        return directory.appendingPathComponent(name, isDirectory: true)
    }

    struct StoredChapter {
        let subtitle: String
        let content: String
    }

    struct Manifest: Codable {
        struct Bulk: Codable {
            let chapter: Int
            let fingerprint: String
        }
        let novelID: String
        let title: String
        /// 小説の最終章番号(iPhone の RealmNovel.lastChapterNumber)
        let chapterCount: Int
        /// chapter 昇順
        let bulks: [Bulk]
    }

    // 展開済みバルクと manifest の小さなメモリキャッシュ。
    // 発話(現在章+次章の先読み)と本文ページが同じバルクを何度も展開しないためのもの
    private static let cache = NovelStorageCache()

    // MARK: 保存(PhoneSessionManager の didReceive から呼ばれる)

    static func storeBulk(fileURL: URL, novelID: String, bulkChapter: Int, fingerprint: String) throws {
        let dir = novelDirectory(novelID: novelID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("bulk_\(bulkChapter)_\(fingerprint).bin")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: fileURL, to: destination)
        // 同じ開始章の古いバルク(更新前の内容)は置き換わったので消す
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("bulk_\(bulkChapter)_")
                && file.lastPathComponent != destination.lastPathComponent {
                try? FileManager.default.removeItem(at: file)
            }
        }
        cache.invalidate(novelID: novelID)
    }

    static func storeManifest(fileURL: URL, novelID: String) throws {
        let dir = novelDirectory(novelID: novelID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("manifest.json")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: fileURL, to: destination)
        cache.invalidate(novelID: novelID)
        // manifest から消えた開始章のバルク(iPhone 側で章が減った等)を掃除する。
        // 同じ開始章で指紋だけ違う古いバルクは、新しいバルクが届くまで読める方が良いので残す
        // (storeBulk が置き換え時に消す)
        guard let manifest = manifest(novelID: novelID),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let validChapters = Set(manifest.bulks.map { $0.chapter })
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("bulk_") else { continue }
            let parts = name.dropFirst("bulk_".count).split(separator: "_")
            guard let chapter = parts.first.flatMap({ Int($0) }), !validChapters.contains(chapter) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func remove(novelID: String) {
        try? FileManager.default.removeItem(at: novelDirectory(novelID: novelID))
        cache.invalidate(novelID: novelID)
    }

    // MARK: メタ情報(manifest ベース。バルクの展開はしない)

    static func storedNovelIDs() -> [String] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) else { return nil }
            return dir.lastPathComponent.removingPercentEncoding
        }
    }

    static func manifest(novelID: String) -> Manifest? {
        if let cached = cache.manifest(novelID: novelID) { return cached }
        let url = novelDirectory(novelID: novelID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        cache.storeManifest(novelID: novelID, manifest: manifest)
        return manifest
    }

    private static func bulkFileURL(novelID: String, chapter: Int, fingerprint: String) -> URL {
        return novelDirectory(novelID: novelID).appendingPathComponent("bulk_\(chapter)_\(fingerprint).bin")
    }

    /// 保存済みバルクの指紋一覧(開始章番号の文字列 → SHA256 hex)。
    /// 転送依頼(requestTransfer)に添えて iPhone 側の差分送信に使われる
    static func storedBulkFingerprints(novelID: String) -> [String: String] {
        let dir = novelDirectory(novelID: novelID)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: String] = [:]
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("bulk_"), name.hasSuffix(".bin") else { continue }
            let parts = name.dropFirst("bulk_".count).dropLast(".bin".count).split(separator: "_")
            guard parts.count == 2, let chapter = Int(parts[0]) else { continue }
            result["\(chapter)"] = String(parts[1])
        }
        return result
    }

    /// manifest の全バルクが「指紋まで一致して」手元に揃っているか(=転送完了)。
    /// 転送依頼中スピナーの停止条件と、autoRefreshStaleStoredNovels の再依頼条件に使う
    static func isComplete(novelID: String) -> Bool {
        guard let manifest = manifest(novelID: novelID), !manifest.bulks.isEmpty else { return false }
        let stored = storedBulkFingerprints(novelID: novelID)
        return manifest.bulks.allSatisfy { stored["\($0.chapter)"] == $0.fingerprint }
    }

    /// 再生・表示できる章の上限(1〜この値の章が対象)。
    /// manifest のバルクを先頭から辿り、最初の「未受信バルク」の手前までの被覆で数える。
    /// 全バルクが揃っていれば manifest の最終章番号と一致する。
    /// - 指紋の一致までは求めない: 更新転送の途中(新 manifest+旧バルク、またはその逆)でも
    ///   同じ開始章のバルクがあれば読める(loadBulk がフォールバックする)ので、
    ///   「読める範囲」として数える。本当に最新かどうかは isComplete が別に判定する。
    ///   これで更新転送の間に本棚の「Apple Watchに転送済み」から一瞬消える事もなくなる
    /// - iPhone 側のバルクに歯抜け(章のギャップ)があっても、それは iPhone にも無い章なので
    ///   「被覆済み」として数える(章の実在は読み出し時に判定される)
    static func storedChapterCount(novelID: String) -> Int {
        guard let manifest = manifest(novelID: novelID), !manifest.bulks.isEmpty else { return 0 }
        let stored = storedBulkFingerprints(novelID: novelID)
        var covered = 0
        for (index, bulk) in manifest.bulks.enumerated() {
            guard stored["\(bulk.chapter)"] != nil else { break }
            if index + 1 < manifest.bulks.count {
                covered = manifest.bulks[index + 1].chapter
            } else {
                covered = max(manifest.chapterCount, bulk.chapter + 1)
            }
        }
        return covered
    }

    /// 指定章が読める(はずの)バルクを受信済みか。バルク内の歯抜けまでは確認しない(軽い判定)
    static func hasChapter(novelID: String, chapter: Int) -> Bool {
        return chapter >= 1 && chapter <= storedChapterCount(novelID: novelID)
    }

    // MARK: 本文の読み出し(バルク単位のオンデマンド展開)

    /// RealmStoryBulk.CalcBulkChapterNumber と同じ(100章 = 1バルク)
    private static let bulkSize = 100
    /// 指定の章を含むバルクの開始章番号(didUpdateNotification の "bulkChapter" との照合にも使う)
    static func bulkChapter(for chapter: Int) -> Int {
        return ((chapter - 1) / bulkSize) * bulkSize
    }

    /// 指定章の本文を読み出す。必要なバルクだけを展開する(展開結果は少数キャッシュされる)
    static func chapter(novelID: String, chapter: Int) -> StoredChapter? {
        guard chapter >= 1 else { return nil }
        return loadBulk(novelID: novelID, bulkChapter: bulkChapter(for: chapter))?[chapter]
    }

    /// 指定章の「次の章」が別バルクなら、そのバルクをバックグラウンドで展開してキャッシュに
    /// 温めておく(発話がバルク境界をまたぐ時に待たせないため)
    static func prefetchNextBulkIfNeeded(novelID: String, currentChapter: Int) {
        let current = bulkChapter(for: currentChapter)
        let next = bulkChapter(for: currentChapter + 1)
        guard next != current, hasChapter(novelID: novelID, chapter: currentChapter + 1) else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = loadBulk(novelID: novelID, bulkChapter: next)
        }
    }

    /// 保存済みの最初の章番号(通常は 1)。先頭バルクの展開を伴う
    static func firstStoredChapter(novelID: String) -> Int? {
        guard let manifest = manifest(novelID: novelID), let firstBulk = manifest.bulks.first else { return nil }
        return loadBulk(novelID: novelID, bulkChapter: firstBulk.chapter)?.keys.min()
    }

    private static func loadBulk(novelID: String, bulkChapter: Int) -> [Int: StoredChapter]? {
        if let cached = cache.bulk(novelID: novelID, bulkChapter: bulkChapter) { return cached }
        // manifest と一致するバルクを優先し、無ければ同じ開始章の手持ち(更新転送の途中でも読めるように)
        let dir = novelDirectory(novelID: novelID)
        var url: URL?
        if let fingerprint = manifest(novelID: novelID)?.bulks.first(where: { $0.chapter == bulkChapter })?.fingerprint,
           FileManager.default.fileExists(atPath: bulkFileURL(novelID: novelID, chapter: bulkChapter, fingerprint: fingerprint).path) {
            url = bulkFileURL(novelID: novelID, chapter: bulkChapter, fingerprint: fingerprint)
        } else if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            url = files.first { $0.lastPathComponent.hasPrefix("bulk_\(bulkChapter)_") }
        }
        guard let bulkURL = url,
              let compressed = try? Data(contentsOf: bulkURL),
              let raw = LZFSE.decompress(data: compressed) else { return nil }
        // iPhone の Story と同じ JSON キー。必要な3つだけ読む(url/novelID/downloadDate は無視される)
        struct BulkStory: Codable {
            let subtitle: String
            let content: String
            let chapterNumber: Int
        }
        guard let storyArray = try? JSONDecoder().decode([BulkStory].self, from: raw) else { return nil }
        var stories: [Int: StoredChapter] = [:]
        for story in storyArray {
            // iPhone は Story のデコード時に改行を正規化している(保存データは正規化前)ので、
            // 発話ブロック分割や位置同期が iPhone とズレないよう同じ正規化をかける
            stories[story.chapterNumber] = StoredChapter(
                subtitle: story.subtitle,
                content: normalizeNewlines(story.content))
        }
        guard !stories.isEmpty else { return nil }
        cache.storeBulk(novelID: novelID, bulkChapter: bulkChapter, stories: stories)
        return stories
    }

    /// NovelSpeakerUtility.NormalizeNewlineString と同じ変換
    private static let newlinePattern = "(\r\n|[\r\u{000B}\u{000C}\u{0085}\u{2028}\u{2029}])"
    private static let newlineDetectSet = CharacterSet(charactersIn: "\r\u{000B}\u{000C}\u{0085}\u{2028}\u{2029}")
    private static func normalizeNewlines(_ string: String) -> String {
        // ほとんどの本文は \n のみなので、対象文字が無ければ正規表現を走らせない
        guard string.rangeOfCharacter(from: newlineDetectSet) != nil else { return string }
        return string.replacingOccurrences(of: newlinePattern, with: "\n", options: [.regularExpression])
    }
}

/// NovelStorage のメモリキャッシュ(展開済みバルク+manifest)。
/// バルクは「現在のバルク+先読みした次のバルク+α」だけ保持できればよいので少数の LRU
private final class NovelStorageCache {
    private let lock = NSLock()
    private var manifests: [String: NovelStorage.Manifest] = [:]
    private var bulks: [String: [Int: NovelStorage.StoredChapter]] = [:]
    private var bulkOrder: [String] = []
    private let bulkLimit = 3

    func manifest(novelID: String) -> NovelStorage.Manifest? {
        lock.lock(); defer { lock.unlock() }
        return manifests[novelID]
    }

    func storeManifest(novelID: String, manifest: NovelStorage.Manifest) {
        lock.lock(); defer { lock.unlock() }
        manifests[novelID] = manifest
    }

    func bulk(novelID: String, bulkChapter: Int) -> [Int: NovelStorage.StoredChapter]? {
        lock.lock(); defer { lock.unlock() }
        return bulks["\(novelID)#\(bulkChapter)"]
    }

    func storeBulk(novelID: String, bulkChapter: Int, stories: [Int: NovelStorage.StoredChapter]) {
        lock.lock(); defer { lock.unlock() }
        let key = "\(novelID)#\(bulkChapter)"
        if bulks[key] == nil {
            bulkOrder.append(key)
            if bulkOrder.count > bulkLimit {
                bulks.removeValue(forKey: bulkOrder.removeFirst())
            }
        }
        bulks[key] = stories
    }

    func invalidate(novelID: String) {
        lock.lock(); defer { lock.unlock() }
        manifests.removeValue(forKey: novelID)
        let prefix = "\(novelID)#"
        bulkOrder.removeAll { key in
            guard key.hasPrefix(prefix) else { return false }
            bulks.removeValue(forKey: key)
            return true
        }
    }
}

/// LZFSE の解凍(Compression framework)。
/// iPhone 側の NiftyUtility.compress()(DataCompression pod の compress(withAlgorithm: .lzfse))が
/// 作る「ヘッダ無しの compression_stream 生ストリーム」を解凍する。
/// 入力を 64KB ずつ与えると Apple の LZFSE デコーダが FINALIZE フラグ付きで稀に失敗する既知の
/// 問題があるため、DataCompression と同じく大きい入力ではフラグを 0 にして最後だけ FINALIZE にする
enum LZFSE {
    static func decompress(data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let sourceSize = rawBuffer.count
            var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 1),
                                            dst_size: 0, src_ptr: source, src_size: 0, state: nil)
            stream.dst_ptr.deallocate()
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE) != COMPRESSION_STATUS_ERROR else { return nil }
            defer { compression_stream_destroy(&stream) }

            let blockLimit = 64 * 1024
            let bufferSize = min(max(sourceSize, 64), blockLimit)
            var flags: Int32 = sourceSize > blockLimit ? 0 : Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            var result = Data()
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            stream.src_ptr = source
            stream.src_size = sourceSize
            while true {
                switch compression_stream_process(&stream, flags) {
                case COMPRESSION_STATUS_OK:
                    guard stream.dst_size == 0 else { return nil }
                    result.append(buffer, count: stream.dst_ptr - buffer)
                    stream.dst_ptr = buffer
                    stream.dst_size = bufferSize
                    if flags == 0 && stream.src_size == 0 {
                        flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    }
                case COMPRESSION_STATUS_END:
                    result.append(buffer, count: stream.dst_ptr - buffer)
                    return result
                default:
                    return nil
                }
            }
        }
    }
}
