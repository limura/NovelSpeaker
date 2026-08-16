//
//  VoicevoxCore.swift
//  NovelSpeaker
//
//  voicevox_core (C API, XCFramework同梱) への最小限のSwiftラッパー。
//  VOICEVOX_IOS_INTEGRATION.md の §2/§3 を踏まえた実装。
//
//  Mac Catalyst では voicevox_core / voicevox_onnxruntime の XCFramework に
//  Catalyst(ios-macabi)スライスが配布されておらずリンクできないため、
//  末尾の #else 側で「常に利用不可」を返す同一サーフェスのスタブに差し替える
//  (Catalyst ビルドは SiteInfo 検査(--scrape-inspect)用途で、VOICEVOX は不要)。
//  pbxproj 側でも framework のリンク/埋め込みと辞書/VVMリソースに
//  platformFilter = ios を付けて Catalyst から除外している。
//

import Foundation
#if !targetEnvironment(macCatalyst) && !os(watchOS)
import voicevox_core
#endif

struct VoicevoxStyle {
    let name: String
    let styleId: UInt32
    let speakerName: String
    let speakerUUID: String
    let vvmPath: String
}

#if !targetEnvironment(macCatalyst) && !os(watchOS)

enum VoicevoxCoreError: LocalizedError {
    case core(VoicevoxResultCode)
    case notSetUp
    case styleNotFound(UInt32)
    case invalidWav

    var errorDescription: String? {
        switch self {
        case .core(let code):
            return String(cString: voicevox_error_result_to_message(code))
        case .notSetUp:
            return "VoicevoxCore.setUp() がまだ呼ばれていません"
        case .styleNotFound(let styleId):
            return "指定されたVOICEVOXスタイル(\(styleId))に対応する音声モデルが見つかりません"
        case .invalidWav:
            return "VOICEVOXの合成結果が不正なWAVデータでした"
        }
    }
}

// voicevox_core の全C呼び出しをこのactorに閉じ込めて直列化する
// (VOICEVOX_IOS_INTEGRATION.md §3-2: ブロッキング呼び出しをメインスレッドで呼ばない/直列化する)。
actor VoicevoxCore {
    static let shared = VoicevoxCore()

    // UI(SpeakerSettingsViewController等)が話者一覧をactor越しにawaitせず同期参照するための
    // ベストエフォートなスナップショット。reloadStyleCatalog() の度に更新される。
    nonisolated(unsafe) static var cachedStyles: [VoicevoxStyle] = []

    // ログ相関用の絶対時刻(壁時計)文字列。「先行合成待ちで無音になった」等の実機ログを、
    // 実際に発話(再生)が開始/終了した絶対時刻と突き合わせられるようにするためのもの。
    // NSLog自体もタイムスタンプ付きだが、コンソールの取得経路によっては見えない事があるため、
    // ログ本文側にも埋め込む。DateFormatterは複数スレッドから同時に使うと安全でないため、
    // 呼び出しの都度使い捨てで生成する(ログ出力頻度なら性能上問題にならない)。
    static func logTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    // OpenJtalkRc / VoicevoxOnnxruntime / VoicevoxSynthesizer / VoicevoxVoiceModelFile はいずれも
    // ヘッダ上では前方宣言のみ(定義本体なし)の不透明型なので、Swiftからは OpaquePointer として扱う。
    private var onnxruntime: OpaquePointer?
    private var openJTalk: OpaquePointer?
    private var synthesizer: OpaquePointer?

    private(set) var styles: [VoicevoxStyle] = []
    // 一度ロードした声モデルのVVMパスの集合(再ロードによる数百ms級の待ちを避けるため)
    private var loadedVvmPaths: Set<String> = []

    // 先行合成キャッシュ: 現在再生中のブロックより先のブロックを、再生が追いつく前に
    // バックグラウンドで合成しておくためのもの(VOICEVOX_IOS_INTEGRATION.md §6-2の
    // SynthesisWorker/PCMキャッシュ相当)。VOICEVOXはブロック全体を一括合成してから
    // 再生を始める方式で、ブロックを再生している間に次のブロックの合成が終わっていないと
    // 発話と発話の間に無音の間ができてしまうため、これを埋める。
    // key は synthesizePrefetchKey(text:styleId:) で作る。
    //
    // このキャッシュ本体だけは actor 隔離ではなく専用ロックで守る(nonisolated(unsafe))。
    // 理由: actor 隔離のままだと、既にキャッシュ済みで即返せるはずの参照(cache HIT)ですら、
    // actor が他の(無関係で低優先度な)先行合成を実行中だとその完了までactorへ入れず
    // 待たされてしまう。実機ログで「既に合成済みの短い会話文なのに、何秒も先の長い
    // 段落の先行合成が終わるまでHITログすら出ない」という現象として確認した
    // (キャッシュそのものは十分前に用意できていたのに、参照するための「actorの順番待ち」
    //  だけで無音になっていた)。読み出しをロックだけで完結させる事で、この種の待ちを無くす。
    // 追い出しの順序が要点なので、実体は VoicevoxWavCache に切り出してある。
    // 会話文の相槌等の短い文字列が再利用されるので、エントリ数は多めに持つ。
    nonisolated let wavCache = VoicevoxWavCache(entryCapacity: 64, totalByteLimit: 16 * 1024 * 1024)

    // actorへ入らずに(=今actorが何をしていても待たされずに)呼べるよう、あえて nonisolated。
    nonisolated private func peekCache(key: String) -> Data? {
        return wavCache.peek(key: key)
    }

    nonisolated private func storeCache(key: String, data: Data) {
        wavCache.store(key: key, data: data)
    }

    /// 指定テキストが先行合成済みなら、その WAV のバイト数を返す(未合成なら nil)。
    /// 「未再生の貯金が何秒あるか」を数えるために使う。actorへ入らず参照できる。
    nonisolated func cachedWavByteCount(text: String, styleId: UInt32) -> Int? {
        return wavCache.byteCount(key: Self.prefetchKey(text: text, styleId: styleId))
    }

    nonisolated private func clearCache() {
        wavCache.clear()
    }

    // 先行合成の待ち行列(「次に何を合成すべきか」の帳簿)。
    // actor の外(ロックのみ)で完結するので、合成中(1本12秒前後のC呼び出しの最中)でも
    // 予約・優先度変更・キャンセルが待たされずに反映される。詳細は VoicevoxSynthesisQueue.swift 参照。
    // 生成時に自分自身のキャッシュ参照を渡す必要があるため、init 内で組み立てる
    // (VoicevoxCore は shared のみのシングルトンなので、この暗黙アンラップは安全)。
    nonisolated(unsafe) private var synthesisQueueStorage: VoicevoxSynthesisQueue!
    nonisolated var synthesisQueue: VoicevoxSynthesisQueue { return synthesisQueueStorage }

    // CPU予算の管理役。背面バッテリー時に、合成を始める前に「この1本を今走らせたら
    // 60秒平均80%の上限を超えるか」を見積もって判断する(詳細は VoicevoxCPUGovernor.swift)。
    nonisolated let cpuGovernor = VoicevoxCPUGovernor()

    /// 合成に使ってよい CPU 予算の割合(OSの上限は80%)。
    ///
    /// 以前は先行合成 0.55 / 再生 0.75 と分けていたが、iPhone SE2 では
    /// 実測の CPU 率が 14〜46% にしかならず、上限に対して予算を大きく余らせていた。
    /// 合成には文字数に依らない固定費(SE2 低電力で20秒前後)があるため、
    /// 予算を小さく取ると分割が細かくなり、固定費を何度も払う羽目になって
    /// 同じ CPU 時間あたりに作れる音声が減る(40文字×1本で音声5.7秒に対し、
    /// 112文字×1本なら16秒)。予算は上限のすぐ手前まで使い切る方が有利。
    ///
    /// 先行合成と再生の優先順位は、この割合ではなく
    /// 「再生に必要な合成が進行中の間は先行合成を待たせる」仕組みで付ける。
    private static let prefetchCPULimitRatio = 0.75
    private static let playbackCPULimitRatio = 0.75
    /// OSの判定窓と同じ長さ。これ以上待っても窓の中身は減らない。
    private static let cpuWindowSeconds = 60.0

    /// CPU予算的に、この合成を始めてよくなるまであと何秒待つべきか。
    /// 上限が適用されない状況(前景/充電中)では常に0。
    nonisolated private func governorWaitSeconds(text: String, limitRatio: Double) -> Double {
        guard VoicevoxPrefetchThrottleMonitor.shared.isCPULimitApplied else { return 0 }
        return cpuGovernor.waitSeconds(forCharacterCount: text.count, limitRatio: limitRatio, at: ProcessInfo.processInfo.systemUptime)
    }

    // ワーカー(待ち行列から1件ずつ取り出して合成するループ)の起動状態。
    // actor へ入らずに判定したいので専用ロックで守る。
    private let workerLock = NSLock()
    nonisolated(unsafe) private var isWorkerRunningUnsafe = false
    /// 再生に必要な(=待たせるとそのまま無音になる)合成が何本進行中か。
    /// 0より大きい間、先行合成は CPU 予算を使わずに待つ。
    /// これが無いと、先行合成が予算を使い切っては再生側を待たせる、というのを
    /// 交互に繰り返して再生が延々と進まなくなる(実機で1ブロックの発話に5分以上)。
    nonisolated(unsafe) private var pendingPlaybackSynthesisCountUnsafe = 0

    nonisolated private func beginPlaybackSynthesis() {
        workerLock.lock()
        pendingPlaybackSynthesisCountUnsafe += 1
        workerLock.unlock()
    }

    nonisolated private func endPlaybackSynthesis() {
        workerLock.lock()
        pendingPlaybackSynthesisCountUnsafe = max(0, pendingPlaybackSynthesisCountUnsafe - 1)
        workerLock.unlock()
    }

    nonisolated private var isPlaybackSynthesisPending: Bool {
        workerLock.lock()
        defer { workerLock.unlock() }
        return pendingPlaybackSynthesisCountUnsafe > 0
    }

    /// 再生に必要な合成が終わるまで、先行合成は手を出さずに待つ。
    /// 待ち過ぎて先行合成が完全に止まらないよう、待つ時間には上限を設ける。
    nonisolated private func waitWhilePlaybackSynthesisIsPending() async {
        let maxWaitCount = 60
        for _ in 0..<maxWaitCount {
            if isPlaybackSynthesisPending == false { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private init() {
        synthesisQueueStorage = VoicevoxSynthesisQueue(capacity: Self.maxPendingPrefetchCount) { [unowned self] text, styleId in
            return self.peekCache(key: Self.prefetchKey(text: text, styleId: styleId)) != nil
        }
    }

    var isSetUp: Bool {
        return synthesizer != nil
    }

    // voicevox_onnxruntime.xcframework の対応OSがiOS 16以降のため、それ未満では機能自体を無効化する。
    static var isAvailableOnThisOS: Bool {
        if #available(iOS 16.0, *) { return true }
        return false
    }

    /// アプリに同梱されている辞書/VVMからの起動時セットアップ。
    /// 同梱リソースが見つからない場合は何もしない(iOS 16未満や、まだVVMを1つも
    /// 用意していない環境でも安全に呼べる)。
    static func setUpFromBundleIfNeeded() async {
        guard isAvailableOnThisOS else { return }
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else { return }
        guard let vvmPath = Bundle.main.path(forResource: "0", ofType: "vvm") else { return }
        let vvmDirectory = (vvmPath as NSString).deletingLastPathComponent
        do {
            try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelDirectoryPaths: [vvmDirectory])
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxCore.setUpFromBundleIfNeeded failed: \(error.localizedDescription)", appendix: [:], isForDebug: true)
        }
    }

    /// 起動時(または初回VOICEVOX利用時)に一度だけ呼ぶ。
    /// - Parameters:
    ///   - dictDirectoryPath: Open JTalk 辞書ディレクトリへのパス(ファイルではなくディレクトリ)
    ///   - voiceModelDirectoryPaths: *.vvm を探索するディレクトリの一覧(バンドル同梱分 + 将来のダウンロード先)
    func setUp(dictDirectoryPath: String, voiceModelDirectoryPaths: [String]) throws {
        if synthesizer == nil {
            var ort: OpaquePointer?
            let ortResult = voicevox_onnxruntime_init_once(&ort)
            guard ortResult == VOICEVOX_RESULT_OK, let ortNotNil = ort else {
                throw VoicevoxCoreError.core(ortResult)
            }
            onnxruntime = ortNotNil

            var openJTalkPointer: OpaquePointer?
            let jtalkResult = dictDirectoryPath.withCString { cString in
                voicevox_open_jtalk_rc_new(cString, &openJTalkPointer)
            }
            guard jtalkResult == VOICEVOX_RESULT_OK, let jtalkNotNil = openJTalkPointer else {
                throw VoicevoxCoreError.core(jtalkResult)
            }
            openJTalk = jtalkNotNil

            try createSynthesizer(onnxruntime: ortNotNil, openJTalk: jtalkNotNil)
        }

        try reloadStyleCatalog(voiceModelDirectoryPaths: voiceModelDirectoryPaths)
    }

    /// 現在の設定値(cpu_num_threads)で synthesizer を作る。
    private func createSynthesizer(onnxruntime: OpaquePointer, openJTalk: OpaquePointer) throws {
        var options = voicevox_make_default_initialize_options()
        options.acceleration_mode = VOICEVOX_ACCELERATION_MODE_CPU
        // 0 = 環境に合わせて自動(= 全コアを使う)。
        // 自動のままだと ONNX が全コアでスレッドを回し、実機ログで CPU 率が 200〜290% まで
        // 上がる事を確認している。バックグラウンドの CPU 上限(60秒平均80%)超過による
        // 強制終了を避けられるかを実測するため、ここを可変にしている。
        options.cpu_num_threads = Self.configuredCPUNumThreads

        var synth: OpaquePointer?
        let synthResult = voicevox_synthesizer_new(onnxruntime, openJTalk, options, &synth)
        guard synthResult == VOICEVOX_RESULT_OK, let synthNotNil = synth else {
            throw VoicevoxCoreError.core(synthResult)
        }
        synthesizer = synthNotNil
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [synthesizer生成] cpu_num_threads=\(Self.configuredCPUNumThreads)")
    }

    /// cpu_num_threads を変更して synthesizer を作り直す。
    /// スレッド数は synthesizer の生成時オプションなので、変更には作り直しが必要。
    /// 比較計測を公平にするため、合成済みキャッシュと性能集計もリセットする。
    func reconfigureCPUNumThreads(_ threads: UInt16) throws {
        Self.configuredCPUNumThreads = threads
        cancelPendingPrefetch()
        clearCache()
        guard let ort = onnxruntime, let jtalk = openJTalk else {
            // まだ setUp されていない場合は、設定だけ保存しておけば次の setUp で反映される。
            return
        }
        if let existing = synthesizer {
            voicevox_synthesizer_delete(existing)
            synthesizer = nil
        }
        // 音声モデルは synthesizer に紐づいてロードされているので、読み直しが必要。
        loadedVvmPaths.removeAll()
        try createSynthesizer(onnxruntime: ort, openJTalk: jtalk)
        VoicevoxPerformanceMonitor.shared.resetForTesting()
        // スレッド数が変わると文字数あたりの CPU 秒も変わるので、見積りも作り直す。
        cpuGovernor.reset()
    }

    /// 指定ディレクトリ群にある *.vvm を全部 open→メタ取得→close して話者カタログを作り直す。
    /// (open だけならロードと違って軽い。VOICEVOX_IOS_INTEGRATION.md §3-4)
    func reloadStyleCatalog(voiceModelDirectoryPaths: [String]) throws {
        var newStyles: [VoicevoxStyle] = []
        let fileManager = FileManager.default
        for directoryPath in voiceModelDirectoryPaths {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directoryPath) else { continue }
            for entry in entries where entry.hasSuffix(".vvm") {
                let vvmPath = (directoryPath as NSString).appendingPathComponent(entry)
                newStyles.append(contentsOf: try stylesFrom(vvmPath: vvmPath))
            }
        }
        styles = newStyles
        VoicevoxCore.cachedStyles = newStyles
    }

    private func stylesFrom(vvmPath: String) throws -> [VoicevoxStyle] {
        var modelPointer: OpaquePointer?
        let openResult = vvmPath.withCString { cString in
            voicevox_voice_model_file_open(cString, &modelPointer)
        }
        guard openResult == VOICEVOX_RESULT_OK, let model = modelPointer else {
            throw VoicevoxCoreError.core(openResult)
        }
        defer { voicevox_voice_model_file_delete(model) }

        guard let jsonCString = voicevox_voice_model_file_create_metas_json(model) else {
            return []
        }
        defer { voicevox_json_free(jsonCString) }
        let jsonString = String(cString: jsonCString)
        return Self.parseMetasJson(jsonString, vvmPath: vvmPath)
    }

    private static func parseMetasJson(_ jsonString: String, vvmPath: String) -> [VoicevoxStyle] {
        struct MetaStyle: Decodable { let name: String; let id: UInt32 }
        struct Meta: Decodable { let name: String; let styles: [MetaStyle]; let speaker_uuid: String }
        guard let data = jsonString.data(using: .utf8),
              let metas = try? JSONDecoder().decode([Meta].self, from: data) else {
            return []
        }
        return metas.flatMap { meta in
            meta.styles.map { style in
                VoicevoxStyle(name: style.name, styleId: style.id, speakerName: meta.name, speakerUUID: meta.speaker_uuid, vvmPath: vvmPath)
            }
        }
    }

    private func ensureVoiceModelLoaded(styleId: UInt32) throws {
        guard let synthesizer = synthesizer else { throw VoicevoxCoreError.notSetUp }
        guard let style = styles.first(where: { $0.styleId == styleId }) else {
            throw VoicevoxCoreError.styleNotFound(styleId)
        }
        if loadedVvmPaths.contains(style.vvmPath) { return }

        var modelPointer: OpaquePointer?
        let openResult = style.vvmPath.withCString { cString in
            voicevox_voice_model_file_open(cString, &modelPointer)
        }
        guard openResult == VOICEVOX_RESULT_OK, let model = modelPointer else {
            throw VoicevoxCoreError.core(openResult)
        }
        // ロードしてしまえば VoicevoxVoiceModelFile 自体は閉じてよい(VOICEVOX_IOS_INTEGRATION.md §2)
        defer { voicevox_voice_model_file_delete(model) }

        let loadResult = voicevox_synthesizer_load_voice_model(synthesizer, model)
        guard loadResult == VOICEVOX_RESULT_OK else {
            throw VoicevoxCoreError.core(loadResult)
        }
        loadedVvmPaths.insert(style.vvmPath)
    }

    /// ONNX に渡す CPU スレッド数(0 = 自動 = 全コア)。
    /// バックグラウンドの CPU 上限超過による強制終了を避けられるかの実測用に可変にしている。
    /// synthesizer 生成時オプションなので、変更を反映するには reconfigureCPUNumThreads() を使う。
    static let cpuNumThreadsUserDefaultsKey = "NovelSpeaker.Voicevox.cpuNumThreads"
    /// 未設定時の既定値。
    ///
    /// 0(自動=全コア)にすると ONNX が全コアでスレッドを回し、実機で CPU 率が
    /// 200〜290% に達する。背面のCPU上限は「1コア相当の80%」なので、これは即座に
    /// 強制終了される値になる。実測ではスレッド数1が CPU 率・RTF の両方で最良で、
    /// スレッドを増やすと発熱で RTF まで悪化した。よって既定は1にする。
    /// (前景・充電中は上限が無いので全コア使う方が速いが、設定は synthesizer の
    ///  生成時オプションで途中変更には作り直しが要るため、安全側に倒して固定する)
    static let defaultCPUNumThreads: UInt16 = 1

    static var configuredCPUNumThreads: UInt16 {
        get {
            guard let stored = UserDefaults.standard.object(forKey: cpuNumThreadsUserDefaultsKey) as? Int else {
                return defaultCPUNumThreads
            }
            return UInt16(clamping: stored)
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: cpuNumThreadsUserDefaultsKey)
        }
    }

    /// 話者設定の voiceIdentifier から VOICEVOX の styleId を求める。
    ///
    /// 再生側(MultiVoiceSpeaker)は数値に変換できない場合 0 にフォールバックするのに対し、
    /// 先行合成側は「変換できないブロックを読み飛ばす」という非対称な実装になっており、
    /// 実機で以下の不具合を起こしていた:
    ///   - type=="VOICEVOX" なのに voiceIdentifier が AVSpeech の音声ID
    ///     (例: com.apple.ttsbundle.siri_O-ren_ja-JP_premium)のままになっている話者設定だと、
    ///     再生側は styleId=0 で合成する一方、先行合成側はそのブロックを一切合成しない。
    ///   - その結果、地の文のブロックが必ずキャッシュMISSになり(実機で MISS内訳=未予約14/16)、
    ///     再生の度にその場で合成して10秒以上の無音になる。
    ///   - さらに「未再生の貯金」の計算でも同じ理由で読み飛ばしていたため、
    ///     実際には合成されていないのに貯金が十分あるように見えていた。
    /// キャッシュのキーは (styleId, text) なので、両者の解釈が一致しない限り
    /// 先行合成は永久に無駄撃ちになる。必ずここを通す事。
    static func styleId(fromVoiceIdentifier voiceIdentifier: String?) -> UInt32 {
        return UInt32(voiceIdentifier ?? "") ?? 0
    }

    private static func prefetchKey(text: String, styleId: UInt32) -> String {
        return "\(styleId)::\(text)"
    }

    /// 実際にC APIを叩いてテキストをWAV(24kHz/mono/16bit, ヘッダ付き)のバイト列に合成する。
    /// キャッシュは見ない・作らない、素の合成のみ。
    private func performSynthesize(text: String, styleId: UInt32) throws -> Data {
        guard let synthesizer = synthesizer else { throw VoicevoxCoreError.notSetUp }
        try ensureVoiceModelLoaded(styleId: styleId)

        var outputWavLength: UInt = 0
        var outputWav: UnsafeMutablePointer<UInt8>?
        let options = voicevox_make_default_tts_options()
        // 実性能(RTF)計測のため、実際の合成呼び出しの前後で CPU 時間と実時間を挟む。
        // ここは先行合成・その場合成の両方が通る唯一の絞り点なので、計測点として適切。
        let cpuBefore = ProcessCPUClock.totalCPUSeconds()
        let wallBefore = Date()
        let result = text.withCString { cString in
            voicevox_synthesizer_tts(synthesizer, cString, styleId, options, &outputWavLength, &outputWav)
        }
        let wallSeconds = Date().timeIntervalSince(wallBefore)
        let cpuSeconds: Double?
        if let cpuBefore = cpuBefore, let cpuAfter = ProcessCPUClock.totalCPUSeconds() {
            cpuSeconds = cpuAfter - cpuBefore
        } else {
            cpuSeconds = nil
        }
        guard result == VOICEVOX_RESULT_OK, let wav = outputWav else {
            throw VoicevoxCoreError.core(result)
        }
        // 受け取ったら即コピーしてから解放する(VOICEVOX_IOS_INTEGRATION.md §3-3: 解放忘れのリーク対策)
        let data = Data(bytes: wav, count: Int(outputWavLength))
        voicevox_wav_free(wav)
        guard data.count > 44, data.prefix(4).elementsEqual("RIFF".utf8) else {
            throw VoicevoxCoreError.invalidWav
        }
        if let cpuSeconds = cpuSeconds {
            VoicevoxPerformanceMonitor.shared.recordSynthesis(wavByteCount: data.count, cpuSeconds: cpuSeconds, wallSeconds: wallSeconds, styleId: styleId)
            // 次回以降の見積り材料。同じ文字数でも端末と発熱状態で数倍違うので、実測が要る。
            cpuGovernor.recordSynthesis(cpuSeconds: cpuSeconds, characterCount: text.count, at: ProcessInfo.processInfo.systemUptime)
        }
        return data
    }

    /// ログ用: 現在キャッシュ(先行合成済み)として持っている音声の合計秒数。
    /// 「あとどれだけ貯金があるか」を実機ログで見るために使う。
    nonisolated func cachedAudioSecondsForLogging() -> Double {
        return wavCache.totalAudioSeconds()
    }

    // ログ用に先頭数文字だけ見えるようにする(全文は長すぎて読みにくいため)。
    private static func logSnippet(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\n", with: "\\n")
        if escaped.count > 20 { return String(escaped.prefix(20)) + "…(\(text.count)文字)" }
        return escaped
    }

    /// テキストをVOICEVOXで合成し、WAV(24kHz/mono/16bit, ヘッダ付き)のバイト列を返す。
    /// 先行合成済み(prefetch済み)であればそれをそのまま使い、無ければその場で合成する。
    /// 再生直前にキャッシュがヒットしたかどうかは「合成待ちで無音になる」不具合の切り分けに
    /// 重要なため、実機ログで後から追えるように状態ごとにログを残す。
    ///
    /// あえて nonisolated にしている: キャッシュ済み(cache HIT)の場合は actor に
    /// 一切入らずロックだけで完結させる事で、actor が他の(無関係で低優先度な)先行合成を
    /// 実行中でも待たされずに即座に返せるようにする(実機ログで、既に合成済みのはずの
    /// 短い会話文が、遠く先の長い段落の先行合成が終わるまでHIT扱いにすらならず
    /// 数秒待たされる、という現象を確認したため)。cache MISS の場合のみ actor 隔離の
    /// 低速パスに委譲する。
    nonisolated func synthesize(text: String, styleId: UInt32) async throws -> Data {
        let key = Self.prefetchKey(text: text, styleId: styleId)
        if let cached = peekCache(key: key) {
            // 再生に使い終わった事を記録する。キャッシュが上限に達した時、
            // これが付いている物から先に捨てる(付いていない=まだ再生していない物を
            // 捨てると、用意できていたのに再生直前で消える事になる)。
            wavCache.markPlayed(key: key)
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [キャッシュHIT] styleId=\(styleId) text=\"\(Self.logSnippet(text))\"")
            VoicevoxPerformanceMonitor.shared.recordPlaybackSynthesisRequest(wasCacheHit: true, waitSeconds: 0)
            VoicevoxPerformanceMonitor.shared.recordEvent("再生HIT style=\(styleId) \"\(Self.logSnippet(text))\"")
            return cached
        }
        // ここに来た = 再生が必要な時点で先行合成が間に合っていなかった。
        // その待ち時間がそのまま無音の長さになるので、回数と待ち時間を記録する。
        let missStart = Date()
        let data = try await synthesizeSlowPath(text: text, styleId: styleId, key: key)
        VoicevoxPerformanceMonitor.shared.recordPlaybackSynthesisRequest(wasCacheHit: false, waitSeconds: Date().timeIntervalSince(missStart))
        return data
    }

    /// cache MISS 時の低速パス。pendingPrefetchTasks の確認・performSynthesize の呼び出しは
    /// actor状態を扱うため、ここは(nonisolatedにせず)actor隔離のままにしておく。
    private func synthesizeSlowPath(text: String, styleId: UInt32, key: String) async throws -> Data {
        // 先行合成に予算を横取りされないよう、再生側の合成が進行中である事を知らせる。
        beginPlaybackSynthesis()
        defer { endPlaybackSynthesis() }
        let snippet = Self.logSnippet(text)
        // 待機中の予約は取り消して(横取りして)この場で合成する。ワーカーが後から
        // 同じ物を重ねて合成しないようにするため。
        // 既に合成中(このメソッドが actor に入れた時点で、そのC呼び出しは完了している)
        // だった場合は、下のキャッシュ再確認で拾える。
        // MISS の原因を判別するための記録。
        //  - 予約済み(pending)   … 先行合成に出してはいたが間に合わなかった = 時間の問題。
        //                          先読みの深さ/優先度で対処する。
        //  - 未予約(not queued) … そもそも先行合成の対象から漏れていた = 取りこぼしの不具合。
        // 実機で「貯金は156秒あるのに再生時HIT率は48.9%」という食い違いが出ており、
        // どちらなのかで対処が全く変わるため、ここで確定させる。
        let claim = synthesisQueue.claimForImmediateSynthesis(text: text, styleId: styleId)
        let wasQueued = claim != .notQueued
        VoicevoxPerformanceMonitor.shared.recordPlaybackCacheMiss(wasQueuedForPrefetch: wasQueued)
        VoicevoxPerformanceMonitor.shared.recordEvent("再生MISS(\(wasQueued ? "予約済" : "未予約")) style=\(styleId) \"\(snippet)\"")
        if claim == .inFlight {
            // ワーカーが今まさに同じ物を合成している。ここで自分でも合成すると
            // 同じ物を二重に合成して CPU 予算を食い合い、どちらも進まなくなる
            // (実機で同じブロックの「分割合成」が二重に走り、1ブロックに4分以上かかっていた)。
            // 完成を待つ方が速い。
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [MISS:先行合成が実行中→その完成を待つ] styleId=\(styleId) text=\"\(snippet)\"")
            VoicevoxPerformanceMonitor.shared.recordEvent("先行合成の完成待ち style=\(styleId) \"\(snippet)\"")
            if let data = await waitForInFlightSynthesis(key: key) {
                return data
            }
        }
        if wasQueued {
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [MISS:予約済みだが未完了→追い越して合成] styleId=\(styleId) text=\"\(snippet)\"")
        } else {
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [MISS:先行合成に未予約] styleId=\(styleId) text=\"\(snippet)\"")
        }
        // 待っている間に先行合成が完了していた可能性があるので、合成前にもう一度確認する。
        if let cached = peekCache(key: key) {
            return cached
        }
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [キャッシュMISS・その場合成開始] styleId=\(styleId) text=\"\(snippet)\"")
        let synthStart = Date()
        // 再生に必要な合成でも、CPU予算を超えたまま突入すると強制終了される
        // (殺されると再生そのものが止まるので、無音より重い)。先行合成より多くの
        // 予算を使ってよいが、上限は守る。
        let data = try await performSynthesizeWithinBudget(text: text, styleId: styleId, limitRatio: Self.playbackCPULimitRatio)
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [その場合成完了 \(String(format: "%.2f", Date().timeIntervalSince(synthStart)))秒] styleId=\(styleId) text=\"\(snippet)\"")
        return data
    }

    /// 待機中の先行合成として溜めておける本数。
    ///
    /// 積み過ぎると、手前のブロックが後ろのバックログに埋もれて完了までの時間が伸びる。
    /// 実機では一度に30件以上が積まれ、予約から完了まで218秒かかる状態になっていた
    /// (その間ずっと「未再生の貯金=0秒」で無音)。積むより先に手前から順に
    /// 完成させる方が、再生には遥かに有利。
    private static let maxPendingPrefetchCount = 4

    /// 現在再生中のブロック位置を待ち行列に伝える。
    /// これより手前の(追い越された)予約は捨てられ、次に合成すべき対象が入れ替わる。
    /// actor へ入らないので、合成中でも即座に反映される。
    nonisolated func notePlaybackBlockIndex(_ index: Int) {
        synthesisQueue.setPlaybackIndex(index)
    }

    /// 現在再生中のブロックより先のブロックを、実際に必要になる前に合成しておく。
    /// blockIndex が小さい(=再生順で手前の)ものほど優先して合成される。
    /// 二重予約(既にキャッシュ済み/予約済み/合成中)は無視するので、何度呼んでも安全。
    /// 失敗しても黙って諦める(実際に必要になった時に synthesize() がその場で合成し直す)。
    ///
    /// あえて nonisolated: 「予約を積む」だけの帳簿処理が、実行中の合成(1本12秒前後の
    /// 同期的なC呼び出し)の完了待ちに巻き込まれないようにするため。以前は actor 隔離の
    /// prefetch() だったせいで、予約が登録されるまで実機で19秒かかっていた。
    /// - Returns: 実際に予約が積まれたら true(既にキャッシュ済み/予約済み/上限で弾かれたら false)。
    @discardableResult
    nonisolated func schedulePrefetch(blockIndex: Int, text: String, styleId: UInt32) -> Bool {
        guard synthesisQueue.enqueue(blockIndex: blockIndex, text: text, styleId: styleId) else { return false }
        let snippet = Self.logSnippet(text)
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成予約] block=\(blockIndex) styleId=\(styleId) text=\"\(snippet)\"")
        VoicevoxPerformanceMonitor.shared.recordEvent("先読み予約 block=\(blockIndex) style=\(styleId) \"\(snippet)\"")
        startWorkerIfNeeded()
        return true
    }

    /// 待ち行列から1件ずつ取り出して合成し続けるワーカーを、走っていなければ起動する。
    /// 同時に走るのは常に1本(voicevox のC呼び出しは actor で直列化されるため、
    /// 複数走らせても速くならず、CPU上限に近づくだけ)。
    nonisolated private func startWorkerIfNeeded() {
        workerLock.lock()
        if isWorkerRunningUnsafe {
            workerLock.unlock()
            return
        }
        isWorkerRunningUnsafe = true
        workerLock.unlock()

        Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            while let request = self.synthesisQueue.takeNext() {
                // 再生に必要な合成が待っている間は、先行合成は予算に手を出さない。
                await self.waitWhilePlaybackSynthesisIsPending()
                await self.runSynthesis(request)
            }
            self.workerLock.lock()
            self.isWorkerRunningUnsafe = false
            self.workerLock.unlock()
            // 終了を決めた直後に積まれた分を取り零さないよう、もう一度だけ確認する。
            if self.synthesisQueue.pendingCount > 0 {
                self.startWorkerIfNeeded()
            }
        }
    }

    /// 先行合成のワーカーが実行中の合成の完成を待つ。
    /// `await` の間 actor は空くので、ワーカー側の合成はその間に進む。
    /// - Returns: 完成した音声。時間内に完成しなければ nil(呼び出し側が自分で合成する)。
    private func waitForInFlightSynthesis(key: String) async -> Data? {
        let deadline = Date().addingTimeInterval(Self.inFlightWaitTimeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let cached = peekCache(key: key) { return cached }
            // ワーカーが失敗・キャンセル等で降りた場合は待っても無駄なので抜ける。
            if synthesisQueue.isInFlight(key: key) == false { return peekCache(key: key) }
        }
        return nil
    }
    /// 先行合成の完成を待つ上限。分割合成だと1ブロックに数分かかる事があるので長めに取る。
    private static let inFlightWaitTimeoutSeconds = 300.0

    /// CPU予算を守りながら1ブロックぶんを合成する。
    ///
    /// 1本の合成が予算に収まらない場合(実測: iPhone SE2 では100文字級で既に超える)は、
    /// 句読点で分割して順に合成し、出来た音声を繋いで1本として返す。
    /// 分割すると繋ぎ目に気になる「間」ができるため、収まる場合は決して分割しない
    /// (速い端末や前景・充電中では分割は起きない)。
    ///
    /// `await Task.sleep` で待つ間 actor は空くので、再生側の要求はその間も処理できる。
    private func performSynthesizeWithinBudget(text: String, styleId: UInt32, limitRatio: Double) async throws -> Data {
        let texts = chunkedTextsForBudget(text: text, limitRatio: limitRatio)
        if texts.count > 1 {
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [CPU予算のため\(texts.count)分割して合成] styleId=\(styleId) text=\"\(Self.logSnippet(text))\"")
            VoicevoxPerformanceMonitor.shared.recordEvent("分割合成 \(texts.count)個 style=\(styleId) \"\(Self.logSnippet(text))\"")
        }
        var wavs: [Data] = []
        for chunk in texts {
            await waitForCPUBudget(text: chunk, styleId: styleId, limitRatio: limitRatio)
            wavs.append(try performSynthesize(text: chunk, styleId: styleId))
        }
        guard let joined = VoicevoxWavJoiner.join(wavs: wavs) else {
            throw VoicevoxCoreError.invalidWav
        }
        return joined
    }

    /// CPU予算に収まらない場合にだけ、句読点で分割したテキストを返す(収まるなら1つのまま)。
    nonisolated private func chunkedTextsForBudget(text: String, limitRatio: Double) -> [String] {
        // 背面CPU上限が適用されない状況(前景/充電中)では分割しない。音質を優先する。
        guard VoicevoxPrefetchThrottleMonitor.shared.isCPULimitApplied else { return [text] }
        let maxCharacterCount = cpuGovernor.maxCharacterCount(withinCPUSeconds: Self.cpuWindowSeconds * limitRatio)
        if text.count <= maxCharacterCount { return [text] }
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: maxCharacterCount)
        return chunks.isEmpty ? [text] : chunks
    }

    /// CPU予算に空きができるまで待つ。
    private func waitForCPUBudget(text: String, styleId: UInt32, limitRatio: Double) async {
        // 待っている間 actor は空くので、その隙に別の合成(再生側の要求等)が走って
        // 予算を使っている事がある。起きた後にもう一度確かめる。
        // ただし待ち続けて再生が完全に止まる方が困るので、確認は1回だけにする
        // (実機で 60秒待機が3回続き、1ブロックに3分以上かかる事があった)。
        let maxWaitCount = 2
        for _ in 0..<maxWaitCount {
            let waitSeconds = governorWaitSeconds(text: text, limitRatio: limitRatio)
            if waitSeconds <= 0 { return }
            // 分割してもなお1本で予算を超える(句読点が全く無い等)場合は、窓が空くまで待った上で
            // 実行する。その1本だけで窓を使い切る形になり、上限超過の確率が最も小さくなる。
            let sleepSeconds = min(waitSeconds.isInfinite ? Self.cpuWindowSeconds : waitSeconds, Self.cpuWindowSeconds)
            let snippet = Self.logSnippet(text)
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [CPU予算のため待機 \(String(format: "%.1f", sleepSeconds))秒] styleId=\(styleId) text=\"\(snippet)\"")
            VoicevoxPerformanceMonitor.shared.recordEvent("合成待機 \(String(format: "%.1f", sleepSeconds))秒(CPU予算) style=\(styleId) \"\(snippet)\"")
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        }
    }

    /// 待ち行列から取り出した1件を実際に合成する(ここだけが actor 隔離 = 直列実行)。
    private func runSynthesis(_ request: VoicevoxSynthesisQueue.Request) async {
        let snippet = Self.logSnippet(request.text)
        // 順番待ちの間に読み上げが停止/シークされていたら、重いC呼び出しには入らず捨てる。
        // これをしないと、停止後も延々と(実機で16分=983秒の先行合成完了ログを確認)
        // 合成され続け、CPU/電池を浪費してしまう。
        if synthesisQueue.isStale(request) {
            VoicevoxPerformanceMonitor.shared.recordEvent("先読みキャンセル style=\(request.styleId) \"\(snippet)\"")
            synthesisQueue.complete(request)
            return
        }
        let startedAt = Date()
        do {
            let data = try await performSynthesizeWithinBudget(text: request.text, styleId: request.styleId, limitRatio: Self.prefetchCPULimitRatio)
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成完了 \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))秒] styleId=\(request.styleId) text=\"\(snippet)\"")
            VoicevoxPerformanceMonitor.shared.recordEvent("先読み完了 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))秒 style=\(request.styleId) \"\(snippet)\"")
            storeCache(key: Self.prefetchKey(text: request.text, styleId: request.styleId), data: data)
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxCore: prefetch failed: \(error.localizedDescription)", appendix: [
                "text": request.text,
                "styleId": "\(request.styleId)",
            ], isForDebug: true)
            VoicevoxPerformanceMonitor.shared.recordEvent("先読み失敗 style=\(request.styleId) \"\(snippet)\" \(error.localizedDescription)")
        }
        synthesisQueue.complete(request)
    }

    /// 待機中の先行合成を全て破棄する。
    /// 完成済みのキャッシュ(prefetchedWav)は残すので、停止→同じ位置から再開した時に
    /// 直近の先読み結果は再利用できる。読み上げ停止時に呼ぶ想定。
    /// (実際に走っているC呼び出し1本はプリエンプトできないが、その1本が終われば
    ///  後続は isStale 判定で即抜けるので、バックログは速やかに解消される)
    nonisolated func cancelPendingPrefetch() {
        synthesisQueue.cancelAll()
    }

    /// 先行合成キャッシュを全て破棄し、待機中の先行合成もキャンセルする
    /// (新しい本文の読み込み・シーク等でこれまでの先読み内容が無意味になった時に呼ぶ)。
    nonisolated func clearPrefetchCache() {
        cancelPendingPrefetch()
        clearCache()
    }

    // 旧APIの名残。呼び出し側は actor の外から直接呼べるようになったので、
    // Task で包む必要はもう無い(名前だけ残して移行の差分を小さくしている)。
    nonisolated func schedulePrefetchCacheClear() {
        clearPrefetchCache()
    }

    nonisolated func scheduleCancelPendingPrefetch() {
        cancelPendingPrefetch()
    }

    /// デバッグ用: キャッシュも CPU 予算も通さずに合成する。
    /// 「一度に合成したもの」と「分割して繋いだもの」を聞き比べるための入り口。
    /// - Parameters:
    ///   - splitCharacterCount: nil なら分割せずに1本で合成する。値があればその長さで分割して繋ぐ。
    ///   - trimJoinSilence: 分割位置の無音を削るかどうか。
    func debugSynthesize(text: String, styleId: UInt32, splitCharacterCount: Int?, trimJoinSilence: Bool) throws -> Data {
        guard let splitCharacterCount = splitCharacterCount else {
            return try performSynthesize(text: text, styleId: styleId)
        }
        let chunks = VoicevoxTextChunker.split(text: text, maxCharacterCount: splitCharacterCount, minimumCharacterCount: 1)
        var wavs: [Data] = []
        for chunk in chunks {
            wavs.append(try performSynthesize(text: chunk, styleId: styleId))
        }
        guard let joined = VoicevoxWavJoiner.join(wavs: wavs, trimJoinSilence: trimJoinSilence) else {
            throw VoicevoxCoreError.invalidWav
        }
        return joined
    }

    // テスト専用: 指定テキストが先行合成キャッシュに乗っているかどうか(進行中/未着手は含まない)。
    nonisolated func isPrefetchedForTesting(text: String, styleId: UInt32) -> Bool {
        return peekCache(key: Self.prefetchKey(text: text, styleId: styleId)) != nil
    }
}

#else // targetEnvironment(macCatalyst) || os(watchOS)

// Mac Catalyst / watchOS 用スタブ。実装本体と同じ公開サーフェスを提供しつつ、
// isAvailableOnThisOS = false によって VOICEVOX 機能全体を「常に利用不可」にする。
// これにより VoicevoxSpeaker / SpeechBlockSpeaker / SpeakerSettingsViewController 等の
// 呼び出し側は #if を書かずにそのままコンパイルできる。

enum VoicevoxCoreError: LocalizedError {
    case notSetUp
    case styleNotFound(UInt32)
    case invalidWav

    var errorDescription: String? {
        switch self {
        case .notSetUp:
            return "VOICEVOXはMac Catalystでは利用できません"
        case .styleNotFound(let styleId):
            return "指定されたVOICEVOXスタイル(\(styleId))に対応する音声モデルが見つかりません"
        case .invalidWav:
            return "VOICEVOXの合成結果が不正なWAVデータでした"
        }
    }
}

final class VoicevoxCore {
    static let shared = VoicevoxCore()
    static var cachedStyles: [VoicevoxStyle] = []
    static var isAvailableOnThisOS: Bool { return false }

    private init() {}

    var isSetUp: Bool { return false }

    static func logTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    static func setUpFromBundleIfNeeded() async {}

    func synthesize(text: String, styleId: UInt32) async throws -> Data {
        throw VoicevoxCoreError.notSetUp
    }

    @discardableResult
    func schedulePrefetch(blockIndex: Int, text: String, styleId: UInt32) -> Bool { return false }
    func notePlaybackBlockIndex(_ index: Int) {}
    func schedulePrefetchCacheClear() {}
    func scheduleCancelPendingPrefetch() {}

    func isPrefetchedForTesting(text: String, styleId: UInt32) -> Bool { return false }

    func debugSynthesize(text: String, styleId: UInt32, splitCharacterCount: Int?, trimJoinSilence: Bool) throws -> Data {
        throw VoicevoxCoreError.notSetUp
    }

    /// ログ用(スタブ側は合成しないので常に 0)。
    func cachedAudioSecondsForLogging() -> Double { return 0 }
    func cachedWavByteCount(text: String, styleId: UInt32) -> Int? { return nil }

    /// 実装側と同じ導出(再生側と先行合成側で解釈が食い違わないようにするため)。
    static func styleId(fromVoiceIdentifier voiceIdentifier: String?) -> UInt32 {
        return UInt32(voiceIdentifier ?? "") ?? 0
    }

    static let cpuNumThreadsUserDefaultsKey = "NovelSpeaker.Voicevox.cpuNumThreads"
    static let defaultCPUNumThreads: UInt16 = 1
    static var configuredCPUNumThreads: UInt16 {
        get {
            guard let stored = UserDefaults.standard.object(forKey: cpuNumThreadsUserDefaultsKey) as? Int else {
                return defaultCPUNumThreads
            }
            return UInt16(clamping: stored)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: cpuNumThreadsUserDefaultsKey) }
    }
    func reconfigureCPUNumThreads(_ threads: UInt16) throws {
        Self.configuredCPUNumThreads = threads
    }
}

#endif
