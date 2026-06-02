//
//  File.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2021/01/16.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker

// NOTE: かつてここに pixiv の実URLへアクセスしてスクレイプ結果を照合する統合テスト
// (testPixiv_FirstPageLink / testPixiv_nextLink_for_LastSeries) があったが、
// 第三者サイトの生挙動(ログイン壁・HTML変更・ネットワーク有無)に依存し単体テストとして成立しないため削除した。
// 「現在の SiteInfo で各サイトを正しくスクレイプできるか」は別の(日次の)監視の仕組みで担保する想定。

class DownloadTest: XCTestCase {

    func testNovelDownloadThrottlePolicyNominalKeepsConfiguredSpeed() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: true, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .nominal, isLowPowerModeEnabled: false, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 5)
        XCTAssertEqual(parameters.queueDelayTime, 1.05, accuracy: 0.001)
    }

    func testNovelDownloadThrottlePolicySeriousThrottlesAggressively() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: true, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .serious, isLowPowerModeEnabled: false, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 1)
        XCTAssertEqual(parameters.queueDelayTime, 2.10, accuracy: 0.001)
    }

    func testNovelDownloadThrottlePolicyLowPowerModeReducesParallelism() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: true, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .nominal, isLowPowerModeEnabled: true, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 4)
        XCTAssertEqual(parameters.queueDelayTime, 1.40, accuracy: 0.001)
    }

    func testNovelDownloadThrottlePolicyCanBeDisabled() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: false, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .critical, isLowPowerModeEnabled: true, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 5)
        XCTAssertEqual(parameters.queueDelayTime, 1.05, accuracy: 0.001)
    }
}
