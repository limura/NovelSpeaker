//
//  VoicevoxRealDeviceReproTest.swift
//  NovelSpeakerTests
//
//  実機で報告された「VOICEVOXでの読み上げが所々で数秒〜数十秒詰まる」不具合を、
//  ユーザーが実際にテストした本文・設定(会話文「」に別話者(VOICEVOX)を割り当て、
//  句読点の「間の設定」は無し)をそのまま使い、シミュレータ上で再現するための統合テスト。
//  実機を都度借りずに、ここでの NSLog 出力(絶対時刻付き)を確認するだけで
//  詰まりの有無・原因を追えるようにする狙い。
//
//  SpeechBlockSpeaker/MultiVoiceSpeaker経由だと VoicevoxSpeaker.Speech(text:) が
//  NiftyUtility.isTesting() で即returnしてしまい(実機での誤発話を防ぐ既存のガード)、
//  テストからは実際の再生パイプラインを駆動できない。そのため、SpeechBlockSpeaker が
//  実際に行っているのと同じ手順(順番にVoicevoxCore.synthesize()を呼び、
//  現在のブロックより先を一定量だけ先行合成しておく)を、このテストの中で直接
//  再現する。再生時間は実際に合成されたWAVの長さから見積り、その分だけ待ってから
//  次のブロックへ進める事で、実機での「再生ペース」を模擬する。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxRealDeviceReproTest: XCTestCase {

    // ユーザーが実際に読み上げさせて詰まりを確認した本文そのもの。
    private static let reproText = """
ことせかい という名前は、iOS の音声合成エンジンが「異世界」という単語を「ことせかい」と発話した事からきています。 「今作ってるアプリはWeb小説を読み上げる奴なんだけどさ、色々読み間違えるんだよね。例えば『異世界』を『ことせかい』って読むから笑っちゃうんだよ」という感じで説明していたら、その読み間違いの印象が大きすぎて話題を出す時に「そういえば作ってるアプリ、えぇと『ことせかい』のやつ。あれがさぁ……」という感じでその読み間違いネタの方が通りがよくなってしまったのでいっそのことそれを名前にしてしまおう、という事で「ことせかい」という名前になったのでした。

はい。iOS の音声合成エンジンは(少なくとも ことせかい の開発が開始された頃は)あまり多くの単語を知っているわけではなく、よく読み間違いを起こします。特に Web小説 のジャンルによっては普通ではない読み方をする単語などが頻発する場合がありますので、ことせかい には読みかたを修正する機能もつけています。この機能の仕組みは単純なもので、読み間違える文字列を別の文字列に置き換えて読み上げさせるというものです。

例えば、先程の例の「異世界」という単語を音声合成エンジンは「ことせかい」と読み上げてしまいます。これを矯正するために、「異世界」から「イセカイ」への読み替えをさせるように設定するわけです。そうすると、読み上げに使う文字列中の「異世界」という文字列がすべて「イセカイ」に変換されて音声合成エンジンに渡されるようになり、音声合成エンジン側からみると「異世界」という文字が存在しなくなって代わりに「イセカイ」という文字があるのでそのまま「いせかい」と読み上げるようになるわけです。

さて、この読み替えの設定は「設定」タブの「読みの修正」項目で設定することができます。「読みの修正」では標準でそれなりの量の読み替え辞書が登録されています(「異世界」から「いせかい」への読み替えも標準の辞書に登録されていますので、恐らくこの文章を読み上げさせた時には正しく「いせかい」と発話したことと思います)。けれども、恐らくは全然足りないかと思われます。そのため、読み間違いを発見したら自分で読み替えを登録していくと良いかもしれません。
"""

    private func setUpCoreAndPickStyles() async throws -> (narrator: UInt32, dialogue: UInt32) {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil),
              let vvmPath = Bundle.main.path(forResource: "0", ofType: "vvm") else {
            XCTFail("同梱の辞書/0.vvm がバンドルに見つかりません")
            return (0, 0)
        }
        let vvmDirectory = (vvmPath as NSString).deletingLastPathComponent
        try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelDirectoryPaths: [vvmDirectory])
        let styles = await VoicevoxCore.shared.styles
        guard let first = styles.first else {
            XCTFail("0.vvm からスタイルが取れませんでした")
            return (0, 0)
        }
        // 実機ログのようにナレーションと会話文で別スタイルになる状況を再現するため、
        // 2種類あればそれぞれ別、1種類しか無ければ同じIDを使う。
        let second = styles.first(where: { $0.styleId != first.styleId }) ?? first
        return (first.styleId, second.styleId)
    }

    private func makeVoicevoxSpeakerSetting(styleId: UInt32) -> SpeakerSetting {
        let realmSetting = RealmSpeakerSetting()
        realmSetting.type = "VOICEVOX"
        realmSetting.voiceIdentifier = "\(styleId)"
        realmSetting.locale = "ja-JP"
        return SpeakerSetting(from: realmSetting)
    }

    // WAV(24kHz/mono/16bit, 44バイトヘッダ)からおおよその再生時間を見積もる。
    private static func wavDurationSeconds(_ data: Data) -> Double {
        guard data.count > 44 else { return 0 }
        let sampleCount = (data.count - 44) / 2
        return Double(sampleCount) / 24000.0
    }

    // SpeechBlockSpeaker.hasNoSpeakableCharacter() と同じ基準。
    private static func hasNoSpeakableCharacter(_ text: String) -> Bool {
        for character in text {
            if character.isWhitespace || character.isNewline { continue }
            if character.isPunctuation || character.isSymbol { continue }
            return false
        }
        return true
    }

    // SpeechBlockSpeaker.refillVoicevoxPrefetchIfNeeded() と同じ定数・同じアルゴリズムを
    // このテストの中で再現する(本体側はprivateで直接呼べないため)。
    private static let prefetchTargetCharacterCount = 300
    private static let prefetchMinimumBlockCount = 3
    private static let prefetchMaxBlockCountToQueue = 8
    private static let prefetchMaxBlocksToScan = 40

    private func refillPrefetch(blockArray: [CombinedSpeechBlock], fromIndex: Int, nextScanIndex: inout Int) {
        var accumulated = 0
        var prefetchedBlockCount = 0
        var index = max(fromIndex, nextScanIndex)
        var scanned = 0
        while index < blockArray.count && scanned < Self.prefetchMaxBlocksToScan
            && prefetchedBlockCount < Self.prefetchMaxBlockCountToQueue
            && (accumulated < Self.prefetchTargetCharacterCount || prefetchedBlockCount < Self.prefetchMinimumBlockCount) {
            let block = blockArray[index]
            scanned += 1
            guard block.type == "VOICEVOX", let styleId = UInt32(block.voiceIdentifier ?? "") else {
                index += 1
                continue
            }
            let text = block.speechText
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Self.hasNoSpeakableCharacter(text) {
                index += 1
                continue
            }
            VoicevoxCore.shared.schedulePrefetch(blockIndex: index, text: text, styleId: styleId)
            accumulated += text.count
            prefetchedBlockCount += 1
            index += 1
        }
        nextScanIndex = index
    }

    // ユーザーの実機設定(句読点の間の設定なし、会話文「」に別VOICEVOX話者)を再現し、
    // SpeechBlockSpeakerが実際に行っているのと同じ手順(順番にsynthesize()を呼び、
    // 現在のブロックより先を先行合成しておく)を直接駆動する。実機と同じ絶対時刻付き
    // ログ([発話発注]/[発話完了]/[キャッシュHIT]等)がコンソールに出力されるので、
    // どこで詰まっているかをここで確認できる。
    func testReproduceRealDeviceStallScenario() async throws {
        let (narratorStyleId, dialogueStyleId) = try await setUpCoreAndPickStyles()
        await VoicevoxCore.shared.clearPrefetchCache()

        let narratorSetting = makeVoicevoxSpeakerSetting(styleId: narratorStyleId)
        let dialogueSetting = makeVoicevoxSpeakerSetting(styleId: dialogueStyleId)
        let sectionConfigList = [SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: dialogueSetting)]

        let blockArray = StoryTextClassifier.CategorizeStoryText(
            content: Self.reproText,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: narratorSetting,
            sectionConfigList: sectionConfigList,
            waitConfigList: [], // 句読点の「間の設定」は無し
            sortedSpeechModArray: []
        )
        NSLog("NovelSpeaker.VoicevoxRealDeviceReproTest: 総ブロック数=\(blockArray.count)")

        var nextScanIndex = 0
        let overallStart = Date()
        var maxSynthesizeSeconds = 0.0

        for i in 0..<blockArray.count {
            let block = blockArray[i]
            guard block.type == "VOICEVOX", let styleId = UInt32(block.voiceIdentifier ?? "") else { continue }
            let text = block.speechText
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Self.hasNoSpeakableCharacter(text) { continue }

            NSLog("NovelSpeaker.SpeechBlockSpeaker: [\(VoicevoxCore.logTimestamp())] [発話発注] blockIndex=\(i) type=VOICEVOX text=\"\(text.prefix(30))\"")
            let dispatchDate = Date()
            let data = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
            let synthesizeSeconds = Date().timeIntervalSince(dispatchDate)
            maxSynthesizeSeconds = max(maxSynthesizeSeconds, synthesizeSeconds)
            let duration = Self.wavDurationSeconds(data)
            NSLog("NovelSpeaker.SpeechBlockSpeaker: [\(VoicevoxCore.logTimestamp())] [発話完了] blockIndex=\(i) 合成待ち=\(String(format: "%.2f", synthesizeSeconds))秒 再生予定長=\(String(format: "%.2f", duration))秒")

            // 現在のブロックより先を先行合成しておく(SpeechBlockSpeaker.enqueueSpeechBlock()相当)。
            refillPrefetch(blockArray: blockArray, fromIndex: i + 1, nextScanIndex: &nextScanIndex)

            // 実機での「再生中」の経過を、実際のWAV長に応じて模擬する。0.1秒間隔の
            // willSpeakRangeタイマー相当で、その間も先読みスキャンを継続させる。
            var remaining = duration
            while remaining > 0 {
                let tick = min(0.1, remaining)
                try await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                remaining -= tick
                refillPrefetch(blockArray: blockArray, fromIndex: i + 1, nextScanIndex: &nextScanIndex)
            }
        }

        let totalElapsed = Date().timeIntervalSince(overallStart)
        NSLog("NovelSpeaker.VoicevoxRealDeviceReproTest: 全ブロック完了。総経過時間=\(String(format: "%.2f", totalElapsed))秒 最大合成待ち=\(String(format: "%.2f", maxSynthesizeSeconds))秒")

        // 合成待ちが極端に長い(=どこかで無音待ちが起きた)場合に気付けるよう、
        // 実機で報告された「詰まり」の目安よりは十分厳しい上限で assert しておく。
        XCTAssertLessThan(maxSynthesizeSeconds, 5.0, "1ブロックの合成待ちが5秒を超えた(=無音の詰まりが発生した可能性が高い)")
    }
}
