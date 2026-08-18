//
//  VoicevoxVoiceModelManageListTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxVoiceModelManageListTest: XCTestCase {

    private func speaker(_ name: String, _ styles: [(String, UInt32)],
                         credit: String? = nil) -> VoicevoxVoiceModelCatalog.Speaker {
        return VoicevoxVoiceModelCatalog.Speaker(
            name: name, uuid: "u-\(name)", version: nil,
            termsURL: "https://zunko.jp/con_ongen_kiyaku.html",
            credit: credit ?? "VOICEVOX:\(name)", policyText: nil,
            officialPageURL: "https://voicevox.hiroshiba.jp/product/\(name)/",
            styles: styles.map { VoicevoxVoiceModelCatalog.Style(name: $0.0, styleId: $0.1) })
    }

    private func makeCatalog() -> VoicevoxVoiceModelCatalog {
        return VoicevoxVoiceModelCatalog(
            vvmFormatVersion: 1, vvmTag: "0.16.4", minimumCoreVersion: "0.16.0", termsPageURL: nil,
            voiceModels: [
                VoicevoxVoiceModelCatalog.VoiceModel(
                    id: "0", url: "https://example.com/0.vvm", byteSize: 58 * 1024 * 1024,
                    vvmFormatVersion: 1,
                    speakers: [speaker("四国めたん", [("ノーマル", 2)]),
                               speaker("ずんだもん", [("ノーマル", 3)])]),
                VoicevoxVoiceModelCatalog.VoiceModel(
                    id: "3", url: "https://example.com/3.vvm", byteSize: 59 * 1024 * 1024,
                    vvmFormatVersion: 1,
                    speakers: [speaker("波音リツ", [("ノーマル", 9)])]),
                VoicevoxVoiceModelCatalog.VoiceModel(
                    id: "5", url: "https://example.com/5.vvm", byteSize: 57 * 1024 * 1024,
                    vvmFormatVersion: 1,
                    // ずんだもん は複数の音声モデルにまたがって入っている。
                    speakers: [speaker("ずんだもん", [("ささやき", 22)])]),
            ])
    }

    // MARK: - 節の分かれ方

    func testStoredAndNotStoredAreSeparated() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: ["0"],
            settingNamesByStyleId: [:], searchText: "")
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].kind, .stored)
        XCTAssertEqual(sections[0].items.map { $0.modelID }, ["0"])
        XCTAssertEqual(sections[1].items.map { $0.modelID }, ["3", "5"])
    }

    func testEmptySectionsAreDropped() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: [],
            settingNamesByStyleId: [:], searchText: "")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].kind, .notStored)
    }

    func testNoCatalogIsNotACrash() {
        XCTAssertEqual(VoicevoxVoiceModelManageListBuilder.build(
            catalog: nil, storedModelIDs: ["0"],
            settingNamesByStyleId: [:], searchText: "").count, 0)
    }

    // MARK: - 「消してよいか」の判断材料

    // ★どの話者設定が使っているかが出る事。これが無いと消してよいか分からない。
    func testUsingSpeakerSettingsAreListed() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: ["0", "5"],
            settingNamesByStyleId: [3: ["地の文", "会話文"], 22: ["ささやき用"]],
            searchText: "")
        let stored = sections[0].items
        XCTAssertEqual(stored.first { $0.modelID == "0" }?.usedBySettingNames, ["会話文", "地の文"])
        XCTAssertEqual(stored.first { $0.modelID == "5" }?.usedBySettingNames, ["ささやき用"])
    }

    // 1つの音声モデルの中の別々のキャラを同じ設定が使っていても、名前は1回だけ。
    func testUsingSettingNamesAreNotDuplicated() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: ["0"],
            settingNamesByStyleId: [2: ["地の文"], 3: ["地の文"]], searchText: "")
        XCTAssertEqual(sections[0].items[0].usedBySettingNames, ["地の文"])
    }

    func testUnusedModelHasNoSettingNames() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: ["0"],
            settingNamesByStyleId: [9: ["誰か"]], searchText: "")
        XCTAssertEqual(sections[0].items[0].usedBySettingNames, [])
    }

    // MARK: - 絞り込み

    func testFilterMatchesSpeakerName() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: [],
            settingNamesByStyleId: [:], searchText: "波音")
        XCTAssertEqual(sections[0].items.map { $0.modelID }, ["3"])
    }

    // ファイル名でも引ける。「5.vvm が何MBだったか」を確かめたい事がある。
    func testFilterMatchesFileName() {
        let sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: makeCatalog(), storedModelIDs: [],
            settingNamesByStyleId: [:], searchText: "5.vvm")
        XCTAssertEqual(sections[0].items.map { $0.modelID }, ["5"])
    }

    // MARK: - 要約と注意書き

    // 音声モデルと作成済み音声を**並べて**出す事。片方だけでは何を消せばよいか決められない。
    func testSummaryShowsBothKindsOfStorage() {
        let text = VoicevoxVoiceModelManageListBuilder.summaryText(
            storedCount: 3, storedBytes: 174 * 1024 * 1024,
            generatedAudioBytes: 512 * 1024 * 1024,
            freeBytes: 12 * 1024 * 1024 * 1024)
        XCTAssertTrue(text.contains("3件"), text)
        XCTAssertTrue(text.contains("174MB"), text)
        XCTAssertTrue(text.contains("512MB"), text)
        XCTAssertTrue(text.contains("12.0GB"), text)
    }

    func testMissingModelWarningNamesTheSettings() throws {
        let warning = try XCTUnwrap(VoicevoxVoiceModelManageListBuilder.missingModelWarning(
            settingNamesByStyleId: [3: ["地の文"], 22: ["会話文"]],
            availableStyleIds: [3]))
        XCTAssertTrue(warning.contains("1件"), warning)
        XCTAssertTrue(warning.contains("会話文"), warning)
        XCTAssertFalse(warning.contains("地の文"), "使える方まで数えている: \(warning)")
        // 設定を壊していない事が伝わる文面である事。
        XCTAssertTrue(warning.contains("取り直せば"), warning)
    }

    func testNoWarningWhenEverythingIsAvailable() {
        XCTAssertNil(VoicevoxVoiceModelManageListBuilder.missingModelWarning(
            settingNamesByStyleId: [3: ["地の文"]], availableStyleIds: [3]))
    }

    // MARK: - クレジット表記

    // 取得済みのキャラだけを並べる。消せばその行も消える。
    func testCreditsOnlyIncludeStoredModels() {
        let entries = VoicevoxCreditList.entries(catalog: makeCatalog(), storedModelIDs: ["0"])
        XCTAssertEqual(entries.map { $0.credit }, ["VOICEVOX:ずんだもん", "VOICEVOX:四国めたん"])
    }

    // 同じキャラが複数の音声モデルに入っていても、クレジットは1行。
    func testCreditsAreNotDuplicated() {
        let entries = VoicevoxCreditList.entries(catalog: makeCatalog(), storedModelIDs: ["0", "5"])
        XCTAssertEqual(entries.filter { $0.credit == "VOICEVOX:ずんだもん" }.count, 1)
    }

    // ★クレジット表記は話者名から組み立てない。
    func testCreditUsesCatalogText() {
        let catalog = VoicevoxVoiceModelCatalog(
            vvmFormatVersion: 1, vvmTag: "t", minimumCoreVersion: "0.16.0", termsPageURL: nil,
            voiceModels: [VoicevoxVoiceModelCatalog.VoiceModel(
                id: "15", url: "https://example.com/15.vvm", byteSize: 1, vvmFormatVersion: 1,
                speakers: [speaker("もち子さん", [("ノーマル", 20)],
                                   credit: "VOICEVOX:もち子(cv 明日葉よもぎ)")])])
        let entries = VoicevoxCreditList.entries(catalog: catalog, storedModelIDs: ["15"])
        XCTAssertEqual(entries.map { $0.credit }, ["VOICEVOX:もち子(cv 明日葉よもぎ)"])
    }

    func testCreditsAreEmptyWhenNothingIsStored() {
        XCTAssertEqual(VoicevoxCreditList.entries(catalog: makeCatalog(), storedModelIDs: []).count, 0)
    }
}
