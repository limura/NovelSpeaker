//
//  VoicevoxVoiceModelDownloadQueue.swift
//  NovelSpeaker
//
//  音声モデルの取得待ち行列と、取得してよいかの判断。
//
//  URLSession から切り離してあるのは、この2つがテストしづらい所に埋まると
//  「モバイル通信で60MB落としてしまった」「空き容量を使い切った」といった
//  取り返しのつかない不具合を、実機で偶然踏むまで見つけられなくなるため。
//

import Foundation

struct VoicevoxVoiceModelDownloadRequest: Equatable {
    let modelID: String
    let url: URL
    let byteSize: Int64
    /// カタログが「これが入っているはず」と言っているスタイル。取り違えの検出に使う。
    let expectedStyleIds: Set<UInt32>
}

enum VoicevoxVoiceModelDownloadState: Equatable {
    case queued
    case downloading(receivedBytes: Int64, totalBytes: Int64)
    case failed(String)

    var fraction: Double {
        switch self {
        case .queued: return 0
        case .failed: return 0
        case .downloading(let received, let total):
            guard total > 0 else { return 0 }
            return min(1.0, max(0.0, Double(received) / Double(total)))
        }
    }
}

/// 取得を始めてよいか。始められない場合はその理由。
enum VoicevoxVoiceModelDownloadBlocker: Equatable {
    /// モバイル通信中で、モバイル通信での取得が許可されていない
    case needsWiFi
    /// 空き容量が足りない
    case notEnoughSpace(requiredBytes: Int64, freeBytes: Int64)
    /// 既に持っている
    case alreadyStored
}

enum VoicevoxVoiceModelDownloadPolicy {
    /// 取得後もこれだけは空けておく。使い切ると端末全体が不調になるため。
    static let minimumFreeBytesAfterDownload: Int64 = 500 * 1024 * 1024

    static func blocker(byteSize: Int64,
                        isAlreadyStored: Bool,
                        isOnCellular: Bool,
                        allowsCellular: Bool,
                        freeBytes: Int64) -> VoicevoxVoiceModelDownloadBlocker? {
        if isAlreadyStored { return .alreadyStored }
        if isOnCellular && allowsCellular == false { return .needsWiFi }
        let required = byteSize + minimumFreeBytesAfterDownload
        if freeBytes < required {
            return .notEnoughSpace(requiredBytes: required, freeBytes: freeBytes)
        }
        return nil
    }
}

/// 取得待ちの行列。**同時に走らせるのは1本だけ。**
///
/// 60MB級を並行して落とすと、帯域も発熱も無駄に食う上、
/// どれも中途半端に終わって「何も使えるようにならない」時間が長くなる。
/// 1本ずつ終わらせれば、終わった物から順に使えるようになる。
final class VoicevoxVoiceModelDownloadQueue {
    private let lock = NSLock()
    private var waiting: [VoicevoxVoiceModelDownloadRequest] = []
    private var active: VoicevoxVoiceModelDownloadRequest?
    private var progress: [String: VoicevoxVoiceModelDownloadState] = [:]

    var activeModelID: String? {
        lock.lock(); defer { lock.unlock() }
        return active?.modelID
    }

    var waitingModelIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return waiting.map { $0.modelID }
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return active == nil && waiting.isEmpty
    }

    /// 既に並んでいる/走っている物は二重に積まない。
    /// - Returns: 実際に積んだら true
    @discardableResult
    func enqueue(_ request: VoicevoxVoiceModelDownloadRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if active?.modelID == request.modelID { return false }
        if waiting.contains(where: { $0.modelID == request.modelID }) { return false }
        waiting.append(request)
        progress[request.modelID] = .queued
        return true
    }

    /// 次に取得すべき物を取り出して、走っている事にする。
    /// 既に1本走っていれば nil(同時には走らせない)。
    func startNext() -> VoicevoxVoiceModelDownloadRequest? {
        lock.lock(); defer { lock.unlock() }
        guard active == nil, waiting.isEmpty == false else { return nil }
        let next = waiting.removeFirst()
        active = next
        progress[next.modelID] = .downloading(receivedBytes: 0, totalBytes: next.byteSize)
        return next
    }

    func update(modelID: String, receivedBytes: Int64, totalBytes: Int64) {
        lock.lock(); defer { lock.unlock() }
        // 走っていない物の進捗は捨てる(取り消し直後に遅れて届く事がある)。
        guard active?.modelID == modelID else { return }
        let total = totalBytes > 0 ? totalBytes : (active?.byteSize ?? 0)
        progress[modelID] = .downloading(receivedBytes: receivedBytes, totalBytes: total)
    }

    /// 成功して終わった。
    func finish(modelID: String) {
        lock.lock(); defer { lock.unlock() }
        if active?.modelID == modelID { active = nil }
        progress[modelID] = nil
    }

    /// 失敗して終わった。理由は画面に出せるように残す。
    func fail(modelID: String, reason: String) {
        lock.lock(); defer { lock.unlock() }
        if active?.modelID == modelID { active = nil }
        waiting.removeAll { $0.modelID == modelID }
        progress[modelID] = .failed(reason)
    }

    /// 取り消す。走っている物なら、走っていない事にする
    /// (実際の URLSessionTask の取り消しは呼び出し側の仕事)。
    /// - Returns: 走っている物を取り消したら true
    @discardableResult
    func cancel(modelID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        waiting.removeAll { $0.modelID == modelID }
        progress[modelID] = nil
        if active?.modelID == modelID {
            active = nil
            return true
        }
        return false
    }

    func cancelAll() -> String? {
        lock.lock(); defer { lock.unlock() }
        waiting.removeAll()
        progress.removeAll()
        let cancelled = active?.modelID
        active = nil
        return cancelled
    }

    func state(ofModelID modelID: String) -> VoicevoxVoiceModelDownloadState? {
        lock.lock(); defer { lock.unlock() }
        return progress[modelID]
    }

    func allStates() -> [String: VoicevoxVoiceModelDownloadState] {
        lock.lock(); defer { lock.unlock() }
        return progress
    }

    /// 失敗の記録だけ消す(画面で「もう一度」を押した時など)。
    func clearFailure(modelID: String) {
        lock.lock(); defer { lock.unlock() }
        if case .failed = progress[modelID] { progress[modelID] = nil }
    }
}
