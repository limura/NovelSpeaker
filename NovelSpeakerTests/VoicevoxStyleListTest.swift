//
//  VoicevoxStyleListTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxStyleListTest: XCTestCase {

    private func makeStyle(_ styleId: UInt32, _ speakerName: String, _ name: String) -> VoicevoxStyle {
        return VoicevoxStyle(name: name, styleId: styleId, speakerName: speakerName,
                             speakerUUID: "u-\(speakerName)", vvmPath: "/dev/null/0.vvm")
    }

    /// 0.vvm に ずんだもん(3,5) と 四国めたん(2)、5.vvm に ずんだもん(22) という形。
    private func makeCatalog() -> VoicevoxVoiceModelCatalog {
        func speaker(_ name: String, _ styles: [(String, UInt32)]) -> VoicevoxVoiceModelCatalog.Speaker {
            return VoicevoxVoiceModelCatalog.Speaker(
                name: name, uuid: "u-\(name)", version: nil,
                termsURL: "https://zunko.jp/con_ongen_kiyaku.html",
                credit: "VOICEVOX:\(name)", policyText: nil,
                styles: styles.map { VoicevoxVoiceModelCatalog.Style(name: $0.0, styleId: $0.1) })
        }
        return VoicevoxVoiceModelCatalog(
            vvmFormatVersion: 1, vvmTag: "0.16.4", minimumCoreVersion: "0.16.0",
            termsPageURL: nil,
            voiceModels: [
                VoicevoxVoiceModelCatalog.VoiceModel(
                    id: "0", url: "https://example.com/0.vvm", byteSize: 58 * 1024 * 1024,
                    vvmFormatVersion: 1,
                    speakers: [speaker("四国めたん", [("ノーマル", 2)]),
                               speaker("ずんだもん", [("ノーマル", 3), ("あまあま", 5)])]),
                VoicevoxVoiceModelCatalog.VoiceModel(
                    id: "5", url: "https://example.com/5.vvm", byteSize: 57 * 1024 * 1024,
                    vvmFormatVersion: 1,
                    speakers: [speaker("ずんだもん", [("ささやき", 22)])]),
            ])
    }

    // MARK: - 節の分かれ方

    // ★取得済みの物が、未取得側にも出てはいけない。
    // 出ると同じ行を2回選べる事になり、片方は取得を促す行になってしまう。
    func testDownloadedStylesDoNotAppearAsDownloadable() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル"), makeStyle(5, "ずんだもん", "あまあま")],
            catalog: makeCatalog(), searchText: "")
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].kind, .available)
        XCTAssertEqual(sections[0].items.map { $0.styleId }, [3, 5])
        XCTAssertEqual(sections[1].kind, .downloadable)
        XCTAssertEqual(sections[1].items.map { $0.styleId }.sorted(), [2, 22])
    }

    // 取りこぼしが無い事。取得済み + 未取得 = カタログ全部。
    func testEveryCatalogStyleIsListedSomewhere() {
        let catalog = makeCatalog()
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル")],
            catalog: catalog, searchText: "")
        let listed = Set(sections.flatMap { $0.items.map { $0.styleId } })
        XCTAssertEqual(listed, catalog.allStyleIds)
    }

    func testDownloadableItemsCarryTheirModel() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [], catalog: makeCatalog(), searchText: "ささやき")
        let item = sections.flatMap { $0.items }.first
        XCTAssertEqual(item?.modelID, "5", "どのファイルを取ればよいか分からなくなっている")
        XCTAssertEqual(item?.megabytesText, "57MB")
    }

    // 取得済みの行に大きさは要らない(もう取ってある)。
    func testAvailableItemsHaveNoSize() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル")], catalog: nil, searchText: "")
        XCTAssertNil(sections[0].items[0].megabytesText)
    }

    // 空の節は出さない。「絞り込んだら消えた」のか「元から無い」のか分からなくなるため。
    func testEmptySectionsAreDropped() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [], catalog: makeCatalog(), searchText: "")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].kind, .downloadable)
    }

    // カタログが読めない時でも、取得済みの物は選べる。
    func testWorksWithoutCatalog() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル")], catalog: nil, searchText: "")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].kind, .available)
    }

    func testNothingAtAllIsNotACrash() {
        XCTAssertEqual(VoicevoxStyleListBuilder.build(
            availableStyles: [], catalog: nil, searchText: "").count, 0)
    }

    // MARK: - 絞り込み

    func testFilterMatchesSpeakerName() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル"), makeStyle(2, "四国めたん", "ノーマル")],
            catalog: nil, searchText: "ずんだ")
        XCTAssertEqual(sections[0].items.map { $0.styleId }, [3])
    }

    // スタイル名でも引ける。「ささやき」を探したい事はよくある。
    func testFilterMatchesStyleName() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [], catalog: makeCatalog(), searchText: "ささやき")
        XCTAssertEqual(sections[0].items.map { $0.styleId }, [22])
    }

    func testFilterIgnoresSurroundingSpaces() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル")], catalog: nil, searchText: "  ずんだ  ")
        XCTAssertEqual(sections[0].items.count, 1)
    }

    func testFilterWithNoMatchReturnsNothing() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル")],
            catalog: makeCatalog(), searchText: "いない人")
        XCTAssertEqual(sections.count, 0)
    }

    func testEmptySearchKeepsEverything() {
        let sections = VoicevoxStyleListBuilder.build(
            availableStyles: [makeStyle(3, "ずんだもん", "ノーマル")], catalog: makeCatalog(), searchText: "   ")
        // 取得済み1件 + 未取得3件(カタログの4件のうち、取得済みの物を除いた分)。
        XCTAssertEqual(sections.flatMap { $0.items }.count, 4)
    }
}
