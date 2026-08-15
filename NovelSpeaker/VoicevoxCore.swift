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
    private let cacheLock = NSLock()
    nonisolated(unsafe) private var prefetchedWavUnsafe: [String: Data] = [:]
    // 際限なく貯め込み続けないよう、挿入順で古いものから追い出す上限を設ける
    // (会話文の相槌等の短い文字列が主な再利用対象なので、これだけあれば十分実用になる)。
    private let prefetchedWavCapacity = 64
    // WAVは 24kHz/mono/16bit なので1秒あたり約48KB、長いブロックだと1本で数MBになる。
    // エントリ数だけの上限だと最悪数十〜100MB級まで太り得るため、合計バイト数でも制限する
    // (超えたら古い物から追い出す。読み上げ済みの過去のWAVを持ち続けるよりも、
    //  直近の使い回し(会話文の相槌等)が効けば十分)。
    private let prefetchedWavTotalByteLimit = 16 * 1024 * 1024
    nonisolated(unsafe) private var prefetchedWavOrderUnsafe: [String] = []
    nonisolated(unsafe) private var prefetchedWavTotalBytesUnsafe = 0

    // actorへ入らずに(=今actorが何をしていても待たされずに)呼べるよう、あえて nonisolated。
    nonisolated private func peekCache(key: String) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return prefetchedWavUnsafe[key]
    }

    nonisolated private func storeCache(key: String, data: Data) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let oldData = prefetchedWavUnsafe[key] {
            prefetchedWavTotalBytesUnsafe -= oldData.count
        } else {
            prefetchedWavOrderUnsafe.append(key)
        }
        prefetchedWavUnsafe[key] = data
        prefetchedWavTotalBytesUnsafe += data.count
        while prefetchedWavOrderUnsafe.count > prefetchedWavCapacity
            || (prefetchedWavTotalBytesUnsafe > prefetchedWavTotalByteLimit && prefetchedWavOrderUnsafe.count > 1) {
            let oldestKey = prefetchedWavOrderUnsafe.removeFirst()
            if let removed = prefetchedWavUnsafe.removeValue(forKey: oldestKey) {
                prefetchedWavTotalBytesUnsafe -= removed.count
            }
        }
    }

    /// 指定テキストが先行合成済みなら、その WAV のバイト数を返す(未合成なら nil)。
    /// 「未再生の貯金が何秒あるか」を数えるために使う。actorへ入らず参照できる。
    nonisolated func cachedWavByteCount(text: String, styleId: UInt32) -> Int? {
        return peekCache(key: Self.prefetchKey(text: text, styleId: styleId))?.count
    }

    nonisolated private func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        prefetchedWavUnsafe.removeAll()
        prefetchedWavOrderUnsafe.removeAll()
        prefetchedWavTotalBytesUnsafe = 0
    }

    private var pendingPrefetchTasks: [String: Task<Void, Never>] = [:]
    // 先行合成タスクを投入順(=実際に必要になる順)通りに直列実行させるための鎖。
    // 単純に Task(priority: .utility) を並べて投げるだけだと、同一優先度のTaskがどの順で
    // actorに入るかはSwift concurrency のスケジューラ任せで、投入順が保証されない
    // (実機ログで、後から予約したはずの短いブロックより先に予約した別ブロックの方が
    //  何十秒も遅れて完了する、という順序の入れ替わりを確認した)。ここでは新しいタスクが
    // 「前のタスクの完了を待ってから」実際の合成に入るようにする事で、投入順=実行順を保証する。
    private var prefetchTailTask: Task<Void, Never>?

    private init() {}

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
    static var configuredCPUNumThreads: UInt16 {
        get {
            // 未設定(キー無し)なら従来どおり 0(自動)。
            return UInt16(clamping: UserDefaults.standard.integer(forKey: cpuNumThreadsUserDefaultsKey))
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: cpuNumThreadsUserDefaultsKey)
        }
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
        }
        return data
    }

    /// ログ用: 現在キャッシュ(先行合成済み)として持っている音声の合計秒数。
    /// 「あとどれだけ貯金があるか」を実機ログで見るために使う。
    nonisolated func cachedAudioSecondsForLogging() -> Double {
        cacheLock.lock()
        let bytes = prefetchedWavTotalBytesUnsafe
        let count = prefetchedWavUnsafe.count
        cacheLock.unlock()
        // 各エントリに WAV ヘッダ分が含まれるので、その分を差し引いてから秒数換算する。
        let payloadBytes = max(0, bytes - count * VoicevoxPerformanceMonitor.wavHeaderByteCount)
        return Double(payloadBytes) / (VoicevoxPerformanceMonitor.outputSampleRate * VoicevoxPerformanceMonitor.outputBytesPerFrame)
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
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [キャッシュHIT] styleId=\(styleId) text=\"\(Self.logSnippet(text))\"")
            VoicevoxPerformanceMonitor.shared.recordPlaybackSynthesisRequest(wasCacheHit: true, waitSeconds: 0)
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
        let snippet = Self.logSnippet(text)
        // 先行合成タスクの完了は「待たない」。
        //
        // 以前はここで await pendingTask.value していたが、先行合成タスクは実行順を保証する
        // ために直列の鎖(prefetchTailTask)になっており、鎖の途中のタスクを待つ事は
        // 「そのタスクより前に積まれた全ての先行合成の完了を待つ」事を意味していた。
        // 実機ではこれが再生時の平均15秒の待ち(= そのまま無音)になり、無音率74.8%の
        // 主因になっていた。再生は先行合成より優先されるべきなので、該当タスクを
        // キャンセルしてこの場で合成する。既に actor に入れている以上、実行中だった
        // 先行合成は完了済みなので、ここでの合成は待たされない。
        if let pendingTask = pendingPrefetchTasks[key] {
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成を追い越して合成] styleId=\(styleId) text=\"\(snippet)\"")
            pendingTask.cancel()
            pendingPrefetchTasks.removeValue(forKey: key)
        }
        // 待っている間に先行合成が完了していた可能性があるので、合成前にもう一度確認する。
        if let cached = peekCache(key: key) {
            return cached
        }
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [キャッシュMISS・その場合成開始] styleId=\(styleId) text=\"\(snippet)\"")
        let synthStart = Date()
        let data = try performSynthesize(text: text, styleId: styleId)
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [その場合成完了 \(String(format: "%.2f", Date().timeIntervalSince(synthStart)))秒] styleId=\(styleId) text=\"\(snippet)\"")
        return data
    }

    /// 現在再生中のブロックより先のブロックを、実際に必要になる前にバックグラウンドで合成しておく。
    /// 二重起動(既にキャッシュ済み/進行中)は無視するので、何度呼んでも安全。
    /// 失敗しても黙って諦める(実際に必要になった時に synthesize() がその場で合成し直す)。
    func prefetch(text: String, styleId: UInt32) {
        let key = Self.prefetchKey(text: text, styleId: styleId)
        if peekCache(key: key) != nil || pendingPrefetchTasks[key] != nil { return }
        let snippet = Self.logSnippet(text)
        NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成開始] styleId=\(styleId) text=\"\(snippet)\"")
        let scheduledAt = Date()
        // 前段のタスクを明示的に待ってから自分の合成に入る事で、投入順=実行順を保証する
        // (優先度は変わらず低めにして、synthesize()側からの割り込み・優先度エスカレーションの
        // 余地は残す)。
        let previousTail = prefetchTailTask
        let newTask = Task(priority: .utility) { [weak self] in
            await previousTail?.value
            guard let self = self else { return }
            // 読み上げ停止等でキャンセルされていたら、実際の合成(重いC呼び出し)には入らず即終了する。
            // これをしないと、長時間再生で本の残り全ブロックが先読みキューに積まれたまま、
            // 停止後も延々と(実機で16分=983秒の先行合成完了ログを確認)直列に合成され続け、
            // CPU/電池を浪費し、合成結果を保持してメモリも増え続けてしまう。
            if Task.isCancelled {
                await self.dropPendingPrefetch(key: key)
                return
            }
            do {
                let data = try await self.performSynthesize(text: text, styleId: styleId)
                NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成完了 \(String(format: "%.2f", Date().timeIntervalSince(scheduledAt)))秒] styleId=\(styleId) text=\"\(snippet)\"")
                await self.storePrefetched(key: key, data: data)
            } catch {
                AppInformationLogger.AddLog(message: "VoicevoxCore: prefetch failed: \(error.localizedDescription)", appendix: [
                    "text": text,
                    "styleId": "\(styleId)",
                ], isForDebug: true)
                await self.dropPendingPrefetch(key: key)
            }
        }
        pendingPrefetchTasks[key] = newTask
        prefetchTailTask = newTask
    }

    private func storePrefetched(key: String, data: Data) {
        pendingPrefetchTasks[key] = nil
        storeCache(key: key, data: data)
    }

    private func dropPendingPrefetch(key: String) {
        pendingPrefetchTasks[key] = nil
    }

    /// 未着手/進行中の先行合成タスク(バックログ)を全てキャンセルする。
    /// 完成済みのキャッシュ(prefetchedWav)は残すので、停止→同じ位置から再開した時に
    /// 直近の先読み結果は再利用できる。読み上げ停止時に呼ぶ想定。
    /// (実際に走っているC呼び出し1本はプリエンプトできないが、その1本が終われば
    ///  後続はキャンセル判定で即抜けるので、バックログは速やかに解消される)
    func cancelPendingPrefetch() {
        for task in pendingPrefetchTasks.values {
            task.cancel()
        }
        pendingPrefetchTasks.removeAll()
        prefetchTailTask?.cancel()
        prefetchTailTask = nil
    }

    /// 先行合成キャッシュを全て破棄し、進行中のバックログもキャンセルする
    /// (新しい本文の読み込み・シーク等でこれまでの先読み内容が無意味になった時に呼ぶ)。
    func clearPrefetchCache() {
        cancelPendingPrefetch()
        clearCache()
    }

    /// SpeechBlockSpeaker 等、actorの外(メインスレッド)から気軽に先行合成を蹴るための入り口。
    nonisolated func schedulePrefetch(text: String, styleId: UInt32) {
        Task { await self.prefetch(text: text, styleId: styleId) }
    }

    /// SpeechBlockSpeaker 等、actorの外から気軽にキャッシュをクリアするための入り口。
    nonisolated func schedulePrefetchCacheClear() {
        Task { await self.clearPrefetchCache() }
    }

    /// SpeechBlockSpeaker 等、actorの外(読み上げ停止時等)から、完成済みキャッシュは残しつつ
    /// 先読みのバックログだけを止めるための入り口。
    nonisolated func scheduleCancelPendingPrefetch() {
        Task { await self.cancelPendingPrefetch() }
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

    func schedulePrefetch(text: String, styleId: UInt32) {}
    func schedulePrefetchCacheClear() {}
    func scheduleCancelPendingPrefetch() {}

    func isPrefetchedForTesting(text: String, styleId: UInt32) -> Bool { return false }

    /// ログ用(スタブ側は合成しないので常に 0)。
    func cachedAudioSecondsForLogging() -> Double { return 0 }
    func cachedWavByteCount(text: String, styleId: UInt32) -> Int? { return nil }

    static let cpuNumThreadsUserDefaultsKey = "NovelSpeaker.Voicevox.cpuNumThreads"
    static var configuredCPUNumThreads: UInt16 {
        get { return UInt16(clamping: UserDefaults.standard.integer(forKey: cpuNumThreadsUserDefaultsKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: cpuNumThreadsUserDefaultsKey) }
    }
    func reconfigureCPUNumThreads(_ threads: UInt16) throws {
        Self.configuredCPUNumThreads = threads
    }
}

#endif
