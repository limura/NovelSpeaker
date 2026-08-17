//
//  VoicevoxVoiceModelCatalogTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxVoiceModelCatalogTest: XCTestCase {

    private func loadEmbedded() throws -> VoicevoxVoiceModelCatalog {
        let bundle = Bundle(for: type(of: self))
        // テストバンドルに無ければアプリ側のバンドルを見る。
        let catalog = VoicevoxVoiceModelCatalogLoader.loadEmbedded(bundle: bundle)
            ?? VoicevoxVoiceModelCatalogLoader.loadEmbedded(bundle: Bundle(for: VoicevoxCore.self))
            ?? VoicevoxVoiceModelCatalogLoader.loadEmbedded()
        return try XCTUnwrap(catalog, "同梱カタログが読めない")
    }

    // MARK: - 同梱カタログそのものの検査

    // 同梱カタログが読めて、中身が揃っている事。
    func testEmbeddedCatalogIsComplete() throws {
        let catalog = try loadEmbedded()
        XCTAssertEqual(catalog.formatVersion, VoicevoxVoiceModelCatalog.supportedFormatVersion)
        XCTAssertFalse(catalog.voiceModels.isEmpty)

        for model in catalog.voiceModels {
            XCTAssertFalse(model.speakers.isEmpty, "\(model.id).vvm に話者がいない")
            XCTAssertGreaterThan(model.byteSize, 1_000_000, "\(model.id).vvm の大きさが不自然")
            XCTAssertEqual(model.vvmFormatVersion, catalog.vvmFormatVersion)
            XCTAssertTrue(model.url.hasPrefix("https://"), "\(model.id).vvm の取得先が https でない")
        }
    }

    // ★取得先が main を指していない事。
    // main は次のコア版に進んでいる事があり、その VVM は形式が変わっていて
    // 今のコアでは開けない(0.17.0 で vvm_format_version が 1→2 になった)。
    func testUrlsArePinnedToTheCoreVersionTag() throws {
        let catalog = try loadEmbedded()
        XCTAssertEqual(catalog.vvmTag, catalog.coreVersion,
                       "VVMのタグはコアのバージョンと一致していなければならない")
        for model in catalog.voiceModels {
            XCTAssertFalse(model.url.contains("/main/"),
                           "\(model.id).vvm の取得先が main を指している: \(model.url)")
            XCTAssertTrue(model.url.contains("/\(catalog.vvmTag)/"),
                          "\(model.id).vvm の取得先がタグ \(catalog.vvmTag) を指していない: \(model.url)")
        }
    }

    // ★規約URLとクレジット表記が全キャラに揃っている事。
    // 1人でも欠けたまま配ると、規約を提示せずに配る事になる。
    func testEverySpeakerHasTermsAndCredit() throws {
        let catalog = try loadEmbedded()
        for model in catalog.voiceModels {
            for speaker in model.speakers {
                XCTAssertNotNil(speaker.termsURL, "\(speaker.name) に規約URLが無い")
                XCTAssertFalse(speaker.termsURL?.isEmpty ?? true, "\(speaker.name) の規約URLが空")
                XCTAssertFalse(speaker.credit?.isEmpty ?? true, "\(speaker.name) のクレジット表記が空")
            }
        }
    }

    // ★クレジット表記を話者名から組み立ててはいけない事の記録。
    // もち子さん の表記は "VOICEVOX:もち子(cv 明日葉よもぎ)" で、話者名と一致しない。
    // 機械的に "VOICEVOX:\(name)" とすると、このキャラのクレジットが間違う。
    func testCreditIsNotAlwaysDerivedFromSpeakerName() throws {
        let catalog = try loadEmbedded()
        let speakers = catalog.voiceModels.flatMap { $0.speakers }
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
        let spanning = modelIdsByName.filter { $0.value.count > 1 }
        XCTAssertFalse(spanning.isEmpty,
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
        let catalog = try loadEmbedded()
        XCTAssertNil(catalog.entry(forStyleId: 999_999))
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

    // MARK: - 取得したカタログを使ってよいかの判定(★これが無いと致命的)

    private func makeCatalog(formatVersion: Int = 1, vvmFormatVersion: Int = 1,
                             modelCount: Int = 1) -> VoicevoxVoiceModelCatalog {
        let style = VoicevoxVoiceModelCatalog.Style(name: "ノーマル", styleId: 3)
        let speaker = VoicevoxVoiceModelCatalog.Speaker(
            name: "ずんだもん", uuid: "u", version: nil, termsURL: "https://example.com",
            credit: "VOICEVOX:ずんだもん", policyText: nil, styles: [style])
        let models = (0..<modelCount).map {
            VoicevoxVoiceModelCatalog.VoiceModel(
                id: "\($0)", url: "https://example.com/\($0).vvm", byteSize: 58_000_000,
                vvmFormatVersion: vvmFormatVersion, speakers: [speaker])
        }
        return VoicevoxVoiceModelCatalog(
            formatVersion: formatVersion, generatedAt: nil, coreVersion: "0.16.4",
            vvmTag: "0.16.4", vvmFormatVersion: vvmFormatVersion,
            termsPageURL: nil, voiceModels: models)
    }

    func testSameShapeRemoteCatalogIsUsed() {
        let embedded = makeCatalog()
        let remote = makeCatalog(modelCount: 3)
        XCTAssertTrue(VoicevoxVoiceModelCatalogLoader.isUsable(remote, insteadOf: embedded))
        XCTAssertEqual(VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: remote), remote)
    }

    // ★本命: このアプリのコアが読めない形式のVVMを並べたカタログは使わない事。
    //
    // 公式が 0.17.0 に進んだ時に配布カタログを更新すると、
    // 更新していない古いアプリがそれを読んでしまう。防がないと、
    // 利用者は1.4GB取得した挙句どれも開けない、という目に遭う。
    func testRemoteCatalogWithIncompatibleVvmFormatIsRejected() {
        let embedded = makeCatalog(vvmFormatVersion: 1)
        let remote = makeCatalog(vvmFormatVersion: 2)
        XCTAssertFalse(VoicevoxVoiceModelCatalogLoader.isUsable(remote, insteadOf: embedded))
        XCTAssertEqual(VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: remote), embedded,
                       "読めない形式のカタログを掴んではいけない")
    }

    // 知らないカタログ形式は解釈できないので使わない。
    func testRemoteCatalogWithNewerFormatVersionIsRejected() {
        let embedded = makeCatalog(formatVersion: 1)
        let remote = makeCatalog(formatVersion: 99)
        XCTAssertFalse(VoicevoxVoiceModelCatalogLoader.isUsable(remote, insteadOf: embedded))
    }

    // 空のカタログで上書きすると、何も取得できなくなるだけ。
    func testEmptyRemoteCatalogIsRejected() {
        let embedded = makeCatalog()
        let remote = makeCatalog(modelCount: 0)
        XCTAssertFalse(VoicevoxVoiceModelCatalogLoader.isUsable(remote, insteadOf: embedded))
        XCTAssertEqual(VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: remote), embedded)
    }

    // 取ってこられなかった時は同梱の物を使う(VOICEVOXが使えなくなったりしない)。
    func testFallsBackToEmbeddedWhenRemoteIsMissing() {
        let embedded = makeCatalog()
        XCTAssertEqual(VoicevoxVoiceModelCatalogLoader.preferred(embedded: embedded, remote: nil), embedded)
    }

    // 壊れたJSONを掴んでも落ちない事。
    func testBrokenJsonIsRejected() {
        XCTAssertNil(VoicevoxVoiceModelCatalogLoader.decode(Data("これはJSONではない".utf8)))
        XCTAssertNil(VoicevoxVoiceModelCatalogLoader.decode(Data("{}".utf8)))
    }
}
