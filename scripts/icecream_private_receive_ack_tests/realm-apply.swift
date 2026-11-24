import Foundation
import CloudKit
import RealmSwift
import Darwin
final class Fixture: Object, CKRecordConvertible, CKRecordRecoverable {
    @objc dynamic var id = ""
    @objc dynamic var value = 0
    @objc dynamic var isDeleted = false
    override static func primaryKey() -> String? { "id" }
}
enum Injected: Error { case localTransaction }
precondition(setenv("REALM_DISABLE_UPDATE_CHECKER", "1", 1) == 0)
precondition(String(cString: getenv("REALM_DISABLE_UPDATE_CHECKER")) == "1")
let report = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
if let report { try Data("UPDATE-CHECKER-DISABLED\n".utf8).write(to: report, options: .atomic) }
print("Realm SDK updater disabled"); fflush(stdout)
let config = Realm.Configuration(inMemoryIdentifier:"ack-fixture-" + UUID().uuidString, objectTypes:[Fixture.self])
let realm = try Realm(configuration:config)
let sync = SyncObject<Fixture,Object,Object,Object>(realmConfiguration:config,type:Fixture.self)
func record(_ id: String, value: Int) -> CKRecord {
    let r = CKRecord(recordType:Fixture.recordType,recordID:CKRecord.ID(recordName:id,zoneID:Fixture.zoneID))
    r["id"] = id
    r["value"] = value
    return r
}
sync.registerLocalDatabase()
sync.pipeToEngine = { _,_ in fatalError("Remote apply echoed outbound") }
try sync.apply(record:record("A",value:1))
realm.refresh()
precondition(realm.object(ofType:Fixture.self,forPrimaryKey:"A")?.value == 1)
var failOnce = true
sync.beforeInboundCommitForTesting = {
    if failOnce { failOnce = false; throw Injected.localTransaction }
}
do { try sync.apply(record:record("B",value:2)); fatalError("must fail") }
catch Injected.localTransaction { }
realm.refresh()
precondition(realm.object(ofType:Fixture.self,forPrimaryKey:"B") == nil)
try sync.apply(record:record("A",value:1))
try sync.apply(record:record("B",value:2))
realm.refresh()
precondition(realm.objects(Fixture.self).count == 2)
precondition(realm.object(ofType:Fixture.self,forPrimaryKey:"B")?.value == 2)
let malformed = record("C",value:3)
malformed["id"] = "D"
do { try sync.apply(record:malformed); fatalError("primary key mismatch") }
catch PrivatePullFailure.invalidRecord { }
realm.refresh()
precondition(realm.objects(Fixture.self).count == 2)
let assetRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ack-asset-fixture-" + UUID().uuidString, isDirectory:true)
try FileManager.default.createDirectory(at:assetRoot,withIntermediateDirectories:false)
let expected = assetRoot.appendingPathComponent("asset")
let incoming = assetRoot.appendingPathComponent("incoming")
try Data([0x01]).write(to:expected)
precondition(!CreamAsset.installReceivedFile(at:incoming,to:expected))
let stillOld = try Data(contentsOf:expected)
precondition(stillOld == Data([0x01]))
try Data([0x02,0x03]).write(to:incoming)
precondition(CreamAsset.installReceivedFile(at:incoming,to:expected))
let replaced = try Data(contentsOf:expected)
precondition(replaced == Data([0x02,0x03]))
try FileManager.default.removeItem(at:assetRoot)
print("PASS exact asset stage: failed copy preserves old bytes; successful copy replaces file")
print("PASS real in-memory Realm: A durable, B transaction rolled back, exact replay A/B stable, no feedback, wrong primary key rejected")
if let report { try Data("UPDATE-CHECKER-DISABLED\nPASS_ASSET\nPASS_REALM\n".utf8).write(to: report, options: .atomic) }
fflush(stdout)
exit(0)
