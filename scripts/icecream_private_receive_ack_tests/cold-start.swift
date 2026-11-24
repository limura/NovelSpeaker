import CloudKit
import Foundation
import Darwin
final class Receiver: DurablePrivateSyncable {
    let recordType = "ColdRegression"
    let zoneID = CKRecordZone.ID(zoneName:"cold")
    var writes = 0, applied = 0
    var zoneChangesToken: CKServerChangeToken? { didSet { writes += 1 } }
    var isCustomZoneCreated = false
    var pipeToEngine: (([CKRecord],[CKRecord.ID])->Void)?
    func registerLocalDatabase() {}
    func cleanUp() {}
    func add(record: CKRecord) { fatalError() }
    func delete(recordID: CKRecord.ID) { fatalError() }
    func resolvePendingRelationships() {}
    func pushLocalObjectsToCloudKit() {}
    func apply(record: CKRecord) throws { applied += 1 }
    func applyDeletion(recordID: CKRecord.ID) throws { fatalError() }
}
let r = Receiver()
let m = PrivateDatabaseManager(testObjects:[r])
let callbacks = DispatchQueue(label:"cold.callbacks")
var dbWrites = 0, initialAttempts = 0, savedZones = 0
m.loadDatabaseTokenForTesting = { nil }
m.storeDatabaseTokenForTesting = { _ in
    dbWrites += 1
    precondition(r.writes == 1 && r.applied == 1 && savedZones == 1 && initialAttempts == 2)
    print("PASS cold start missing zone: initial checkpoints held, successful creation schedules healthy receive")
    exit(0)
}
m.submitPullForTesting = { op in
    callbacks.async {
        if let o = op as? CKFetchDatabaseChangesOperation {
            o.fetchDatabaseChangesCompletionBlock?(nil,false,nil)
        } else if let o = op as? CKFetchRecordZoneChangesOperation {
            initialAttempts += 1
            if initialAttempts == 1 {
                o.recordZoneFetchCompletionBlock?(r.zoneID,nil,nil,false,CKError(.zoneNotFound))
                o.fetchRecordZoneChangesCompletionBlock?(CKError(.partialFailure))
            } else {
                let id = CKRecord.ID(recordName:"syn",zoneID:r.zoneID)
                o.recordWasChangedBlock?(id,.success(CKRecord(recordType:r.recordType,recordID:id)))
                o.recordZoneFetchCompletionBlock?(r.zoneID,nil,nil,false,nil)
                o.fetchRecordZoneChangesCompletionBlock?(nil)
            }
        } else if let o = op as? CKModifyRecordZonesOperation {
            savedZones += 1
            precondition(o.recordZonesToSave?.map(\.zoneID) == [r.zoneID])
            o.modifyRecordZonesCompletionBlock?(o.recordZonesToSave,nil,nil)
        } else { fatalError("unexpected") }
    }
}
m.fetchChangesInDatabase { error in
    precondition((error as? CKError)?.code == .zoneNotFound && r.writes == 0 && dbWrites == 0)
    m.createCustomZonesIfAllowed()
}
DispatchQueue.main.asyncAfter(deadline:.now()+8) { fatalError("offline timeout") }
dispatchMain()
