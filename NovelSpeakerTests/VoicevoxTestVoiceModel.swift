//
//  VoicevoxTestVoiceModel.swift
//  NovelSpeakerTests
//
//  テストで使う 0.vvm の在り処。
//
//  **アプリ本体にはもう同梱していない。**
//  同梱すると ことせかい が VVM の再配布者になるため、
//  利用者には公式から取得してもらう方針にした
//  (DESIGN_VOICEVOXの音声モデル取得.md §4)。
//  一方でテストは実物が無いと合成まで確かめられないので、
//  テストバンドルにだけ入れてある。
//
//  実体は git に入っていないので、clone した直後は
//  scripts/fetch_voicevox_vendor.sh を走らせないと存在しない。
//  その時はテストを落とさず飛ばす(取ってきていないだけで、壊れてはいない)。
//

import XCTest
@testable import NovelSpeaker

enum VoicevoxTestVoiceModel {
    /// テストバンドルに入っている 0.vvm。無ければ nil。
    static func path() -> String? {
        return Bundle(for: VoicevoxTestVoiceModelMarker.self).path(forResource: "0", ofType: "vvm")
    }

    /// 取ってきていない時はテストを飛ばす。
    static func requirePath() throws -> String {
        guard let path = path() else {
            throw XCTSkip("テスト用の 0.vvm がありません。scripts/fetch_voicevox_vendor.sh を実行してください")
        }
        return path
    }
}

/// テストバンドルを指すためだけのクラス。
private class VoicevoxTestVoiceModelMarker {}
