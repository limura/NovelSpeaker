//
//  RealmSpeakerSettingDefaultValueTest.swift
//  NovelSpeakerTests
//
//  Realm のモデルの「既定値」に重い処理を書いてはいけない、という事のテスト。
//
//  Realm は保存済みのオブジェクトを取り出す時にも Swift の既定値初期化子を走らせるので、
//  既定値に重い処理を書くと **1件取り出すごとに** その処理が走る。
//
//  実機(iPhone)の計測では、話者設定がたった4件しか無いのに
//    realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", ...).first
//  1回に118msかかっていた。voiceIdentifier の既定値 GuessBestVoiceIdentifier() が
//  AVSpeechSynthesisVoice.speechVoices() を呼んでおり、これが実機で100ms級だったため。
//  読み上げ設定の組み立てが1作品0.5秒かかっていた主因がこれだった。
//  (シミュレータは入っている音声が少なく速いので、母艦での計測では見えなかった)
//

import XCTest
import AVFoundation
import RealmSwift
@testable import NovelSpeaker

class RealmSpeakerSettingDefaultValueTest: XCTestCase {

    // 既定の音声の判定は、何度呼んでも1回ぶんの手間で済む事。
    func testGuessBestVoiceIdentifierIsCached() {
        // 1回目で覚えるので、まず1回呼んでおく。
        let first = RealmSpeakerSetting.GuessBestVoiceIdentifier()

        let start = Date()
        for _ in 0..<1000 {
            XCTAssertEqual(RealmSpeakerSetting.GuessBestVoiceIdentifier(), first)
        }
        let elapsed = Date().timeIntervalSince(start)
        NSLog("NovelSpeaker.Benchmark: GuessBestVoiceIdentifier 1000回 = %.1f ms", elapsed * 1000)
        // 覚えていなければ speechVoices() が1000回走る事になる。
        // 実機では1回100ms級なので100秒かかる計算になり、桁で落ちる。
        XCTAssertLessThan(elapsed, 1.0, "既定の音声の判定が毎回やり直されている(オブジェクトを作る度に走る)")
    }

    // オブジェクトを沢山作っても、既定値の計算で待たされない事。
    func testCreatingManySpeakerSettingsIsFast() {
        _ = RealmSpeakerSetting.GuessBestVoiceIdentifier()
        let start = Date()
        for _ in 0..<1000 {
            _ = RealmSpeakerSetting()
        }
        let elapsed = Date().timeIntervalSince(start)
        NSLog("NovelSpeaker.Benchmark: RealmSpeakerSetting を1000個作る = %.1f ms", elapsed * 1000)
        XCTAssertLessThan(elapsed, 1.0, "話者設定を作るのが遅い(既定値に重い処理が入っている)")
    }

    // 参考: 端末に入っている音声の一覧の取得そのものが、どれだけ掛かるか。
    // ここが遅い端末ほど、覚えておく効果が大きい。
    func testSpeechVoicesCostForReference() {
        let start = Date()
        _ = AVSpeechSynthesisVoice.speechVoices()
        NSLog("NovelSpeaker.Benchmark: AVSpeechSynthesisVoice.speechVoices() = %.1f ms",
              Date().timeIntervalSince(start) * 1000)
    }
}
