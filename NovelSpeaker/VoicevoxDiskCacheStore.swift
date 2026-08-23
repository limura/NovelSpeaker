//
//  VoicevoxDiskCacheStore.swift
//  NovelSpeaker
//
//  VOICEVOX の合成済み音声をディスクに貯めておく保存層。
//
//  なぜ必要か:
//  背面バッテリー駆動では iOS の CPU 上限(60秒平均で1コア相当の80%)が効くため、
//  実測で iPhone 17 Pro Max ですら 1.45倍速に必要な CPU 率は 128%、
//  iPhone SE2 では 226% で、どうやっても実時間で合成し切れない
//  (スケジューラ側は既に理論下限まで詰めてある)。
//  事前に作って貯めておく以外に、無音を無くす方法が無い。
//
//  設計:
//   - **索引ファイルを持たない**。壊れた索引の整合性を取る処理を書かなくて済むよう、
//     音声の長さをファイル名自体(`<鍵>_<ミリ秒>.m4a`)に持たせる。
//     容量も合計時間もディレクトリを読むだけで求まり、途中で電源が切れても
//     「中途半端なファイルが1つ余分にある」以上の壊れ方をしない。
//   - **鍵は内容アドレス方式**(styleId と読み上げ文字列から決まる)。
//     読み替え辞書を変更しても、変わったブロックだけが作り直しになる。
//   - **小説ごと・話ごとのディレクトリ**。
//       `<小説の鍵>/<話番号>/<ブロックの鍵>_<ミリ秒>.m4a`
//     話ごとに掘るのは、1ディレクトリのファイル数を数十に抑えるためだけでなく、
//     「20話目の何%まで作れたか」がそのディレクトリを数えるだけで求まるため。
//   - **パスに版を1段入れる**(`v1/...`)。
//     鍵は styleId と読み上げ文字列からしか作っていないので、
//     将来 user dict のように「音に影響するが鍵に入っていない入力」を足すと、
//     同じ鍵のまま音が変わる = 「辞書を直したのに古い音が鳴り続ける」という
//     追いにくい不具合になる。その時は版を上げれば、古い版のディレクトリが
//     起動時に丸ごと消えるので、孤児が残り続ける事故が原理的に起きない
//     (この置き場所はこのアプリ専用なので、「今の版でない物は全部要らない」で言い切れる)。
//     (SiteInfo のキャッシュで「キャッシュ名のバンプ忘れ」を踏んだのと同じ教訓)
//     なお **VVMの版は鍵に入れない**。入れるとモデルを更新するたびに
//     全キャッシュが無効になるため、そちらは更新時に個別に尋ねる。
//   - 保存先は Application Support(Caches は OS に勝手に消される)+ バックアップ除外。
//   - **端末ローカル限定**。他端末では話者(VVM)がダウンロードされているとは限らず、
//     読み替え辞書も同じとは限らないので、共有しても使えない。
//     よって Realm には持たせない(バックアップ/同期/コピーの並行リストが増えるため)。
//

import Foundation
import CryptoKit

/// キャッシュの集計結果(管理画面の「何分ぶん作れたか」用)。
struct VoicevoxDiskCacheSummary: Equatable {
    let entryCount: Int
    let audioSeconds: Double
    let byteCount: Int

    static let empty = VoicevoxDiskCacheSummary(entryCount: 0, audioSeconds: 0, byteCount: 0)

    static func + (lhs: VoicevoxDiskCacheSummary, rhs: VoicevoxDiskCacheSummary) -> VoicevoxDiskCacheSummary {
        return VoicevoxDiskCacheSummary(
            entryCount: lhs.entryCount + rhs.entryCount,
            audioSeconds: lhs.audioSeconds + rhs.audioSeconds,
            byteCount: lhs.byteCount + rhs.byteCount
        )
    }
}

final class VoicevoxDiskCacheStore {

    static let shared = VoicevoxDiskCacheStore(rootDirectory: VoicevoxDiskCacheStore.defaultRootDirectory())

    /// 保存する音声のファイル拡張子。生の WAV は 1秒あたり約48KB(1時間で約170MB)あるので、
    /// AAC に圧縮して置く(1時間で約15MB)。
    static let fileExtension = "m4a"

    /// 小説ディレクトリに置く、小説IDを書いた印。
    ///
    /// ディレクトリ名は小説IDのハッシュなので元に戻せない。管理画面で
    /// 「どの小説のキャッシュか」を出すためにこれを読む。
    /// 失われても音声そのものは無事で、「不明な小説」として削除だけはできる
    /// (索引と違って、壊れても整合性を取り直す必要が無い)。
    private static let novelIDMarkerFileName = "novelID.txt"

    /// **音に影響する入力が変わったら上げる版。**
    /// 上げると、古い版のディレクトリは起動時に丸ごと消える。
    /// 鍵の式(key(text:styleId:))を変えた時も上げる事。
    static let formatVersion = 1

    private let rootDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    /// ディレクトリの内容をメモリ上に写したもの(話ディレクトリのパス → 鍵 → 実体)。
    /// 索引「ファイル」ではないので壊れる心配は無く、初回参照時に readdir 1回で作れる。
    /// 「もう作ってあるか」の判定を毎回ディレクトリを読まずに済ませるためのもの。
    private var listings: [String: [String: Entry]] = [:]

    private struct Entry {
        let fileName: String
        let byteCount: Int
        let durationSeconds: Double
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    static func defaultRootDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("VoicevoxAudioCache", isDirectory: true)
    }

    // MARK: - 鍵

    /// 音声の内容から決まる鍵。話者と読み上げ文字列が同じなら同じ音声になる。
    /// そのままファイル名にするので、英数字のみ(SHA256 の16進表記)である事が必要。
    ///
    /// ★VOICEVOX のユーザー辞書も内容のうちに入る。
    ///
    /// 読み替えを変えると本文そのものが変わるので鍵も自然に変わるが、
    /// ユーザー辞書は本文を変えずに読み方だけを変えるので、そのままでは
    /// 古い音声が使われ続けてしまう。かといって辞書全体の版番号を混ぜると、
    /// 1語直しただけで何時間ぶんもの作り置きが一斉に無駄になる。
    /// **その本文に実際に効いてくる語だけ**を署名にして混ぜる。
    /// 何も効かない本文では空文字列になるので、辞書を使っていない限り
    /// 鍵はこれまでと同じままである。
    static func key(text: String, styleId: UInt32) -> String {
        let signature = VoicevoxUserDictionary.shared.signature(forText: text)
        if signature.isEmpty {
            return sha256Hex("\(styleId)::\(text)")
        }
        return sha256Hex("\(styleId)::\(text)::\(signature)")
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 小説IDはURL等でファイル名に使えない文字を含み得るので、そのまま使わない。
    private static func directoryName(novelID: String) -> String {
        return sha256Hex(novelID)
    }

    // MARK: - 場所

    /// 音声の置き場所は2つある。
    ///
    /// - `permanent`: 利用者が「作って」と言った分。消えない。
    /// - `temporary`: 読み上げ中に足りなくなって作った分。自動で消える。
    ///
    /// 分けているのは、**利用者の実感と実体を合わせるため**。
    /// 1つにすると「作らせた覚えの無い容量」が「作成済み」に混ざって増えていく。
    /// 分けておけば「作成済み = 自分が作らせた分」で一致し、
    /// 一時分は別勘定で「聴き終わった所から消える物」として説明できる。
    enum Area: CaseIterable {
        case permanent
        case temporary

        /// 探す順。作らせた分を先に見る(同じ物が両方にある事は無いが、順を決めておく)。
        static var lookupOrder: [Area] { return [.permanent, .temporary] }
    }

    static func versionDirectoryName(_ version: Int) -> String {
        return "v\(version)"
    }

    static func temporaryDirectoryName(_ version: Int) -> String {
        return "t\(version)"
    }

    static func directoryName(of area: Area, version: Int) -> String {
        switch area {
        case .permanent: return versionDirectoryName(version)
        case .temporary: return temporaryDirectoryName(version)
        }
    }

    private func areaRoot(_ area: Area) -> URL {
        return rootDirectory.appendingPathComponent(Self.directoryName(of: area, version: Self.formatVersion),
                                                    isDirectory: true)
    }

    /// 今の版の置き場所(作らせた分)。
    private var versionedRoot: URL { return areaRoot(.permanent) }

    private func novelDirectory(novelID: String, area: Area = .permanent) -> URL {
        return areaRoot(area).appendingPathComponent(Self.directoryName(novelID: novelID), isDirectory: true)
    }

    private func chapterDirectory(novelID: String, chapterNumber: Int, area: Area = .permanent) -> URL {
        return novelDirectory(novelID: novelID, area: area)
            .appendingPathComponent("\(chapterNumber)", isDirectory: true)
    }

    // MARK: - 保存と取り出し

    func store(novelID: String, chapterNumber: Int, key: String, data: Data, durationSeconds: Double,
               area: Area = .permanent) throws {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber, area: area)
        try prepareDirectories(novelID: novelID, chapterDirectory: directory, area: area)

        let milliseconds = max(0, Int((durationSeconds * 1000).rounded()))
        let fileName = "\(key)_\(milliseconds).\(Self.fileExtension)"
        let destination = directory.appendingPathComponent(fileName)

        // 途中で電源が切れても半端なファイルを掴まないよう、書いてから置き換える。
        let temporary = directory.appendingPathComponent("tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)

        lock.lock()
        var listing = listingUnsafe(directory: directory)
        // 同じ鍵で長さの違う古いファイルが残っていたら消す(名前が変わるので上書きにならない)。
        if let old = listing[key], old.fileName != fileName {
            try? fileManager.removeItem(at: directory.appendingPathComponent(old.fileName))
        }
        listing[key] = Entry(fileName: fileName, byteCount: data.count, durationSeconds: Double(milliseconds) / 1000)
        listings[directory.path] = listing
        lock.unlock()
    }

    /// 作らせた分と一時分の両方から探す。再生側から見れば区別は無い。
    func load(novelID: String, chapterNumber: Int, key: String) -> Data? {
        for area in Area.lookupOrder {
            let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber, area: area)
            if let entry = entry(directory: directory, key: key) {
                return try? Data(contentsOf: directory.appendingPathComponent(entry.fileName))
            }
        }
        return nil
    }

    /// 中身を読まずに有無だけを判定する(生成の再開時に「どこまで作れているか」を数えるため)。
    func contains(novelID: String, chapterNumber: Int, key: String) -> Bool {
        return Area.lookupOrder.contains { area in
            entry(directory: chapterDirectory(novelID: novelID, chapterNumber: chapterNumber, area: area),
                  key: key) != nil
        }
    }

    /// 保存してある音声の長さ。中身を読まずに求まる(ファイル名に入っているため)。
    /// 「この先どれだけ再生ぶんが貯まっているか」の計算に使う。
    func durationSeconds(novelID: String, chapterNumber: Int, key: String) -> Double? {
        for area in Area.lookupOrder {
            if let entry = entry(directory: chapterDirectory(novelID: novelID, chapterNumber: chapterNumber, area: area),
                                 key: key) {
                return entry.durationSeconds
            }
        }
        return nil
    }

    private func entry(directory: URL, key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return listingUnsafe(directory: directory)[key]
    }

    // MARK: - 集計

    /// ★作らせた分だけを数える(管理画面の「作成済み」用)。
    /// 一時分は「作らせた覚えの無い容量」なので、ここには混ぜない。
    func summary(novelID: String, chapterNumber: Int) -> VoicevoxDiskCacheSummary {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        lock.lock()
        let listing = listingUnsafe(directory: directory)
        lock.unlock()
        return Self.summarize(listing.values)
    }

    /// ★置き場所を問わず数える(「この先どれだけ再生ぶんが貯まっているか」用)。
    ///
    /// 再生する側から見れば作らせた分と一時分の区別は無いので、貯金の計算はこちらを使う。
    /// 作らせた分だけを数えていたため、裏の作り足しが置いた分(一時分)が
    /// 一切貯金に入らず、「15分貯まったら止める」に永遠に到達しない不具合になっていた
    /// (実機で3時間半、作り足しが小説の最後まで走り続けた)。
    func summaryInAnyArea(novelID: String, chapterNumber: Int) -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for area in Area.allCases {
            let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber, area: area)
            lock.lock()
            let listing = listingUnsafe(directory: directory)
            lock.unlock()
            total = total + Self.summarize(listing.values)
        }
        return total
    }

    func summary(novelID: String) -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for chapterNumber in chapterNumbers(novelID: novelID) {
            total = total + summary(novelID: novelID, chapterNumber: chapterNumber)
        }
        return total
    }

    /// 指定ページより前(そのページ自身は含まない)に貯まっている分。
    /// 「もう聴き終わった所を消す」時に、消える量を先に見せるために使う。
    func summary(novelID: String, beforeChapterNumber: Int) -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for chapterNumber in chapterNumbers(novelID: novelID) where chapterNumber < beforeChapterNumber {
            total = total + summary(novelID: novelID, chapterNumber: chapterNumber)
        }
        return total
    }

    /// 指定ページより前(そのページ自身は含まない)を消す。
    func removeChapters(novelID: String, beforeChapterNumber: Int) {
        for chapterNumber in chapterNumbers(novelID: novelID) where chapterNumber < beforeChapterNumber {
            remove(novelID: novelID, chapterNumber: chapterNumber)
        }
    }

    func totalSummary() -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for novelID in cachedNovelIDs() {
            total = total + summary(novelID: novelID)
        }
        return total
    }

    /// キャッシュを持っている話の番号(小さい順)。
    func chapterNumbers(novelID: String) -> [Int] {
        let directory = novelDirectory(novelID: novelID)
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { Int($0) }.sorted()
    }

    /// キャッシュを持っている小説のID(管理画面用)。
    /// ディレクトリ名はハッシュで元に戻せないので、置いてある印から読む。
    func cachedNovelIDs() -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: versionedRoot.path) else { return [] }
        var result: [String] = []
        for name in names {
            let markerURL = versionedRoot.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(Self.novelIDMarkerFileName)
            guard let data = try? Data(contentsOf: markerURL),
                  let novelID = String(data: data, encoding: .utf8) else { continue }
            result.append(novelID)
        }
        return result
    }

    private static func summarize<S: Sequence>(_ entries: S) -> VoicevoxDiskCacheSummary where S.Element == Entry {
        var count = 0
        var seconds = 0.0
        var bytes = 0
        for entry in entries {
            count += 1
            seconds += entry.durationSeconds
            bytes += entry.byteCount
        }
        return VoicevoxDiskCacheSummary(entryCount: count, audioSeconds: seconds, byteCount: bytes)
    }

    // MARK: - 削除

    func remove(novelID: String) {
        for area in Area.allCases {
            let directory = novelDirectory(novelID: novelID, area: area)
            try? fileManager.removeItem(at: directory)
            forgetListings(under: directory)
        }
    }

    // MARK: - 一時分

    /// 一時分の合計(容量の表示と、上限の判定に使う)。
    func temporaryTotalSummary() -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for novelID in temporaryNovelIDs() {
            total = total + temporarySummary(novelID: novelID)
        }
        return total
    }

    func temporarySummary(novelID: String) -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        let novelDirectory = self.novelDirectory(novelID: novelID, area: .temporary)
        guard let names = try? fileManager.contentsOfDirectory(atPath: novelDirectory.path) else { return total }
        for name in names.compactMap({ Int($0) }).sorted() {
            let directory = novelDirectory.appendingPathComponent("\(name)", isDirectory: true)
            lock.lock()
            let listing = listingUnsafe(directory: directory)
            lock.unlock()
            total = total + Self.summarize(listing.values)
        }
        return total
    }

    /// 一時分を持っている小説のID。
    func temporaryNovelIDs() -> [String] {
        let root = areaRoot(.temporary)
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var result: [String] = []
        for name in names {
            let markerURL = root.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(Self.novelIDMarkerFileName)
            guard let data = try? Data(contentsOf: markerURL),
                  let novelID = String(data: data, encoding: .utf8) else { continue }
            result.append(novelID)
        }
        return result
    }

    /// ★別の小説を読み始めた時に、それ以外の小説の一時分を捨てる。
    ///
    /// 一時分は「今読んでいる小説のための物」と決めておくと、
    /// 消す条件がこれだけで済み、説明も1行で済む
    /// (「別の小説を読み始めると、前の小説の一時分は消えます」)。
    /// 複数の小説の一時分を上限の中で按分し合う仕組みは、
    /// 得られる物の割に説明が増える。
    /// - Returns: 消したバイト数。
    @discardableResult
    func removeTemporary(exceptNovelID novelID: String?) -> Int64 {
        var freed: Int64 = 0
        let root = areaRoot(.temporary)
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return 0 }
        let keepDirectoryName = novelID.map { Self.directoryName(novelID: $0) }
        for name in names where name != keepDirectoryName {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            freed += Self.byteCount(of: directory)
            try? fileManager.removeItem(at: directory)
            forgetListings(under: directory)
        }
        return freed
    }

    /// ★一時分が予算を超えていたら、**再生位置から遠い所から**捨てる。
    ///
    /// 更新時刻の古い順に消していた事があるが、それは踏んではいけない側だった。
    /// 作り足しは前から順に書くので、**再生ヘッドのすぐ前が一番古い**。
    /// 聴き終わった分を消し尽くすと、次に消えるのは「次に鳴らす1本」になり、
    ///   消される → 再生側が作り直す → その書き込みがまた刈り取りを呼ぶ
    /// という堂々巡りに入る(実機で、生成の6〜9割が作り直しに化けた)。
    ///
    /// なので捨てる順は話番号で決める:
    ///   1. 今読んでいる話より前(聴き終わった分)を、遠い方から
    ///   2. それでも収まらなければ、今読んでいる話より先を、遠い方から
    ///   3. **今読んでいる話には手を付けない**(消せば必ず作り直しになるため)
    /// 同じ話の中では、これまでどおり更新時刻の古い順(=前のブロックから)にする。
    ///
    /// - Parameter playbackChapterNumber: 今読んでいる話。分からない時(nil)は
    ///   これまでどおり更新時刻の古い順に消す。
    /// - Returns: 消したバイト数。
    @discardableResult
    func trimTemporary(novelID: String, keepingSeconds: Double, playbackChapterNumber: Int? = nil) -> Int64 {
        struct Candidate {
            let url: URL
            let directory: URL
            let chapterNumber: Int
            let modifiedAt: Date
            let durationSeconds: Double
            let byteCount: Int
        }
        let novelDirectory = self.novelDirectory(novelID: novelID, area: .temporary)
        guard let chapterNames = try? fileManager.contentsOfDirectory(atPath: novelDirectory.path) else { return 0 }
        var candidates: [Candidate] = []
        for chapterName in chapterNames.compactMap({ Int($0) }).sorted() {
            let directory = novelDirectory.appendingPathComponent("\(chapterName)", isDirectory: true)
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names {
                guard let parsed = Self.parse(fileName: name) else { continue }
                let url = directory.appendingPathComponent(name)
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                candidates.append(Candidate(
                    url: url,
                    directory: directory,
                    chapterNumber: chapterName,
                    modifiedAt: (attributes?[.modificationDate] as? Date) ?? Date.distantPast,
                    durationSeconds: parsed.durationSeconds,
                    byteCount: (attributes?[.size] as? Int) ?? 0))
            }
        }
        let total = candidates.reduce(0.0) { $0 + $1.durationSeconds }
        guard total > keepingSeconds else { return 0 }

        let order: [Candidate]
        if let playbackChapterNumber = playbackChapterNumber {
            // 今読んでいる話は消さないので、候補から外す。
            let behind = candidates.filter { $0.chapterNumber < playbackChapterNumber }
                .sorted { ($0.chapterNumber, $0.modifiedAt) < ($1.chapterNumber, $1.modifiedAt) }
            let ahead = candidates.filter { $0.chapterNumber > playbackChapterNumber }
                .sorted { ($1.chapterNumber, $1.modifiedAt) < ($0.chapterNumber, $0.modifiedAt) }
            order = behind + ahead
        } else {
            order = candidates.sorted { $0.modifiedAt < $1.modifiedAt }
        }

        var remaining = total
        var freed: Int64 = 0
        for candidate in order {
            if remaining <= keepingSeconds { break }
            try? fileManager.removeItem(at: candidate.url)
            forgetListings(under: candidate.directory)
            remaining -= candidate.durationSeconds
            freed += Int64(candidate.byteCount)
        }
        return freed
    }

    func remove(novelID: String, chapterNumber: Int) {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        try? fileManager.removeItem(at: directory)
        forgetListings(under: directory)
    }

    func removeAll() {
        try? fileManager.removeItem(at: rootDirectory)
        lock.lock()
        listings.removeAll()
        lock.unlock()
    }

    // MARK: - 版の掃除

    /// 今の版のディレクトリ(作らせた分・一時分)以外を、この置き場所から丸ごと消す。
    ///
    /// **この置き場所はこのアプリ専用**なので、
    /// 「今の版でない物は全部要らない」で言い切れる。
    /// 版を上げた時の古い分も、版を入れる前の時代の分も、これ1つで片付く。
    /// これがあるから「鍵の式を変えたら古いファイルが孤児として残り続ける」
    /// という事故が起きない。
    /// - Returns: 消したバイト数。
    @discardableResult
    func removeOutdatedLayouts() -> Int64 {
        guard let names = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path) else { return 0 }
        let current = Set(Area.allCases.map { Self.directoryName(of: $0, version: Self.formatVersion) })
        var freed: Int64 = 0
        for name in names where current.contains(name) == false {
            let url = rootDirectory.appendingPathComponent(name, isDirectory: true)
            freed += Self.byteCount(of: url)
            try? fileManager.removeItem(at: url)
        }
        if freed > 0 {
            lock.lock()
            listings.removeAll()
            lock.unlock()
        }
        return freed
    }

    private static func byteCount(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// 残す鍵の一覧に無いものが、どれだけあるか(消さずに数えるだけ)。
    /// 「今の設定だと x時間y分ぶん(zMB)が無駄になっています」を、
    /// 実際に消す前に見せるために使う。
    func summary(novelID: String, chapterNumber: Int, notIn keysToKeep: Set<String>) -> VoicevoxDiskCacheSummary {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        lock.lock()
        let listing = listingUnsafe(directory: directory)
        lock.unlock()
        return Self.summarize(listing.filter { keysToKeep.contains($0.key) == false }.values)
    }

    /// 残す鍵の一覧に無いものを消す。
    /// 読み替え辞書の変更等で内容が変わった時に使う。作り直しには数十分かかるので、
    /// 全消しではなく「変わった分だけ」を消せる必要がある。
    func removeEntries(novelID: String, chapterNumber: Int, notIn keysToKeep: Set<String>) {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        lock.lock()
        var listing = listingUnsafe(directory: directory)
        for (key, entry) in listing where keysToKeep.contains(key) == false {
            try? fileManager.removeItem(at: directory.appendingPathComponent(entry.fileName))
            listing.removeValue(forKey: key)
        }
        listings[directory.path] = listing
        lock.unlock()
    }

    private func forgetListings(under directory: URL) {
        lock.lock()
        for path in listings.keys where path == directory.path || path.hasPrefix(directory.path + "/") {
            listings.removeValue(forKey: path)
        }
        lock.unlock()
    }

    // MARK: - ディレクトリ

    private func prepareDirectories(novelID: String, chapterDirectory: URL, area: Area = .permanent) throws {
        if fileManager.fileExists(atPath: rootDirectory.path) == false {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        // 合成し直せる物であり1作品で数百MBになるため、バックアップには含めない。
        // (含めると利用者のバックアップ容量を無断で食い潰す事になる)
        var backupExclusionTarget = rootDirectory
        if (try? backupExclusionTarget.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? backupExclusionTarget.setResourceValues(values)
        }
        let root = areaRoot(area)
        if fileManager.fileExists(atPath: root.path) == false {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: chapterDirectory.path) == false {
            try fileManager.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        }
        let markerURL = novelDirectory(novelID: novelID, area: area).appendingPathComponent(Self.novelIDMarkerFileName)
        if fileManager.fileExists(atPath: markerURL.path) == false {
            try? Data(novelID.utf8).write(to: markerURL, options: .atomic)
        }
    }

    /// ディレクトリを1回読んで、鍵→実体の対応を作る。lock は呼び出し側で取っている前提。
    private func listingUnsafe(directory: URL) -> [String: Entry] {
        if let cached = listings[directory.path] { return cached }
        var listing: [String: Entry] = [:]
        if let names = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            for name in names {
                guard let parsed = Self.parse(fileName: name) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
                let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                listing[parsed.key] = Entry(fileName: name, byteCount: byteCount, durationSeconds: parsed.durationSeconds)
            }
        }
        listings[directory.path] = listing
        return listing
    }

    /// `<鍵>_<ミリ秒>.m4a` を読み解く。読めない名前(書きかけの tmp-… 等)は無視する。
    private static func parse(fileName: String) -> (key: String, durationSeconds: Double)? {
        guard fileName.hasSuffix(".\(fileExtension)") else { return nil }
        let base = String(fileName.dropLast(fileExtension.count + 1))
        guard let separator = base.lastIndex(of: "_") else { return nil }
        let key = String(base[base.startIndex..<separator])
        let millisecondsText = String(base[base.index(after: separator)...])
        guard key.isEmpty == false, let milliseconds = Int(millisecondsText) else { return nil }
        return (key, Double(milliseconds) / 1000)
    }
}
