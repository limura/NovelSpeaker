//
//  VoicevoxVoiceModelDownloader.swift
//  NovelSpeaker
//
//  音声モデル(VVM)を公式から取ってくる本体。
//
//  1ファイル60MB前後を、遅い回線なら何分もかけて落とす事になる。
//  そのため **background configuration の URLSession** を使う:
//  アプリを閉じても、落ちても、OS が代わりに落とし続けてくれる。
//  終わった時にアプリが起きていなければ、OS がアプリを起こして知らせてくれる
//  (AppDelegate の handleEventsForBackgroundURLSession)。
//
//  待ち行列と「取得してよいか」の判断は VoicevoxVoiceModelDownloadQueue 側にある
//  (URLSession から切り離してテストできるようにするため)。
//  ここはその判断に従って実際に投げる係。
//
//  **モバイル通信の扱いは OS に任せる。** リクエストの
//  allowsCellularAccess = false にしておけば、
//  background session は Wi-Fi に繋がるまで**待ってくれる**(失敗にならない)。
//  自前で回線を監視して止めるより確実で、繋がった瞬間に勝手に再開する。
//

import Foundation

extension Notification.Name {
    /// 取得の状態が変わった(進捗・完了・失敗)。画面の更新に使う。
    static let voicevoxVoiceModelDownloadDidChange =
        Notification.Name("NovelSpeaker.voicevoxVoiceModelDownloadDidChange")
}

final class VoicevoxVoiceModelDownloader: NSObject {
    static let shared = VoicevoxVoiceModelDownloader()

    /// background session は識別子で OS 側に紐づく。変えると前の取得を拾えなくなる。
    static let sessionIdentifier = "jp.limuraproducts.novelspeaker.voicevoxVoiceModel"

    /// モバイル通信でも取得してよいか。既定は Wi-Fi のみ。
    static var allowsCellularAccess: Bool {
        get { return UserDefaults.standard.bool(forKey: allowsCellularAccessKey) }
        set {
            let changed = Self.allowsCellularAccess != newValue
            UserDefaults.standard.set(newValue, forKey: allowsCellularAccessKey)
            if changed {
                Self.shared.applyCellularAccessPolicyIfNeeded()
            }
        }
    }
    private static let allowsCellularAccessKey = "VoicevoxVoiceModelDownloadAllowsCellular"

    let queue = VoicevoxVoiceModelDownloadQueue()
    private let store: VoicevoxVoiceModelStore
    private let readableFormats: Set<Int>

    /// OS がアプリを起こして「背面の取得が全部終わった」と伝えてきた時の後始末。
    var backgroundEventsCompletionHandler: (() -> Void)?

    /// 走っているタスクを、途中で止められるように覚えておく。
    private let taskLock = NSLock()
    private var activeTask: URLSessionDownloadTask?
    private var activeRequest: VoicevoxVoiceModelDownloadRequest?
    /// 中断からの再開に使うデータ(取得先が Range に対応していれば OS が作る)。
    private struct ResumeData {
        let data: Data
        let allowsCellularAccess: Bool
    }
    private var resumeDataByModelID: [String: ResumeData] = [:]

    /// 通信設定の変更でキャンセルしたタスク。通常の失敗として扱わず、
    /// キャンセル完了後に新しい設定で作り直す。
    private struct PolicyReconfiguration {
        let request: VoicevoxVoiceModelDownloadRequest
        var cancellationCallbackReceived = false
        var taskDidComplete = false
    }
    private var policyReconfigurations: [Int: PolicyReconfiguration] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // 電池と通信量に優しくしてもらう。急ぐ物ではない。
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        // 回線の許可・禁止はタスクごとの URLRequest で決める。
        // ここを設定値にすると、設定変更後も既存の background session に
        // 古い値が残り、新しいタスクまでセルラー通信できなくなる。
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(store: VoicevoxVoiceModelStore = .shared,
         readableFormats: Set<Int> = VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions) {
        self.store = store
        self.readableFormats = readableFormats
        super.init()
    }

    /// アプリを起こしてでも session を作り直しておく(前回の取得の続きを拾うため)。
    func resumePendingDownloadsIfNeeded() {
        session.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            // OS が引き継いでいるタスクがあれば、それが「走っている物」。
            if let running = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first {
                self.taskLock.lock()
                self.activeTask = running
                self.taskLock.unlock()
            } else {
                self.startNextIfPossible()
            }
        }
    }

    /// 設定変更後も既存タスクに古い通信許可が残らないようにする。
    /// URLSessionTask の allowsCellularAccess は後から変更できないため、
    /// 途中データを残してタスクを作り直す。
    private func applyCellularAccessPolicyIfNeeded() {
        taskLock.lock()
        let task = activeTask
        let request = activeRequest
        let isReconfiguring = policyReconfigurations.isEmpty == false
        taskLock.unlock()

        guard isReconfiguring == false else { return }
        guard let task = task, let request = request else {
            startNextIfPossible()
            return
        }
        guard VoicevoxVoiceModelDownloadPolicy.needsCellularAccessReconfiguration(
            currentTaskAllowsCellularAccess: task.currentRequest?.allowsCellularAccess,
            desiredAllowsCellularAccess: Self.allowsCellularAccess) else {
            return
        }

        let taskIdentifier = task.taskIdentifier
        taskLock.lock()
        policyReconfigurations[taskIdentifier] = PolicyReconfiguration(request: request)
        taskLock.unlock()

        // 通信許可が変わるため、resume data は新しい設定では使わない。
        // 取得先が Range 対応でも、resume data 内の古い request を
        // そのまま使うと古い通信許可が残る可能性があるため。
        _ = queue.cancel(modelID: request.modelID)
        task.cancel(byProducingResumeData: { [weak self] _ in
            self?.policyCancellationCallbackReceived(taskIdentifier: taskIdentifier)
        })
        notifyChanged()
    }

    private func policyCancellationCallbackReceived(taskIdentifier: Int) {
        var requestToRestart: VoicevoxVoiceModelDownloadRequest?
        taskLock.lock()
        if var reconfiguration = policyReconfigurations[taskIdentifier] {
            reconfiguration.cancellationCallbackReceived = true
            if reconfiguration.taskDidComplete {
                policyReconfigurations.removeValue(forKey: taskIdentifier)
                requestToRestart = reconfiguration.request
            } else {
                policyReconfigurations[taskIdentifier] = reconfiguration
            }
        }
        taskLock.unlock()

        if let requestToRestart = requestToRestart {
            restartAfterPolicyChange(taskIdentifier: taskIdentifier, request: requestToRestart)
        }
    }

    private func policyTaskDidComplete(taskIdentifier: Int) -> Bool {
        var isPolicyReconfiguration = false
        var requestToRestart: VoicevoxVoiceModelDownloadRequest?
        taskLock.lock()
        if var reconfiguration = policyReconfigurations[taskIdentifier] {
            isPolicyReconfiguration = true
            reconfiguration.taskDidComplete = true
            if reconfiguration.cancellationCallbackReceived {
                policyReconfigurations.removeValue(forKey: taskIdentifier)
                requestToRestart = reconfiguration.request
            } else {
                policyReconfigurations[taskIdentifier] = reconfiguration
            }
        }
        taskLock.unlock()

        if let requestToRestart = requestToRestart {
            restartAfterPolicyChange(taskIdentifier: taskIdentifier, request: requestToRestart)
        }
        return isPolicyReconfiguration
    }

    private func restartAfterPolicyChange(
        taskIdentifier: Int,
        request: VoicevoxVoiceModelDownloadRequest) {
        // 通信設定が変わったため、古い設定で作られた resume data は捨てる。
        resumeDataByModelID.removeValue(forKey: request.modelID)
        taskLock.lock()
        if activeTask?.taskIdentifier == taskIdentifier {
            activeTask = nil
            activeRequest = nil
        } else if activeTask == nil && activeRequest?.modelID == request.modelID {
            activeRequest = nil
        }
        taskLock.unlock()

        // キャンセルと完了通知が競合した場合、既に保存済みになっている
        // 可能性がある。二重取得はしない。
        if store.isStored(modelID: request.modelID, readableFormats: readableFormats) == false {
            _ = queue.enqueueAtFront(request)
        }
        notifyChanged()
        startNextIfPossible()
    }

    // MARK: - 積む / 取り消す

    /// カタログの音声モデルを取得待ちに積む。
    /// - Returns: 積めなかった理由(積めたら nil)
    @discardableResult
    func enqueue(model: VoicevoxVoiceModelCatalog.VoiceModel) -> VoicevoxVoiceModelDownloadBlocker? {
        let blocker = VoicevoxVoiceModelDownloadPolicy.blocker(
            byteSize: model.byteSize,
            isAlreadyStored: store.isStored(modelID: model.id, readableFormats: readableFormats),
            // 実際に止めるのは OS(allowsCellularAccess)に任せるので、ここでは弾かない。
            // 画面に「Wi-Fiを待っています」と出すための判定は呼び出し側で行う。
            isOnCellular: false,
            allowsCellular: true,
            freeBytes: Self.freeDiskBytes())
        if let blocker = blocker { return blocker }

        guard let url = URL(string: model.url) else { return .alreadyStored }
        let request = VoicevoxVoiceModelDownloadRequest(
            modelID: model.id, url: url, byteSize: model.byteSize,
            expectedStyleIds: Set(model.allStyleIds))
        if queue.enqueue(request) {
            notifyChanged()
            startNextIfPossible()
        }
        return nil
    }

    func cancel(modelID: String) {
        if queue.cancel(modelID: modelID) {
            taskLock.lock()
            let task = activeTask
            activeTask = nil
            activeRequest = nil
            taskLock.unlock()
            task?.cancel()
        }
        notifyChanged()
        startNextIfPossible()
    }

    func cancelAll() {
        _ = queue.cancelAll()
        taskLock.lock()
        let task = activeTask
        activeTask = nil
        activeRequest = nil
        taskLock.unlock()
        task?.cancel()
        notifyChanged()
    }

    private func startNextIfPossible() {
        guard let request = queue.startNext() else { return }
        let allowsCellularAccess = Self.allowsCellularAccess
        let urlRequest = VoicevoxVoiceModelDownloadPolicy.urlRequest(
            url: request.url, allowsCellularAccess: allowsCellularAccess)

        let task: URLSessionDownloadTask
        // 途中まで落ちていれば、そこから再開する(取得先は Range に対応している)。
        if let resumeData = resumeDataByModelID.removeValue(forKey: request.modelID),
           VoicevoxVoiceModelDownloadPolicy.canUseResumeData(
               resumeDataAllowsCellularAccess: resumeData.allowsCellularAccess,
               desiredAllowsCellularAccess: allowsCellularAccess) {
            task = session.downloadTask(withResumeData: resumeData.data)
        } else {
            task = session.downloadTask(with: urlRequest)
        }
        // どの音声モデルのタスクかを、delegate 側で引けるようにしておく。
        task.taskDescription = request.modelID
        taskLock.lock()
        activeTask = task
        activeRequest = request
        taskLock.unlock()
        task.resume()
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .voicevoxVoiceModelDownloadDidChange, object: nil)
    }

    /// 端末の空き容量。取れなければ「たっぷりある」事にする
    /// (取れないだけで取得を止めると、何もできなくなるため)。
    static func freeDiskBytes() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }
}

extension VoicevoxVoiceModelDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let modelID = downloadTask.taskDescription else { return }
        queue.update(modelID: modelID,
                     receivedBytes: totalBytesWritten,
                     totalBytes: totalBytesExpectedToWrite)
        notifyChanged()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let modelID = downloadTask.taskDescription else { return }
        // **この関数を抜けると location のファイルは消える。** ここで移し切る。
        // 検証は store がやる(壊れた物・形式違い・取り違えを弾いてから置く)。
        let expected = queue.state(ofModelID: modelID) != nil ? expectedStyleIds(forModelID: modelID) : []
        do {
            try store.store(temporaryFileURL: location, modelID: modelID,
                            expectedStyleIds: expected, readableFormats: readableFormats)
            queue.finish(modelID: modelID)
            // 置いただけでは使えない。話者一覧を作り直して初めて選べるようになる。
            VoicevoxCore.reloadStyleCatalogFromCurrentFiles()
            AppInformationLogger.AddLog(
                message: "VOICEVOXの音声モデル \(modelID).vvm を取得しました", isForDebug: true)
        } catch {
            queue.fail(modelID: modelID, reason: Self.describe(storeError: error))
            AppInformationLogger.AddLog(
                message: "VOICEVOXの音声モデル \(modelID).vvm の取得に失敗しました: \(Self.describe(storeError: error))",
                isForDebug: true)
        }
        taskLock.lock()
        if activeTask?.taskIdentifier == downloadTask.taskIdentifier {
            activeTask = nil
            activeRequest = nil
        }
        taskLock.unlock()
        notifyChanged()
        startNextIfPossible()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let modelID = task.taskDescription else { return }
        if policyTaskDidComplete(taskIdentifier: task.taskIdentifier) {
            // 設定変更に伴うキャンセル。失敗表示や queue.fail は行わない。
            taskLock.lock()
            if activeTask?.taskIdentifier == task.taskIdentifier {
                activeTask = nil
            }
            taskLock.unlock()
            notifyChanged()
            return
        }
        guard let error = error else { return } // 成功時は didFinishDownloadingTo で処理済み
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        // 途中まで落ちていれば取っておく。次に積まれた時、そこから再開できる。
        if let resumeData = resumeData {
            resumeDataByModelID[modelID] = ResumeData(
                data: resumeData,
                allowsCellularAccess: task.currentRequest?.allowsCellularAccess ?? Self.allowsCellularAccess)
        }
        if nsError.code == NSURLErrorCancelled {
            // 利用者が取り消した。失敗としては記録しない。
            queue.finish(modelID: modelID)
        } else {
            queue.fail(modelID: modelID, reason: error.localizedDescription)
            AppInformationLogger.AddLog(
                message: "VOICEVOXの音声モデル \(modelID).vvm の取得に失敗しました: \(error.localizedDescription)",
                isForDebug: true)
        }
        taskLock.lock()
        if activeTask?.taskIdentifier == task.taskIdentifier {
            activeTask = nil
            activeRequest = nil
        }
        taskLock.unlock()
        notifyChanged()
        startNextIfPossible()
    }

    /// 背面で全部終わった。OS に「片付いた」と返す。
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundEventsCompletionHandler?()
            self?.backgroundEventsCompletionHandler = nil
        }
    }

    private func expectedStyleIds(forModelID modelID: String) -> Set<UInt32> {
        // カタログから引き直す。待ち行列は状態だけを持ち、内容は持たない。
        guard let catalog = VoicevoxVoiceModelCatalogLoader.preferredCatalog(
            readableVvmFormatVersions: readableFormats),
              let model = catalog.model(withID: modelID) else { return [] }
        return Set(model.allStyleIds)
    }

    static func describe(storeError: Error) -> String {
        guard let error = storeError as? VoicevoxVoiceModelStoreError else {
            return (storeError as NSError).localizedDescription
        }
        switch error {
        case .unreadable:
            return NSLocalizedString("VoicevoxVoiceModelStore_Unreadable", comment: "取得したファイルの中身を確認できませんでした")
        case .unsupportedFormat(let format):
            return String(format: NSLocalizedString(
                "VoicevoxVoiceModelStore_UnsupportedFormatFormat",
                comment: "このアプリでは読めない形式の音声モデルでした(形式%@)"), "\(format)")
        case .missingExpectedStyles(let styles):
            return String(format: NSLocalizedString(
                "VoicevoxVoiceModelStore_MissingExpectedStylesFormat",
                comment: "期待していた話者が入っていませんでした(%@)"),
                styles.sorted().map(String.init).joined(separator: ","))
        }
    }
}
