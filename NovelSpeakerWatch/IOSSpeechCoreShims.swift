//
//  IOSSpeechCoreShims.swift
//  NovelSpeakerWatch
//
//  iOS 側の発話コア(Speaker/MultiVoiceSpeaker/SpeechBlockSpeaker/StoryTextClassifier)を
//  watchOS ターゲットでもコンパイルできるようにするための最小シム。
//  iOS 側の巨大なユーティリティ(NiftyUtility/AppInformationLogger は UIKit/Realm 依存)のうち、
//  発話コアが参照しているシンボルだけを watch 用に埋める。
//  ここに実装を足したくなったら、それは「発話コアの iOS 依存が増えた」というサインなので、
//  できれば iOS 側を #if !os(watchOS) で囲む方向を先に検討すること。
//

import Foundation

class NiftyUtility {
    static func isTesting() -> Bool {
        return NSClassFromString("XCTestCase") != nil
    }
}

class AppInformationLogger {
    static func AddLog(message:String, appendix:[String:String] = [:], isForDebug:Bool) {
        NSLog("NovelSpeakerWatch.AppInformationLogger: \(message) \(appendix)")
    }
}
