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
/// また、開始ページも併記する。100ページ目から作り始めた時に「102/1000ページ目」とだけ
/// 出ていると、最初の102ページぶんが出来ているように読めてしまうため。
struct VoicevoxCacheGenerationProgress {
    let chapterNumber: Int
    let chapterTitle: String
    let generatedBlockCount: Int
    let totalBlockCount: Int
    /// その小説について貯まっている音声の合計秒数。
    let totalAudioSeconds: Double
    /// 全ページ数(分からなければ nil)。
    var lastChapterNumber: Int? = nil
    /// この生成を始めたページ。
    var startChapterNumber: Int? = nil
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
        if isPausedByBackground { return "画面が消えた(背面にある)ため一時停止中" }
        if isPausedByDownload { return "小説の更新確認中のため一時停止中" }
        return nil
    }

    var description: String {
        var text = "\(chapterNumber)ページ目"
        if let last = lastChapterNumber { text += "/全\(last)ページ" }
        if chapterTitle.isEmpty == false { text += "「\(chapterTitle)」" }
        text += "の\(chapterPercent)%まで生成"
        if let start = startChapterNumber {
            text += "(\(start)ページ目から開始)"
        }
        text += "・この小説の合計\(Self.durationText(seconds: totalAudioSeconds))"
        if let reason = pauseReasonText {
            text += "\n\(reason)"
        }
        return text
    }

    static func durationText(seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return "\(total / 3600)時間\((total % 3600) / 60)分"
        }
        if total >= 60 {
            return "\(total / 60)分\(total % 60)秒"
        }
        return "\(total)秒"
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
}

/// どの小説でキャッシュ生成を有効にしているか、どこまで作ったか。
///
/// Realm ではなく UserDefaults に置く。生成済み音声そのものが端末ローカル限定
/// (他端末では話者(VVM)が入っているとは限らず、読み替え辞書も同じとは限らない)なので、
/// 同期する意味が無く、Realm に足すとバックアップ/CloudKit同期/Realm間コピー/件数表示の
/// 並行リストを全部触る必要が出てしまう。
/// 失われても「今の再生位置から作り直す」だけで済む情報しか持たせない。
final class VoicevoxCacheGenerationState {

    struct Position: Equatable {
        let chapterNumber: Int
        let blockIndex: Int
    }

    static let shared = VoicevoxCacheGenerationState(userDefaults: UserDefaults.standard)

    private static let enabledNovelIDsKey = "NovelSpeaker.Voicevox.diskCacheEnabledNovelIDs"
    private static let resumePositionKeyPrefix = "NovelSpeaker.Voicevox.diskCacheResume."

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
        if enabled == false {
            // 次に始める時は、その時の再生位置から作り直す。
            userDefaults.removeObject(forKey: Self.resumePositionKeyPrefix + novelID)
        }
        lock.unlock()
    }

    func resumePosition(novelID: String) -> Position? {
        lock.lock()
        defer { lock.unlock() }
        guard let values = userDefaults.array(forKey: Self.resumePositionKeyPrefix + novelID) as? [Int],
              values.count == 2 else {
            return nil
        }
        return Position(chapterNumber: values[0], blockIndex: values[1])
    }

    func setResumePosition(chapterNumber: Int, blockIndex: Int, novelID: String) {
        lock.lock()
        userDefaults.set([chapterNumber, blockIndex], forKey: Self.resumePositionKeyPrefix + novelID)
        lock.unlock()
    }
}
