//
//  VoicevoxStageTimingTest.swift
//  NovelSpeakerTests
//
//  VOICEVOX の合成コストに見えている「固定費(文字数に依らない費用)」の正体を切り分けるための
//  計測用テスト。合成を段階ごとに分けて呼び、各段階の壁時計時間と CPU 時間を NSLog に出す。
//
//  0.16.4 の C API で分割できるのは以下だけ(ヘッダ実物で確認済み):
//    1. voicevox_open_jtalk_rc_analyze              テキスト → AccentPhrase[]   (Open JTalk・推論なし)
//    2. voicevox_synthesizer_replace_phoneme_length 音素長の推論 (predict_duration)
//    3. voicevox_synthesizer_replace_mora_pitch     音高の推論   (predict_intonation)
//    4. voicevox_audio_query_create_from_accent_phrases  AccentPhrase[] → AudioQuery (純JSON)
//    5. voicevox_synthesizer_synthesis              AudioQuery → WAV (decode/render 推論)
//  voicevox_synthesizer_create_audio_query は 1+2+3+4、voicevox_synthesizer_tts は 1〜5 の
//  ショートハンドに過ぎない。「呼び出しをまたいで使い回せる中間結果」は無い
//  (1〜4 の出力はすべてテキストに依存する)。それでも段階別に測るのは、
//  「固定費」がどの段階に乗っているのかを実測で確定させるため。
//
//  シミュレータでも走るが、シミュレータの CPU は Mac のものなので絶対値には意味が無い。
//  値を採るのは実機。実機でのやり方は本ファイル末尾のコメント参照。
//
//  このテストは検証(XCTAssert)をほとんど行わない。ログを読むための道具である。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxStageTimingTest: XCTestCase {

    // MARK: - 準備

    private struct Environment {
        let styleId: UInt32
    }

    /// 0.vvm / 辞書が無い環境ではスキップする。
    private func setUpCore() async throws -> Environment {
        guard VoicevoxCore.isAvailableOnThisOS else {
            throw XCTSkip("この OS では VOICEVOX を利用できません")
        }
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else {
            throw XCTSkip("open_jtalk_dic_utf_8-1.11 がバンドルにありません(scripts/fetch_voicevox_vendor.sh 未実行?)")
        }
        guard let vvmPath = VoicevoxTestVoiceModel.path() else {
            throw XCTSkip("0.vvm がバンドルにありません(scripts/fetch_voicevox_vendor.sh 未実行?)")
        }
        try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])
        let styles = await VoicevoxCore.shared.styles
        guard let style = styles.first else {
            throw XCTSkip("0.vvm からスタイルが取れませんでした")
        }
        return Environment(styleId: style.styleId)
    }

    private static func log(_ message: String) {
        // 実機のコンソールから grep しやすいように接頭辞を固定する。
        NSLog("NovelSpeaker.VoicevoxStageTiming: \(message)")
    }

    private static func log(_ label: String, _ timing: VoicevoxStageTiming) {
        log("[\(label)] \(timing.logLine)")
    }

    /// 文字数を指定して、日本語として自然な計測用テキストを作る。
    /// 同じ短文の繰り返しだと Open JTalk 側に有利に出るため、複数の文を並べた地の文を使う。
    private static func makeText(characterCount: Int) -> String {
        let source = "彼は静かに立ち上がり、窓の外に広がる街並みをしばらく眺めていた。遠くの空には厚い雲がかかっていて、今にも雨が降り出しそうだった。少年は鞄を肩にかけ直すと、誰にも気づかれないように部屋を出ていった。廊下の突き当たりには古びた時計が掛かっていて、針は既に約束の時刻を過ぎている事を示していた。私はその場に立ち尽くしたまま、これから起こる事を何一つ想像できずにいた。風が吹き抜けるたびに、木々の葉が乾いた音を立てて揺れていた。"
        var result = ""
        while result.count < characterCount {
            result += source
        }
        return String(result.prefix(characterCount))
    }

    // MARK: - 計測1: ウォームアップの切り分け

    /// 同じ文を繰り返し合成し、1回目と2回目以降で各段階の時間がどう変わるかを見る。
    ///
    /// 「固定費」が本当に毎回払う費用なのか、それとも初回のモデルロードや
    /// ONNX セッションの遅延初期化が1回目にだけ乗っているだけなのかを切り分ける。
    /// 2回目以降も同じだけ掛かるなら固定費は本物、1回目だけなら固定費ではない。
    func testStageTimingWarmup() async throws {
        let environment = try await setUpCore()
        let text = Self.makeText(characterCount: 60)
        let repeatCount = 5

        Self.log("=== ウォームアップ切り分け: 同じ \(text.count) 文字を \(repeatCount) 回合成 ===")
        for index in 0..<repeatCount {
            let timing = try await VoicevoxCore.shared.debugMeasureStages(text: text, styleId: environment.styleId)
            Self.log("回数=\(index + 1)", timing)
        }
        Self.log("=== ウォームアップ切り分け ここまで ===")
    }

    // MARK: - 計測2: 文字数を変えた時に伸びる段階の特定

    /// 文字数を変えて測り、どの段階が文字数に比例して伸び、どの段階が伸びないかを見る。
    ///
    /// 「固定費 + 文字数比例」に分解できるなら、伸びない段階(=切片)がどこかに現れるはず。
    /// どの段階も原点を通る直線なら、見えていた固定費は合成そのものの費用ではなく、
    /// 計測側(発熱・CPU上限待ち・回帰の当てはめ)の産物という事になる。
    func testStageTimingByCharacterCount() async throws {
        let environment = try await setUpCore()
        let characterCounts = [10, 20, 40, 80, 120, 160, 240]

        // 先に一度合成して、初回のモデルロード/遅延初期化を計測から追い出しておく。
        _ = try await VoicevoxCore.shared.debugMeasureStages(text: "ウォームアップ", styleId: environment.styleId)

        Self.log("=== 文字数スイープ(ウォームアップ済み) ===")
        var summary: [(chars: Int, staged: Double, tts: Double, synthesis: Double, audio: Double, analyze: Double, duration: Double, pitch: Double)] = []
        for characterCount in characterCounts {
            let text = Self.makeText(characterCount: characterCount)
            let timing = try await VoicevoxCore.shared.debugMeasureStages(text: text, styleId: environment.styleId)
            Self.log("文字数=\(characterCount)", timing)
            summary.append((characterCount,
                            timing.stagedTotal.cpu,
                            timing.ttsOneShot.cpu,
                            timing.synthesis.cpu,
                            timing.audioSeconds,
                            timing.openJTalkAnalyze.cpu,
                            timing.replacePhonemeLength.cpu,
                            timing.replaceMoraPitch.cpu))
        }

        // 最小二乗で「固定費 + 単価×文字数」に当てはめて、切片が本当に出るかを見る。
        Self.log("--- 当てはめ(CPU秒 = 固定費 + 単価 × 文字数) ---")
        Self.log("staged合計:    " + Self.fitDescription(summary.map { (Double($0.chars), $0.staged) }))
        Self.log("tts一発:       " + Self.fitDescription(summary.map { (Double($0.chars), $0.tts) }))
        Self.log("synthesisのみ: " + Self.fitDescription(summary.map { (Double($0.chars), $0.synthesis) }))
        Self.log("analyzeのみ:   " + Self.fitDescription(summary.map { (Double($0.chars), $0.analyze) }))
        Self.log("音素長推論:    " + Self.fitDescription(summary.map { (Double($0.chars), $0.duration) }))
        Self.log("音高推論:      " + Self.fitDescription(summary.map { (Double($0.chars), $0.pitch) }))
        Self.log("音声秒数:      " + Self.fitDescription(summary.map { (Double($0.chars), $0.audio) }))
        Self.log("=== 文字数スイープ ここまで ===")
    }

    // MARK: - 計測3: 段階分割 vs tts 一発

    /// 段階に分けて呼んだ合計と、tts 一発の時間を比べる。
    ///
    /// 分割して呼ぶこと自体にオーバーヘッド(JSON の往復コスト等)があるかを見る。
    /// なお 0.16.4 には「呼び出しをまたいで使い回せる中間結果」は存在しないので、
    /// これは固定費を減らす手段の検証ではなく、段階分割が実用に耐えるかの確認である。
    func testStagedVersusOneShotTTS() async throws {
        let environment = try await setUpCore()
        _ = try await VoicevoxCore.shared.debugMeasureStages(text: "ウォームアップ", styleId: environment.styleId)

        Self.log("=== 段階分割 vs tts一発 ===")
        for characterCount in [40, 120, 240] {
            let text = Self.makeText(characterCount: characterCount)
            let timing = try await VoicevoxCore.shared.debugMeasureStages(text: text, styleId: environment.styleId)
            let stagedCPU = timing.stagedTotal.cpu
            let ttsCPU = timing.ttsOneShot.cpu
            let ratio = ttsCPU > 0 ? stagedCPU / ttsCPU : 0
            Self.log(String(format: "文字数=%d staged=%.3fs tts=%.3fs staged/tts=%.3f", characterCount, stagedCPU, ttsCPU, ratio))
            Self.log("内訳 文字数=\(characterCount)", timing)
        }
        Self.log("=== 段階分割 vs tts一発 ここまで ===")
    }

    // MARK: - 計測4: 分割合成の損得(固定費の実在確認)

    /// 同じ本文を「1本で合成」した場合と「N分割して合成」した場合で、
    /// 合計 CPU 秒がどれだけ変わるかを直接測る。
    ///
    /// 固定費が本当に「合成1回あたり」で発生するなら、分割数に比例して合計が増えるはず。
    /// 増えないなら、細切れにしてもスループットは落ちないという事になり、
    /// 現在の「分割すると損」という前提そのものが崩れる。
    func testSplitPenalty() async throws {
        let environment = try await setUpCore()
        _ = try await VoicevoxCore.shared.debugMeasureStages(text: "ウォームアップ", styleId: environment.styleId)

        let total = 240
        let text = Self.makeText(characterCount: total)
        Self.log("=== 分割の損得(合計 \(total) 文字) ===")
        for splitCount in [1, 2, 4, 8] {
            let chunkLength = total / splitCount
            var cpuSum = 0.0
            var wallSum = 0.0
            var audioSum = 0.0
            var offset = text.startIndex
            for _ in 0..<splitCount {
                let end = text.index(offset, offsetBy: chunkLength, limitedBy: text.endIndex) ?? text.endIndex
                let chunk = String(text[offset..<end])
                offset = end
                if chunk.isEmpty { continue }
                let timing = try await VoicevoxCore.shared.debugMeasureStages(text: chunk, styleId: environment.styleId, includeOneShotTTS: false)
                cpuSum += timing.stagedTotal.cpu
                wallSum += timing.stagedTotal.wall
                audioSum += timing.audioSeconds
            }
            Self.log(String(format: "分割数=%d (1本%d文字) cpu合計=%.3fs wall合計=%.3fs 音声=%.2fs RTF(cpu)=%.3f",
                            splitCount, chunkLength, cpuSum, wallSum, audioSum, audioSum > 0 ? cpuSum / audioSum : 0))
        }
        Self.log("=== 分割の損得 ここまで ===")
    }

    // MARK: - 当てはめ

    /// 最小二乗で y = a + b*x に当てはめ、結果を文字列にする。
    private static func fitDescription(_ points: [(Double, Double)]) -> String {
        guard points.count >= 2 else { return "サンプル不足" }
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.0 }
        let sumY = points.reduce(0) { $0 + $1.1 }
        let sumXY = points.reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = points.reduce(0) { $0 + $1.0 * $1.0 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return "当てはめ不能" }
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        // 決定係数。当てはまりが悪ければ「固定費+比例」というモデル自体が疑わしい。
        let meanY = sumY / n
        let ssTot = points.reduce(0.0) { $0 + ($1.1 - meanY) * ($1.1 - meanY) }
        let ssRes = points.reduce(0.0) { accumulated, point in
            let predicted = intercept + slope * point.0
            return accumulated + (point.1 - predicted) * (point.1 - predicted)
        }
        let r2 = ssTot > 0 ? 1 - ssRes / ssTot : 0
        return String(format: "固定費=%.3f  単価=%.4f/文字  R^2=%.4f", intercept, slope, r2)
    }
}

//
// 実機での走らせ方:
//
//   xcodebuild -workspace novelspeaker.xcworkspace -scheme NovelSpeakerTests \
//     -destination 'platform=iOS,name=<端末名>' \
//     -only-testing:NovelSpeakerTests/VoicevoxStageTimingTest test
//
// (シミュレータなら -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5')
// ログは接頭辞 "NovelSpeaker.VoicevoxStageTiming:" で grep できる。
//
// 実機で見るべき点:
//
//  1. testStageTimingWarmup
//     1回目と2回目以降で staged合計 / tts一発 の CPU 秒が大きく違うなら、
//     見えていた「固定費」は初回のロード・遅延初期化であって、毎回の固定費ではない。
//     modelLoad の値も見る事(2回目以降は 0 のはず)。
//
//  2. testStageTimingByCharacterCount
//     「固定費=」の値が 0 に近ければ、合成1回あたりの固定費は存在しない。
//     R^2 が低い(0.9 未満など)なら、そもそも「固定費+比例」で説明できていない
//     = ばらつき(発熱・CPU上限)を固定費として読んでいた可能性が高い。
//     synthesis(decode)だけが文字数に比例し、analyze/音素長/音高が小さいままなら、
//     コストの本体は decode であり、そこには使い回せる中間結果は無い。
//
//  3. testSplitPenalty
//     分割数を増やしても cpu合計がほぼ変わらないなら、分割は損ではない。
//     分割数に比例して増えるなら固定費は実在する。その場合、増分がどの段階かを
//     testStageTimingByCharacterCount の内訳と突き合わせる。
//
//  4. 発熱の影響を避けるため、実機は充電を外し、端末が冷えた状態から始める事。
//     連続で走らせると後半のテストほど遅くなる(それ自体が「固定費」の正体候補)。
//     4つのテストは1つずつ、間を空けて走らせるのが望ましい。
//
