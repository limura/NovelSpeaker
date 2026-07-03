//
//  VoicevoxCore.swift
//  NovelSpeaker
//
//  voicevox_core (C API, XCFramework同梱) への最小限のSwiftラッパー。
//  VOICEVOX_IOS_INTEGRATION.md の §2/§3 を踏まえた実装。
//

import Foundation
import voicevox_core

struct VoicevoxStyle {
    let name: String
    let styleId: UInt32
    let speakerName: String
    let speakerUUID: String
    let vvmPath: String
}

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
    nonisolated(unsafe) private var prefetchedWavOrderUnsafe: [String] = []

    // actorへ入らずに(=今actorが何をしていても待たされずに)呼べるよう、あえて nonisolated。
    nonisolated private func peekCache(key: String) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return prefetchedWavUnsafe[key]
    }

    nonisolated private func storeCache(key: String, data: Data) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if prefetchedWavUnsafe[key] == nil {
            prefetchedWavOrderUnsafe.append(key)
        }
        prefetchedWavUnsafe[key] = data
        while prefetchedWavOrderUnsafe.count > prefetchedWavCapacity {
            let oldestKey = prefetchedWavOrderUnsafe.removeFirst()
            prefetchedWavUnsafe.removeValue(forKey: oldestKey)
        }
    }

    nonisolated private func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        prefetchedWavUnsafe.removeAll()
        prefetchedWavOrderUnsafe.removeAll()
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

            var options = voicevox_make_default_initialize_options()
            options.acceleration_mode = VOICEVOX_ACCELERATION_MODE_CPU
            options.cpu_num_threads = 0 // 環境に合わせて自動

            var synth: OpaquePointer?
            let synthResult = voicevox_synthesizer_new(ortNotNil, jtalkNotNil, options, &synth)
            guard synthResult == VOICEVOX_RESULT_OK, let synthNotNil = synth else {
                throw VoicevoxCoreError.core(synthResult)
            }
            synthesizer = synthNotNil
        }

        try reloadStyleCatalog(voiceModelDirectoryPaths: voiceModelDirectoryPaths)
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
        let result = text.withCString { cString in
            voicevox_synthesizer_tts(synthesizer, cString, styleId, options, &outputWavLength, &outputWav)
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
        return data
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
            return cached
        }
        return try await synthesizeSlowPath(text: text, styleId: styleId, key: key)
    }

    /// cache MISS 時の低速パス。pendingPrefetchTasks の確認・performSynthesize の呼び出しは
    /// actor状態を扱うため、ここは(nonisolatedにせず)actor隔離のままにしておく。
    private func synthesizeSlowPath(text: String, styleId: UInt32, key: String) async throws -> Data {
        let snippet = Self.logSnippet(text)
        // 既に先行合成が進行中なら、二重に合成せずその完了を待つ。
        if let pendingTask = pendingPrefetchTasks[key] {
            NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成待ち] styleId=\(styleId) text=\"\(snippet)\"")
            let waitStart = Date()
            await pendingTask.value
            let waited = Date().timeIntervalSince(waitStart)
            if let cached = peekCache(key: key) {
                NSLog("NovelSpeaker.VoicevoxCore: [\(Self.logTimestamp())] [先行合成待ち完了 \(String(format: "%.2f", waited))秒] styleId=\(styleId) text=\"\(snippet)\"")
                return cached
            }
            // 先行合成が失敗していた場合はここに落ちてくるので、その場で合成し直す。
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

    /// 先行合成キャッシュを全て破棄する(新しい本文の読み込み・シーク等でこれまでの
    /// 先読み内容が無意味になった時に呼ぶ)。進行中のタスクはキャンセルはせず、
    /// 完了時に(誰も参照しない)キャッシュへ書き込まれるだけにして単純化している。
    func clearPrefetchCache() {
        clearCache()
        pendingPrefetchTasks.removeAll()
        // 鎖を切っておかないと、新しい本文の先読みが「もう誰も要らない旧本文の
        // 残りチェーン」の後ろに繋がってしまい、無駄に待たされる。
        prefetchTailTask = nil
    }

    /// SpeechBlockSpeaker 等、actorの外(メインスレッド)から気軽に先行合成を蹴るための入り口。
    nonisolated func schedulePrefetch(text: String, styleId: UInt32) {
        Task { await self.prefetch(text: text, styleId: styleId) }
    }

    /// SpeechBlockSpeaker 等、actorの外から気軽にキャッシュをクリアするための入り口。
    nonisolated func schedulePrefetchCacheClear() {
        Task { await self.clearPrefetchCache() }
    }

    // テスト専用: 指定テキストが先行合成キャッシュに乗っているかどうか(進行中/未着手は含まない)。
    nonisolated func isPrefetchedForTesting(text: String, styleId: UInt32) -> Bool {
        return peekCache(key: Self.prefetchKey(text: text, styleId: styleId)) != nil
    }
}
