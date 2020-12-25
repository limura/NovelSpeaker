//
//  SloppyError.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/07/11.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//
// ゲンナリする位イケてないエラー
// 単にコンストラクタで指定した文字列を覚えていて localizedDescription でそれを返すだけです。
// 唯一の中身がそれなのにも関わらず、localize されていない文字列を返すというステキ仕様！

import UIKit

class SloppyError: Error, LocalizedError {
    let msg:String
    init(msg:String) {
        self.msg = msg
    }
    
    var localizedDescription: String {
        return self.msg
    }
    
    var errorDescription: String? {
        return self.msg
    }
}
