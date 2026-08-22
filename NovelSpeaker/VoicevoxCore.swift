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

/// VOICEVOX の読み上げの不調(無音・固着)を「アプリ内エラーのお知らせ」に出すかどうか。
///
/// 既定は false で、これらはデバッグ用のログにだけ残る。
/// 固着は 15秒ほどで自力復帰するので、普段の利用では気付かないまま過ぎてしまう。
/// 「おかしいと思ったら点けてもらう」ための、調査用のスイッチ。
///
/// デバッグメニューの表示状態には紐付けていない。
/// デバッグメニューを常に出している人が見たいものは、大抵これとは別の物だから。
///
/// ここに置いてあるのは、固着検出(SpeechBlockSpeaker)が watchOS を含む
/// 全ターゲットでコンパイルされるため。NovelSpeakerUtility は watchOS には無い。
enum VoicevoxDiagnostics {
    static let isVisibleInAppInformationKey = "IsVoicevoxDiagnosticsVisible"

    static var isVisibleInAppInformation: Bool {
        get {
            let defaults = UserDefaults.standard
            defaults.register(defaults: [isVisibleInAppInformationKey: false])
            return defaults.bool(forKey: isVisibleInAppInformationKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isVisibleInAppInformationKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// AppInformationLogger の isForDebug に渡す値。
    /// 表示する時だけ false(=通常のお知らせ扱い)になる。
    static var isForDebug: Bool { return isVisibleInAppInformation == false }
}

/// Open JTalk の解析結果のモーラ1つ。
///
/// VOICEVOX が返す JSON にはこれ以外に長さや音高も入っているが、
/// アクセントの設定画面で要るのは「どう読むか」だけなので、そこだけ取る。
struct VoicevoxMora: Codable, Equatable {
    /// カタカナ1モーラ。
    let text: String
    let consonant: String?
    let vowel: String
}

/// Open JTalk の解析結果のアクセント句1つ。
struct VoicevoxAccentPhrase: Codable, Equatable {
    let moras: [VoicevoxMora]
    /// アクセント核の位置。0 = 平板、N = N モーラ目の後で下がる。
    let accent: Int
    let pauseMora: VoicevoxMora?

    enum CodingKeys: String, CodingKey {
        case moras
        case accent
        case pauseMora = "pause_mora"
    }

    /// 読み(カタカナ)。
    var kana: String { return moras.map({ $0.text }).joined() }
}

extension Array where Element == VoicevoxAccentPhrase {
    /// 全体の読み(カタカナ)。
    var kana: String { return map({ $0.kana }).joined() }
    /// 全体のモーラ列。
    var allMoras: [VoicevoxMora] { return flatMap({ $0.moras }) }
}

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
            return NSLocalizedString("VoicevoxCoreError_NotSetUp", comment: "VOICEVOXの準備ができていません")
        case .styleNotFound(let styleId):
            return String(format: NSLocalizedString(
                "VoicevoxCoreError_StyleNotFoundFormat",
                comment: "指定されたVOICEVOXスタイル(%u)に対応する音声モデルが見つかりません"), styleId)
        case .invalidWav:
            return NSLocalizedString("VoicevoxCoreError_InvalidWav", comment: "VOICEVOXの合成結果が不正なWAVデータでした")
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
    /// 今 Open JTalk に登録してあるユーザー辞書。作り直す時に古い方を捨てるために持つ。
    private var userDict: OpaquePointer?

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

    // MARK: - ディスクキャッシュ(2層目)
    //
    // 参照は メモリ → ディスク → その場で合成 の順に落ちる。
    // 書き込み先は「その小説でキャッシュ生成が有効か」だけで決まり、モードの切り替えは無い。
    // (「ディスクを読み切ったらメモリ側に戻す」というような状態遷移を書くと、
    //  その境界にバグが生まれる。層にしておけば、使い切った後にその場で合成した分も
    //  そのままディスクへ積み上がり、次に同じ所を聴く時には出来ている)
    //
    // どの小説のどの話を再生中かは VoicevoxCore からは分からないので、
    // 再生側(StorySpeaker)が話を切り替える度にここへ教える。

    struct DiskCacheContext {
        let novelID: String
        let chapterNumber: Int

        /// ディスクへ書き足してよいか(利用者がその小説でキャッシュ生成を有効にしている時だけ true)。
        /// 普通に聴いているだけで断りなくストレージを使い始めない、という線引き。
        ///
        /// ここは保持せず、その都度調べる。読み上げ中の小説について後から生成を
        /// 有効にする(詳細画面から「生成する」を押す)事があり、作った時点の値を
        /// 覚えていると、その回の読み上げでは一切ディスクに積まれなくなる。
        var isWritable: Bool {
            return VoicevoxCacheGenerationState.shared.isEnabled(novelID: novelID)
        }
    }

    private let diskCacheContextLock = NSLock()
    nonisolated(unsafe) private var diskCacheContextUnsafe: DiskCacheContext?

    nonisolated var diskCacheContext: DiskCacheContext? {
        diskCacheContextLock.lock()
        defer { diskCacheContextLock.unlock() }
        return diskCacheContextUnsafe
    }

    /// 今どの小説のどの話を読んでいるかを教える(nil で解除)。
    nonisolated func setDiskCacheContext(novelID: String?, chapterNumber: Int) {
        let context: DiskCacheContext? = novelID.map { DiskCacheContext(novelID: $0, chapterNumber: chapterNumber) }
        diskCacheContextLock.lock()
        diskCacheContextUnsafe = context
        diskCacheContextLock.unlock()
    }

    /// 既にディスクに作ってあるか(音声そのものは読まない)。
    nonisolated func isStoredOnDisk(text: String, styleId: UInt32) -> Bool {
        guard let context = diskCacheContext else { return false }
        let key = VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
        return VoicevoxDiskCacheStore.shared.contains(novelID: context.novelID, chapterNumber: context.chapterNumber, key: key)
    }

    nonisolated private func peekDiskCache(text: String, styleId: UInt32) -> Data? {
        guard let context = diskCacheContext else { return nil }
        let key = VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
        guard let data = VoicevoxDiskCacheStore.shared.load(novelID: context.novelID, chapterNumber: context.chapterNumber, key: key) else { return nil }
        VoicevoxCPUUsageReporter.shared.noteDiskCacheHit()
        return data
    }

    /// 合成できた音声をディスクにも積む(有効な小説の時だけ)。
    ///
    /// 圧縮は合成に比べれば誤差(実測: iPhone SE2 で 8.9秒の音声に対し合成24.44秒/圧縮152ms
    /// = 合成の0.62%)なので、合成の裏で気にせず走らせてよい。
    /// 呼び出し元(合成の完了直後)を待たせないよう、別タスクへ逃がす。
    nonisolated func storeToDiskCacheIfNeeded(text: String, styleId: UInt32, wav: Data) {
        guard let context = diskCacheContext else { return }
        // ★ここで作った物は必ず一時分に置く(作成済みとしては残さない)。
        // 利用者が「作って」と言っていない音声なので、聴き終わったら消えてよい。
        // 一時分にする事で、事前生成を有効にしていない小説でも貯められるようになり、
        // メモリキャッシュ(16MB≒6分)の頭打ちに縛られなくなる。
        guard VoicevoxCacheLimits.storesWhilePlaying else { return }
        // 上限に達していたら積まない(生成側と同じ線引き)。
        guard VoicevoxCacheGenerator.currentStopCause() == nil else { return }
        let key = VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
        guard VoicevoxDiskCacheStore.shared.contains(novelID: context.novelID, chapterNumber: context.chapterNumber, key: key) == false else {
            // 合成し終えてから「既にあった」と分かった = この1本は作らなくてよかった。
            // 裏の作り足しと再生側が同じブロックを同時に作っていると、ここが増える。
            VoicevoxCPUUsageReporter.shared.noteDuplicateSynthesis(by: .playback)
            return
        }
        // 優先度を落とし過ぎない。3コアを合成で埋め切っている間 .utility は後回しにされ続け、
        // 「作ったのにディスクに現れない」時間が伸びる。その間は作り足し側から見て
        // 「まだ無い」ままなので、同じブロックをもう一度作ってしまう。
        // 圧縮は合成の 0.62% しかかからないので、少し上げても再生を邪魔しない。
        // 書き終わるまでは、相手から見て「まだ無い」ままになる。
        // その間に同じ物を作られないよう、書き出しの間も帳簿に載せておく。
        VoicevoxSynthesisInProgress.shared.begin(key: key, side: .playback)
        Task(priority: .medium) {
            defer { VoicevoxSynthesisInProgress.shared.end(key: key) }
            do {
                let encoded = try VoicevoxAudioCompressor.encode(wav: wav)
                try VoicevoxDiskCacheStore.shared.store(
                    novelID: context.novelID,
                    chapterNumber: context.chapterNumber,
                    key: key,
                    data: encoded,
                    durationSeconds: VoicevoxAudioCompressor.durationSeconds(wav: wav),
                    area: .temporary
                )
                VoicevoxTemporaryAudio.trimIfNeeded(novelID: context.novelID)
            } catch {
                AppInformationLogger.AddLog(message: "VoicevoxCore: 音声キャッシュの保存に失敗: \(error.localizedDescription)", isForDebug: true)
            }
        }
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
    /// 上限が適用されない状況(前景)では常に0。
    nonisolated private func governorWaitSeconds(text: String, limitRatio: Double) -> Double {
        guard VoicevoxPrefetchThrottleMonitor.shared.isCPULimitApplied else { return 0 }
        return cpuGovernor.waitSeconds(forCharacterCount: text.count, limitRatio: limitRatio, at: ProcessInfo.processInfo.systemUptime)
    }

    // 直前の合成について、見積りが幾らで何秒待たせたか(計測ログ用)。
    // 合成は直列に走るので、単純に上書きしてよい。
    nonisolated(unsafe) private var lastEstimatedCPUSeconds: Double = 0
    nonisolated(unsafe) private var lastGovernorWaitedSeconds: Double = 0

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

    /// 再生に必要な合成が進行中(順番待ち・CPU予算待ちを含む)か。
    ///
    /// 固着検出(SpeechBlockSpeaker)から見えないと困るので internal にしてある。
    /// 「発話中のつもりなのに音も出ていないし合成もしていない」を判定するのに使う。
    nonisolated var isPlaybackSynthesisPending: Bool {
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
            if self.peekCache(key: Self.prefetchKey(text: text, styleId: styleId)) != nil { return true }
            // 既にディスクに作ってあるものは合成し直さない。
            // ここを見ないと、事前生成しておいたのに再生の度に先行合成が走り、
            // ディスクキャッシュがあってもCPUを使ってしまう。
            return self.isStoredOnDisk(text: text, styleId: styleId)
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
    /// いま使える *.vvm の一覧(利用者が取得した物だけ)。
    ///
    /// **アプリには音声モデルを同梱していない。**
    /// 同梱すると ことせかい が VVM の再配布者になるため、
    /// 公式から取得してもらう方針にした(DESIGN_VOICEVOXの音声モデル取得.md §4)。
    /// つまり**入れた直後は1つも無い**のが正しい状態で、
    /// その時は話者一覧が空になる(選ぼうとすると取得へ促される)。
    /// (形式の重複は VoicevoxVoiceModelStore が既に潰している)
    static func currentVoiceModelFilePaths() -> [String] {
        return VoicevoxVoiceModelStore.shared.modelFileURLs(
            readableFormats: VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions)
            .map { $0.path }
    }

    /// 音声モデルを取得した/消した後に、話者一覧を作り直す。
    static func reloadStyleCatalogFromCurrentFiles() {
        guard isAvailableOnThisOS else { return }
        let paths = currentVoiceModelFilePaths()
        Task {
            do {
                try await VoicevoxCore.shared.reloadStyleCatalog(voiceModelFilePaths: paths)
            } catch {
                AppInformationLogger.AddLog(message: "VoicevoxCore.reloadStyleCatalogFromCurrentFiles failed: \(error.localizedDescription)", appendix: [:], isForDebug: true)
            }
        }
    }

    static func setUpFromBundleIfNeeded() async {
        guard isAvailableOnThisOS else { return }
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else { return }
        do {
            try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath,
                                                voiceModelFilePaths: currentVoiceModelFilePaths())
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxCore.setUpFromBundleIfNeeded failed: \(error.localizedDescription)", appendix: [:], isForDebug: true)
        }
    }

    /// 起動時(または初回VOICEVOX利用時)に一度だけ呼ぶ。
    /// - Parameters:
    ///   - dictDirectoryPath: Open JTalk 辞書ディレクトリへのパス(ファイルではなくディレクトリ)
    ///   - voiceModelFilePaths: 読み込む *.vvm の一覧(同梱分 + 取得済み)
    func setUp(dictDirectoryPath: String, voiceModelFilePaths: [String]) throws {
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

            try createSynthesizer(onnxruntime: ortNotNil, openJTalk: jtalkNotNil, threadCount: Self.configuredCPUNumThreads)
        }

        // 「読みの修正」で指定された読みとアクセントを Open JTalk に持たせる。
        applyUserDictionary(VoicevoxUserDictionary.shared.entries)

        try reloadStyleCatalog(voiceModelFilePaths: voiceModelFilePaths)
    }

    // MARK: - ユーザー辞書

    /// 「読みの修正」で指定された読みとアクセントを、Open JTalk のユーザー辞書として登録し直す。
    ///
    /// 置換ではアクセントを変えられない(「橋」「箸」「端」はどれも「ハシ」)ので、
    /// アクセントを指定できるのはここだけである。
    ///
    /// 1語ずつ足し引きせず**毎回作り直す**。追加・変更・削除を差分で追うと、
    /// UUID の管理が要るうえに Realm 側の変更(iCloud 経由の同期を含む)と
    /// ずれた時に直す手段が無くなる。数千件でもミリ秒で終わる処理なので、
    /// 「今あるべき姿を作って差し替える」方が確実に合う。
    func applyUserDictionary(_ entries: [VoicevoxUserDictionaryEntry]) {
        guard let openJTalk = openJTalk else { return }
        guard let dict = voicevox_user_dict_new() else { return }
        var addedCount = 0
        var rejectedCount = 0
        for entry in entries {
            // ★C文字列の寿命に注意。
            // voicevox_user_dict_word_make が返す構造体は surface / pronunciation の
            // ポインタを**そのまま持つ**ので、withCString の外へ持ち出すと解放済みの
            // メモリを指す事になる(実際にテストランナーが落ちた)。
            // 追加まで入れ子の内側で済ませる。
            let result = entry.surface.withCString { surfacePointer -> VoicevoxResultCode in
                return entry.pronunciation.withCString { pronunciationPointer -> VoicevoxResultCode in
                    var word = voicevox_user_dict_word_make(surfacePointer, pronunciationPointer, UInt(entry.accentType))
                    word.priority = UInt8(entry.priority)
                    var uuid = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                                UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
                    return withUnsafeMutableBytes(of: &uuid) { rawBuffer -> VoicevoxResultCode in
                        guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return VOICEVOX_RESULT_INVALID_USER_DICT_WORD_ERROR
                        }
                        return voicevox_user_dict_add_word(dict, &word, UnsafeMutablePointer<(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)>(OpaquePointer(base)))
                    }
                }
            }
            if result == VOICEVOX_RESULT_OK {
                addedCount += 1
            } else {
                // 1語弾かれても他は使えるので止めない。
                // 表記に記号が入っている・読みがカタカナでない等で弾かれる。
                rejectedCount += 1
            }
        }
        let useResult = voicevox_open_jtalk_rc_use_user_dict(openJTalk, dict)
        if useResult != VOICEVOX_RESULT_OK {
            voicevox_user_dict_delete(dict)
            AppInformationLogger.AddLog(message: "VoicevoxCore: ユーザー辞書の登録に失敗しました(\(useResult.rawValue))", isForDebug: true)
            return
        }
        if let previous = userDict {
            voicevox_user_dict_delete(previous)
        }
        userDict = dict
        // ★メモリキャッシュを捨てる。
        // ディスク側の鍵には辞書の署名が入っているので、辞書を変えれば自然に別物になるが、
        // メモリ側の鍵は「話者::本文」だけで辞書を見ていない。捨てないと、
        // 読みを直した直後のその箇所が、古い読みのまま鳴り続ける事になる。
        clearCache()
        if entries.isEmpty == false {
            AppInformationLogger.AddLog(message: "VoicevoxCore: ユーザー辞書を登録しました(\(addedCount)語・受け付けられなかったもの \(rejectedCount)語)", isForDebug: true)
        }
    }

    /// この内容で VOICEVOX のユーザー辞書に登録できるか。
    ///
    /// **判定は VOICEVOX 自身にさせる。** 受け付けられる文字の範囲を
    /// こちらで書き写すと、本体の更新でずれた時に「登録したつもりで効いていない」
    /// という一番分かりにくい壊れ方をする。
    ///
    /// 読みがカタカナでないと弾かれるが、弾かれても**発話自体は普通にできてしまう**
    /// (置換の方は効くので)。利用者からは「アクセントだけ効かない」と見え、
    /// 原因に辿り着けない。だから登録できるかどうかを先に確かめて知らせる。
    func canRegisterUserDictWord(surface: String, pronunciation: String, accentType: Int) -> Bool {
        guard surface.isEmpty == false, pronunciation.isEmpty == false else { return false }
        guard let dict = voicevox_user_dict_new() else { return false }
        defer { voicevox_user_dict_delete(dict) }
        let result = surface.withCString { surfacePointer -> VoicevoxResultCode in
            return pronunciation.withCString { pronunciationPointer -> VoicevoxResultCode in
                var word = voicevox_user_dict_word_make(surfacePointer, pronunciationPointer, UInt(max(0, accentType)))
                var uuid = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
                return withUnsafeMutableBytes(of: &uuid) { rawBuffer -> VoicevoxResultCode in
                    guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return VOICEVOX_RESULT_INVALID_USER_DICT_WORD_ERROR
                    }
                    return voicevox_user_dict_add_word(dict, &word, UnsafeMutablePointer<(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)>(OpaquePointer(base)))
                }
            }
        }
        return result == VOICEVOX_RESULT_OK
    }

    /// テキストを Open JTalk に解析させて、モーラ列とアクセントを得る。
    ///
    /// **声のモデル(VVM)は要らない。** synthesizer ではなく Open JTalk が持っている
    /// 機能なので、音声モデルを1つも持っていない端末でも読みとアクセントは出せる。
    ///
    /// アクセントの設定画面で、
    ///  - 利用者が入れた文字列(漢字混じりでもよい)のカタカナ読み
    ///  - 今のところ VOICEVOX がどう読むつもりなのか
    /// を出すのに使う。**実際に喋るのと同じ解析器**なので、答えは本物である。
    func analyze(text: String) throws -> [VoicevoxAccentPhrase] {
        guard let openJTalk = openJTalk else { throw VoicevoxCoreError.notSetUp }
        var json: UnsafeMutablePointer<CChar>?
        let result = text.withCString { cString in
            voicevox_open_jtalk_rc_analyze(openJTalk, cString, &json)
        }
        guard result == VOICEVOX_RESULT_OK, let json = json else {
            throw VoicevoxCoreError.core(result)
        }
        defer { voicevox_json_free(json) }
        let data = Data(String(cString: json).utf8)
        return try JSONDecoder().decode([VoicevoxAccentPhrase].self, from: data)
    }

    /// 指定されたスレッド数で synthesizer を作る。
    private func createSynthesizer(onnxruntime: OpaquePointer, openJTalk: OpaquePointer, threadCount: UInt16) throws {
        var options = voicevox_make_default_initialize_options()
        options.acceleration_mode = VOICEVOX_ACCELERATION_MODE_CPU
        // 0 = 環境に合わせて自動(= 全コアを使う)。
        // 全コアだと ONNX が CPU を 200〜290% 使うため、背面バッテリー時は
        // CPU 上限(60秒平均80%)超過で即座に強制終了される。一方で前景/充電中は
        // その上限が無く、全コアの方が実時間では倍近く速い。
        // よって固定せず、状況に応じて切り替える(VoicevoxThreadPolicy)。
        options.cpu_num_threads = threadCount

        var synth: OpaquePointer?
        let synthResult = voicevox_synthesizer_new(onnxruntime, openJTalk, options, &synth)
        guard synthResult == VOICEVOX_RESULT_OK, let synthNotNil = synth else {
            throw VoicevoxCoreError.core(synthResult)
        }
        synthesizer = synthNotNil
        Self.activeCPUNumThreads = threadCount
        Self.lastThreadCountChangeDate = Date()
    }

    /// 指定された *.vvm を全部 open→メタ取得→close して話者カタログを作り直す。
    /// (open だけならロードと違って軽い。VOICEVOX_IOS_INTEGRATION.md §3-4)
    ///
    /// ディレクトリを走査せずファイルを名指しで受け取るのは、
    /// 同じ番号の音声モデルが複数の場所にある事があるため
    /// (同梱と取得済み、形式1と形式2)。どれを使うかは呼び出し側で決める。
    func reloadStyleCatalog(voiceModelFilePaths: [String]) throws {
        var newStyles: [VoicevoxStyle] = []
        for vvmPath in voiceModelFilePaths {
            newStyles.append(contentsOf: try stylesFrom(vvmPath: vvmPath))
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

        // 0.17.0 でオプション引数が増えた。既定は「同じIDが既に読み込まれていたらエラー」で、
        // これは 0.16.4 までの挙動と同じ。こちらは loadedVvmPaths で二重ロードを防いでいるので
        // 既定のままでよい(RELOAD はメモリを開放し直したい時のための物)。
        let loadOptions = voicevox_make_default_load_voice_model_options()
        let loadResult = voicevox_synthesizer_load_voice_model(synthesizer, model, loadOptions)
        guard loadResult == VOICEVOX_RESULT_OK else {
            throw VoicevoxCoreError.core(loadResult)
        }
        loadedVvmPaths.insert(style.vvmPath)
    }

    /// 今の状況で使いたい CPU スレッド数(0 = 全コア)。
    ///
    /// synthesizer の生成時オプションなので、変えるには synthesizer の作り直しが要る。
    /// 状況に応じて自動で切り替える(VoicevoxThreadPolicy 参照)。
    static var configuredCPUNumThreads: UInt16 {
        let monitor = VoicevoxPrefetchThrottleMonitor.shared
        return VoicevoxThreadPolicy.desiredThreadCount(
            isBackground: monitor.isBackground,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// 今の synthesizer を作った時のスレッド数。
    nonisolated(unsafe) private(set) static var activeCPUNumThreads: UInt16 = 0
    /// 最後にスレッド数を切り替えた時刻(往復を防ぐための間隔判定に使う)。
    nonisolated(unsafe) private static var lastThreadCountChangeDate = Date.distantPast

    /// 状況が変わっていればスレッド数を切り替える(synthesizer の作り直しを伴う)。
    ///
    /// 合成の直前に毎回呼ぶ。通知(前景/背面・電源)を取り零しても、次の合成で必ず
    /// 追いつけるようにするため。合成済みキャッシュ(=貯金)は音声データなので
    /// スレッド数とは無関係。捨てずにそのまま残す。
    func applyThreadCountIfNeeded() {
        let desired = Self.configuredCPUNumThreads
        let elapsed = Date().timeIntervalSince(Self.lastThreadCountChangeDate)
        guard VoicevoxThreadPolicy.shouldReconfigure(current: Self.activeCPUNumThreads, desired: desired, secondsSinceLastChange: elapsed) else { return }
        guard let ort = onnxruntime, let jtalk = openJTalk else { return }
        do {
            if let existing = synthesizer {
                voicevox_synthesizer_delete(existing)
                synthesizer = nil
            }
            // 音声モデルは synthesizer に紐づいてロードされているので、読み直しが必要。
            loadedVvmPaths.removeAll()
            try createSynthesizer(onnxruntime: ort, openJTalk: jtalk, threadCount: desired)
            // 文字数あたりの CPU 秒はスレッド数で変わるので、見積りは切り替える。
            // 捨てるのではなく**スレッド数ごとに覚えておく**(行き来しても既定値に戻らない)。
            // ただし「既に使った CPU」の記録は残す(消すと、直前まで全コアで回していた事を
            // 忘れて、背面に移った直後の60秒窓で予算超過=強制終了を招く)。
            cpuGovernor.useThreadCountProfile(desired)
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxCore: スレッド数の切り替えに失敗: \(error.localizedDescription)", isForDebug: true)
        }
    }

    static func threadCountDescription(_ threadCount: UInt16) -> String {
        return threadCount == 0 ? "自動(全コア)" : "\(threadCount)"
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
        // ここは先行合成・その場合成の両方が通る唯一の絞り点なので、実測点として適切。
        // 測った CPU 秒は、次の合成を走らせてよいかの見積り(VoicevoxCPUGovernor)に使う。
        let cpuBefore = ProcessCPUClock.totalCPUSeconds()
        let wallBefore = ProcessInfo.processInfo.systemUptime
        let result = text.withCString { cString in
            voicevox_synthesizer_tts(synthesizer, cString, styleId, options, &outputWavLength, &outputWav)
        }
        // 実時間も測る。CPU 上限の判定窓(60秒)は実時間の窓なので、
        // 「その合成が窓のどこをどれだけ占めていたか」は実時間でないと置けない
        // (全コアで走れば 17 CPU秒 の合成でも実時間は4秒ほどしかない)。
        let wallSeconds = ProcessInfo.processInfo.systemUptime - wallBefore
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
            // 次回以降の見積り材料。同じ文字数でも端末と発熱状態で数倍違うので、実測が要る。
            cpuGovernor.recordSynthesis(cpuSeconds: cpuSeconds, wallSeconds: wallSeconds, characterCount: text.count, at: ProcessInfo.processInfo.systemUptime)
            // 「予算管理が効いていたのに使い過ぎた」のかどうかを後から判断できるように、
            // プロセス全体の使用率と一緒に残す(VoicevoxCPUUsageReporter 参照)。
            VoicevoxCPUUsageReporter.shared.report(
                characterCount: text.count,
                estimatedCPUSeconds: lastEstimatedCPUSeconds,
                actualCPUSeconds: cpuSeconds,
                actualWallSeconds: wallSeconds,
                audioSeconds: VoicevoxAudioCompressor.durationSeconds(wav: data),
                waitedSeconds: lastGovernorWaitedSeconds,
                isCPULimitApplied: VoicevoxPrefetchThrottleMonitor.shared.isCPULimitApplied)
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
            return cached
        }
        // メモリに無くても、事前に作ってディスクに貯めてあれば、そこから即座に返せる。
        // 背面バッテリーでは実時間合成が原理的に不可能(必要CPU率128〜226%に対し使えるのは80%)
        // なので、無音を無くせるのは実質この経路だけ。
        if let disk = peekDiskCache(text: text, styleId: styleId) {
            return disk
        }
        // ここに来た = 再生が必要な時点で先行合成が間に合っていなかった。
        // その待ち時間がそのまま無音の長さになる(VoicevoxSilenceReporter が拾う)。
        // MISS の原因判定と「待機中の予約の横取り」は、**actor に入る前**に行う。
        //  - 予約済み(pending)   … 先行合成に出してはいたが間に合わなかった = 時間の問題。
        //  - 合成中(inFlight)   … ワーカーが今まさに作っている。完成を待つ方が速い。
        //  - 未予約(not queued) … そもそも先行合成の対象から漏れていた = 取りこぼしの不具合。
        // どちらなのかで対処が全く変わるため、ここで確定させる。
        //
        // 以前は actor 隔離の中で判定していたが、それだと実行中の合成(1本30秒近い)の
        // 完了を待たされる間に待ち行列の状態が「合成中」→「完了」へ変わってしまい、
        // 本当は予約済みだったものが「未予約」として記録されていた
        // (実機ログで、予約済みの block=9 の合成完了と同時刻に「再生MISS(未予約)」が
        //  出ており、未予約22件のほとんどがこの誤判定だった)。
        // 横取りを先に済ませる事で、actor 待ちの間にワーカーが同じ物を始める余地も無くなる。
        let claim = synthesisQueue.claimForImmediateSynthesis(text: text, styleId: styleId)
        let wasQueued = claim != .notQueued
        VoicevoxSilenceReporter.shared.noteCacheMiss(wasQueuedForPrefetch: wasQueued)

        let data = try await synthesizeSlowPath(text: text, styleId: styleId, key: key, claim: claim)
        return data
    }

    /// cache MISS 時の低速パス。pendingPrefetchTasks の確認・performSynthesize の呼び出しは
    /// actor状態を扱うため、ここは(nonisolatedにせず)actor隔離のままにしておく。
    private func synthesizeSlowPath(text: String, styleId: UInt32, key: String, claim: VoicevoxSynthesisQueue.ClaimResult) async throws -> Data {
        // 先行合成に予算を横取りされないよう、再生側の合成が進行中である事を知らせる。
        beginPlaybackSynthesis()
        defer { endPlaybackSynthesis() }
        // actor に入るまでの間に先行合成が完成している事がある(むしろ、実行中だった
        // 合成の完了を待って actor に入るので、その可能性は高い)。まず確認する。
        if let cached = peekCache(key: key) {
            return cached
        }
        let wasQueued = claim != .notQueued
        if claim == .inFlight {
            // ワーカーが今まさに同じ物を合成している。ここで自分でも合成すると
            // 同じ物を二重に合成して CPU 予算を食い合い、どちらも進まなくなる
            // (実機で同じブロックの「分割合成」が二重に走り、1ブロックに4分以上かかっていた)。
            // 完成を待つ方が速い。
            if let data = await waitForInFlightSynthesis(key: key) {
                return data
            }
        }
        if wasQueued {
        } else {
        }
        // 待っている間に先行合成が完了していた可能性があるので、合成前にもう一度確認する。
        if let cached = peekCache(key: key) {
            return cached
        }
        // 裏の作り足しが、待っている間にディスクへ置いていった可能性もある。
        // メモリだけを見ていると、それを見落として同じ物をもう一度作る事になる。
        if let disk = peekDiskCache(text: text, styleId: styleId) {
            return disk
        }
        // 作り足しが「今まさに」同じ物を作っている最中なら、出来上がりを待つ。
        // 合成は直列なので、自分でも作ると相手の完了を待ってから自分の合成が始まり、
        // 二回ぶん待つ事になる(そのぶんそのまま無音が伸びる)。
        let diskKey = VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
        if VoicevoxSynthesisInProgress.shared.isInProgress(key: diskKey, by: .generator) {
            if await VoicevoxSynthesisInProgress.shared.waitForCompletion(key: diskKey, timeoutSeconds: 30),
               let disk = peekDiskCache(text: text, styleId: styleId) {
                return disk
            }
        }
        VoicevoxSynthesisInProgress.shared.begin(key: diskKey, side: .playback)
        defer { VoicevoxSynthesisInProgress.shared.end(key: diskKey) }
        // 再生に必要な合成でも、CPU予算を超えたまま突入すると強制終了される
        // (殺されると再生そのものが止まるので、無音より重い)。先行合成より多くの
        // 予算を使ってよいが、上限は守る。
        let data = try await performSynthesizeWithinBudget(text: text, styleId: styleId, limitRatio: Self.playbackCPULimitRatio)
        // キャッシュを使い切った後にその場で合成した分も、そのままディスクへ積み上げる。
        // (次に同じ所を聴く時には出来ている)
        storeToDiskCacheIfNeeded(text: text, styleId: styleId, wav: data)
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
        // 前景/背面や電源状態が変わっていれば、ここでスレッド数を合わせる。
        // 通知を取り零しても、次の合成で必ず追いつけるようにするため
        // (「前景で再生開始 → ロック → 電源を抜く」で全コアのまま走り続けると
        //  背面CPU上限で強制終了されるので、取り零しは許容できない)。
        applyThreadCountIfNeeded()
        // 合成の入口はここ一箇所しか無いので、ここで「同じ物を二度作っていないか」を見張る。
        // 同じ鍵を二度合成したら、それは条件に依らず必ず無駄撃ちである
        // (詳細は VoicevoxRepeatedSynthesisDetector.swift)。
        VoicevoxRepeatedSynthesisDetector.shared.noteSynthesisStarting(
            key: VoicevoxDiskCacheStore.key(text: text, styleId: styleId))
        let texts = chunkedTextsForBudget(text: text, limitRatio: limitRatio)
        var wavs: [Data] = []
        for (index, chunk) in texts.enumerated() {
            // 分割した2つ目以降でも、その都度スレッド数を見直す。
            // 合成は走り始めたら止められない(スレッド数は synthesizer の生成時オプションで、
            // 実行中の合成には効かないし、途中で中断する手段も無い)ので、
            // 「今から走らせる1本」を減らす事でしか間に合わせられない。
            // ここが無いと、1つ目の途中で背面に落ちた時に残りの塊まで全コアで走ってしまう。
            if index > 0 {
                applyThreadCountIfNeeded()
            }
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
        lastEstimatedCPUSeconds = cpuGovernor.estimatedCPUSeconds(forCharacterCount: text.count)
        lastGovernorWaitedSeconds = 0
        let maxWaitCount = 2
        for _ in 0..<maxWaitCount {
            let waitSeconds = governorWaitSeconds(text: text, limitRatio: limitRatio)
            if waitSeconds <= 0 { return }
            // 分割してもなお1本で予算を超える(句読点が全く無い等)場合は、窓が空くまで待った上で
            // 実行する。その1本だけで窓を使い切る形になり、上限超過の確率が最も小さくなる。
            let sleepSeconds = min(waitSeconds.isInfinite ? Self.cpuWindowSeconds : waitSeconds, Self.cpuWindowSeconds)
            lastGovernorWaitedSeconds += sleepSeconds
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        }
    }

    /// 事前生成(ディスクキャッシュ作成)のための合成。
    ///
    /// 再生に必要な合成が待っている間は手を出さない(待たせるとそのまま無音になるため)。
    /// 合成結果をメモリキャッシュには入れない。事前生成は本文を延々と舐めていくので、
    /// 入れると再生に必要な物を押し出してしまう。作った物はディスクに置かれ、
    /// 再生時はそちらから読まれる。
    /// - Parameter isStillNeeded: 重いC呼び出しに入る**直前**に、まだ作る必要があるかを問い合わせる。
    ///   false を返したら合成せず nil を返す。
    ///
    ///   呼び出し側で先に確かめても足りない。ここには
    ///   「再生側の合成が終わるまで待つ」(最大30秒)と actor の順番待ちがあり、
    ///   **待っている間に再生側が同じブロックを作り終えている**。
    ///   実機ログでは合成のちょうど半分がこれで二度手間になっていた。
    func synthesizeForDiskCache(text: String, styleId: UInt32,
                                isStillNeeded: (@Sendable () -> Bool)? = nil) async throws -> Data? {
        await waitWhilePlaybackSynthesisIsPending()
        // 待ちが明けた今の状態で確かめる。
        if peekCache(key: Self.prefetchKey(text: text, styleId: styleId)) != nil { return nil }
        if let isStillNeeded, isStillNeeded() == false { return nil }
        return try await performSynthesizeWithinBudget(text: text, styleId: styleId, limitRatio: Self.prefetchCPULimitRatio)
    }

    /// 待ち行列から取り出した1件を実際に合成する(ここだけが actor 隔離 = 直列実行)。
    private func runSynthesis(_ request: VoicevoxSynthesisQueue.Request) async {
        // 順番待ちの間に読み上げが停止/シークされていたら、重いC呼び出しには入らず捨てる。
        // これをしないと、停止後も延々と(実機で16分=983秒の先行合成完了ログを確認)
        // 合成され続け、CPU/電池を浪費してしまう。
        // 停止/シークで用済みになっていないか、待っている間に別経路(裏の作り足し)が
        // 同じ物を作り終えていないかを、重いC呼び出しの直前にもう一度確かめる。
        if synthesisQueue.isStillNeeded(request) == false {
            synthesisQueue.complete(request)
            return
        }
        // 作り足しが同じ物を作っている最中なら、出来上がりを待たずに諦める。
        // 先行合成なので、置かれた物を再生時にディスクから読めばよい。
        let prefetchDiskKey = VoicevoxDiskCacheStore.key(text: request.text, styleId: request.styleId)
        if VoicevoxSynthesisInProgress.shared.isInProgress(key: prefetchDiskKey, by: .generator) {
            synthesisQueue.complete(request)
            return
        }
        VoicevoxSynthesisInProgress.shared.begin(key: prefetchDiskKey, side: .playback)
        defer { VoicevoxSynthesisInProgress.shared.end(key: prefetchDiskKey) }
        do {
            let data = try await performSynthesizeWithinBudget(text: request.text, styleId: request.styleId, limitRatio: Self.prefetchCPULimitRatio)
            storeCache(key: Self.prefetchKey(text: request.text, styleId: request.styleId), data: data)
            storeToDiskCacheIfNeeded(text: request.text, styleId: request.styleId, wav: data)
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxCore: prefetch failed: \(error.localizedDescription)", appendix: [
                "text": request.text,
                "styleId": "\(request.styleId)",
            ], isForDebug: true)
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

    /// 前景/背面や電源状態が変わった時に呼ぶ。スレッド数を今の状況に合わせ直す。
    ///
    /// 合成の直前にも同じ判定を行っているので、これは「次の合成を待たずに早めに
    /// 反映する」ためのもの。actor に入るため、実行中の合成が終わるまでは待たされる。
    nonisolated func scheduleThreadCountUpdate() {
        Task(priority: .userInitiated) { [weak self] in
            await self?.applyThreadCountIfNeeded()
        }
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
            return NSLocalizedString("VoicevoxCoreError_NotAvailableOnCatalyst", comment: "VOICEVOXはMac Catalystでは利用できません")
        case .styleNotFound(let styleId):
            return String(format: NSLocalizedString(
                "VoicevoxCoreError_StyleNotFoundFormat",
                comment: "指定されたVOICEVOXスタイル(%u)に対応する音声モデルが見つかりません"), styleId)
        case .invalidWav:
            return NSLocalizedString("VoicevoxCoreError_InvalidWav", comment: "VOICEVOXの合成結果が不正なWAVデータでした")
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
    static func currentVoiceModelFilePaths() -> [String] { return [] }
    static func reloadStyleCatalogFromCurrentFiles() {}

    func synthesize(text: String, styleId: UInt32) async throws -> Data {
        throw VoicevoxCoreError.notSetUp
    }

    func synthesizeForDiskCache(text: String, styleId: UInt32,
                                isStillNeeded: (@Sendable () -> Bool)? = nil) async throws -> Data? {
        throw VoicevoxCoreError.notSetUp
    }

    nonisolated var isPlaybackSynthesisPending: Bool { return false }

    func applyUserDictionary(_ entries: [VoicevoxUserDictionaryEntry]) {}
    func canRegisterUserDictWord(surface: String, pronunciation: String, accentType: Int) -> Bool { return false }
    func analyze(text: String) throws -> [VoicevoxAccentPhrase] {
        throw VoicevoxCoreError.notSetUp
    }

    @discardableResult
    func schedulePrefetch(blockIndex: Int, text: String, styleId: UInt32) -> Bool { return false }
    func notePlaybackBlockIndex(_ index: Int) {}
    func schedulePrefetchCacheClear() {}
    func scheduleCancelPendingPrefetch() {}

    func isPrefetchedForTesting(text: String, styleId: UInt32) -> Bool { return false }

    /// ログ用(スタブ側は合成しないので常に 0)。
    func cachedAudioSecondsForLogging() -> Double { return 0 }
    func cachedWavByteCount(text: String, styleId: UInt32) -> Int? { return nil }

    /// 実装側と同じ導出(再生側と先行合成側で解釈が食い違わないようにするため)。
    static func styleId(fromVoiceIdentifier voiceIdentifier: String?) -> UInt32 {
        return UInt32(voiceIdentifier ?? "") ?? 0
    }

    static var configuredCPUNumThreads: UInt16 {
        let monitor = VoicevoxPrefetchThrottleMonitor.shared
        return VoicevoxThreadPolicy.desiredThreadCount(
            isBackground: monitor.isBackground,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
    nonisolated(unsafe) private(set) static var activeCPUNumThreads: UInt16 = 0
    static func threadCountDescription(_ threadCount: UInt16) -> String {
        return threadCount == 0 ? "自動(全コア)" : "\(threadCount)"
    }
    func applyThreadCountIfNeeded() {}
    func scheduleThreadCountUpdate() {}

    struct DiskCacheContext {
        let novelID: String
        let chapterNumber: Int
        var isWritable: Bool { return false }
    }
    var diskCacheContext: DiskCacheContext? { return nil }

    func setDiskCacheContext(novelID: String?, chapterNumber: Int) {}
    func isStoredOnDisk(text: String, styleId: UInt32) -> Bool { return false }
    func storeToDiskCacheIfNeeded(text: String, styleId: UInt32, wav: Data) {}
}

#endif
