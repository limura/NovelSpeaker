import CloudKit
import Foundation
import Darwin
final class Sink: DurablePrivateSyncable {
    let recordType = "DialogueRegression"
    let zoneID = CKRecordZone.ID(zoneName: "scratch-receive")
    var ackCount = 0
    var failOnce = true
    var log: [String] = []
    var objects: [String: Int] = [:]
    var zoneChangesToken: CKServerChangeToken? { didSet { ackCount += 1; log.append("zone") } }
    var isCustomZoneCreated = true
    var pipeToEngine: (([CKRecord], [CKRecord.ID]) -> Void)?
    func registerLocalDatabase() {}
    func cleanUp() {}
    func add(record: CKRecord) { fatalError("legacy void path") }
    func delete(recordID: CKRecord.ID) { fatalError("legacy void path") }
    func resolvePendingRelationships() {}
    func pushLocalObjectsToCloudKit() {}
    func apply(record: CKRecord) throws {
        let key = record.recordID.recordName
        log.append(key)
        if key == "B", failOnce { failOnce = false; throw Injected.write }
        objects[key] = (record["n"] as? Int) ?? 0
    }
    func applyDeletion(recordID: CKRecord.ID) throws { objects[recordID.recordName] = nil }
}
enum Injected: Error { case write }
let sink = Sink()
let manager = PrivateDatabaseManager(testObjects: [sink])
let transport = DispatchQueue(label:"offline.fakes")
var batches = 0
var zones = 0
var dbWrites = 0
var dbReads = 0
manager.loadDatabaseTokenForTesting = { dbReads += 1; return nil }
manager.storeDatabaseTokenForTesting = { _ in dbWrites += 1; sink.log.append("db") }
manager.submitPullForTesting = { operation in
    transport.async {
        if let db = operation as? CKFetchDatabaseChangesOperation {
            batches += 1
            db.fetchDatabaseChangesCompletionBlock?(nil, false, nil)
        } else if let zone = operation as? CKFetchRecordZoneChangesOperation {
            zones += 1
            precondition(zone.recordZoneIDs == [sink.zoneID])
            precondition(zone.configurationsByRecordZoneID?[sink.zoneID]?.previousServerChangeToken == nil)
            for key in ["A","B"] {
                let id = CKRecord.ID(recordName:key,zoneID:sink.zoneID)
                let record = CKRecord(recordType:sink.recordType,recordID:id)
                record["n"] = 42
                zone.recordWasChangedBlock?(id,.success(record))
                if key == "A" { zone.recordZoneFetchCompletionBlock?(sink.zoneID,nil,nil,true,nil) }
            }
            zone.recordZoneFetchCompletionBlock?(sink.zoneID,nil,nil,false,nil)
            zone.fetchRecordZoneChangesCompletionBlock?(nil)
        } else { fatalError("unexpected operation") }
    }
}
manager.fetchChangesInDatabase { error in
    precondition(error is Injected)
    precondition(sink.objects == ["A":42] && dbWrites == 0 && sink.ackCount == 0)
    precondition(batches == 1 && zones == 1 && dbReads == 1)
    manager.fetchChangesInDatabase { error in
        precondition(error == nil)
        precondition(sink.objects == ["A":42,"B":42] && dbWrites == 1 && sink.ackCount == 1)
        precondition(batches == 2 && zones == 2 && dbReads == 2)
        precondition(sink.log == ["A","B","A","B","zone","db"])
        print("PASS fail after successful A; whole pull replay; intermediate page and high-level completion; zone ACK then DB ACK")
        exit(0)
    }
}
DispatchQueue.main.asyncAfter(deadline:.now()+8) { fatalError("timeout") }
dispatchMain()
