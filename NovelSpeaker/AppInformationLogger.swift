//
//  AppInformationLogger.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/11/24.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

struct AnyCodable: Codable, Equatable, CustomStringConvertible {
    let value: Any
    
    init(_ value: Any?) {
        self.value = value ?? NSNull()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let dateValue = try? container.decode(Date.self) {
            value = dateValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let stringValue as String:
            try container.encode(stringValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let dateValue as Date:
            try container.encode(dateValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictionaryValue as [String: Any]:
            try container.encode(dictionaryValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
    
    // Equatableプロトコル準拠
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (let lhsValue as String, let rhsValue as String):
            return lhsValue == rhsValue
        case (let lhsValue as Int, let rhsValue as Int):
            return lhsValue == rhsValue
        case (let lhsValue as Double, let rhsValue as Double):
            return lhsValue == rhsValue
        case (let lhsValue as Bool, let rhsValue as Bool):
            return lhsValue == rhsValue
        case (let lhsValue as Date, let rhsValue as Date):
            return lhsValue == rhsValue
        case (let lhsValue as [AnyCodable], let rhsValue as [AnyCodable]):
            return lhsValue == rhsValue
        case (let lhsValue as [String: AnyCodable], let rhsValue as [String: AnyCodable]):
            return lhsValue == rhsValue
        case (is NSNull, is NSNull):
            return true
        default:
            return false
        }
    }
    
    var description: String {
        get {
            switch value {
            case let stringValue as String:
                return stringValue
            case let intValue as Int:
                return "\(intValue)"
            case let doubleValue as Double:
                return "\(doubleValue)"
            case let boolValue as Bool:
                return "\(boolValue)"
            case let dateValue as Date:
                return "\(dateValue)"
            case let arrayValue as [AnyCodable]:
                return "[" + arrayValue.map { $0.description }.joined(separator: ", ") + "]"
            case let dictionaryValue as [String: AnyCodable]:
                return "{" + dictionaryValue.map { (key: String, value: AnyCodable) in
                    print("AnyCodable description dictionaryValue.map(AnyCodable): \(key): ", value)
                    return "\(key): \(value.description)"
                }.joined(separator: ", ") + "}"
            case let dictionaryValue as [String: Any]:
                return "{" + dictionaryValue.map { (key: String, value: Any) in
                    print("AnyCodable description dictionaryValue.map(Any): \(key): ", value)
                    if let codableValue = value as? AnyCodable {
                        return "\(key): \(codableValue.description)"
                    }
                    return "\(key): \(value)"
                }.joined(separator: ", ") + "}"
            default:
                return "-"
            }
        }
    }
}

struct AppInformationLog: Codable, CustomStringConvertible {
    let message:String
    let date:Date
    let appendix:[String:AnyCodable]
    let isForDebug:Bool
    let file:String
    let line:Int
    let function:String
    
    var description: String {
        get {
            let fileName:String
            if let fileNameSubstring = file.split(separator: "/").last {
                fileName = String(fileNameSubstring)
            }else{
                fileName = file
            }
            if appendix.count <= 0 {
                return "\(date.description(with: Locale.current)):\n\(message)\n\(fileName):\(line) \(function)"
            }
            let adix = appendix.map({"\($0): \($1)"}).map({"  \($0)"}).joined(separator: "\n")
            return "\(date.description(with: Locale.current)): \(message)\n\(fileName):\(line) \(function)\n\(adix))"
        }
    }
}

protocol AppInformationAliveDelegate {
    func NewAppInformationAlive()
}

/// アプリ側からユーザへ通知するためのログを保存しておくための物
/// ログは UserDefaults に保存されます。
class AppInformationLogger : NSObject {
    static let USERDEFAULTS_NAME = "AppInformationLoggerUserDefaults";
    static let LOG_KEY = "log";
    static let READ_DATE_KEY = "readDate";
    static let WRITE_DATE_KEY = "writeDate";
    static let MAX_LOG_COUNTS = 1000;
    static var delegate:AppInformationAliveDelegate? = nil
    
    @objc static func AddLog(message:String, appendix:[String:String] = [:], isForDebug:Bool, file:String = #file, line:Int = #line, function:String = #function) {
        var appendixAny:[String:AnyCodable] = [:]
        for (key,value) in appendix {
            appendixAny[key] = AnyCodable(value)
        }
        AddLogWithStruct(message: message, appendix: appendixAny, isForDebug: isForDebug, file:file, line:line, function:function)
    }
    
    static func AddLogWithStruct(message:String, appendix:[String:AnyCodable] = [:], isForDebug:Bool, file:String = #file, line:Int = #line, function:String = #function) {
        let log = AppInformationLog(message: message, date: Date(), appendix: appendix, isForDebug: isForDebug, file: file, line: line, function: function)
        print(log)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let logJSONData = try? encoder.encode(log), let logJSONString = String(data: logJSONData, encoding: .utf8) else { return }
        
        if let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) {
            userDefaults.register(defaults: [LOG_KEY: []])
            if var logArray = userDefaults.stringArray(forKey: LOG_KEY) {
                if logArray.count > MAX_LOG_COUNTS {
                    logArray = ReduceLogStringArray(logStringArray: logArray)
                    if logArray.count > MAX_LOG_COUNTS {
                        logArray = Array(logArray.suffix(MAX_LOG_COUNTS - 1))
                    }
                }
                logArray.append(logJSONString)
                userDefaults.set(logArray, forKey: LOG_KEY)
            }else{
                userDefaults.set([logJSONString], forKey: LOG_KEY)
            }
            if isForDebug == false {
                userDefaults.setValue(NiftyUtility.Date2ISO8601String(date: Date()), forKey: WRITE_DATE_KEY)
            }
            userDefaults.synchronize()
            if isForDebug == true { return }
            delegate?.NewAppInformationAlive()
            #if !os(watchOS)
            NiftyUtility.UpdateSettingsTabBadge(badge: "!")
            #endif
        }
    }
    
    static func isNewLogAlive() -> Bool {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME), let writeDateString = userDefaults.string(forKey: WRITE_DATE_KEY), let writeDate = NiftyUtility.ISO8601String2Date(iso8601String: writeDateString), let readDateString = userDefaults.string(forKey: READ_DATE_KEY), let readDate = NiftyUtility.ISO8601String2Date(iso8601String: readDateString) else { return false }
        return readDate < writeDate
    }
    
    static func CheckLogShowed() {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) else { return }
        userDefaults.setValue(NiftyUtility.Date2ISO8601String(date: Date()), forKey: READ_DATE_KEY)
        userDefaults.synchronize()
    }
    
    /// 同じlogが続いている場合にはそれを減らします。
    static func ReduceLogStringArray(logStringArray:[String]) -> [String] {
        let currentLogArray = LogStringArrayToObjectArray(logStringArray: logStringArray)
        let reducedLogArray = MergeSameLog(logArray: currentLogArray)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let logJSONStringArray = reducedLogArray.map({ (info) -> String in
            guard let logJSONData = try? encoder.encode(info), let logJSONString = String(data: logJSONData, encoding: .utf8) else { return "" }
            return logJSONString
        }).filter({$0 != ""})
        return logJSONStringArray
    }
    static func MergeSameLog(logArray:[AppInformationLog]) -> [AppInformationLog] {
        var result:[AppInformationLog] = []
        var prevLog:AppInformationLog? = nil
        var sameCount:Int = 1
        var sameLogDate = Date()
        var sameLogIsForDebug = false
        for log in logArray {
            if let prevLog = prevLog, prevLog.message == log.message, prevLog.isForDebug == log.isForDebug, prevLog.appendix == log.appendix, prevLog.file == log.file, prevLog.line == log.line, prevLog.function == log.function {
                sameCount += 1
                sameLogDate = prevLog.date
                sameLogIsForDebug = prevLog.isForDebug
            }else{
                if sameCount > 1 {
                    result.append(AppInformationLog(message: String(format: NSLocalizedString("AppInformationLogger_SameLogFoundMessage_Format", comment: "%d回同じメッセージが繰り返されています。"), sameCount), date: sameLogDate, appendix: [:], isForDebug: sameLogIsForDebug, file: log.file, line: log.line, function: log.function))
                }
                sameCount = 1
                prevLog = log
                result.append(log)
            }
        }
        return result
    }
    
    static func LogStringArrayToObjectArray(logStringArray:[String]) -> [AppInformationLog] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let logObjArray = logStringArray.map { (jsonString) -> AppInformationLog? in
            guard let data = jsonString.data(using: .utf8), let info = try? decoder.decode(AppInformationLog.self, from: data) else { return nil }
            return info
        }
        return logObjArray.reduce([]) { (result, info) -> [AppInformationLog] in
            guard let info = info else { return result }
            var result = result
            result.append(info)
            return result
        }
    }
    
    static func LoadLogObjectArray(isIncludeDebugLog:Bool) -> [AppInformationLog] {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME), let logArray = userDefaults.array(forKey: LOG_KEY) as? [String] else { return [] }
        return LogStringArrayToObjectArray(logStringArray: logArray)
    }
    
    static func LoadLogString(isIncludeDebugLog:Bool) -> String {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME), let logArray = userDefaults.array(forKey: LOG_KEY) as? [String] else { return "" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return logArray.map({ (jsonString) in
            guard let data = jsonString.data(using: .utf8), let info = try? decoder.decode(AppInformationLog.self, from: data) else { return "" }
            if isIncludeDebugLog == false && info.isForDebug == true { return "" }
            return info.description
        }).filter({$0 != ""}).reversed().joined(separator: "\n")
    }
    
    static func LoadLogObjectArrayAsJSON(isIncludeDebugLog:Bool) -> String? {
        let logArray = LoadLogObjectArray(isIncludeDebugLog: isIncludeDebugLog)
        if !JSONSerialization.isValidJSONObject(logArray) {
            print("invalid JSON object: \(logArray)")
            return nil
        }
        let json:Data
        do {
            json = try JSONSerialization.data(withJSONObject: logArray)
        }catch{
            return nil
        }
        return String(data: json, encoding: .utf8)
    }
    
    static func ClearLogs() {
        guard let userDefaults = UserDefaults.init(suiteName: USERDEFAULTS_NAME) else { return }
        userDefaults.removeObject(forKey: LOG_KEY)
        userDefaults.synchronize()
    }
}
