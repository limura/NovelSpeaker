//
//  VoicevoxCacheGeneration.swift
//  NovelSpeaker
//
//  音声キャッシュの生成まわりの、VOICEVOX 実体に依らない部分
//  (進捗の表示・先にどれだけ貯まっているかの計算・生成の有効/無効と再開位置)。
//

import Foundation

/// 生成の進み具合。
///
/// 「ここまで作れているなら、このまま持ち出していいかな」を利用者が判断できる事を狙う。
/// そのため「何ブロック目」ではなく、ページ位置と合計時間で出す。
///
/// 「第2話」のような言い方は使わない。実機で『第2話「第1話」の34%』という表示になり
/// (2ページ目の章題が「第1話」だった)、何を指しているのか分からなくなった。
/// ページ番号は「Nページ目/全Mページ」と明示し、章題は引用符でくくって区別する。
///
/// 「Nページ目から開始」という言い方もしない。**作ってある範囲は連続とは限らない**ため。
/// 100〜102ページを作った後で1ページ目に戻って作り始めると、1ページ目付近と
/// 100〜102ページの二箇所が出来ている状態になり、「Nページ目から102ページ目まで」と
/// 読める表示はどう書いても嘘になる。
/// 代わりに「作成済み87ページ・合計3時間12分」と、連続性を主張しない形で出す。
struct VoicevoxCacheGenerationProgress {
    let chapterNumber: Int
    let chapterTitle: String
    let generatedBlockCount: Int
    let totalBlockCount: Int
    /// その小説について貯まっている音声の合計秒数。
    let totalAudioSeconds: Double
    /// 全ページ数(分からなければ nil)。
    var lastChapterNumber: Int? = nil
    /// 音声が1つでも作ってあるページの数(連続しているとは限らない)。
    var generatedChapterCount: Int = 0
    /// 背面に入って一時停止しているか。
    var isPausedByBackground: Bool = false
    /// 小説の更新確認(ダウンロード)中で一時停止しているか。
    var isPausedByDownload: Bool = false

    var chapterPercent: Int {
        // 読み上げる物が無い話(空ページ等)は、作り終えている扱いにする(0除算も避ける)。
        guard totalBlockCount > 0 else { return 100 }
        let percent = Int((Double(generatedBlockCount) / Double(totalBlockCount) * 100).rounded())
        return max(0, min(100, percent))
    }

    var pauseReasonText: String? {
        if isPausedByBackground {
            return NSLocalizedString("VoicevoxCacheGeneration_PausedByBackground", comment: "画面が消えた(背面にある)ため一時停止中")
        }
        if isPausedByDownload {
            return NSLocalizedString("VoicevoxCacheGeneration_PausedByDownload", comment: "小説の更新確認中のため一時停止中")
        }
        return nil
    }

    var description: String {
        // 「Nページ目」「Nページ目/全Mページ」「〜「章題」」までを1つの塊にしてから
        // 「〜の何%を生成中」に差し込む。英語では語順が丸ごと変わるため、
        // 部品を連結せずに書式文字列側で並べ替えられるようにしてある。
        var location: String
        if let last = lastChapterNumber {
            location = String(format: NSLocalizedString(
                "VoicevoxCacheGeneration_PageNumberOfTotalFormat",
                comment: "%1$dページ目/全%2$dページ"), chapterNumber, last)
        } else {
            location = String(format: NSLocalizedString(
                "VoicevoxCacheGeneration_PageNumberFormat", comment: "%dページ目"), chapterNumber)
        }
        if chapterTitle.isEmpty == false {
            location = String(format: NSLocalizedString(
                "VoicevoxCacheGeneration_PageWithTitleFormat", comment: "%1$@「%2$@」"), location, chapterTitle)
        }
        var text = String(format: NSLocalizedString(
            "VoicevoxCacheGeneration_GeneratingFormat",
            comment: "%1$@の%2$d%%を生成中"), location, chapterPercent)
        text += "\n" + Self.storedText(chapterCount: generatedChapterCount, audioSeconds: totalAudioSeconds)
        if let reason = pauseReasonText {
            text += "\n\(reason)"
        }
        return text
    }

    /// 作ってある量の言い方。連続性を主張しない
    /// (「Nページ目まで作成済み」と書くと、その手前が全部あるように読める)。
    static func storedText(chapterCount: Int, audioSeconds: Double) -> String {
        return String(format: NSLocalizedString(
            "VoicevoxCacheGeneration_StoredFormat",
            comment: "%1$dページぶん作成済み・合計%2$@"), chapterCount, durationText(seconds: audioSeconds))
    }

    static func durationText(seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return String(format: NSLocalizedString(
                "VoicevoxCacheGeneration_DurationHoursMinutesFormat",
                comment: "%1$d時間%2$d分"), total / 3600, (total % 3600) / 60)
        }
        if total >= 60 {
            return String(format: NSLocalizedString(
                "VoicevoxCacheGeneration_DurationMinutesSecondsFormat",
                comment: "%1$d分%2$d秒"), total / 60, total % 60)
        }
        return String(format: NSLocalizedString(
            "VoicevoxCacheGeneration_DurationSecondsFormat", comment: "%d秒"), total)
    }
}

/// 再生位置から先に、どれだけ音声が貯まっているか。
enum VoicevoxCacheLead {

    /// この分数を下回っていたら、再生中でも生成を続ける。
    ///
    /// キャッシュから再生している間は合成の CPU がゼロなので、80% の予算が丸ごと空く。
    /// 生成には最良の条件で、ここで作っておかないと、キャッシュを使い切った瞬間から
    /// 無音だらけの実時間合成に戻ってしまう。
    /// 一方で十分に貯まっているなら、聴き終わらないかもしれない分を作るのは電池の無駄。
    ///
    /// 適切な値は「どのくらい先まで聴き続けるか」「端末がどれだけ速いか」で変わり、
    /// 手元の実測だけで決め打ちできる自信が無いので設定から変えられるようにしてある。
    /// 0 にすると「再生中は生成しない」になる。
    static let defaultKeepGeneratingBelowMinutes = 15
    static let keepGeneratingBelowMinutesUserDefaultsKey = "NovelSpeaker.Voicevox.diskCacheKeepGeneratingBelowMinutes"

    static var keepGeneratingBelowMinutes: Int {
        get {
            guard let stored = UserDefaults.standard.object(forKey: keepGeneratingBelowMinutesUserDefaultsKey) as? Int else {
                return defaultKeepGeneratingBelowMinutes
            }
            return max(0, stored)
        }
        set { UserDefaults.standard.set(max(0, newValue), forKey: keepGeneratingBelowMinutesUserDefaultsKey) }
    }

    static var keepGeneratingBelowSeconds: Double {
        return Double(keepGeneratingBelowMinutes) * 60
    }

    /// 再生位置から先の、**途切れずに繋がっている**キャッシュの秒数。
    /// 穴の向こうに何時間分あっても、穴に当たった時点で無音になるので数えない。
    /// - Parameter upcomingDurations: これから再生する順に並んだ各ブロックの長さ(nil = 未生成)。
    static func contiguousSeconds(upcomingDurations: [Double?]) -> Double {
        var total = 0.0
        for duration in upcomingDurations {
            guard let duration = duration else { break }
            total += duration
        }
        return total
    }

    static func shouldKeepGenerating(contiguousLeadSeconds: Double, thresholdSeconds: Double) -> Bool {
        return contiguousLeadSeconds < thresholdSeconds
    }

    static func shouldKeepGenerating(contiguousLeadSeconds: Double) -> Bool {
        return shouldKeepGenerating(contiguousLeadSeconds: contiguousLeadSeconds, thresholdSeconds: keepGeneratingBelowSeconds)
    }

    /// 今の再生位置から先に、**途切れずに**貯めてある音声の秒数。
    ///
    /// 今読んでいるページの残りを1ブロックずつ数え、ページを跨いだ後は
    /// 「そのページに貯めてある合計」を足していき、何も無いページで打ち切る。
    /// 後半は概算で、部分的にしか出来ていないページを丸ごと数えてしまうが、
    /// 生成は前から順に埋めていくので、そういうページは境目の1つだけになる
    /// (=多く見積もってもそのページ1つぶん)。
    ///
    /// ブロック列の取り出し(StorySpeaker 依存)は呼ぶ側に置いてある。
    /// この判断が狂うと作り足しが止まらなくなるので、ここだけはテストから叩けるようにしておく。
    static func contiguousLeadSeconds(store: VoicevoxDiskCacheStore,
                                      novelID: String,
                                      chapterNumber: Int,
                                      upcomingDurations: [Double?]) -> Double {
        var lead = contiguousSeconds(upcomingDurations: upcomingDurations)

        // このページの最後まで揃っている時だけ、次のページ以降も数える。
        guard upcomingDurations.contains(where: { $0 == nil }) == false else { return lead }

        var nextChapterNumber = chapterNumber + 1
        while true {
            let summary = store.summaryInAnyArea(novelID: novelID, chapterNumber: nextChapterNumber)
            if summary.entryCount == 0 { break }
            lead += summary.audioSeconds
            nextChapterNumber += 1
            // 何時間も先まで数えても判断は変わらないので、適当な所で切り上げる。
            if lead >= keepGeneratingBelowSeconds { break }
        }
        return lead
    }
}

/// どの小説でキャッシュ生成を有効にしているか。
///
/// Realm ではなく UserDefaults に置く。生成済み音声そのものが端末ローカル限定
/// (他端末では話者(VVM)が入っているとは限らず、読み替え辞書も同じとは限らない)なので、
/// 同期する意味が無く、Realm に足すとバックアップ/CloudKit同期/Realm間コピー/件数表示の
/// 並行リストを全部触る必要が出てしまう。
/// 失われても「今の再生位置から作り直す」だけで済む情報しか持たせない。
///
/// 「どこまで作ったか」は覚えない。生成は常に今の読み上げ位置から始めて、
/// 既に作ってある分を飛ばしていく形にしたため(読み上げ位置を前に戻してから
/// 生成を始めた時に、ずっと先の続きが作られてしまうのを避けるため)。
final class VoicevoxCacheGenerationState {

    /// 生成を始める位置。
    struct Position: Equatable {
        let chapterNumber: Int
        let blockIndex: Int
    }

    static let shared = VoicevoxCacheGenerationState(userDefaults: UserDefaults.standard)

    private static let enabledNovelIDsKey = "NovelSpeaker.Voicevox.diskCacheEnabledNovelIDs"

    private let userDefaults: UserDefaults
    private let lock = NSLock()

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func enabledNovelIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.stringArray(forKey: Self.enabledNovelIDsKey) ?? []
    }

    func isEnabled(novelID: String) -> Bool {
        return enabledNovelIDs().contains(novelID)
    }

    func setEnabled(_ enabled: Bool, novelID: String) {
        lock.lock()
        var ids = userDefaults.stringArray(forKey: Self.enabledNovelIDsKey) ?? []
        if enabled {
            if ids.contains(novelID) == false { ids.append(novelID) }
        } else {
            ids.removeAll(where: { $0 == novelID })
        }
        userDefaults.set(ids, forKey: Self.enabledNovelIDsKey)
        lock.unlock()
    }
}
