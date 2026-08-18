//
//  VoicevoxChunkedSynthesisTest.swift
//  NovelSpeakerTests
//
//  「1本の合成が CPU 予算(60秒窓×割合)に収まらない場合にだけ、句読点で分割して合成し、
//   出来た音声を繋いで1つのブロックとして扱う」仕組みのテスト。
//
//  なぜ「収まらない場合にだけ」なのか:
//  分割して別々に合成した音声を繋ぐと、一度に合成した場合と比べて繋ぎ目に
//  気になる「間」ができる(VOICEVOX が発話の前後に無音を付けるため)。
//  音質のためには分割しないのが最善なので、分割は「そうしないと背面で合成できない」
//  時の最後の手段にする。iPhone SE2 では 0.33〜0.8 秒/文字かかり、100文字級の
//  ブロックが1本で予算(48秒)を超えてしまうため、この端末では分割が必須になる。
//  一方 iPhone 17 Pro Max では 0.13 秒/文字なので、まず分割は起きない。
//
//  繋ぎ目の「間」は、自分で作った分割位置に限って前後の無音を削る事で緩和する
//  (ブロック全体の先頭・末尾の無音は元のまま残す。そこは元々の発話の一部なので触らない)。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxTextChunkerTest: XCTestCase {

    // 上限に収まるテキストは分割しない(音質を優先するため、分ける必要が無ければ分けない)。
    func testShortEnoughTextIsNotSplit() {
        let text = "これは短い文です。"
        XCTAssertEqual(VoicevoxTextChunker.split(text: text, maxCharacterCount: 100), [text])
    }

    // 上限を超えたら句読点で分ける。各断片は上限以下で、繋ぐと元通りになる事。
    func testSplitsAtPunctuationAndPreservesTheWholeText() {
        let text = "むかしむかしあるところに、おじいさんとおばあさんがいました。おじいさんは山へ芝刈りに、おばあさんは川へ洗濯に行きました。"
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 30, minimumCharacterCount: 1)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 30, "各断片は上限以下であるべき: \(chunk)")
        }
        XCTAssertEqual(chunks.joined(), text, "分割で文字が失われたり増えたりしてはいけない")
    }

    // 上限の範囲内で「一番後ろの句読点」で切る(できるだけ長く=繋ぎ目を少なくする)。
    func testCutsAtTheLastPunctuationWithinTheLimit() {
        let text = "あい、うえお、かきくけこさしすせそたちつてと"
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 10, minimumCharacterCount: 1)
        XCTAssertEqual(chunks.first, "あい、うえお、", "上限内で最後の「、」で切るべき")
    }

    // 句読点が全く無い場合でも、上限を超えたまま返してはいけない(予算を超えて殺される)。
    func testFallsBackToHardCutWhenThereIsNoPunctuation() {
        let text = String(repeating: "あ", count: 50)
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 20, minimumCharacterCount: 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 20)
        }
        XCTAssertEqual(chunks.joined(), text)
    }

    // 上限が極端に小さくても無限ループしない事。
    func testDoesNotLoopForeverWithTinyLimit() {
        let chunks = VoicevoxTextChunker.split(text: "あいうえお", maxCharacterCount: 1, minimumCharacterCount: 1)
        XCTAssertEqual(chunks.count, 5)
        XCTAssertEqual(chunks.joined(), "あいうえお")
    }

    func testEmptyTextGivesEmptyResult() {
        XCTAssertEqual(VoicevoxTextChunker.split(text: "", maxCharacterCount: 10), [])
    }

    // 空白・改行だけの断片を作らない事。
    // 実機で本文が "\n\u{3000}意外な状況で…" のように改行+全角空白で始まっており、
    // 上限内の最後の区切り文字が全角空白だったために "\n\u{3000}" という断片ができ、
    // VOICEVOX が「入力テキストの解析に失敗しました」で合成に失敗していた。
    func testDoesNotProduceWhitespaceOnlyChunk() {
        let text = "\n\u{3000}意外な状況で顔を合わせた意外なクラスメイトと、しみじみその意外性について語り合う男女。それ自体は珍しい訳ではない。"
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 20, minimumCharacterCount: 1)
        for chunk in chunks {
            XCTAssertFalse(chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "空白のみの断片を作ってはいけない: \(chunk.debugDescription)")
        }
        XCTAssertEqual(chunks.joined(), text)
    }

    // 細切れにし過ぎない事。
    // 合成には文字数に依らない固定費(実測: iPhone SE2 低電力で20秒超)があるため、
    // 細かく分けるほど合計 CPU 時間が増えて逆効果になる。実機では 102文字が8分割、
    // 132文字が9分割まで細かくなり、1ブロックの発話に5分以上かかっていた。
    func testDoesNotSplitBelowTheMinimumChunkSize() {
        let text = String(repeating: "あいうえお、", count: 20) // 120文字
        // 上限を5文字と指示しても、最小長(40)を下回る細切れにはしない。
        // 句読点で切る都合上ちょうど40にはならないが、40文字ぶんの窓の中で切るので
        // 8分割にも9分割にもならない。
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 5, minimumCharacterCount: 40)
        XCTAssertLessThanOrEqual(chunks.count, 4, "120文字が細切れになってはいけない: \(chunks.count)分割")
        // 末尾は割り切れない余りなので短くなり得る(最後に一度だけ固定費を余分に払う)。
        for chunk in chunks.dropLast() {
            XCTAssertGreaterThanOrEqual(chunk.count, 20, "最小長を大きく下回る断片を作ってはいけない: \(chunk)")
        }
        XCTAssertEqual(chunks.joined(), text)
    }
}

// 合成には文字数に依らない固定費(実測: iPhone SE2 低電力で20秒前後)があるため、
// 同じ CPU 時間を使うなら「大きく1本」の方が作れる音声は多くなる。
//   40文字×1本 (20秒 + 10秒) → 音声 約5.7秒
//  112文字×1本 (20秒 + 28秒) → 音声 約16秒
// したがって分割は「予算に収まる範囲で最も少ない個数」にしなければならない。
class VoicevoxChunkBalanceTest: XCTestCase {

    // 予算に収まる範囲で、できるだけ少ない個数に分ける事。
    func testSplitsIntoTheFewestPiecesThatFit() {
        let text = String(repeating: "あいうえおかきくけこ、", count: 12) // 132文字
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 64)
        XCTAssertEqual(chunks.count, 3, "132文字が64文字に収まる最小個数(3個)で分かれるべき")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 64)
        }
        XCTAssertEqual(chunks.joined(), text)
    }

    // 個数が同じなら、長さを揃えて末尾だけ極端に短くならないようにする事
    // (短い断片でも固定費は丸ごとかかるため、極端に短い断片は純粋な損になる)。
    func testBalancesChunkLengthsInsteadOfLeavingATinyTail() {
        let text = String(repeating: "あいうえおかきくけこ、", count: 12) // 132文字
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 64)
        let shortest = chunks.map { $0.count }.min() ?? 0
        XCTAssertGreaterThan(shortest, 20, "末尾だけ極端に短い断片を作ってはいけない: \(chunks.map { $0.count })")
    }
}

// 区切り文字が上限までに現れない場合の扱い。
//
// ぶつ切りにすると発音そのものが変わってしまう(実機で「安全係数(1.25倍)を掛」と
// 「けた上で〜」に分かれ、「をかけ」「けたうえで」と読まれた)。繋ぎ目の無音を削るような
// 緩和もできないので、まずは上限を伸ばして区切り文字を探す。
// ただし無制限には伸ばせない(合成の入力が長いと ONNX Runtime が確保する内部メモリが
// 増えて戻らなくなる。ブロック自体の上限も160文字)。伸ばしても見つからなければ諦めて切る。
class VoicevoxChunkBoundarySearchTest: XCTestCase {

    // 上限を少し超えた所に区切り文字があるなら、そこまで伸ばして区切る事。
    func testExtendsBeyondTheLimitToFindAPunctuation() {
        // 上限20文字。20文字の位置は語の途中で、25文字目に「、」がある。
        let text = "安全係数を掛けた上でどの実測値も下回らないように、上側へ倒しているので余裕があります。"
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 20, minimumCharacterCount: 1)
        let first = try! XCTUnwrap(chunks.first)
        XCTAssertTrue(first.hasSuffix("、"), "上限を伸ばしてでも区切り文字で切るべき。実際: \(first)")
        XCTAssertEqual(chunks.joined(), text)
    }

    // 伸ばす幅には上限があり、それを超えてまでは探さない事
    // (合成の入力が長くなり過ぎるとメモリを圧迫するため)。
    func testDoesNotExtendBeyondTheHardMaximum() {
        // 区切り文字が遥か先にしか無い文。
        let text = String(repeating: "あ", count: 300) + "。"
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 20, minimumCharacterCount: 1, hardMaxCharacterCount: 60)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 60, "伸ばす上限を超えてはいけない")
        }
        XCTAssertEqual(chunks.joined(), text)
    }

    // 伸ばしても区切り文字が無ければ、諦めてぶつ切りにする(予算超過で殺される方が困る)。
    func testFallsBackToHardCutWhenNoPunctuationEvenAfterExtending() {
        let text = String(repeating: "あ", count: 100)
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 20, minimumCharacterCount: 1, hardMaxCharacterCount: 40)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 40)
        }
        XCTAssertEqual(chunks.joined(), text)
    }

    // 上限内に区切り文字があるなら、伸ばさずにそこで切る事(伸ばすのは最後の手段)。
    func testDoesNotExtendWhenAPunctuationIsWithinTheLimit() {
        let text = "あいうえお、かきくけこさしすせそたちつてとなにぬねの。はひふへほ"
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: 20, minimumCharacterCount: 1)
        XCTAssertEqual(chunks.first, "あいうえお、", "上限内の区切り文字を使うべき")
    }
}

class VoicevoxWavJoinerTest: XCTestCase {

    private let sampleRate = 24000

    /// 24kHz/mono/16bit の WAV を組み立てる(先頭と末尾に指定秒数の無音を付ける)。
    private func makeWav(bodySampleCount: Int, leadingSilence: Int = 0, trailingSilence: Int = 0, amplitude: Int16 = 8000) -> Data {
        var samples = [Int16](repeating: 0, count: leadingSilence)
        // 無音判定に引っかからないよう、±amplitude で振動させる。
        samples.append(contentsOf: (0..<bodySampleCount).map { $0 % 2 == 0 ? amplitude : -amplitude })
        samples.append(contentsOf: [Int16](repeating: 0, count: trailingSilence))
        var payload = Data()
        for sample in samples {
            payload.append(UInt8(truncatingIfNeeded: sample))
            payload.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        return Self.wavData(payload: payload, sampleRate: sampleRate)
    }

    static func wavData(payload: Data, sampleRate: Int) -> Data {
        var data = Data()
        func appendUInt32(_ value: UInt32) {
            data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff)); data.append(UInt8((value >> 24) & 0xff))
        }
        func appendUInt16(_ value: UInt16) {
            data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + payload.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func sampleCount(of wav: Data) -> Int {
        guard let parsed = VoicevoxWavJoiner.parse(wav: wav) else { return -1 }
        return parsed.payload.count / 2
    }

    // 1本だけなら何も加工せずそのまま返す(触らないのが最善)。
    func testSingleWavIsReturnedUnchanged() {
        let wav = makeWav(bodySampleCount: 100, leadingSilence: 10, trailingSilence: 10)
        XCTAssertEqual(VoicevoxWavJoiner.join(wavs: [wav]), wav)
    }

    // 繋いだ結果が正しい WAV になっていて、長さが合っている事。
    func testJoinedWavIsValidAndHasExpectedLength() throws {
        let a = makeWav(bodySampleCount: 100)
        let b = makeWav(bodySampleCount: 200)
        let joined = try XCTUnwrap(VoicevoxWavJoiner.join(wavs: [a, b]))
        XCTAssertEqual(joined.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(sampleCount(of: joined), 300)
        // ヘッダのサイズ欄が中身と一致している事(不一致だと AVAudioFile が読めない)。
        let parsed = try XCTUnwrap(VoicevoxWavJoiner.parse(wav: joined))
        XCTAssertEqual(parsed.sampleRate, sampleRate)
        XCTAssertEqual(parsed.channelCount, 1)
        XCTAssertEqual(parsed.bitsPerSample, 16)
    }

    // 分割した繋ぎ目の無音は削る(ここが「気になる間」の正体)。
    func testInteriorSilenceAtTheJoinIsTrimmed() throws {
        let a = makeWav(bodySampleCount: 100, trailingSilence: 2400) // 末尾に0.1秒の無音
        let b = makeWav(bodySampleCount: 100, leadingSilence: 2400)  // 先頭に0.1秒の無音
        let joined = try XCTUnwrap(VoicevoxWavJoiner.join(wavs: [a, b]))
        XCTAssertEqual(sampleCount(of: joined), 200, "繋ぎ目の無音は削られるべき")
    }

    // ブロック全体の先頭と末尾の無音は残す(元の発話の一部なので触らない)。
    func testLeadingAndTrailingSilenceOfTheWholeBlockIsKept() throws {
        let a = makeWav(bodySampleCount: 100, leadingSilence: 1200)
        let b = makeWav(bodySampleCount: 100, trailingSilence: 1200)
        let joined = try XCTUnwrap(VoicevoxWavJoiner.join(wavs: [a, b]))
        XCTAssertEqual(sampleCount(of: joined), 1200 + 100 + 100 + 1200,
                       "先頭・末尾の無音は残し、繋ぎ目だけを削るべき")
    }

    // 全部無音の断片を削り切って音声を消してしまわない事。
    func testAllSilentChunkIsNotCompletelyRemoved() throws {
        let silent = Self.wavData(payload: Data(repeating: 0, count: 2400 * 2), sampleRate: sampleRate)
        let voiced = makeWav(bodySampleCount: 100)
        let joined = try XCTUnwrap(VoicevoxWavJoiner.join(wavs: [silent, voiced]))
        XCTAssertGreaterThan(sampleCount(of: joined), 100, "無音のみの断片でも全部は消さない")
    }

    // 壊れたデータを渡された時に落ちない事。
    func testInvalidWavIsRejected() {
        XCTAssertNil(VoicevoxWavJoiner.parse(wav: Data("RIFF".utf8)))
        XCTAssertNil(VoicevoxWavJoiner.join(wavs: []))
        XCTAssertNil(VoicevoxWavJoiner.join(wavs: [Data("これはWAVではない".utf8)]))
    }
}

// 合成コストは「固定費 + 文字数比例」だが、**固定費は小さい**(1〜3秒)。
//
// ここには以前「固定費20秒」という前提のテストが並んでいた。
// その値は VoicevoxCPUGovernor のラチェットが作った産物で、実在しなかった
// (VoicevoxStageTimingTest で iPhone SE2 実機を測り直した結果:
//  固定費1.60秒 + 0.346秒/文字, R^2=0.997)。
// 誤った前提のデータを食わせて「再現できる事」を確かめていたので、
// 実測に沿った形に置き換えてある。
class VoicevoxCostModelTest: XCTestCase {

    private func makeGovernor() -> VoicevoxCPUGovernor {
        return VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 1.0)
    }

    /// iPhone SE2 実機の実測(2026-08-18)。
    private let realDeviceSamples: [(cpu: Double, chars: Int)] = [
        (5.18, 10), (15.74, 40), (41.07, 120), (86.81, 240),
    ]

    // 実測を食わせたら、その実測を言い当てられる事。
    func testReproducesRealDeviceMeasurements() {
        let governor = makeGovernor()
        for sample in realDeviceSamples {
            governor.recordSynthesis(cpuSeconds: sample.cpu, characterCount: sample.chars, at: 0)
        }
        for sample in realDeviceSamples {
            let estimate = governor.estimatedCPUSeconds(forCharacterCount: sample.chars)
            XCTAssertGreaterThanOrEqual(estimate, sample.cpu,
                                        "\(sample.chars)文字の見積りが実測を下回っている")
            XCTAssertLessThan(estimate, sample.cpu * 1.6,
                              "\(sample.chars)文字の見積り \(estimate) が実測 \(sample.cpu) に対し過大")
        }
    }

    // 分割すると合計コストが増える事が見積りに現れる事(=無闇に分割しない根拠になる)。
    // 固定費が小さくなっても、この性質自体は保たれていなければならない。
    func testSplittingCostsMoreInTotalBecauseOfTheFixedOverhead() {
        let governor = makeGovernor()
        for sample in realDeviceSamples {
            governor.recordSynthesis(cpuSeconds: sample.cpu, characterCount: sample.chars, at: 0)
        }
        let whole = governor.estimatedCPUSeconds(forCharacterCount: 120)
        let halves = governor.estimatedCPUSeconds(forCharacterCount: 60) * 2
        XCTAssertGreaterThan(halves, whole, "分割した方が合計コストは大きくなるはず")
    }

    // 見積りが実測を下回らない事(下回るとそのまま強制終了に繋がる)。
    // 発熱で1点だけ極端に重いサンプルが混じっても成り立つ事。
    func testEstimateNeverFallsBelowAnyMeasurement() {
        let governor = makeGovernor()
        let samples: [(Double, Int)] = [(5.18, 10), (60.0, 80), (86.81, 240)] // 80文字だけ極端に重い
        for (cpu, count) in samples {
            governor.recordSynthesis(cpuSeconds: cpu, characterCount: count, at: 0)
        }
        for (cpu, count) in samples {
            XCTAssertGreaterThanOrEqual(governor.estimatedCPUSeconds(forCharacterCount: count), cpu,
                                        "\(count)文字の見積りが実測(\(cpu)秒)を下回ってはいけない")
        }
    }

    // ★極端に重いサンプルが混じっても、固定費が膨らまない事。
    // 以前はここで固定費が20秒級まで押し上げられていた。
    func testOutlierDoesNotInflateTheFixedCost() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 5.18, characterCount: 10, at: 0)
        governor.recordSynthesis(cpuSeconds: 60.0, characterCount: 80, at: 1) // 発熱で極端に重い
        governor.recordSynthesis(cpuSeconds: 86.81, characterCount: 240, at: 2)
        XCTAssertLessThan(governor.estimatedCPUSeconds(forCharacterCount: 0), 5.0,
                          "固定費が膨らんでいる(外れ値を固定費に吸収してしまっている)")
    }
}

class VoicevoxGovernorChunkSizeTest: XCTestCase {

    // 予算に収まる最大の文字数を、実測から逆算できる事。
    // これが「どのくらいの長さなら分割せずに済むか」の判断基準になる。
    func testMaxCharacterCountIsDerivedFromMeasurements() {
        let governor = VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 0)
        governor.recordSynthesis(cpuSeconds: 33, characterCount: 100, at: 0) // 0.33秒/文字
        // 予算 48秒 ÷ 0.33秒/文字 ≒ 145文字
        let maxCount = governor.maxCharacterCount(withinCPUSeconds: 48)
        XCTAssertEqual(maxCount, 145)
        XCTAssertLessThanOrEqual(governor.estimatedCPUSeconds(forCharacterCount: maxCount), 48)
        XCTAssertGreaterThan(governor.estimatedCPUSeconds(forCharacterCount: maxCount + 1), 48)
    }

    // 端末が速ければ、分割せずに済む長さは長くなる(=分割が起きない)。
    func testFastDeviceAllowsMuchLongerText() {
        let governor = VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 0)
        governor.recordSynthesis(cpuSeconds: 13, characterCount: 100, at: 0) // 0.13秒/文字
        XCTAssertGreaterThan(governor.maxCharacterCount(withinCPUSeconds: 48), 300,
                             "速い端末ではブロック最大長(160文字)を余裕で超えるので分割は起きない")
    }

    // 極端に遅くても最低1文字は返す(0を返すと分割が終わらなくなる)。
    func testNeverReturnsZero() {
        let governor = VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 0)
        governor.recordSynthesis(cpuSeconds: 100, characterCount: 1, at: 0)
        XCTAssertGreaterThanOrEqual(governor.maxCharacterCount(withinCPUSeconds: 1), 1)
    }
}
