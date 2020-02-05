//
//  EurekaCustomRows.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/03/11.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

// ButtonRowで detail を書けるようにします
// from https://stackoverflow.com/questions/38189640/swift-eureka-adding-text-value-to-buttonrow
public final class DetailedButtonRowOf<T: Equatable> : _ButtonRowOf<T>, RowType {
    public required init(tag: String?) {
        super.init(tag: tag)
        cellStyle = .value1
    }
}
public typealias DetailedButtonRow = DetailedButtonRowOf<String>
