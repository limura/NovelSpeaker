//
//  VoicevoxUserDictionary.swift
//  NovelSpeaker
//
//  「読みの修正」で指定された VOICEVOX 用の読みとアクセントを、
//  VOICEVOX 本体のユーザー辞書として組み立てる役。
//
//  なぜ要るか:
//  「読みの修正」は合成前に**文字列を置換する**仕組みなので、読みは変えられても
//  **アクセントは変えられない**。「橋」と「箸」と「端」はどれも「ハシ」なので、
//  カタカナに置き換えても言い分けられない。
//  アクセントを指定できるのは VOICEVOX 本体のユーザー辞書だけである。
//
//  ★surface(表記)に何を入れるかが、この仕組みの肝。
//
//  ユーザー辞書は「VOICEVOX が読む文字列」に対して効く。つまり、
//  その読み替えが VOICEVOX にも適用されるかどうかで、入れるべき文字列が変わる。
//
//  | その行が VOICEVOX に適用されるか | surface |
//  |---|---|
//  | される      | **読み替え後**(VOICEVOX はその文字列を読むので) |
//  | されない    | **読み替え前**(VOICEVOX には元の文字列が届くので) |
//
//  例: 「実際」→「"実際"」は端末の音声の癖を避けるための引用符付けで、
//  VOICEVOX には適用しない。この時 VOICEVOX が目にするのは「実際」なので、
//  surface は「実際」でなければならない。「"実際"」を登録しても一致しない
//  (そもそも記号入りの表記は VOICEVOX に受け付けてもらえない)。
//

import Foundation

/// VOICEVOX 本体のユーザー辞書に登録する1語。
struct VoicevoxUserDictionaryEntry: Equatable {
    /// VOICEVOX が読む文字列。
    let surface: String
    /// 読み。**カタカナでなければ VOICEVOX が受け付けない。**
    let pronunciation: String
    /// アクセント核の位置。0 = 平板(下がらない)、N = N モーラ目の後で下がる。
    let accentType: Int
    /// 優先度(0〜10)。大きいほど採用されやすい。
    ///
    /// Open JTalk は**長い語が自動的に勝つ仕組みではない**。
    /// 文全体のコストが最小になる分割を選ぶだけなので、
    /// 「黒剣騎士団」と「黒剣」の両方を登録した場合に長い方が勝つ保証は無い。
    /// 勝たせたい方はここを上げてもらう必要がある。
    let priority: Int

    /// 既定の優先度。VOICEVOX 側の既定値に合わせてある。
    static let defaultPriority = 5
    /// 「優先する」を選んだ時の値。
    static let preferredPriority = 10
    static let priorityRange = 0...10
}

enum VoicevoxUserDictionaryBuilder {

    /// 「読みの修正」1行から、ユーザー辞書に登録する1語を作る。
    ///
    /// - Parameters:
    ///   - before: 読み替え前。
    ///   - after: 読み替え後。
    ///   - isUseRegularExpression: 正規表現マッチか。
    ///   - isAppliedToVoicevox: この読み替えが VOICEVOX にも適用されるか。
    ///   - pronunciation: VOICEVOX に渡す読み(カタカナ)。空なら登録しない。
    ///   - accentType: アクセント核の位置。
    ///   - priority: 優先度。
    /// - Returns: 登録すべき語。登録できない/する必要が無い場合は nil。
    static func entry(before: String,
                      after: String,
                      isUseRegularExpression: Bool,
                      isAppliedToVoicevox: Bool,
                      pronunciation: String,
                      accentType: Int,
                      priority: Int) -> VoicevoxUserDictionaryEntry? {
        // 読みが無いものは、そもそもこの機能を使っていない行。
        let pronunciation = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pronunciation.isEmpty == false else { return nil }
        // 正規表現マッチの行では登録できない。
        // 読み替え後が "$1" のようなテンプレートで、実際に何という文字列になるのかが
        // 登録の時点では決まらないため。画面でもこの場合は欄を出さない。
        guard isUseRegularExpression == false else { return nil }
        // ★VOICEVOX が実際に目にする文字列を表記にする(冒頭のコメント参照)。
        let surface = isAppliedToVoicevox ? after : before
        guard surface.isEmpty == false else { return nil }
        return VoicevoxUserDictionaryEntry(
            surface: surface,
            pronunciation: pronunciation,
            accentType: max(0, accentType),
            priority: min(max(priority, VoicevoxUserDictionaryEntry.priorityRange.lowerBound),
                          VoicevoxUserDictionaryEntry.priorityRange.upperBound))
    }

    /// 同じ表記が複数あった場合に1つへ絞る(優先度の高い方を残す)。
    ///
    /// VOICEVOX は同じ表記を2つ登録できないので、こちらで決める必要がある。
    /// 優先度も同じなら、後から出てきた方を残す(利用者が後で足した方が新しい意図)。
    static func deduplicated(_ entries: [VoicevoxUserDictionaryEntry]) -> [VoicevoxUserDictionaryEntry] {
        var bySurface: [String: VoicevoxUserDictionaryEntry] = [:]
        for entry in entries {
            if let existing = bySurface[entry.surface], existing.priority > entry.priority { continue }
            bySurface[entry.surface] = entry
        }
        // 並びを決めておかないと、同じ内容でも署名が変わってキャッシュが無駄になる。
        return bySurface.values.sorted { $0.surface < $1.surface }
    }

    /// この本文に効いてくるユーザー辞書の署名。
    ///
    /// ディスクキャッシュの鍵に混ぜるために使う。
    ///
    /// なぜ全体の版番号ではいけないのか:
    /// 辞書を1語直しただけで全部の鍵が変わると、何時間ぶんもの作り置きが
    /// 一斉に無駄になる。**その語を含む本文の鍵だけ**が変わるようにする。
    ///
    /// 何も効かない本文では空文字列を返す。これにより、
    /// ユーザー辞書を使っていない限り鍵はこれまでと同じままになる。
    static func signature(forText text: String, entries: [VoicevoxUserDictionaryEntry]) -> String {
        var parts: [String] = []
        for entry in entries where text.contains(entry.surface) {
            parts.append("\(entry.surface)\u{1}\(entry.pronunciation)\u{1}\(entry.accentType)\u{1}\(entry.priority)")
        }
        if parts.isEmpty { return "" }
        return parts.joined(separator: "\u{2}")
    }
}

/// アクセントの見せ方。
///
/// **数値では選べない。**「橋」なのか「箸」なのかは無意識に言い分けているもので、
/// 「アクセント核は1です」と言われて分かる人はほとんどいない。
/// 型の名前と、下がる位置を示した読みを並べて、聞いて選んでもらう。
enum VoicevoxAccentDisplay {

    /// 下がる位置に印を付けた読み。
    ///
    /// 「ハꜜシ」のように、**下がる直前のモーラの後ろ**に ꜜ(U+A71C)を置く。
    /// 日本語のアクセント表記として一般的な書き方で、桁を揃える必要が無い
    /// (モーラは「キャ」のように2文字になる事があるので、上下に線を引く形だと揃わない)。
    static func markedKana(moras: [String], accentType: Int) -> String {
        guard accentType > 0, accentType <= moras.count else { return moras.joined() }
        var result = ""
        for (index, mora) in moras.enumerated() {
            result += mora
            if index + 1 == accentType { result += "\u{A71C}" }
        }
        return result
    }

    /// アクセント型の呼び名。
    ///
    /// 平板と尾高は**その語だけでは同じ音になる**(違うのは後ろに付く助詞が
    /// 下がるかどうかだけ)。聞き比べてもらうには助詞を付けて鳴らす必要がある。
    static func typeName(accentType: Int, moraCount: Int) -> String {
        if accentType <= 0 { return NSLocalizedString("VoicevoxAccent_TypeFlat", comment: "平板") }
        if accentType == 1 { return NSLocalizedString("VoicevoxAccent_TypeHead", comment: "頭高") }
        if accentType >= moraCount { return NSLocalizedString("VoicevoxAccent_TypeTail", comment: "尾高") }
        return NSLocalizedString("VoicevoxAccent_TypeMiddle", comment: "中高")
    }

    /// 聞き比べる時に鳴らす文字列。
    ///
    /// ★語を単独で鳴らしてはいけない。
    /// 平板(0)と尾高(モーラ数と同じ値)は、その語だけでは**まったく同じ音**になる。
    /// 助詞を付けて初めて違いが出る(実物で確認済み・VoicevoxAccentTest)。
    static let previewParticle = "が"
    static func previewText(kana: String) -> String {
        return kana + previewParticle
    }

    /// 選べるアクセント型の一覧(0 〜 モーラ数)。
    static func candidates(moraCount: Int) -> [Int] {
        guard moraCount > 0 else { return [] }
        return Array(0...moraCount)
    }
}

/// 今この端末で有効なユーザー辞書。
///
/// ディスクキャッシュの鍵(`VoicevoxDiskCacheStore.key`)と、
/// VOICEVOX 本体への登録の両方から参照される。
final class VoicevoxUserDictionary {
    static let shared = VoicevoxUserDictionary()

    private let lock = NSLock()
    private var entriesUnsafe: [VoicevoxUserDictionaryEntry] = []

    private init() {}

    var entries: [VoicevoxUserDictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entriesUnsafe
    }

    /// 中身が変わったかどうかを返す(変わっていなければ作り直しも捨てるのも要らない)。
    @discardableResult
    func replace(with newEntries: [VoicevoxUserDictionaryEntry]) -> Bool {
        let deduplicated = VoicevoxUserDictionaryBuilder.deduplicated(newEntries)
        lock.lock()
        let changed = deduplicated != entriesUnsafe
        entriesUnsafe = deduplicated
        lock.unlock()
        return changed
    }

    /// この本文に効いてくる辞書の署名(キャッシュの鍵用)。
    func signature(forText text: String) -> String {
        return VoicevoxUserDictionaryBuilder.signature(forText: text, entries: entries)
    }
}
