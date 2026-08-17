//
//  VoicevoxCacheLimits.swift
//  NovelSpeaker
//
//  音声ディスクキャッシュの容量まわりの設定と判定。
//
//  音声1時間ぶんで約15MBなので、長編を何作も貯めると簡単に数GBに達する。
//  「気付いたらストレージが足りない」を避けるため、
//   - キャッシュ全体の上限
//   - 端末の空き容量の下限
//  の2つで止められるようにする。どちらも利用者ごとに事情が違うので設定から変えられる。
//

import Foundation

enum VoicevoxCacheLimits {

    // MARK: - キャッシュ全体の上限

    /// 0 = 無制限。
    static let defaultMaximumTotalMegabytes = 2048
    static let maximumTotalMegabytesUserDefaultsKey = "NovelSpeaker.Voicevox.diskCacheMaximumTotalMegabytes"

    static var maximumTotalMegabytes: Int {
        get {
            guard let stored = UserDefaults.standard.object(forKey: maximumTotalMegabytesUserDefaultsKey) as? Int else {
                return defaultMaximumTotalMegabytes
            }
            return max(0, stored)
        }
        set { UserDefaults.standard.set(max(0, newValue), forKey: maximumTotalMegabytesUserDefaultsKey) }
    }

    static var maximumTotalBytes: Int64 {
        return Int64(maximumTotalMegabytes) * 1024 * 1024
    }

    // MARK: - 端末の空き容量の下限

    static let defaultMinimumFreeMegabytes = 500
    static let minimumFreeMegabytesUserDefaultsKey = "NovelSpeaker.Voicevox.diskCacheMinimumFreeMegabytes"

    static var minimumFreeMegabytes: Int {
        get {
            guard let stored = UserDefaults.standard.object(forKey: minimumFreeMegabytesUserDefaultsKey) as? Int else {
                return defaultMinimumFreeMegabytes
            }
            return max(0, stored)
        }
        set { UserDefaults.standard.set(max(0, newValue), forKey: minimumFreeMegabytesUserDefaultsKey) }
    }

    static var minimumFreeBytes: Int64 {
        return Int64(minimumFreeMegabytes) * 1024 * 1024
    }

    // MARK: - 再生中の貯め込み

    /// 生成を有効にした小説で、読み上げ中に合成した分もディスクへ積むか。
    ///
    /// これが入だと、一度でも生成を有効にした小説は聴くたびにディスクが増えていく。
    /// 作り直しの手間が省ける一方、放っておくと際限なく増えるので切れるようにしておく
    /// (切っても、明示的に始めた生成と読み上げ中の自動生成では貯まる)。
    static let defaultStoresWhilePlaying = true
    static let storesWhilePlayingUserDefaultsKey = "NovelSpeaker.Voicevox.diskCacheStoresWhilePlaying"

    static var storesWhilePlaying: Bool {
        get {
            guard let stored = UserDefaults.standard.object(forKey: storesWhilePlayingUserDefaultsKey) as? Bool else {
                return defaultStoresWhilePlaying
            }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: storesWhilePlayingUserDefaultsKey) }
    }

    // MARK: - 判定

    /// 止めるべき理由(無ければ nil)。
    enum StopCause {
        case totalLimit(usedBytes: Int64, limitBytes: Int64)
        case freeSpace(freeBytes: Int64, minimumBytes: Int64)

        var message: String {
            switch self {
            case .totalLimit(let used, let limit):
                return "音声の合計が上限(\(Self.megabytesText(limit)))に達したため止めました(現在 \(Self.megabytesText(used)))"
            case .freeSpace(let free, let minimum):
                return "端末の空き容量が下限(\(Self.megabytesText(minimum)))を下回ったため止めました(残り \(Self.megabytesText(free)))"
            }
        }

        static func megabytesText(_ bytes: Int64) -> String {
            let megabytes = Double(bytes) / 1024 / 1024
            if megabytes >= 1024 {
                return String(format: "%.1fGB", megabytes / 1024)
            }
            return String(format: "%.0fMB", megabytes)
        }
    }

    /// これ以上作ってよいか。
    /// - Parameters:
    ///   - usedBytes: 今キャッシュが使っているバイト数。
    ///   - freeBytes: 端末の空きバイト数(取れなければ nil)。
    static func stopCause(usedBytes: Int64, freeBytes: Int64?) -> StopCause? {
        let limit = maximumTotalBytes
        if limit > 0 && usedBytes >= limit {
            return .totalLimit(usedBytes: usedBytes, limitBytes: limit)
        }
        let minimumFree = minimumFreeBytes
        if let freeBytes = freeBytes, minimumFree > 0, freeBytes <= minimumFree {
            return .freeSpace(freeBytes: freeBytes, minimumBytes: minimumFree)
        }
        return nil
    }
}
