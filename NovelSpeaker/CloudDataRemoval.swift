import Foundation
import CloudKit

/// 本文やRealmには触れない。同期OFFの専用コンテナを空にするための通信だけを担当する。
protocol CloudDataRemovalClient {
    func outstanding(_ completion: @escaping (Result<[CKOperation.ID], Error>) -> Void)
    func receive(_ id: CKOperation.ID, completion: @escaping (Result<Void, Error>) -> Void)
    func zones(_ completion: @escaping (Result<[CKRecordZone.ID], Error>) -> Void)
    func deleteZone(_ id: CKRecordZone.ID, completion: @escaping (Result<Void, Error>) -> Void)
    func subscriptions(_ completion: @escaping (Result<[String], Error>) -> Void)
    func deleteSubscription(_ id: String, completion: @escaping (Result<Void, Error>) -> Void)
    func cancelRequests()
}

enum CloudDataRemovalError: LocalizedError {
    case syncEnabled, busy, timedOut, remainingOperations, remainingData, unsupportedOperation
    var errorDescription: String? {
        let key: String
        switch self {
        case .syncEnabled: key = "CloudDataRemoval_DisableSync"
        case .busy: key = "CloudDataRemoval_Busy"
        case .timedOut: key = "CloudDataRemoval_Timeout"
        case .remainingOperations: key = "CloudDataRemoval_RemainingOperations"
        case .remainingData: key = "CloudDataRemoval_RemainingData"
        case .unsupportedOperation: key = "CloudDataRemoval_UnsupportedOperation"
        }
        return NSLocalizedString(key, comment: "iCloudデータ削除のエラー")
    }
}

/// 全コールバックを直列化。時間切れ後に遅れて届いた応答から削除を進めない。
final class CloudDataRemoval {
    private let client: CloudDataRemovalClient
    private let queue = DispatchQueue(label: "NovelSpeaker.CloudDataRemoval")
    enum Mode { case removeData, recoverOutstanding }
    private let mode: Mode
    private let timeout: TimeInterval
    private let operationClearanceRetries: Int
    private let operationClearanceRetryDelay: TimeInterval
    private var completion: ((Result<Void, Error>) -> Void)?
    private var finished = false
    private var started = false
    private var deadline: DispatchWorkItem?

    init(client: CloudDataRemovalClient, mode: Mode = .removeData, timeout: TimeInterval = 180,
         operationClearanceRetries: Int = 5, operationClearanceRetryDelay: TimeInterval = 1) {
        self.client = client
        self.mode = mode
        self.timeout = timeout
        self.operationClearanceRetries = operationClearanceRetries
        self.operationClearanceRetryDelay = operationClearanceRetryDelay
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            guard !self.started else {
                DispatchQueue.main.async { completion(.failure(CloudDataRemovalError.busy)) }
                return
            }
            self.started = true
            self.completion = completion
            let deadline = DispatchWorkItem { self.finish(.failure(CloudDataRemovalError.timedOut)) }
            self.deadline = deadline
            self.queue.asyncAfter(deadline: .now() + self.timeout, execute: deadline)
            self.client.outstanding(self.next { ids in
                // cancelだけではIDが残る事を実機で確認済み。完了通知を受け取ってから削除する。
                self.each(ids, action: self.client.receive) {
                    self.waitForOperationClearance(retries: self.operationClearanceRetries)
                }
            })
        }
    }

    private func next<T>(_ action: @escaping (T) -> Void) -> (Result<T, Error>) -> Void {
        return { result in
            self.queue.async {
                guard !self.finished else { return }
                switch result {
                case .success(let value): action(value)
                case .failure(let error): self.finish(.failure(error))
                }
            }
        }
    }

    private func each<T>(_ items: [T], action: @escaping (T, @escaping (Result<Void, Error>) -> Void) -> Void,
                         done: @escaping () -> Void) {
        guard let first = items.first else { done(); return }
        action(first, next { _ in self.each(Array(items.dropFirst()), action: action, done: done) })
    }

    private func waitForOperationClearance(retries: Int) {
        client.outstanding(next { ids in
            if ids.isEmpty {
                if self.mode == .recoverOutstanding { self.finish(.success(())) }
                else { self.deleteData() }
                return
            }
            // 完了通知直後に一覧の更新が間に合わない場合を待つ。再送はしない。
            guard retries > 0 else { self.finish(.failure(CloudDataRemovalError.remainingOperations)); return }
            self.queue.asyncAfter(deadline: .now() + self.operationClearanceRetryDelay) {
                guard !self.finished else { return }
                self.waitForOperationClearance(retries: retries - 1)
            }
        })
    }

    private func deleteData() {
        client.zones(next { zones in
            // IceCreamは型ごとのカスタムZoneを使う。デフォルトZoneは使用していない。
            let customZones = zones.filter { $0.zoneName != CKRecordZone.default().zoneID.zoneName }
            self.each(customZones, action: self.client.deleteZone) {
                self.client.subscriptions(self.next { subscriptions in
                    self.each(subscriptions, action: self.client.deleteSubscription) { self.verify() }
                })
            }
        })
    }

    private func verify() {
        client.zones(next { zones in
            guard zones.allSatisfy({ $0.zoneName == CKRecordZone.default().zoneID.zoneName }) else {
                self.finish(.failure(CloudDataRemovalError.remainingData)); return
            }
            self.client.subscriptions(self.next { subscriptions in
                guard subscriptions.isEmpty else { self.finish(.failure(CloudDataRemovalError.remainingData)); return }
                self.client.outstanding(self.next { ids in
                    guard ids.isEmpty else { self.finish(.failure(CloudDataRemovalError.remainingOperations)); return }
                    self.finish(.success(()))
                })
            })
        })
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        deadline = nil
        client.cancelRequests()
        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?(result) }
    }
}

/// 同期エンジンを起動せず、OSから列挙したIDをそのまま使う。再インストール後も利用可能。
final class CloudKitDataRemovalClient: CloudDataRemovalClient {
    private let container: CKContainer
    private let lock = NSLock()
    private var requests: [CKOperation] = []
    private var cancelled = false

    init(container: CKContainer) { self.container = container }

    private func add(_ operation: CKDatabaseOperation) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { operation.cancel(); return }
        operation.configuration.timeoutIntervalForRequest = 30
        operation.configuration.timeoutIntervalForResource = 60
        requests.append(operation)
        container.privateCloudDatabase.add(operation)
    }

    func cancelRequests() {
        lock.lock()
        cancelled = true
        let requests = self.requests
        self.requests.removeAll()
        lock.unlock()
        requests.forEach { $0.cancel() }
    }

    func outstanding(_ completion: @escaping (Result<[CKOperation.ID], Error>) -> Void) {
        container.fetchAllLongLivedOperationIDs { ids, error in
            if let error = error { completion(.failure(error)) }
            else if let ids = ids { completion(.success(ids)) }
            else { completion(.failure(CKError(.internalError))) }
        }
    }

    func receive(_ id: CKOperation.ID, completion: @escaping (Result<Void, Error>) -> Void) {
        container.fetchLongLivedOperation(withID: id) { operation, error in
            if let error = error { completion(.failure(error)); return }
            guard let operation = operation else { completion(.success(())); return }
            guard let modify = operation as? CKModifyRecordsOperation,
                  modify.database?.databaseScope != .public,
                  modify.database?.databaseScope != .shared else {
                completion(.failure(CloudDataRemovalError.unsupportedOperation)); return
            }
            modify.modifyRecordsCompletionBlock = { _, _, error in
                // 認証や通信エラーを隠して成功扱いにはしない。
                // 失敗時は削除を止め、次の試行で一覧を再取得する。
                if let error = error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
            self.add(modify)
        }
    }

    func zones(_ completion: @escaping (Result<[CKRecordZone.ID], Error>) -> Void) {
        let operation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
        operation.fetchRecordZonesCompletionBlock = { zones, error in
            if let error = error { completion(.failure(error)) }
            else if let zones = zones { completion(.success(Array(zones.keys))) }
            else { completion(.failure(CKError(.internalError))) }
        }
        add(operation)
    }

    func deleteZone(_ id: CKRecordZone.ID, completion: @escaping (Result<Void, Error>) -> Void) {
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [id])
        operation.modifyRecordZonesCompletionBlock = { _, _, error in
            if let error = error { completion(.failure(error)) }
            else { completion(.success(())) }
        }
        add(operation)
    }

    func subscriptions(_ completion: @escaping (Result<[String], Error>) -> Void) {
        let operation = CKFetchSubscriptionsOperation.fetchAllSubscriptionsOperation()
        operation.fetchSubscriptionCompletionBlock = { subscriptions, error in
            if let error = error { completion(.failure(error)) }
            else if let subscriptions = subscriptions { completion(.success(Array(subscriptions.keys))) }
            else { completion(.failure(CKError(.internalError))) }
        }
        add(operation)
    }

    func deleteSubscription(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: [id])
        operation.modifySubscriptionsCompletionBlock = { _, _, error in
            if let error = error { completion(.failure(error)) }
            else { completion(.success(())) }
        }
        add(operation)
    }
}
