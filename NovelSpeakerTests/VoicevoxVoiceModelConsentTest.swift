//
//  VoicevoxVoiceModelConsentTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxVoiceModelConsentTest: XCTestCase {

    private var directory: URL!
    private var store: VoicevoxVoiceModelConsentStore!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("consent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = VoicevoxVoiceModelConsentStore(fileURL: directory.appendingPathComponent("consent.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 部品

    private func makeSpeaker(name: String, uuid: String, termsURL: String?,
                             credit: String? = nil, policyText: String? = nil,
                             styleId: UInt32 = 3) -> VoicevoxVoiceModelCatalog.Speaker {
        return VoicevoxVoiceModelCatalog.Speaker(
            name: name, uuid: uuid, version: "0.16.0", termsURL: termsURL,
            credit: credit, policyText: policyText,
            styles: [VoicevoxVoiceModelCatalog.Style(name: "ノーマル", styleId: styleId)])
    }

    /// zunko.jp に2人相乗り + 別規約が1人、という実際の 0.vvm と同じ形。
    private func makeModel() -> VoicevoxVoiceModelCatalog.VoiceModel {
        return VoicevoxVoiceModelCatalog.VoiceModel(
            id: "0", url: "https://example.com/0.vvm", byteSize: 58 * 1024 * 1024,
            vvmFormatVersion: 1,
            speakers: [
                makeSpeaker(name: "四国めたん", uuid: "u-metan", termsURL: "https://zunko.jp/con_ongen_kiyaku.html",
                            credit: "VOICEVOX:四国めたん", styleId: 2),
                makeSpeaker(name: "ずんだもん", uuid: "u-zunda", termsURL: "https://zunko.jp/con_ongen_kiyaku.html",
                            credit: "VOICEVOX:ずんだもん", styleId: 3),
                makeSpeaker(name: "春日部つむぎ", uuid: "u-tsumugi", termsURL: "https://tsumugi-official.studio.site/rule",
                            credit: "VOICEVOX:春日部つむぎ", styleId: 8),
            ])
    }

    // MARK: - 束ね方

    func testSpeakersAreGroupedByTermsURL() {
        let groups = VoicevoxVoiceModelConsentText.groups(of: makeModel())
        XCTAssertEqual(groups.count, 2, "同じ規約URLがまとまっていない")
        XCTAssertEqual(groups[0].speakers.count, 2)
        XCTAssertEqual(groups[0].speakerNames, "四国めたん / ずんだもん")
        XCTAssertEqual(groups[0].hostName, "zunko.jp")
        XCTAssertEqual(groups[1].speakerNames, "春日部つむぎ")
    }

    func testGroupingKeepsEveryone() {
        let model = makeModel()
        let groups = VoicevoxVoiceModelConsentText.groups(of: model)
        XCTAssertEqual(groups.flatMap { $0.speakers }.count, model.speakers.count)
    }

    // 規約URLが無いキャラが混ざっていても、束ねる時に消えてはいけない。
    func testSpeakerWithoutTermsURLIsStillListed() {
        let model = VoicevoxVoiceModelCatalog.VoiceModel(
            id: "9", url: "https://example.com/9.vvm", byteSize: 1, vvmFormatVersion: 1,
            speakers: [makeSpeaker(name: "謎の人", uuid: "u-x", termsURL: nil)])
        let groups = VoicevoxVoiceModelConsentText.groups(of: model)
        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].termsURL)
        XCTAssertEqual(groups[0].speakerNames, "謎の人")
        XCTAssertEqual(groups[0].hostName, "")
    }

    // MARK: - 文面

    func testMessageMentionsEverythingWeAreObligedToShow() {
        let message = VoicevoxVoiceModelConsentText.message(
            model: makeModel(),
            requestedStyleDisplayName: "ずんだもん - ノーマル",
            termsPageURL: "https://example.com/terms")
        XCTAssertTrue(message.contains("ずんだもん - ノーマル"))
        XCTAssertTrue(message.contains("58MB"), "大きさが出ていない: \(message)")
        XCTAssertTrue(message.contains("https://zunko.jp/con_ongen_kiyaku.html"), "規約URLが出ていない")
        XCTAssertTrue(message.contains("https://tsumugi-official.studio.site/rule"), "規約URLが出ていない")
        XCTAssertTrue(message.contains("VOICEVOX:ずんだもん"), "クレジット表記が出ていない")
        XCTAssertTrue(message.contains("https://example.com/terms"), "全体の規約が出ていない")
    }

    // ★クレジット表記は話者名から組み立ててはいけない。
    // もち子さん の表記は "VOICEVOX:もち子(cv 明日葉よもぎ)" で話者名と違う。
    func testCreditIsTakenFromCatalogNotFromName() {
        let model = VoicevoxVoiceModelCatalog.VoiceModel(
            id: "7", url: "https://example.com/7.vvm", byteSize: 1, vvmFormatVersion: 1,
            speakers: [makeSpeaker(name: "もち子さん", uuid: "u-mochiko",
                                   termsURL: "https://example.com/rule",
                                   credit: "VOICEVOX:もち子(cv 明日葉よもぎ)")])
        XCTAssertEqual(VoicevoxVoiceModelConsentText.creditLines(of: model),
                       ["VOICEVOX:もち子(cv 明日葉よもぎ)"])
    }

    func testMessageIncludesPolicyText() {
        let model = VoicevoxVoiceModelCatalog.VoiceModel(
            id: "7", url: "https://example.com/7.vvm", byteSize: 1, vvmFormatVersion: 1,
            speakers: [makeSpeaker(name: "誰か", uuid: "u", termsURL: "https://example.com/rule",
                                   policyText: "企業が携わる場合は事前に確認が必要です")])
        let message = VoicevoxVoiceModelConsentText.message(
            model: model, requestedStyleDisplayName: nil, termsPageURL: nil)
        XCTAssertTrue(message.contains("企業が携わる場合は事前に確認が必要です"))
    }

    // MARK: - 記録

    func testRecordsOnePerTermsURL() throws {
        let added = store.recordConsent(model: makeModel(), vvmTag: "0.16.0")
        XCTAssertEqual(added.count, 2, "規約URLごとに1件のはず")
        XCTAssertEqual(Set(store.consentedTermsURLs),
                       ["https://zunko.jp/con_ongen_kiyaku.html",
                        "https://tsumugi-official.studio.site/rule"])
        let zunko = try XCTUnwrap(store.records.first { $0.termsURL.contains("zunko.jp") })
        XCTAssertEqual(zunko.speakerNames, ["四国めたん", "ずんだもん"])
        XCTAssertEqual(zunko.speakerUUIDs, ["u-metan", "u-zunda"])
        XCTAssertEqual(zunko.modelID, "0")
        XCTAssertEqual(zunko.vvmTag, "0.16.0")
    }

    // ★規約は改訂されるので、同じ規約への再同意は上書きせず足す。
    // 「いつ同意したか」が消えると、何に同意したのか辿れなくなる。
    func testReConsentIsAppendedNotOverwritten() {
        let first = Date(timeIntervalSince1970: 1_000_000)
        let second = Date(timeIntervalSince1970: 2_000_000)
        store.recordConsent(model: makeModel(), vvmTag: "0.16.0", agreedAt: first)
        store.recordConsent(model: makeModel(), vvmTag: "0.17.0", agreedAt: second)
        XCTAssertEqual(store.records.count, 4)
        XCTAssertEqual(store.lastAgreedAt(termsURL: "https://zunko.jp/con_ongen_kiyaku.html"), second)
    }

    func testHasConsented() {
        XCTAssertFalse(store.hasConsented(termsURL: "https://zunko.jp/con_ongen_kiyaku.html"))
        store.recordConsent(model: makeModel(), vvmTag: nil)
        XCTAssertTrue(store.hasConsented(termsURL: "https://zunko.jp/con_ongen_kiyaku.html"))
        XCTAssertFalse(store.hasConsented(termsURL: "https://example.com/other"))
    }

    // 記録はファイルに残る。アプリを起動し直しても消えない。
    func testRecordsSurviveReload() {
        store.recordConsent(model: makeModel(), vvmTag: "0.16.0",
                            agreedAt: Date(timeIntervalSince1970: 1_000_000))
        let reloaded = VoicevoxVoiceModelConsentStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.records.count, 2)
        XCTAssertEqual(reloaded.lastAgreedAt(termsURL: "https://zunko.jp/con_ongen_kiyaku.html"),
                       Date(timeIntervalSince1970: 1_000_000))
    }

    func testEmptyStoreIsNotAnError() {
        XCTAssertEqual(store.records.count, 0)
        XCTAssertFalse(store.hasConsented(termsURL: "https://example.com"))
        XCTAssertNil(store.lastAgreedAt(termsURL: "https://example.com"))
    }

    // 規約URLの無いキャラだけの音声モデルでは、記録する物が無い。
    func testNothingIsRecordedWhenThereIsNoTermsURL() {
        let model = VoicevoxVoiceModelCatalog.VoiceModel(
            id: "9", url: "https://example.com/9.vvm", byteSize: 1, vvmFormatVersion: 1,
            speakers: [makeSpeaker(name: "謎の人", uuid: "u-x", termsURL: nil)])
        XCTAssertEqual(store.recordConsent(model: model, vvmTag: nil).count, 0)
        XCTAssertEqual(store.records.count, 0)
    }

    // MARK: - 同梱カタログとの突き合わせ

    // ★同梱カタログの全キャラに規約URLとクレジット表記がある事。
    // どちらかが欠けると、義務を果たせないまま取得させてしまう。
    func testEveryEmbeddedSpeakerHasTermsAndCredit() throws {
        let file = try XCTUnwrap(
            VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(bundle: Bundle(for: VoicevoxCore.self))
                ?? VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(bundle: Bundle(for: type(of: self))))
        for catalog in file.variants {
            for model in catalog.voiceModels {
                for speaker in model.speakers {
                    XCTAssertNotNil(speaker.termsURL, "\(model.id).vvm の \(speaker.name) に規約URLが無い")
                    XCTAssertNotNil(speaker.credit, "\(model.id).vvm の \(speaker.name) にクレジット表記が無い")
                }
            }
        }
    }
}
