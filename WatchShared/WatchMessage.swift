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
        case skipBackward
        case skipForward
        case previousChapter
        case nextChapter
        /// 指定小説を開く(args: novelID)。開くだけで再生はしない
        case openNovel
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
    }

    /// iPhone → Watch: applicationContext のキー
    enum Context {
        /// 再生状態辞書(PlayState を辞書化したもの)
        static let playState = "playState"
        /// 小説一覧([辞書] NovelSummary を辞書化したもの)
        static let novelList = "novelList"
        /// 送信時刻(TimeInterval)。古い context の判別用
        static let sentAt = "sentAt"
        /// Watch→iPhone 方向: Watch に本文が転送されている小説の novelID 一覧([String])
        static let watchStoredNovelIDs = "storedNovelIDs"
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

    func toDictionary() -> [String: Any] {
        return [
            "id": novelID,
            "title": title,
            "like": isLiked,
            "chapters": chapterCount,
            "reading": readingChapterNumber,
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
        return summary
    }
}
