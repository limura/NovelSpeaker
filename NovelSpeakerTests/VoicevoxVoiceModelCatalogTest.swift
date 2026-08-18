//
//  VoicevoxVoiceModelCatalogTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxVoiceModelCatalogTest: XCTestCase {

    private func loadEmbeddedFile() throws -> VoicevoxVoiceModelCatalogFile {
        let bundle = Bundle(for: type(of: self))
        let file = VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(bundle: bundle)
            ?? VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(bundle: Bundle(for: VoicevoxCore.self))
            ?? VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile()
        return try XCTUnwrap(file, "同梱カタログが読めない")
    }

    /// このアプリのコアが実際に使う一式。
    private func loadEmbedded() throws -> VoicevoxVoiceModelCatalog {
        let file = try loadEmbeddedFile()
        return try XCTUnwrap(
            file.catalog(readableVvmFormatVersions: VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions),
            "このアプリのコアが読める形式の一式がカタログに無い")
    }

    // MARK: - 同梱カタログそのものの検査

    func testEmbeddedCatalogIsComplete() throws {
        let file = try loadEmbeddedFile()
        XCTAssertEqual(file.formatVersion, VoicevoxVoiceModelCatalogFile.supportedFormatVersion)
        XCTAssertFalse(file.variants.isEmpty)

        for catalog in file.variants {
            XCTAssertFalse(catalog.voiceModels.isEmpty, "形式\(catalog.vvmFormatVersion) が空")
            for model in catalog.voiceModels {
                XCTAssertFalse(model.speakers.isEmpty, "\(model.id).vvm に話者がいない")
                XCTAssertGreaterThan(model.byteSize, 1_000_000, "\(model.id).vvm の大きさが不自然")
                XCTAssertEqual(model.vvmFormatVersion, catalog.vvmFormatVersion)
                XCTAssertTrue(model.url.hasPrefix("https://"), "\(model.id).vvm の取得先が https でない")
            }
        }
    }

    // ★このアプリのコアが読める形式の一式が、必ず入っている事。
    // 無いとVOICEVOXの音声モデルを1つも取得できなくなる。
    func testEmbeddedCatalogHasAVariantThisAppCanRead() throws {
        let file = try loadEmbeddedFile()
        let catalog = try XCTUnwrap(
            file.catalog(readableVvmFormatVersions: VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions))
        XCTAssertTrue(VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions.contains(catalog.vvmFormatVersion))
    }

    // ★取得先が main を指していない事。
    // main は次のコア版に進んでいる事があり、その VVM は形式が変わっていて
    // 今のコアでは開けない(0.17.0 で vvm_format_version が 1→2 になった)。
    func testUrlsArePinnedToATag() throws {
        for catalog in try loadEmbeddedFile().variants {
            for model in catalog.voiceModels {
                XCTAssertFalse(model.url.contains("/main/"),
                               "\(model.id).vvm の取得先が main を指している: \(model.url)")
                XCTAssertTrue(model.url.contains("/\(catalog.vvmTag)/"),
                              "\(model.id).vvm の取得先がタグ \(catalog.vvmTag) を指していない: \(model.url)")
            }
        }
    }

    // ★規約URLとクレジット表記が全キャラに揃っている事。
    // 1人でも欠けたまま配ると、規約を提示せずに配る事になる。
    func testEverySpeakerHasTermsAndCredit() throws {
        for catalog in try loadEmbeddedFile().variants {
            for model in catalog.voiceModels {
                for speaker in model.speakers {
                    XCTAssertFalse(speaker.termsURL?.isEmpty ?? true, "\(speaker.name) の規約URLが無い")
                    XCTAssertFalse(speaker.credit?.isEmpty ?? true, "\(speaker.name) のクレジット表記が無い")
                }
            }
        }
    }

    // ★クレジット表記を話者名から組み立ててはいけない事の記録。
    // もち子さん の表記は "VOICEVOX:もち子(cv 明日葉よもぎ)" で、話者名と一致しない。
    func testCreditIsNotAlwaysDerivedFromSpeakerName() throws {
        let speakers = try loadEmbedded().voiceModels.flatMap { $0.speakers }
        let mismatched = speakers.filter { $0.credit != "VOICEVOX:\($0.name)" }
        XCTAssertFalse(mismatched.isEmpty,
                       "話者名と違うクレジット表記のキャラがいなくなった。"
                       + "カタログの作り方が変わっていないか確認する事")
    }

    // styleId は全体で重複しない = これ単体で話者を特定できる。
    // 話者設定は styleId しか保存していないので、ここが崩れると設定が壊れる。
    func testStyleIdsAreUniqueAcrossAllModels() throws {
        let catalog = try loadEmbedded()
        var seen: [UInt32: String] = [:]
        for model in catalog.voiceModels {
            for speaker in model.speakers {
                for style in speaker.styles {
                    if let existing = seen[style.styleId] {
                        XCTFail("styleId \(style.styleId) が重複: \(existing) と \(speaker.name) - \(style.name)")
                    }
                    seen[style.styleId] = "\(speaker.name) - \(style.name)"
                }
            }
        }
        XCTAssertEqual(seen.count, catalog.allStyleIds.count)
    }

    // ★styleId が形式をまたいで同じである事。
    //
    // これが崩れると、コアを上げた瞬間に全員の話者設定が別人を指す。
    // (話者設定は styleId しか保存していないため)
    // 逆にここが保たれている限り、取得済みのVVMはコアを上げても使い続けられ、
    // 再取得を強いる必要が無い。
    func testStyleIdsAreStableAcrossVvmFormats() throws {
        let variants = try loadEmbeddedFile().variants
        try XCTSkipUnless(variants.count > 1, "形式が1つしか無いので比較できない")
        func styleMap(_ catalog: VoicevoxVoiceModelCatalog) -> [UInt32: String] {
            var result: [UInt32: String] = [:]
            for model in catalog.voiceModels {
                for speaker in model.speakers {
                    for style in speaker.styles {
                        result[style.styleId] = "\(speaker.name) - \(style.name)"
                    }
                }
            }
            return result
        }
        let base = styleMap(variants[0])
        for other in variants.dropFirst() {
            let map = styleMap(other)
            for (styleId, name) in base {
                if let otherName = map[styleId] {
                    XCTAssertEqual(otherName, name,
                                   "styleId \(styleId) が形式によって別人を指している")
                }
            }
        }
    }

    // MARK: - 引き当て

    // 1キャラのスタイルが複数のVVMに分かれている、という前提が崩れていない事。
    // ここが崩れると「キャラ単位で選ばせる」UIでよくなり、設計判断が変わる。
    func testOneSpeakerCanSpanMultipleVoiceModels() throws {
        let catalog = try loadEmbedded()
        var modelIdsByName: [String: Set<String>] = [:]
        for model in catalog.voiceModels {
            for speaker in model.speakers {
                modelIdsByName[speaker.name, default: []].insert(model.id)
            }
        }
        XCTAssertFalse(modelIdsByName.filter { $0.value.count > 1 }.isEmpty,
                       "1キャラのスタイルが複数のVVMに分かれている前提が崩れた")
    }

    func testEntryLookupByStyleId() throws {
        let catalog = try loadEmbedded()
        let anyStyleId = try XCTUnwrap(catalog.voiceModels.first?.speakers.first?.styles.first?.styleId)
        let entry = try XCTUnwrap(catalog.entry(forStyleId: anyStyleId))
        XCTAssertEqual(entry.style.styleId, anyStyleId)
        XCTAssertTrue(entry.displayName.contains(entry.speaker.name))
        XCTAssertTrue(entry.displayName.contains(entry.style.name))
        XCTAssertEqual(catalog.model(forStyleId: anyStyleId)?.id, entry.model.id)
    }

    func testUnknownStyleIdIsNotFound() throws {
        XCTAssertNil(try loadEmbedded().entry(forStyleId: 999_999))
    }

    // 同意画面用に、同じ規約URLのキャラをまとめられる事。
    func testSpeakersAreGroupedByTermsURL() throws {
        let catalog = try loadEmbedded()
        // 0.vvm は 四国めたん/ずんだもん(同じ zunko.jp) と 春日部つむぎ/雨晴はう(別々)。
        let model = try XCTUnwrap(catalog.model(withID: "0"))
        let groups = catalog.speakersGroupedByTermsURL(of: model)
        XCTAssertLessThan(groups.count, model.speakers.count, "同じ規約URLがまとめられていない")
        XCTAssertEqual(groups.flatMap { $0.speakers }.count, model.speakers.count,
                       "まとめる時にキャラを取りこぼしている")
    }

    // MARK: - 形式ごとの一式の選び方(★ここが壊れると利用者が無駄な1.4GBを掴む)

    private func makeFile(catalogFormatVersion: Int = 2,
                          vvmFormatVersions: [Int] = [1],
                          emptyFormats: Set<Int> = []) -> VoicevoxVoiceModelCatalogFile {
        let style = VoicevoxVoiceModelCatalog.Style(name: "ノーマル", styleId: 3)
        let speaker = VoicevoxVoiceModelCatalog.Speaker(
            name: "ずんだもん", uuid: "u", version: nil, termsURL: "https://example.com",
            credit: "VOICEVOX:ずんだもん", policyText: nil, styles: [style])
        let variants = vvmFormatVersions.map { format in
            VoicevoxVoiceModelCatalog(
                vvmFormatVersion: format, vvmTag: "tag\(format)",
                minimumCoreVersion: "0.16.0", termsPageURL: nil,
                voiceModels: emptyFormats.contains(format) ? [] : [
                    VoicevoxVoiceModelCatalog.VoiceModel(
                        id: "0", url: "https://example.com/0.vvm", byteSize: 58_000_000,
                        vvmFormatVersion: format, speakers: [speaker])
                ])
        }
        return VoicevoxVoiceModelCatalogFile(
            formatVersion: catalogFormatVersion, generatedAt: nil, variants: variants)
    }

    // 読める形式のうち一番新しい物を選ぶ。
    func testPicksNewestReadableFormat() {
        let file = makeFile(vvmFormatVersions: [1, 2, 3])
        XCTAssertEqual(file.catalog(readableVvmFormatVersions: [1, 2])?.vvmFormatVersion, 2)
        XCTAssertEqual(file.catalog(readableVvmFormatVersions: [1])?.vvmFormatVersion, 1)
        XCTAssertEqual(file.catalog(readableVvmFormatVersions: [1, 2, 3])?.vvmFormatVersion, 3)
    }

    // ★本命: 読めない形式しか無いカタログからは、何も選ばない事。
    //
    // 公式が次の形式に進んだ時、配布カタログから古い形式の一式が落ちると、
    // 更新できない端末の利用者が「開けないVVMを1.4GB取得」する事になる。
    func testPicksNothingWhenNoReadableFormatExists() {
        let file = makeFile(vvmFormatVersions: [2, 3])
        XCTAssertNil(file.catalog(readableVvmFormatVersions: [1]))
        XCTAssertFalse(VoicevoxVoiceModelCatalogLoader.isUsable(file, readableVvmFormatVersions: [1]))
    }

    // ★古いアプリは古い形式の一式を使い続けられる事(これが変異体を持つ理由)。
    func testOldAppKeepsUsingItsOwnFormatEvenWhenNewerExists() {
        let file = makeFile(vvmFormatVersions: [1, 2])
        let catalog = file.catalog(readableVvmFormatVersions: [1])
        XCTAssertEqual(catalog?.vvmFormatVersion, 1)
        XCTAssertEqual(catalog?.vvmTag, "tag1")
    }

    // 中身が空の一式は選ばない(選ぶと何も取得できないだけ)。
    func testEmptyVariantIsNotPicked() {
        let file = makeFile(vvmFormatVersions: [1, 2], emptyFormats: [2])
        XCTAssertEqual(file.catalog(readableVvmFormatVersions: [1, 2])?.vvmFormatVersion, 1)
    }

    // 知らないカタログ形式は解釈できないので使わない。
    func testUnknownCatalogFormatVersionIsRejected() {
        let file = makeFile(catalogFormatVersion: 99)
        XCTAssertNil(file.catalog(readableVvmFormatVersions: [1]))
        XCTAssertFalse(VoicevoxVoiceModelCatalogLoader.isUsable(file, readableVvmFormatVersions: [1]))
    }

    // MARK: - 同梱と取得済みの選択

    func testUsableRemoteIsPreferred() {
        let embedded = makeFile(vvmFormatVersions: [1])
        let remote = makeFile(vvmFormatVersions: [1, 2])
        XCTAssertEqual(
            VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: remote,
                                                      readableVvmFormatVersions: [1, 2])?.vvmFormatVersion,
            2)
    }

    // 取ってきたカタログが使えない時は同梱の物に戻る(VOICEVOXが使えなくならない)。
    func testFallsBackToEmbeddedWhenRemoteIsUnusable() {
        let embedded = makeFile(vvmFormatVersions: [1])
        let unusableRemote = makeFile(vvmFormatVersions: [2, 3])
        XCTAssertEqual(
            VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: unusableRemote,
                                                      readableVvmFormatVersions: [1])?.vvmTag,
            "tag1")
    }

    func testFallsBackToEmbeddedWhenRemoteIsMissing() {
        let embedded = makeFile(vvmFormatVersions: [1])
        XCTAssertEqual(
            VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: nil,
                                                      readableVvmFormatVersions: [1])?.vvmTag,
            "tag1")
    }

    // 壊れたJSONを掴んでも落ちない事。
    func testBrokenJsonIsRejected() {
        XCTAssertNil(VoicevoxVoiceModelCatalogLoader.decode(Data("これはJSONではない".utf8)))
        XCTAssertNil(VoicevoxVoiceModelCatalogLoader.decode(Data("{}".utf8)))
    }
}
