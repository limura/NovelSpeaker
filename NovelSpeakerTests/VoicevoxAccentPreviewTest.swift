//
//  VoicevoxAccentPreviewTest.swift
//  NovelSpeakerTests
//
//  「アクセント設定画面の聞き比べで、選んだアクセントの音が本当に鳴るか」のテスト。
//
//  耳で「同じに聞こえる」と思った時、それが
//   (a) VOICEVOX がそういう音を出しているのか
//   (b) 別のアクセントで作った音が使い回されているのか
//  を人間が聞いて区別するのは難しい。波形が違うかどうかなら機械が判定できる。
//
//  実機で「4つのアクセントをどれも同じに聞こえる」という報告があった。
//  原因は、聞き比べ中の一時的な辞書がキャッシュの鍵に入っていなかった事で、
//  4つとも同じ鍵になり、最初に作った音が使い回されていた。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxAccentPreviewTest: XCTestCase {

    private func setUpCore() async throws -> (VoicevoxCore, VoicevoxStyle) {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else {
            throw XCTSkip("同梱の open_jtalk_dic_utf_8-1.11 がバンドルに見つかりません")
        }
        let vvmPath = try VoicevoxTestVoiceModel.requirePath()
        let core = VoicevoxCore.shared
        try await core.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])
        let styles = await core.styles
        guard let style = styles.first else {
            throw XCTSkip("0.vvm からスタイルが取れませんでした")
        }
        return (core, style)
    }

    override func tearDown() async throws {
        await VoicevoxCore.shared.applyUserDictionary([])
        VoicevoxCore.shared.setDiskCacheContext(novelID: nil, chapterNumber: 0)
        VoicevoxCore.shared.schedulePrefetchCacheClear()
        VoicevoxDiskCacheStore.shared.remove(novelID: Self.testNovelID)
    }

    private static let testNovelID = "VoicevoxAccentPreviewTest-novel"

    /// アクセント設定画面の聞き比べが作る辞書(その語だけを差し替えた一時的な物)。
    private func previewEntries(pronunciation: String, accentType: Int) -> [VoicevoxUserDictionaryEntry] {
        return [VoicevoxUserDictionaryEntry(surface: pronunciation,
                                            pronunciation: pronunciation,
                                            accentType: accentType,
                                            priority: VoicevoxUserDictionaryEntry.preferredPriority)]
    }

    /// ★鍵は「その音を作った条件」を表していなければならない。
    ///
    /// 表していないと、条件が違うのに同じ鍵になり、前に作った別物の音が返る。
    /// 聞き比べは辞書を一時的に差し替えるので、差し替えた内容が鍵に入っていないと
    /// アクセントを変えても鍵が変わらない。
    func testCacheKeyChangesWhenTheInstalledDictionaryChanges() async throws {
        let (core, _) = try await setUpCore()
        let text = VoicevoxAccentDisplay.previewText(kana: "サンチ")

        await core.applyUserDictionary(previewEntries(pronunciation: "サンチ", accentType: 0))
        let keyForFlat = VoicevoxDiskCacheStore.key(text: text, styleId: 0)
        await core.applyUserDictionary(previewEntries(pronunciation: "サンチ", accentType: 1))
        let keyForHead = VoicevoxDiskCacheStore.key(text: text, styleId: 0)

        XCTAssertNotEqual(keyForFlat, keyForHead,
                          "アクセントが違えば音も違うのだから、鍵も違わなければならない")
    }

    /// 聞き比べと同じ手順(辞書を差し替えて synthesize する)を4回繰り返し、
    /// 4つのアクセントで**実際に鳴る音**が全て違う事を確かめる。
    ///
    /// 読み上げ中に設定画面へ入った状況を再現するため、
    /// ディスクキャッシュの置き場所(diskCacheContext)を設定した状態で行う。
    /// これが設定されていると、聞き比べで作った音がディスクにも積まれるため、
    /// メモリを捨てるだけでは前の音の使い回しを防げない。
    func testEveryAccentCandidateProducesDifferentAudio() async throws {
        let (core, style) = try await setUpCore()
        // 「読み上げ中に設定画面へ入った」状況。
        core.setDiskCacheContext(novelID: Self.testNovelID, chapterNumber: 1)

        let kana = "サンチ"
        let text = VoicevoxAccentDisplay.previewText(kana: kana)
        let moraCount = VoicevoxAccentDisplay.moras(fromKatakana: kana).count
        let candidates = VoicevoxAccentDisplay.candidates(moraCount: moraCount)
        XCTAssertEqual(candidates.count, moraCount + 1)

        var audioByAccent: [Int: Data] = [:]
        for candidate in candidates {
            await core.applyUserDictionary(previewEntries(pronunciation: kana, accentType: candidate))
            audioByAccent[candidate] = try await core.synthesize(text: text, styleId: style.styleId)
        }

        for first in candidates {
            for second in candidates where second > first {
                XCTAssertNotEqual(audioByAccent[first], audioByAccent[second],
                                  "アクセント \(first) と \(second) で同じ音が返っている(前に作った音の使い回し)")
            }
        }
    }
}
