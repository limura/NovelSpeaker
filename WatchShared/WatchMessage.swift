//
//  WatchMessage.swift
//  NovelSpeaker
//
//  iOS 側と watchOS 側の両ターゲットでコンパイルされる、WCSession メッセージの共通定義。
//  Foundation 以外に依存しないこと(Realm/UIKit/WatchKit を import しない)。
//

import Foundation

/// WCSession でやりとりするメッセージの共通定義
enum WatchMessage {
    /// sendMessage の辞書に必ず入れるコマンド種別のキー
    static let commandKey = "cmd"

    /// Watch → iPhone のコマンド種別
    enum Command: String {
        // 再生操作(iPhone 側 StorySpeaker への遠隔操作)
        case togglePlayPause
        /// 再生の開始のみ(既に再生中なら何もしない)。ウィジェット「iPhoneで再生」用
        /// (トグルだと再生中に押した時に止めてしまうため別コマンド)
        case startSpeech
        case skipBackward
        case skipForward
        case previousChapter
        case nextChapter
        /// 指定小説を開く(args: novelID)。開くだけで再生はしない
        case openNovel
        /// 指定小説を開いて再生を開始する(args: novelID)。ウィジェット「この小説を再生」用
        case playNovel
        // 便利機能
        case checkUpdatesAll
        case checkUpdates      // args: novelID
        case setLike           // args: novelID, enabled(Bool)
        /// 小説本文の転送依頼(特急転送) args: novelID
        case requestTransfer
        /// 現在状態と小説一覧の再送を依頼
        case requestStatus
        /// 指定した novelID 群が iPhone の本棚にまだ存在するか確認する
        /// (本棚から削除された小説の孤児キャッシュを Watch 側で掃除するため)
        case checkNovelExistence
        /// Watch 単体再生の発話直前に、手元の発話設定(args: fingerprint)が最新か確認する。
        /// 古ければ iPhone 側が transferFile を積む(reply: settingsUpToDate)
        case syncSpeechSettings
        // 本文表示の位置購読(purchase/subscribe モデル)
        case subscribeSpeechBlock
        case unsubscribeSpeechBlock
        /// デフォルト話者の速度・音量を変更する(args: rate, volume)。
        /// iPhone 側の RealmSpeakerSetting に保存され、発話中なら次のブロックから反映される
        case setDefaultSpeakerConfig
        /// 「再生が末尾に達した時の動作」を変更する(args: repeatType, loopNoCheck)。
        /// iPhone 側の RealmGlobalState に保存される
        case setRepeatSpeechConfig
    }

    /// コマンド引数のキー
    enum Arg {
        static let novelID = "novelID"
        static let novelIDs = "novelIDs"
        static let enabled = "enabled"
        static let chapterNumber = "chapter"
        static let location = "location"
        /// Watch が保存している発話設定の指紋(SHA256 hex)
        static let fingerprint = "fingerprint"
        /// 発話速度(Double, AVSpeechUtterance.rate と同じ 0.0-1.0)
        static let rate = "rate"
        /// 発話音量(Double, 0.0-1.0)
        static let volume = "volume"
        /// 「再生が末尾に達した時の動作」(Int, WatchRepeatSpeechType の rawValue)
        static let repeatType = "repeatType"
        /// 「次の小説の選択方式」が「順に1ページ目から再生」か(Bool)
        static let loopNoCheckReadingPoint = "loopNoCheck"
        /// requestTransfer: Watch が保存済みの本文バルクの指紋
        /// ([String: String]、キーはバルク開始章番号の文字列、値は SHA256 hex)。
        /// iPhone はこれと一致するバルクの送信を省略する(差分転送)
        static let bulkFingerprints = "bulkFingerprints"
    }

    /// iPhone → Watch: applicationContext のキー
    enum Context {
        /// 再生状態辞書(PlayState を辞書化したもの)
        static let playState = "playState"
        /// 小説一覧([辞書] NovelSummary を辞書化したもの)
        static let novelList = "novelList"
        /// 送信時刻(TimeInterval)。古い context の判別用
        static let sentAt = "sentAt"
        /// iPhone の本棚の並び順のグループ種別(String)。Watch の「iPhoneと同じ」表示が
        /// iPhone と同じフォルダ分けを再現するのに使う。
        /// 値: "folder" / "writer" / "website" / "readDateBuckets" / "downloadDateBuckets" /
        ///     "unreadBuckets" / "flat"(グループ無し。再現できない種別も flat)
        static let phoneSortGrouping = "sortGrouping"
        /// iPhone が最後に転送キューへ積んだ小説一覧(全量ファイル)の指紋(String)。
        /// Watch は受信済みファイルの指紋と比較して「同期中…」表示を出すのに使う
        static let novelListFingerprint = "novelListFingerprint"
        /// iPhone 側で本文(RealmStoryBulk)が最後に変化した時刻(TimeInterval)。
        /// 章数が変わらない内容だけの更新(誤字修正等)は章数比較では検知できないため、
        /// Watch はこの値が前回確認時より進んでいたら転送済み小説を指紋付きで再依頼する
        /// (変わっていない小説はマニフェスト1個が返るだけの軽い往復で済む)
        static let bulkChangeToken = "bulkChangeToken"
        /// Watch→iPhone 方向: Watch に本文が転送されている小説の novelID 一覧([String])
        static let watchStoredNovelIDs = "storedNovelIDs"
        /// Watch→iPhone 方向: Watch が受信済みの小説一覧ファイルの指紋(String、未受信なら "")。
        /// iPhone は自分が最後に送った指紋と比較し、違えば一覧ファイルを送り直す
        /// (再インストール等でファイルが消えた Watch に「送信済みだから送らない」とならないように)
        static let watchNovelListReceivedFingerprint = "receivedNovelListFingerprint"
        /// Watch→iPhone 方向: Watch 単体再生の読み上げ位置
        /// (辞書: novelID/chapter/location/updatedAt(TimeInterval))
        /// 旧形式(最新1件)。新しい watchReadingPositions が使えない場合のフォールバック用に残す
        static let watchReadingPosition = "readingPosition"
        /// Watch→iPhone 方向: Watch 単体再生の読み上げ位置(直近の複数件、上と同じ辞書の配列)。
        /// 連続再生で複数の小説を読み終えた場合も、読了位置が漏れずに iPhone の栞へ反映されるように
        static let watchReadingPositions = "readingPositions"
    }

    /// iPhone → Watch: 返信ではない片方向プッシュ(sendMessage, replyHandler なし)のキー
    enum Push {
        /// 本文ページの購読(subscribeSpeechBlock)中に送られる読み上げ位置。
        /// 値は辞書: novelID(String) / chapter(Int) / location(Int, 表示文字ベース)
        static let readingPoint = "readingPoint"
    }

    /// コマンドへの返信辞書のキー
    enum Reply {
        static let ok = "ok"
        static let errorMessage = "error"
        /// 返信に相乗りする最新の再生状態
        static let playState = "playState"
        /// checkNovelExistence の返信: 本棚に存在しなかった novelID 群
        static let missingNovelIDs = "missing"
        /// syncSpeechSettings の返信: Watch の発話設定が最新なら true(false ならファイルが届く)
        static let speechSettingsUpToDate = "settingsUpToDate"
    }
}

/// 小説一覧ファイル(transferFile)の共通定義。
/// 本棚が大きいと applicationContext のサイズ上限に収まらないため、全量はファイルで送る。
/// applicationContext の novelList(先頭 novelListLimit 冊)は旧バージョン互換と
/// ファイル未着時のフォールバック用
enum WatchNovelListFile {
    static let transferTypeKey = "type"
    static let transferTypeValue = "novelList"
    static let transferFingerprintKey = "fingerprint"
    /// ファイル JSON のトップレベルキー(値は WatchNovelSummary 辞書の配列、本棚の並び順)
    static let novelsKey = "novels"
}

/// 小説本文の転送(transferFile)の共通定義。
/// iPhone の RealmStoryBulk が保存している「最大100章ぶんの [Story] JSON を LZFSE 圧縮した
/// バイナリ」を無加工のまま転送・保存する(iPhone 側で展開・再構築しない)。
/// 転送は「変わったバルクだけ」+「manifest(全バルクの指紋一覧)」の組で行い、
/// 1章の更新で全章を送り直さずに済むようにする。Watch 側は manifest と手元のバルクを
/// 突き合わせて完成/不足を判定する
enum WatchNovelBulkFile {
    static let transferTypeKey = "type"
    /// バルク1個(LZFSE 圧縮された [Story] JSON)
    static let bulkTypeValue = "novelBulk"
    /// manifest(JSON)。バルクを全部積んだ後に送る
    static let manifestTypeValue = "novelManifest"
    static let novelIDKey = "novelID"
    /// バルクの開始章番号(RealmStoryBulk.chapterNumber と同じ。0, 100, 200, ...)
    static let bulkChapterKey = "bulkChapter"
    /// 今回の転送で何個目のバルクか(0始まり)。Watch 側の「転送中 (n/m)」進捗表示用。
    /// 依頼への返信に載せない(巨大小説では指紋計算が sendMessage の返信期限に間に合わない)で、
    /// 届いたバルク自身に載せることでタイミング問題を避ける
    static let queueIndexKey = "queueIndex"
    /// 今回の転送で送るバルクの総数(差分転送なので「小説全体のバルク数」ではない)
    static let queueTotalKey = "queueTotal"
    /// バルクバイナリの SHA256 hex
    static let fingerprintKey = "fingerprint"

    // manifest JSON のキー
    static let manifestTitleKey = "title"
    /// 小説の最終章番号(RealmNovel.lastChapterNumber)
    static let manifestChapterCountKey = "chapterCount"
    /// [{"chapter": Int, "fingerprint": String}] (chapter 昇順)
    static let manifestBulksKey = "bulks"
}

/// iPhone の現在の再生状態。applicationContext / sendMessage 返信で Watch へ送る
struct WatchPlayState {
    var novelID: String = ""
    var title: String = ""
    var chapterNumber: Int = 0
    var chapterCount: Int = 0
    /// 現在の章タイトル(subtitle)。無い章もある。コンプリケーション表示に使う
    var chapterSubtitle: String = ""
    var isPlaying: Bool = false
    /// 章内の読み上げ位置(0.0-1.0)
    var progress: Double = 0
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    /// 栞の位置(読み上げ中の章内の文字オフセット)。Watch 単体再生の開始位置同期に使う
    var readingLocation: Int = 0
    /// 栞の更新日時(RealmNovel.lastReadDate)。Watch ローカル位置との「新しい方優先」比較に使う
    var bookmarkUpdatedAt: Date = Date(timeIntervalSince1970: 0)

    func toDictionary() -> [String: Any] {
        return [
            "novelID": novelID,
            "title": title,
            "chapterNumber": chapterNumber,
            "chapterCount": chapterCount,
            "chapterSubtitle": chapterSubtitle,
            "isPlaying": isPlaying,
            "progress": progress,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "readingLocation": readingLocation,
            "bookmarkUpdatedAt": bookmarkUpdatedAt.timeIntervalSince1970,
        ]
    }

    static func from(dictionary: [String: Any]) -> WatchPlayState? {
        guard let novelID = dictionary["novelID"] as? String else { return nil }
        var state = WatchPlayState()
        state.novelID = novelID
        state.title = dictionary["title"] as? String ?? ""
        state.chapterNumber = dictionary["chapterNumber"] as? Int ?? 0
        state.chapterCount = dictionary["chapterCount"] as? Int ?? 0
        state.chapterSubtitle = dictionary["chapterSubtitle"] as? String ?? ""
        state.isPlaying = dictionary["isPlaying"] as? Bool ?? false
        state.progress = dictionary["progress"] as? Double ?? 0
        state.updatedAt = Date(timeIntervalSince1970: dictionary["updatedAt"] as? TimeInterval ?? 0)
        state.readingLocation = dictionary["readingLocation"] as? Int ?? 0
        state.bookmarkUpdatedAt = Date(timeIntervalSince1970: dictionary["bookmarkUpdatedAt"] as? TimeInterval ?? 0)
        return state
    }
}

/// 本棚一覧用の小説メタデータ(1件分)。applicationContext で全小説分を Watch へ送る
struct WatchNovelSummary {
    var novelID: String = ""
    var title: String = ""
    var isLiked: Bool = false
    var chapterCount: Int = 0
    /// 読み上げ中(しおり)の章番号
    var readingChapterNumber: Int = 0
    /// 作者名(「同じ作者の小説を再生」の候補選びと本棚の作者順に使う)
    var writer: String = ""
    /// 栞の更新日時(本棚の「小説を開いた日時順」に使う)
    var lastReadDate: Date = Date(timeIntervalSince1970: 0)
    /// 最終ダウンロード日時(本棚の「最終ダウンロード日時順」に使う)
    var lastDownloadDate: Date = Date(timeIntervalSince1970: 0)
    /// 本棚に登録した日時(本棚の「本棚登録順」に使う)
    var createdDate: Date = Date(timeIntervalSince1970: 0)
    /// 栞の章内位置(「未読章数別」の読了判定に使う。iPhone の m_readingChapterReadingPoint)
    var readingChapterReadingPoint: Int = 0
    /// 栞の章の本文の長さ(同上。iPhone の m_readingChapterContentCount)
    var readingChapterContentCount: Int = 0

    func toDictionary() -> [String: Any] {
        return [
            "id": novelID,
            "title": title,
            "like": isLiked,
            "chapters": chapterCount,
            "reading": readingChapterNumber,
            "writer": writer,
            "lastRead": lastReadDate.timeIntervalSince1970,
            "lastDownload": lastDownloadDate.timeIntervalSince1970,
            "created": createdDate.timeIntervalSince1970,
            "readPoint": readingChapterReadingPoint,
            "readContentCount": readingChapterContentCount,
        ]
    }

    static func from(dictionary: [String: Any]) -> WatchNovelSummary? {
        guard let novelID = dictionary["id"] as? String else { return nil }
        var summary = WatchNovelSummary()
        summary.novelID = novelID
        summary.title = dictionary["title"] as? String ?? ""
        summary.isLiked = dictionary["like"] as? Bool ?? false
        summary.chapterCount = dictionary["chapters"] as? Int ?? 0
        summary.readingChapterNumber = dictionary["reading"] as? Int ?? 0
        summary.writer = dictionary["writer"] as? String ?? ""
        summary.lastReadDate = Date(timeIntervalSince1970: dictionary["lastRead"] as? TimeInterval ?? 0)
        summary.lastDownloadDate = Date(timeIntervalSince1970: dictionary["lastDownload"] as? TimeInterval ?? 0)
        summary.createdDate = Date(timeIntervalSince1970: dictionary["created"] as? TimeInterval ?? 0)
        summary.readingChapterReadingPoint = dictionary["readPoint"] as? Int ?? 0
        summary.readingChapterContentCount = dictionary["readContentCount"] as? Int ?? 0
        return summary
    }
}
