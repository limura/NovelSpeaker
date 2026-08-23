//
//  VoicevoxReadingReconcileTool.swift
//  NovelSpeakerTests
//
//  標準の読み替え辞書を VOICEVOX に持っていくための、下ごしらえの道具。
//
//  なぜ要るか:
//  標準の読み替え辞書は5000件あり、その大半が「システムの音声で変な読みになる語」に
//  かな読みを当てたもの(「魔石」→「ませき」)である。
//  VOICEVOX でも同じ語が変な読みになる事はあるが、**VOICEVOX が既に正しく読める語も多い**。
//  全部を人が耳で確かめ直すのは現実的ではないので、まず機械で振り分ける。
//
//  やり方:
//  VOICEVOX の解析器(Open JTalk)に「読み替え前」と「読み替え後」の両方を読ませ、
//  出てくるカタカナを突き合わせる。
//   - 一致 → VOICEVOX は既に意図どおり読めている。**辞書に入れる必要が無い**。
//   - 不一致 → 辞書に入れる候補。読みとアクセントの初期値も一緒に出す。
//  解析器は実際に喋る時と同じ物なので、この答えは本物である。
//  音声モデルは要らない(読みとアクセントは Open JTalk だけで出る)。
//
//  使い方(普段のテストでは走らない。入力ファイルを置いた時だけ動く):
//    cp DefaultSpeechModList-tagged.json /tmp/voicevox-reconcile-input.json
//    xcodebuild ... -only-testing:NovelSpeakerTests/VoicevoxReadingReconcileTool
//    結果は /tmp/voicevox-reconcile-worklist.tsv に出る。
//
//  環境変数ではなく決まった場所のファイルにしてあるのは、
//  xcodebuild からアプリに載る単体テストへ環境変数を渡す手段が無いため
//  (TEST_RUNNER_ 接頭辞は UI テストの runner 向けで、こちらには届かない)。
//  シミュレータの中からでも、母艦の /tmp はそのまま見える。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxReadingReconcileTool: XCTestCase {

    /// 突き合わせたい読み替え辞書(DefaultSpeechModList 形式の JSON)。
    static let inputPath = "/tmp/voicevox-reconcile-input.json"
    /// 人が見るべき物だけを並べた一覧。
    static let outputPath = "/tmp/voicevox-reconcile-worklist.tsv"

    private struct Entry {
        let before: String
        let after: String
        let isRegexp: Bool
        let engineTypes: [String]
    }

    private func setUpAnalyzer() async throws -> VoicevoxCore {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else {
            throw XCTSkip("同梱の open_jtalk_dic_utf_8-1.11 がバンドルに見つかりません")
        }
        let core = VoicevoxCore.shared
        // 読みとアクセントだけなら音声モデルは要らない。
        try await core.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [])
        return core
    }

    private func loadEntries(from url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw XCTSkip("JSON の形が配列ではありません: \(url.path)")
        }
        return array.compactMap { dictionary in
            // 先頭に説明用の要素が入っているので、before/after のある物だけを拾う。
            guard let before = dictionary["before"] as? String,
                  let after = dictionary["after"] as? String else { return nil }
            return Entry(before: before,
                         after: after,
                         isRegexp: (dictionary["isRegexp"] as? Bool) ?? false,
                         engineTypes: (dictionary["targetSpeechEngineTypeArray"] as? [String]) ?? [])
        }
    }

    /// ★比較はカタカナの字面ではなく「音」で行う。
    ///
    /// Open JTalk は、辞書から引いた読みでは長音を「セエジャク」「マドオ」のように
    /// 母音で綴るが、こちらが与えたかな(「せいじゃく」)はそのまま「セイジャク」になる。
    /// 字面で比べると**同じ音なのに違う**と判定してしまい、直す必要の無い語まで
    /// 一覧に載ってしまう(実際に「霊体 レエタイ → レイタイ」等が混ざっていた)。
    ///
    /// モーラには子音と母音が分解されて入っているので、そちらを並べて比べれば
    /// 綴り方に左右されずに済む。
    /// 母音を小文字に揃えるのは、無声化(母音が大文字で返る)の違いを無視するため。
    /// 無声化は前後の音で決まるもので、こちらが直したい「読み」の違いではない。
    ///
    /// さらに長音を揃える。解析器は、辞書から引いた読みでは「レエタイ」と母音で綴るが、
    /// こちらが与えたかな(「れいたい」)は字のまま「レイタイ」になる。
    /// 同じ音なので、エ段+イ → エ段+エ、オ段+ウ → オ段+オ に寄せてから比べる。
    /// (これをしないと、直す必要の無い語が何百件も一覧に載る)
    private static func sound(of phrases: [VoicevoxAccentPhrase]) -> String {
        var result: [String] = []
        var previousVowel = ""
        for mora in phrases.allMoras {
            let consonant = (mora.consonant ?? "").lowercased()
            var vowel = mora.vowel.lowercased()
            if consonant.isEmpty {
                if vowel == "i", previousVowel == "e" { vowel = "e" }
                if vowel == "u", previousVowel == "o" { vowel = "o" }
            }
            result.append(consonant + vowel)
            previousVowel = vowel
        }
        return result.joined(separator: "-")
    }

    /// 突き合わせて、人が見るべき物だけの一覧を書き出す。
    func testGenerateWorkList() async throws {
        let inputPath = Self.inputPath
        let outputPath = Self.outputPath
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw XCTSkip("\(inputPath) が無いので何もしません")
        }
        let core = try await setUpAnalyzer()
        let entries = try loadEntries(from: URL(fileURLWithPath: inputPath))
        XCTAssertGreaterThan(entries.count, 0, "読み替えが1件も読めていません")

        var lines: [String] = ["状態\t読み替え前\t読み替え後\tVOICEVOXの今の読み\t入れたい読み\tアクセント\tモーラ数\t対象エンジン\t備考"]
        var counts: [String: Int] = [:]
        for entry in entries {
            var status = ""
            var note = ""
            var currentKana = ""
            var intendedKana = ""
            var accent = ""
            var moraCount = ""

            if entry.isRegexp {
                status = "対象外"
                note = "正規表現(辞書に入れられない)"
            } else {
                let current = (try? await core.analyze(text: entry.before)) ?? []
                let intended = (try? await core.analyze(text: entry.after)) ?? []
                currentKana = current.kana
                intendedKana = intended.kana
                if current.isEmpty || intended.isEmpty {
                    status = "対象外"
                    note = "解析できない"
                } else if Self.sound(of: current) == Self.sound(of: intended) {
                    status = "不要"
                    note = "VOICEVOXは既に意図どおり読んでいる"
                } else {
                    status = "要"
                    moraCount = "\(intended.allMoras.count)"
                    if intended.count == 1 {
                        accent = "\(intended[0].accent)"
                    } else {
                        // 複数のアクセント句に割れた = 語ではなく文として読まれている。
                        // 辞書は1語単位なので、そのままでは入れられない事が多い。
                        note = "読みが\(intended.count)つの句に割れている(要確認)"
                        accent = intended.map({ "\($0.accent)" }).joined(separator: "/")
                    }
                }
            }
            counts[status, default: 0] += 1
            lines.append([status, entry.before, entry.after, currentKana, intendedKana,
                          accent, moraCount, entry.engineTypes.joined(separator: "+"), note]
                .map({ $0.replacingOccurrences(of: "\t", with: " ") })
                .joined(separator: "\t"))
        }

        try lines.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("=== 読み替えの突き合わせ 結果 ===")
        print("入力: \(entries.count)件 -> \(outputPath)")
        for (status, count) in counts.sorted(by: { $0.value > $1.value }) {
            print("  \(status): \(count)件")
        }
    }
}
