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
//  **モバイル通信の扱いは OS に任せる。** allowsCellularAccess = false にしておけば、
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
        set { UserDefaults.standard.set(newValue, forKey: allowsCellularAccessKey) }
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
    /// 中断からの再開に使うデータ(取得先が Range に対応していれば OS が作る)。
    private var resumeDataByModelID: [String: Data] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // 電池と通信量に優しくしてもらう。急ぐ物ではない。
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = Self.allowsCellularAccess
        configuration.waitsForConnectivity = true
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
        taskLock.unlock()
        task?.cancel()
        notifyChanged()
    }

    private func startNextIfPossible() {
        guard let request = queue.startNext() else { return }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.allowsCellularAccess = Self.allowsCellularAccess

        let task: URLSessionDownloadTask
        // 途中まで落ちていれば、そこから再開する(取得先は Range に対応している)。
        if let resumeData = resumeDataByModelID.removeValue(forKey: request.modelID) {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: urlRequest)
        }
        // どの音声モデルのタスクかを、delegate 側で引けるようにしておく。
        task.taskDescription = request.modelID
        taskLock.lock()
        activeTask = task
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
        taskLock.lock(); activeTask = nil; taskLock.unlock()
        notifyChanged()
        startNextIfPossible()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let modelID = task.taskDescription else { return }
        guard let error = error else { return } // 成功時は didFinishDownloadingTo で処理済み
        let nsError = error as NSError
        // 途中まで落ちていれば取っておく。次に積まれた時、そこから再開できる。
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeDataByModelID[modelID] = resumeData
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
        taskLock.lock(); activeTask = nil; taskLock.unlock()
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
