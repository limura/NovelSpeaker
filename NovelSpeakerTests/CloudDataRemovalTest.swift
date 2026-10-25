import XCTest
import CloudKit
@testable import NovelSpeaker

final class CloudDataRemovalTest: XCTestCase {
    private final class Client: CloudDataRemovalClient {
        let zone = CKRecordZone.ID(zoneName: "RealmNovel", ownerName: CKCurrentUserDefaultName)
        var ids = ["saved-before-reinstall"]
        var storedZones: [CKRecordZone.ID] = [CKRecordZone.default().zoneID]
        var storedSubscriptions = ["private_changes"]
        var calls: [String] = []
        var receiveError: Error?
        var retainZoneAfterDelete = false
        var retainIDAfterReceive = false
        var staleAfterReceive = false
        var staleListsRemaining = 0
        var hang = false
        var lateOutstanding: ((Result<[CKOperation.ID], Error>) -> Void)?
        var cancelled = false
        func outstanding(_ completion: @escaping (Result<[CKOperation.ID], Error>) -> Void) {
            calls.append("listIDs")
            if hang { lateOutstanding = completion; return }
            if ids.isEmpty && staleListsRemaining > 0 {
                staleListsRemaining -= 1
                completion(.success(["saved-before-reinstall"]))
            } else { completion(.success(ids)) }
        }
        func receive(_ id: CKOperation.ID, completion: @escaping (Result<Void, Error>) -> Void) {
            calls.append("receive:\(id)")
            if let error = receiveError { completion(.failure(error)); return }
            if !retainIDAfterReceive { ids.removeAll { $0 == id } }
            if staleAfterReceive { staleListsRemaining = 1 }
            completion(.success(()))
        }
        func zones(_ completion: @escaping (Result<[CKRecordZone.ID], Error>) -> Void) {
            calls.append("zones")
            completion(.success(storedZones))
        }
        func deleteZone(_ id: CKRecordZone.ID, completion: @escaping (Result<Void, Error>) -> Void) {
            calls.append("deleteZone:\(id.zoneName)")
            if !retainZoneAfterDelete { storedZones.removeAll { $0 == id } }
            completion(.success(()))
        }
        func subscriptions(_ completion: @escaping (Result<[String], Error>) -> Void) {
            calls.append("subscriptions")
            completion(.success(storedSubscriptions))
        }
        func deleteSubscription(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
            calls.append("deleteSubscription")
            storedSubscriptions.removeAll { $0 == id }
            completion(.success(()))
        }
        func cancelRequests() { cancelled = true }
    }

    func testRecoveryOnlyClearsOperationsWithoutReadingOrDeletingStoredData() {
        let client = Client()
        client.storedZones.append(client.zone)
        let done = expectation(description: "recovered without deletion")
        CloudDataRemoval(client: client, mode: .recoverOutstanding).start { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            XCTAssertEqual(client.ids, [])
            XCTAssertEqual(client.storedZones, [CKRecordZone.default().zoneID, client.zone])
            XCTAssertEqual(client.storedSubscriptions, ["private_changes"])
            XCTAssertEqual(client.calls, ["listIDs", "receive:saved-before-reinstall", "listIDs"])
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRecoveryWithNoOperationsDoesNotTouchCloudData() {
        let client = Client()
        client.ids = []
        let done = expectation(description: "nothing outstanding")
        CloudDataRemoval(client: client, mode: .recoverOutstanding).start { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            XCTAssertEqual(client.calls, ["listIDs", "listIDs"])
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRecoveryFailureDoesNotReportSuccessOrDeleteData() {
        let client = Client()
        client.receiveError = CKError(.networkUnavailable)
        let done = expectation(description: "recovery failed")
        CloudDataRemoval(client: client, mode: .recoverOutstanding).start { result in
            if case .success = result { XCTFail("must fail") }
            XCTAssertEqual(client.ids, ["saved-before-reinstall"])
            XCTAssertFalse(client.calls.contains("zones"))
            XCTAssertEqual(client.storedSubscriptions, ["private_changes"])
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRecoveryChecksThatOperationsActuallyDisappeared() {
        let client = Client()
        client.retainIDAfterReceive = true
        let done = expectation(description: "still outstanding")
        CloudDataRemoval(client: client, mode: .recoverOutstanding, operationClearanceRetries: 0).start { result in
            guard case .failure(CloudDataRemovalError.remainingOperations) = result else { XCTFail("\(result)"); done.fulfill(); return }
            XCTAssertFalse(client.calls.contains("zones"))
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRecoversEnumeratedIDsBeforeDeletingAndVerifiesRemoval() {
        let client = Client()
        client.storedZones.append(client.zone)
        let done = expectation(description: "deleted")
        CloudDataRemoval(client: client).start { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(client.ids, [])
            XCTAssertEqual(client.storedZones, [CKRecordZone.default().zoneID])
            XCTAssertEqual(client.storedSubscriptions, [])
            XCTAssertLessThan(client.calls.firstIndex(of: "receive:saved-before-reinstall")!, client.calls.firstIndex(of: "deleteZone:RealmNovel")!)
            XCTAssertEqual(client.calls.filter { $0 == "zones" }.count, 2)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testReceiveFailureDoesNotStartDeletingData() {
        let client = Client()
        client.receiveError = CKError(.networkUnavailable)
        let done = expectation(description: "failed")
        CloudDataRemoval(client: client).start { result in
            if case .success = result { XCTFail("must fail") }
            XCTAssertFalse(client.calls.contains("zones"))
            XCTAssertEqual(client.storedSubscriptions, ["private_changes"])
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRemainingIDPreventsDeletionEvenAfterSuccessfulCallback() {
        let client = Client()
        client.retainIDAfterReceive = true
        let done = expectation(description: "remaining operation")
        CloudDataRemoval(client: client, operationClearanceRetries: 0).start { result in
            guard case .failure(CloudDataRemovalError.remainingOperations) = result else { XCTFail("\(result)"); done.fulfill(); return }
            XCTAssertFalse(client.calls.contains("zones"))
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testWaitsForIDListToCatchUpWithoutResubmitting() {
        let client = Client()
        client.staleAfterReceive = true
        let done = expectation(description: "list caught up")
        CloudDataRemoval(client: client, operationClearanceRetries: 1, operationClearanceRetryDelay: 0.01).start { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            XCTAssertEqual(client.calls.filter { $0 == "receive:saved-before-reinstall" }.count, 1)
            XCTAssertTrue(client.calls.contains("deleteSubscription"))
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRecreatedZoneDoesNotReportSuccess() {
        let client = Client()
        client.ids = []
        client.storedZones.append(client.zone)
        client.retainZoneAfterDelete = true
        let done = expectation(description: "remaining data")
        CloudDataRemoval(client: client).start { result in
            guard case .failure(CloudDataRemovalError.remainingData) = result else { XCTFail("\(result)"); done.fulfill(); return }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testTimeoutIgnoresLateResponseAndDoesNotDelete() {
        let client = Client()
        client.hang = true
        let done = expectation(description: "timeout")
        let late = expectation(description: "late callback ignored")
        var completions = 0
        CloudDataRemoval(client: client, timeout: 0.02).start { result in
            completions += 1
            guard case .failure(CloudDataRemovalError.timedOut) = result else { XCTFail("\(result)"); done.fulfill(); return }
            XCTAssertTrue(client.cancelled)
            // タイムアウト後の遅い応答でも削除を開始しない。
            client.lateOutstanding?(.success([]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                XCTAssertFalse(client.calls.contains("zones"))
                XCTAssertEqual(completions, 1)
                late.fulfill()
            }
            done.fulfill()
        }
        wait(for: [done, late], timeout: 2)
    }
}
