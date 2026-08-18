//
//  VoicevoxVoiceModelConsent.swift
//  NovelSpeaker
//
//  音声モデルの利用規約への同意と、その記録。
//
//  VOICEVOX の音声モデルには**キャラクターごとに利用規約がある**。
//  取得前に提示して、同意を取り、クレジット表記を常設する、の3つが義務。
//
//  **規約は改訂される。**そのため「同意した事がある」という真偽値ではなく、
//  「いつ・どのキャラクターの・どの規約URLに同意したか」を1件ずつ残す。
//  後から「あの時どの規約に同意したのか」を辿れないと、
//  改訂された時に何が変わったのかを利用者に説明できない。
//
//  記録は**音声モデルを消しても残す**。
//  「同意して取得した」という事実は、ファイルの有無とは別の話であるため。
//
//  規約はキャラクターごとにあるが、**URLで束ねると実質20種弱**になる
//  (zunko.jp 系に何人も相乗りしている)。42行並べても読まれないので、
//  提示も記録も**規約URLを単位**にする。
//

import Foundation

/// 「いつ・誰の・どの規約に同意したか」1件分。
struct VoicevoxVoiceModelConsentRecord: Codable, Equatable {
    let termsURL: String
    /// この規約に相乗りしているキャラクターの名前(表示用)。
    let speakerNames: [String]
    /// 同じ名前のキャラクターが将来出てきても区別できるように uuid も残す。
    let speakerUUIDs: [String]
    /// 同意のきっかけになった音声モデル。
    let modelID: String?
    /// その時のカタログが指していた voicevox_vvm のタグ。
    let vvmTag: String?
    let agreedAt: Date
}

/// 同意の記録の置き場所。
///
/// UserDefaults ではなくファイルに置く。
/// UserDefaults は「設定」であって「記録」ではなく、
/// 設定の初期化や移行で消えると、同意の証跡としての意味を失うため。
class VoicevoxVoiceModelConsentStore {
    static let shared = VoicevoxVoiceModelConsentStore()

    let fileURL: URL
    private let lock = NSLock()
    private var cache: [VoicevoxVoiceModelConsentRecord]?

    /// - Parameter fileURL: 省略時は Application Support 配下。テストでは差し替える。
    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base.appendingPathComponent("VoicevoxVoiceModelConsent.json")
        }
    }

    // MARK: - 読み書き

    var records: [VoicevoxVoiceModelConsentRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    private func loadLocked() -> [VoicevoxVoiceModelConsentRecord] {
        if let cache = cache { return cache }
        guard let data = try? Data(contentsOf: fileURL) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([VoicevoxVoiceModelConsentRecord].self, from: data)) ?? []
        cache = loaded
        return loaded
    }

    private func saveLocked(_ records: [VoicevoxVoiceModelConsentRecord]) {
        cache = records
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 問い合わせ

    var consentedTermsURLs: Set<String> {
        return Set(records.map { $0.termsURL })
    }

    func hasConsented(termsURL: String) -> Bool {
        return records.contains { $0.termsURL == termsURL }
    }

    /// その規約に最後に同意した日時。
    func lastAgreedAt(termsURL: String) -> Date? {
        return records.filter { $0.termsURL == termsURL }.map { $0.agreedAt }.max()
    }

    // MARK: - 記録

    /// この音声モデルに含まれる全ての規約への同意を記録する。
    ///
    /// 同じ規約に再度同意した場合も、**上書きせず1件足す**。
    /// 規約が改訂された後にもう一度同意した事が分かるようにするため。
    @discardableResult
    func recordConsent(model: VoicevoxVoiceModelCatalog.VoiceModel,
                       vvmTag: String?,
                       agreedAt: Date = Date()) -> [VoicevoxVoiceModelConsentRecord] {
        let groups = VoicevoxVoiceModelConsentText.groups(of: model)
        let added: [VoicevoxVoiceModelConsentRecord] = groups.compactMap { group in
            guard let termsURL = group.termsURL else { return nil }
            return VoicevoxVoiceModelConsentRecord(
                termsURL: termsURL,
                speakerNames: group.speakers.map { $0.name },
                speakerUUIDs: group.speakers.map { $0.uuid },
                modelID: model.id,
                vvmTag: vvmTag,
                agreedAt: agreedAt)
        }
        guard added.isEmpty == false else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let merged = loadLocked() + added
        saveLocked(merged)
        return added
    }

    /// テスト用。実運用では消さない(消すと証跡でなくなる)。
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        saveLocked([])
    }
}

/// 同意ダイアログに出す文面。UIから切り離してあるのは、
/// 「規約URLが1つも無いキャラクターが混ざっていないか」等を試験で見るため。
enum VoicevoxVoiceModelConsentText {
    struct Group: Equatable {
        let termsURL: String?
        let speakers: [VoicevoxVoiceModelCatalog.Speaker]

        var speakerNames: String {
            return speakers.map { $0.name }.joined(separator: " / ")
        }

        /// ボタンに出す短い表記。URLそのものはボタンに入り切らない。
        var hostName: String {
            guard let termsURL = termsURL,
                  let host = URL(string: termsURL)?.host else { return "" }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    /// 同じ規約URLのキャラクターを束ねる。
    static func groups(of model: VoicevoxVoiceModelCatalog.VoiceModel) -> [Group] {
        var order: [String] = []
        var grouped: [String: [VoicevoxVoiceModelCatalog.Speaker]] = [:]
        for speaker in model.speakers {
            let key = speaker.termsURL ?? ""
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(speaker)
        }
        return order.map { key in
            Group(termsURL: key.isEmpty ? nil : key, speakers: grouped[key] ?? [])
        }
    }

    /// クレジット表記。**話者名から組み立ててはいけない**ので、
    /// カタログの credit をそのまま使い、無い時だけ諦めて名前で作る。
    static func creditLines(of model: VoicevoxVoiceModelCatalog.VoiceModel) -> [String] {
        return model.speakers.map { $0.credit ?? "VOICEVOX:\($0.name)" }
    }

    static func megabytesText(_ byteSize: Int64) -> String {
        return String(format: "%.0fMB", Double(byteSize) / 1024.0 / 1024.0)
    }

    /// 取得前に出す本文。
    static func message(model: VoicevoxVoiceModelCatalog.VoiceModel,
                        requestedStyleDisplayName: String?,
                        termsPageURL: String?) -> String {
        var lines: [String] = []
        if let requestedStyleDisplayName = requestedStyleDisplayName {
            lines.append("「\(requestedStyleDisplayName)」を使うには、"
                         + "音声モデル \(model.id).vvm (\(megabytesText(model.byteSize))) の取得が必要です。")
        } else {
            lines.append("音声モデル \(model.id).vvm (\(megabytesText(model.byteSize))) を取得します。")
        }
        lines.append("")
        lines.append("このファイルには次のキャラクターの音声が入っています。"
                     + "それぞれの利用規約に同意する必要があります。")
        lines.append("")
        for group in groups(of: model) {
            lines.append("・\(group.speakerNames)")
            if let termsURL = group.termsURL {
                lines.append("    \(termsURL)")
            } else {
                lines.append("    (規約の場所が分かりませんでした)")
            }
            for speaker in group.speakers {
                guard let policyText = speaker.policyText, policyText.isEmpty == false else { continue }
                lines.append("    \(policyText)")
            }
        }
        lines.append("")
        lines.append("作った音声を公開する場合は、次のようなクレジット表記が必要です。")
        for credit in creditLines(of: model) {
            lines.append("・\(credit)")
        }
        if let termsPageURL = termsPageURL {
            lines.append("")
            lines.append("音声モデル全体の規約: \(termsPageURL)")
        }
        lines.append("")
        lines.append("ファイルは VOICEVOX の公式の配布場所から取得します。"
                     + "モバイル通信では取得せず、Wi-Fi に繋がるまで待ちます。")
        return lines.joined(separator: "\n")
    }
}
