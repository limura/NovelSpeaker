//
//  WatchSpeechSettings.swift
//  NovelSpeaker
//
//  Watch 単体再生用の発話設定一式。iPhone 側で Realm 上の設定から生成して transferFile で送り、
//  Watch 側は保存しておいて StoryTextClassifier への入力(plain struct)に変換して使う。
//  WatchMessage.swift と同じく、Foundation 以外に依存しないこと。
//
//  v1.5 時点では「全小説対象(anyTarget)のグローバル設定のみ」を扱う。
//  小説別の話者・小説別の読み替えは未対応(必要になったら本文転送 JSON に相乗りさせる想定)。
//

import Foundation

struct WatchSpeechSettings: Codable {
    struct Speaker: Codable {
        var pitch: Float = 1.0
        var rate: Float = 0.5
        var volume: Float = 1.0
        var type: String = "AVSpeechSynthesizer"
        var voiceIdentifier: String = ""
        var locale: String = "ja-JP"
    }
    struct SectionConfig: Codable {
        var startText: String
        var endText: String
        var speaker: Speaker
    }
    struct WaitConfig: Codable {
        var targetText: String
        var delayTimeInSec: Float
    }
    struct Mod: Codable {
        var before: String
        var after: String
        var isRegexp: Bool
        /// 空 = 全エンジン対象。標準の読み替え辞書由来のエントリは ["AVSpeechSynthesizer"]
        var targetEngines: [String]
    }

    var defaultSpeaker = Speaker()
    var sectionConfigs: [SectionConfig] = []
    var waitConfigs: [WaitConfig] = []
    var speechMods: [Mod] = []
    /// URL を読まない設定。正規表現本体は StoryTextClassifier.ignoreURIStringRegexpPattern を
    /// 両ターゲットで共有しているので、フラグだけ送って Watch 側で読み替えに変換する
    var isIgnoreURIStringSpeechEnabled = false
    /// ルビの読み替えは本文に依存するので、フラグだけ送って Watch 側で章毎に生成する
    var isOverrideRubyEnabled = false
    var notRubyCharactorStringArray = ""
    var isDisableNarouRuby = false
    var updatedAt = Date(timeIntervalSince1970: 0)

    /// transferFile の metadata でファイル種別(本文か発話設定か)を区別するためのキーと値
    static let transferTypeKey = "type"
    static let transferTypeValue = "speechSettings"
    /// transferFile の metadata に載せる指紋(SHA256 hex)。Watch 側が保存しておき、
    /// 発話直前の syncSpeechSettings で「手元の設定が最新か」の確認に使う
    static let transferFingerprintKey = "fingerprint"
}
