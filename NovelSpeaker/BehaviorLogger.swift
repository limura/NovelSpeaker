//
//  BehaviorLogger.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/02/26.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit

class BehaviorLogger: NSObject {
    static let USERDEFAULTS_NAME = "BehaviorLoggerUserDefaults";
    static let LOG_KEY = "log";
    static let MAX_LOG_COUNTS = 1000;
    public static let LOGGER_ENABLED = false;
    
    /// ログを追加します。ログは UserDefaults の特定のSuiteに最大 n件(default 1000件) 保存されます。
    /// ログには AddLog() を呼び出した時間が追加されます。
    /// 注意：何らかの失敗をした場合でも、特に何もエラーをすることなくこの関数は終了します。
    @objc static public func AddLog(description: String, data: Dictionary<String, Any>) -> Void {
        var logDictionary = ["description": description,
                             "dateTime": Date().description(with: Locale.init(identifier: "ja_JP"))] as [String : Any];
        if data.count > 0 {
            logDictionary["data"] = data
        }
        var logJSONString:String;
        do {
            let logJSONData = try JSONSerialization.data(withJSONObject: logDictionary, options: .prettyPrinted)
            if let string = String(bytes: logJSONData, encoding: .utf8) {
                logJSONString = string;
            }else{
                return;
            }
        } catch {
            return;
        }
        GlobalDataSingleton.getInstance()?.addLogString(logJSONString)
        if !LOGGER_ENABLED {
            return
        }

        if let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) {
            userDefaults.register(defaults: [LOG_KEY: []])
            if var logArray = userDefaults.array(forKey: LOG_KEY) {
                if logArray.count > MAX_LOG_COUNTS {
                    logArray = Array(logArray.suffix(MAX_LOG_COUNTS - 1))
                }
                logArray.append(logJSONString)
                userDefaults.set(logArray, forKey: LOG_KEY)
            }else{
                userDefaults.set([logJSONString], forKey: LOG_KEY)
            }
            userDefaults.synchronize()
        }
    }
    
    static public func AddLogSimple(description: String) -> Void {
        BehaviorLogger.AddLog(description: description, data: [:]);
    }
    
    /// 保存されているログを文字列の形式で取り出します。
    /// ログはAddLogが呼び出された順番の配列のJSON文字列として取り出されます。
    /// 何らかの失敗をした場合は "[]\n" が返されます(あくまでもJSON文字列を返します)。
    static public func LoadLog() -> String {
        var result = "[]\n"
        if let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) {
            if let logArray = userDefaults.array(forKey: LOG_KEY) as? [String] {
                var firstTime = true;
                var logString = "[";
                for log in logArray {
                    if !firstTime {
                        logString += ",";
                    }
                    firstTime = false
                    logString += log;
                }
                logString += "]\n";
                result = logString;
            }
        }
        return result
    }
}
