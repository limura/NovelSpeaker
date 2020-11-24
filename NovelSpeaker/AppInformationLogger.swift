//
//  AppInformationLogger.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/11/24.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

struct AppInfomationLog: Codable, CustomStringConvertible {
    let message:String
    let date:Date
    let appendix:[String:String]
    let isForDebug:Bool
    
    var description: String {
        get {
            if appendix.count <= 0 {
                return "\(date.description(with: Locale.current)): \(message)"
            }
            let adix = appendix.map({"\($0): \($1)"}).map({"  \($0)"}).joined(separator: "\n")
            return "\(date.description(with: Locale.current)): \(message)\n\(adix))"
        }
    }
}

protocol AppInformationAliveDelegate {
    func NewAppInformationAlive()
}

/// アプリ側からユーザへ通知するためのログを保存しておくための物
/// ログは UserDefaults に保存されます。
class AppInformationLogger {
    static let USERDEFAULTS_NAME = "AppInformationLoggerUserDefaults";
    static let LOG_KEY = "log";
    static let READ_DATE_KEY = "readDate";
    static let WRITE_DATE_KEY = "writeDate";
    static let MAX_LOG_COUNTS = 1000;
    static var delegate:AppInformationAliveDelegate? = nil
    
    static func AddLog(message:String, appendix:[String:String] = [:], isForDebug:Bool) {
        let log = AppInfomationLog(message: message, date: Date(), appendix: appendix, isForDebug: isForDebug)
        print(log)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let logJSONData = try? encoder.encode(log), let logJSONString = String(data: logJSONData, encoding: .utf8) else { return }
        
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
            if isForDebug == false {
                userDefaults.setValue(NiftyUtilitySwift.Date2ISO8601String(date: Date()), forKey: WRITE_DATE_KEY)
            }
            userDefaults.synchronize()
            if isForDebug == true { return }
            delegate?.NewAppInformationAlive()
            #if !os(watchOS)
            NiftyUtilitySwift.UpdateSettingsTabBadge(badge: "!")
            #endif
        }
    }
    
    static func isNewLogAlive() -> Bool {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME), let writeDateString = userDefaults.string(forKey: WRITE_DATE_KEY), let writeDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: writeDateString), let readDateString = userDefaults.string(forKey: READ_DATE_KEY), let readDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: readDateString) else { return false }
        return readDate < writeDate
    }
    
    static func CheckLogShowed() {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) else { return }
        userDefaults.setValue(NiftyUtilitySwift.Date2ISO8601String(date: Date()), forKey: READ_DATE_KEY)
        userDefaults.synchronize()
    }
    
    static func LoadLogString(isIncludeDebugLog:Bool) -> String {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME), let logArray = userDefaults.array(forKey: LOG_KEY) as? [String] else { return "" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return logArray.map({ (jsonString) in
            guard let data = jsonString.data(using: .utf8), let info = try? decoder.decode(AppInfomationLog.self, from: data) else { return "" }
            if isIncludeDebugLog == false && info.isForDebug == true { return "" }
            return info.description
        }).filter({$0 != ""}).reversed().joined(separator: "\n")
    }
    
    static func ClearLogs() {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) else { return }
        userDefaults.removeObject(forKey: LOG_KEY)
        userDefaults.synchronize()
    }
}
