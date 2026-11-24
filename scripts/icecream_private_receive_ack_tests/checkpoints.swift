import CloudKit
import Foundation
import Darwin
final class Receiver: DurablePrivateSyncable {
    let recordType = "OfflineRegression"
    let zoneID = CKRecordZone.ID(zoneName:"offline")
    var zoneWrites = 0
    var zoneChangesToken: CKServerChangeToken? { didSet { zoneWrites += 1 } }
    var isCustomZoneCreated = true
    var pipeToEngine: (([CKRecord],[CKRecord.ID])->Void)?
    var applied: [String] = []
    func registerLocalDatabase() {}
    func cleanUp() {}
    func add(record: CKRecord) { fatalError() }
    func delete(recordID: CKRecord.ID) { fatalError() }
    func pushLocalObjectsToCloudKit() {}
    func resolvePendingRelationships() {}
    func apply(record: CKRecord) throws { applied.append(record.recordID.recordName) }
    func applyDeletion(recordID: CKRecord.ID) throws { applied.append("del:" + recordID.recordName) }
}
let r = Receiver()
let m = PrivateDatabaseManager(testObjects:[r])
let callbacks = DispatchQueue(label:"offline.transport")
var zones = 0, dbs = 0, saved = 0
var mode = "partial"
var held: CKFetchRecordZoneChangesOperation?
var firstCompetingCompletion = false
func outcome(_ op:CKFetchRecordZoneChangesOperation, key:String, more:Bool = false, finish:Bool = true) {
    let id = CKRecord.ID(recordName:key,zoneID:r.zoneID)
    op.recordWasChangedBlock?(id,.success(CKRecord(recordType:r.recordType,recordID:id)))
    op.recordZoneFetchCompletionBlock?(r.zoneID,nil,nil,more,nil)
    if finish { op.fetchRecordZoneChangesCompletionBlock?(nil) }
}
m.loadDatabaseTokenForTesting = { nil }
m.storeDatabaseTokenForTesting = { _ in saved += 1 }
m.submitPullForTesting = { op in
    callbacks.async {
        if let o = op as? CKFetchDatabaseChangesOperation {
            dbs += 1
            o.fetchDatabaseChangesCompletionBlock?(nil,false,nil)
        } else if let o = op as? CKFetchRecordZoneChangesOperation {
            zones += 1
            switch mode {
            case "partial":
                o.recordZoneFetchCompletionBlock?(r.zoneID,nil,nil,false,CKError(.partialFailure))
                o.fetchRecordZoneChangesCompletionBlock?(nil)
            case "incomplete": outcome(o,key:"open",more:true)
            case "expired":
                mode = "retry"
                o.recordZoneFetchCompletionBlock?(r.zoneID,nil,nil,false,CKError(.changeTokenExpired))
                o.fetchRecordZoneChangesCompletionBlock?(CKError(.partialFailure))
            case "compete-hold", "reset-hold", "stop-hold":
                held = o
                DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {
                    if mode == "compete-hold" {
                        precondition(!firstCompetingCompletion && dbs == 4 && zones == 5)
                        mode = "compete-next"
                        callbacks.async { outcome(o,key:"older") }
                    } else {
                        precondition(["reset-hold","stop-hold"].contains(mode))
                        let isStop = mode == "stop-hold"
                        m.invalidatePulls(stop:isStop) { mode = isStop ? "after-stop" : "after-reset" }
                        callbacks.async { outcome(o,key:isStop ? "stale-stop" : "stale-reset") }
                        if isStop {
                            callbacks.async {
                                DispatchQueue.main.async {
                                    m.fetchChangesInDatabase { error in
                                        precondition(error is PrivatePullFailure && saved == 4 && r.zoneWrites == 4)
                                        precondition(dbs == 8 && zones == 9)
                                        precondition(r.applied == ["open","retry","older","compete-next","after-reset"])
                                        print("PASS partial + missing terminal + expired bounded replay + competing order + stale reset and stop callbacks")
                                        exit(0)
                                    }
                                }
                            }
                        }
                    }
                }
            default: outcome(o,key:mode)
            }
        } else { fatalError("unexpected op") }
    }
}
m.fetchChangesInDatabase { error in
    precondition((error as? CKError)?.code == .partialFailure && saved == 0 && r.zoneWrites == 0)
    mode = "incomplete"
    m.fetchChangesInDatabase { error in
        precondition(error != nil && saved == 0 && r.zoneWrites == 0)
        mode = "expired"
        m.fetchChangesInDatabase { error in
            precondition(error == nil && saved == 1 && r.zoneWrites == 1 && zones == 4 && dbs == 3)
            mode = "compete-hold"
            m.fetchChangesInDatabase { error in
                precondition(error == nil && saved >= 2)
                firstCompetingCompletion = true
            }
            m.fetchChangesInDatabase { error in
                precondition(error == nil && firstCompetingCompletion && saved == 3 && r.zoneWrites == 3)
                precondition(r.applied == ["open","retry","older","compete-next"])
                mode = "reset-hold"
                m.fetchChangesInDatabase { error in
                    precondition(error is PrivatePullFailure && saved == 3 && r.zoneWrites == 3)
                    m.fetchChangesInDatabase { error in
                        precondition(error == nil && saved == 4 && r.zoneWrites == 4)
                        precondition(r.applied == ["open","retry","older","compete-next","after-reset"])
                        mode = "stop-hold"
                        m.fetchChangesInDatabase { error in precondition(error is PrivatePullFailure) }
                    }
                }
            }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline:.now()+8) { fatalError("offline timeout") }
dispatchMain()
