//
//  GatherStorySpeechSettingsBenchmarkTest.swift
//  NovelSpeakerTests
//
//  読み上げ設定の組み立て(GatherStorySpeechSettings)のどこが重いのかを、
//  実機と同じくらいのデータ量を Realm に用意して測る。
//
//  実機の計測(iPhone)では1作品あたり約0.55秒かかっており、内訳は
//    話者=125ms 会話文=234ms 間の設定=0ms 標準辞書の鍵集合=0ms 読み替え辞書(5354件)=57ms
//  だった。**作品数に比例**するので、作品を沢山持っている人ほど効く。
//  ここでは何が効いているのかを手元で再現して、対策の効果も確かめられるようにする。
//

import XCTest
import RealmSwift
@testable import NovelSpeaker

class GatherStorySpeechSettingsBenchmarkTest: XCTestCase {

    private static let novelIDPrefix = "GatherBenchmark-novel-"

    /// 実機に近いデータを用意する。
    /// - 読み替え辞書は標準辞書ぶん(5000件超)
    /// - 会話文の話者割り当ては数件(全小説向け)
    private func prepareRealm(novelCount: Int, speechModCount: Int, sectionConfigCount: Int) {
        RealmUtil.Write { realm in
            for index in 0..<novelCount {
                let novel = RealmNovel()
                novel.novelID = "\(Self.novelIDPrefix)\(index)"
                novel.title = "計測用小説\(index)"
                realm.add(novel, update: .modified)
            }
            for index in 0..<speechModCount {
                let mod = RealmSpeechModSetting()
                mod.before = "計測用読み替え\(index)"
                mod.after = "けいそくよう\(index)"
                mod.isUseRegularExpression = false
                // 実機と同じく、大半は「全小説向け」に登録されている。
                mod.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                realm.add(mod, update: .modified)
            }
            for index in 0..<sectionConfigCount {
                let config = RealmSpeechSectionConfig()
                config.startText = "「\(index)"
                config.endText = "」"
                config.targetNovelIDArray.append(RealmSpeechSectionConfig.anyTarget)
                realm.add(config, update: .modified)
            }
        }
    }

    private func cleanUpRealm() {
        RealmUtil.Write { realm in
            let novels = realm.objects(RealmNovel.self).filter("novelID BEGINSWITH %@", Self.novelIDPrefix)
            realm.delete(novels)
            let mods = realm.objects(RealmSpeechModSetting.self).filter("before BEGINSWITH %@", "計測用読み替え")
            realm.delete(mods)
            let configs = realm.objects(RealmSpeechSectionConfig.self).filter("endText = %@ AND startText BEGINSWITH %@", "」", "「")
            realm.delete(configs)
        }
    }

    override func tearDownWithError() throws {
        cleanUpRealm()
        try super.tearDownWithError()
    }

    private func measureSeconds(_ label: String, iterations: Int = 1, _ block: () -> Void) {
        let start = Date()
        for _ in 0..<iterations { block() }
        let elapsed = Date().timeIntervalSince(start) / Double(iterations)
        NSLog("NovelSpeaker.Benchmark: %@ = %.1f ms", label, elapsed * 1000)
    }

    /// 1作品ぶんの設定組み立てに、どれだけ掛かるか。
    func testGatherCostWithRealisticData() throws {
        prepareRealm(novelCount: 10, speechModCount: 5000, sectionConfigCount: 5)
        let novelID = "\(Self.novelIDPrefix)0"

        StoryTextClassifier.isGatherStorySpeechSettingsProfilingEnabled = true
        defer { StoryTextClassifier.isGatherStorySpeechSettingsProfilingEnabled = false }

        measureSeconds("設定の組み立て(1作品・読み替え5000件)", iterations: 3) {
            _ = StoryTextClassifier.GatherStorySpeechSettings(novelID: novelID)
        }

        // 段階ごとに、何が効いているのかを個別にも測る。
        RealmUtil.RealmBlock { realm in
            measureSeconds("・小説の検索+既定話者", iterations: 5) {
                _ = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.defaultSpeakerWith(realm: realm)
            }
            measureSeconds("・会話文の話者割り当ての検索", iterations: 5) {
                _ = RealmSpeechSectionConfig.SearchSettingsFor(realm: realm, novelID: novelID).map { Array($0) }
            }
            measureSeconds("・間の設定の検索", iterations: 5) {
                _ = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm)?.map({ SpeechWaitConfig(from: $0) })
            }
            measureSeconds("・読み替え辞書の検索+変換", iterations: 5) {
                _ = RealmSpeechModSetting.SearchSettingsFor(realm: realm, novelID: novelID)?.map { SpeechModSetting(from: $0) }
            }

            // 段階の合計と、関数全体の時間が大きく食い違っている。
            // 差分は StorySpeechSettings の init(=並べ替え・重複除去・索引作り)しかないので、
            // そこを個別に測る。
            let mods = RealmSpeechModSetting.SearchSettingsFor(realm: realm, novelID: novelID)?.map { SpeechModSetting(from: $0) } ?? []
            NSLog("NovelSpeaker.Benchmark: 読み替え辞書 %d件", mods.count)
            let nonRegexp = mods.filter { $0.isUseRegularExpression == false }
            measureSeconds("・並べ替えだけ", iterations: 3) {
                _ = StoryTextClassifier.SpeechModArraySort(speechModArray: nonRegexp)
            }
            let sorted = StoryTextClassifier.SpeechModArraySort(speechModArray: nonRegexp)
            measureSeconds("・重複除去だけ", iterations: 3) {
                _ = StoryTextClassifier.UniqSpeechModArray(speechModArray: sorted)
            }
            let uniqued = StoryTextClassifier.UniqSpeechModArray(speechModArray: sorted)
            measureSeconds("・索引作りだけ", iterations: 3) {
                _ = StoryTextClassifier.IndexSpeechModArray(sortedSpeechModArray: uniqued)
            }
            measureSeconds("・isUseRegularExpression での振り分けだけ", iterations: 3) {
                _ = mods.filter { $0.isUseRegularExpression == false }
                _ = mods.filter { $0.isUseRegularExpression }
            }
        }
    }

    /// 作品数に比例して増える事の確認(まとめて処理する時に効く)。
    func testGatherCostScalesWithNovelCount() throws {
        prepareRealm(novelCount: 20, speechModCount: 5000, sectionConfigCount: 5)
        let start = Date()
        for index in 0..<20 {
            _ = StoryTextClassifier.GatherStorySpeechSettings(novelID: "\(Self.novelIDPrefix)\(index)")
        }
        let elapsed = Date().timeIntervalSince(start)
        NSLog("NovelSpeaker.Benchmark: 20作品ぶんの設定組み立て(毎回Realmを開く) = %.0f ms (1作品 %.1f ms)", elapsed * 1000, elapsed / 20 * 1000)

        // Realm を1回だけ開いて済ませた場合。
        let sharedStart = Date()
        RealmUtil.RealmBlock { realm in
            for index in 0..<20 {
                _ = StoryTextClassifier.GatherStorySpeechSettings(realm: realm, novelID: "\(Self.novelIDPrefix)\(index)")
            }
        }
        let sharedElapsed = Date().timeIntervalSince(sharedStart)
        NSLog("NovelSpeaker.Benchmark: 20作品ぶんの設定組み立て(Realmは1回) = %.0f ms (1作品 %.1f ms)", sharedElapsed * 1000, sharedElapsed / 20 * 1000)
    }
}
