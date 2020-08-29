//
//  RobotsFileTool.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/08/29.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//
// robots.txt の仕様はこの辺りを参照するとよさげ
// https://developers.google.com/search/reference/robots_txt
// https://qiita.com/rana_kualu/items/a5bebcae76fa6257167b
// TODO: なんだけど、自分がテキトーに作ったものなんかより「わかってる」人が作ったのが使いたいよぅ……(´・ω・`)

import Foundation
import Network

@available(iOS 12.0, *)
@available(watchOS 5.0, *)
class HTTPUserAgentCatcherServer {
    var listener:NWListener? = nil
    var cachedUserAgent:String? = nil
    
    func recvHandler(data:Data) {
        let string = String(decoding: data, as: UTF8.self)
        let lines = string.split(separator: "\n")
        for line in lines {
            let lowerLine = line.lowercased()
            guard lowerLine.range(of: "user-agent")?.lowerBound == lowerLine.startIndex else { continue }
            let splited = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
            if splited.count < 2 { continue }
            let value = String(splited[1]).trimmingCharacters(in: .whitespaces)
            self.cachedUserAgent = value
            print("get User-Agent: \(value)")
            break
        }
    }
    
    func startDummyHTTPServer() -> Bool{
        do {
            self.listener = try NWListener(using: .tcp)
        }catch{
            return false
        }
        guard let listener = self.listener else { return false }
        listener.newConnectionHandler = { (connection) in
            connection.start(queue: DispatchQueue.global(qos: .background))
            connection.receiveMessage { (data, connectionContext, flug, error) in
                guard let data = data else { return }
                if error != nil { return }
                self.recvHandler(data: data)
                connection.send(content: "HTTP/1.0 200 OK\r\n\r\n<html><body></body></html>".data(using: .utf8), completion: NWConnection.SendCompletion.contentProcessed({ (err) in
                    // nothing to do.
                }))
                connection.cancel()
            }
        }
        return true
    }
    
    func stopDummyHTTPServer(){
        if let listener = self.listener {
            listener.cancel()
        }
        self.listener = nil
    }
    
    func getListenedPort() -> NWEndpoint.Port? {
        return self.listener?.port
    }
}

// robots.txt の allow: や disallow: の行を格納する物
struct RobotsDirectiveLine {
    let isAllow:Bool
    let pathPattern:String
    let pathRegexp:NSRegularExpression

    static func PathPatternToRegularExpressoin(pathPattern: String) -> NSRegularExpression? {
        // 空文字列なものは無視されるとあるので排除します
        guard let firstChar = pathPattern.first else { return nil }
        // 空文字列でないならば、最初の文字は "/" である必要があります
        if firstChar != "/" { return nil }
        // テキトーに正規表現文字列として使えるようにします。
        // 定義によると、特殊文字は "*" と "$" で、"$" は行末だけで意味を持ちます。
        // という事で、正規表現で使いそうな文字は "\\" でエスケープしつつ、
        // "*" だけは ".*" に変換する事で対応します。
        // 末尾の "$" は正規表現と同じ意味なのでそのままで大丈夫のはずです。
        let escapedPattern = pathPattern
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: "[", with: "\\[")
        .replacingOccurrences(of: ".", with: "\\.")
        .replacingOccurrences(of: "{", with: "\\{")
        .replacingOccurrences(of: "+", with: "\\+")
        .replacingOccurrences(of: "?", with: "\\?")
        .replacingOccurrences(of: "*", with: ".*")
        return try? NSRegularExpression(pattern: escapedPattern, options: [])
    }
    func IsMatched(url: URL) -> Bool {
        let path = url.path
        return pathRegexp.firstMatch(in: path, options: [], range: NSMakeRange(0, path.count)) != nil
    }
    
    static func Decode(line:String) -> RobotsDirectiveLine? {
        let lowerCasedLine = line.lowercased()
        let isAllow:Bool
        if let allowRange = lowerCasedLine.range(of: "allow"), allowRange.lowerBound == lowerCasedLine.startIndex {
            isAllow = true
        }else if let disallowRange = lowerCasedLine.range(of: "disallow"), disallowRange.lowerBound == lowerCasedLine.startIndex {
            isAllow = false
        }else{
            return nil
        }
        let splited = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
        let pathPattern:String
        if splited.count < 2 {
            pathPattern = ""
        }else{
            pathPattern = String(splited[1]).trimmingCharacters(in: .whitespaces)
        }
        guard let pathRegexp = PathPatternToRegularExpressoin(pathPattern: pathPattern) else { return nil }
        return RobotsDirectiveLine(isAllow: isAllow, pathPattern: pathPattern, pathRegexp: pathRegexp)
    }
}

// robots.txt の user-agent で区切られる「グループ」の一つを格納する物
struct RobotsUserAgentGroup {
    let userAgent:[String]
    let directiveArray:[RobotsDirectiveLine]
    
    static func isUserAgentLine(line:String) -> (Bool, String?) {
        let lowerCasedLine = line.lowercased()
        if let userAgentRange = lowerCasedLine.range(of: "user-agent"), userAgentRange.lowerBound == lowerCasedLine.startIndex {
            let splited = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
            if splited.count < 2 { return (false, nil) }
            let userAgentString = String(splited[1]).trimmingCharacters(in: .whitespaces)
            return (true, userAgentString)
        }
        return (false, nil)
    }
    
    // WARN: 最初の行が "user-agent" で始まる事を確認「していません」
    static func Decode(lines:[String]) -> RobotsUserAgentGroup? {
        var userAgentArray:[String] = []
        var index:Int = 0
        while index < lines.count {
            let line = lines[index]
            let (isUserAgentLine, userAgent) = RobotsUserAgentGroup.isUserAgentLine(line: line)
            if isUserAgentLine == false { break }
            if let userAgent = userAgent {
                userAgentArray.append(userAgent)
            }else{
                break
            }
            index += 1
        }
        if userAgentArray.count <= 0 {
            return nil
        }
        
        var directiveArray:[RobotsDirectiveLine] = []
        while index < lines.count {
            let line = lines[index]
            if let directive = RobotsDirectiveLine.Decode(line:line) {
                directiveArray.append(directive)
            }
            index += 1
        }
        // directive は pathPattern が長い順で効果があるようなので、長い順にソートしておきます
        directiveArray.sort { $0.pathPattern.count > $1.pathPattern.count }
        return RobotsUserAgentGroup(userAgent: userAgentArray, directiveArray: directiveArray)
    }
    
    func isTargetUserAgent(userAgent:String) -> Bool {
        for ua in self.userAgent {
            if userAgent.range(of: ua) != nil {
                return true
            }
            if ua == "*" {
                return true
            }
        }
        return false
    }
    
    func isAllow(url:URL) -> Bool {
        for directive in directiveArray {
            if directive.IsMatched(url: url) {
                return directive.isAllow
            }
        }
        return true
    }
}

// robots.txt の一つ(ファイル)を格納する物
struct RobotsCache {
    let robotsURL:URL
    let createdDate:Date
    let userAgentGroupArray:[RobotsUserAgentGroup]
    
    static func Decode(robotsURL: URL, data:Data) -> RobotsCache? {
        let string = String(decoding: data, as: UTF8.self)
        // コメントや前後の空白、空行を排除しておく
        let lines = string.split(separator: "\n").map { (string) -> String in
            var line = String(string)
            if let commentRange = line.range(of: "#") {
                line = String(line[line.startIndex..<commentRange.lowerBound])
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.count > 0 }
        var index:Int = 0
        var userAgentGroupArray:[RobotsUserAgentGroup] = []
        var currentUserAgentGroupLines:[String] = []
        func addNewUserAgentGroupIfNeeded(){
            if currentUserAgentGroupLines.count > 0 {
                if let newUserAgentGroup = RobotsUserAgentGroup.Decode(lines: currentUserAgentGroupLines) {
                    userAgentGroupArray.append(newUserAgentGroup)
                }
                currentUserAgentGroupLines.removeAll()
            }
        }
        var prevLineIsUserAgentLine:Bool = true
        while index < lines.count {
            let line = lines[index]
            let (isUserAgent, _) = RobotsUserAgentGroup.isUserAgentLine(line: line)
            if isUserAgent == true && prevLineIsUserAgentLine == false {
                addNewUserAgentGroupIfNeeded()
            }
            prevLineIsUserAgentLine = isUserAgent
            currentUserAgentGroupLines.append(line)
            index += 1
        }
        addNewUserAgentGroupIfNeeded()
        // 全て駄目なのだけにしてテスト場合はコメントアウトする
        //userAgentGroupArray = [RobotsUserAgentGroup(userAgent: "*", directiveArray: [RobotsDirectiveLine(isAllow: false, pathPattern: "/", pathRegexp: try! NSRegularExpression(pattern: "/", options: []))])]
        // 後で使う時には UserAgent のマッチ文字列は長い方が優先なので長い方を前に出てくるようにソートしておきます
        let sortedUserAgentGroupArray = userAgentGroupArray.sorted { $0.userAgent.count > $1.userAgent.count }
        return RobotsCache(robotsURL: robotsURL, createdDate: Date(), userAgentGroupArray: sortedUserAgentGroupArray)
    }
    
    func SearchTargetUserAgentGroup(userAgent:String) -> RobotsUserAgentGroup? {
        for group in userAgentGroupArray {
            if group.isTargetUserAgent(userAgent: userAgent) {
                return group
            }
        }
        return nil
    }
}

/*
 * Usage: RobotsFileTool.shared.CheckRobotsTxt()
 */
class RobotsFileTool {
    static let shared = RobotsFileTool()
    let lock = NSLock()
    let memoryCacheTimeoutSecond:Double = 60*60*4
    static let fileCacheTimeoutSecond:Double = 60*60*24-1
    // このリストによるは memoryCacheTimeoutSecond の間だけ有効とします。
    // コレ以外に FileCachedHttpGet を使って fileCacheTimeoutSecond の間はファイルキャッシュを持つので、
    // ・robots.txt が存在するホストの場合は (おおよそ)fileCacheTimeoutSecond の間隔で
    // ・robots.txt が存在しないホストの場合は memoryCacheTimeoutSecond の間隔で
    // 再読み込みが行われるようになる……はずです。
    var robotsCacheArray:[URL:RobotsCache] = [:]

    static func URLToRobotsURL(url:URL) -> URL? {
        return URL(string: "/robots.txt", relativeTo: url)
    }
    static func GetRobotsText(url:URL, completion:((RobotsCache?)->Void)?) {
        guard let targetURL = URLToRobotsURL(url: url), let host = url.host?.lowercased(), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            completion?(nil)
            return
        }
        let port = url.port ?? -1
        let cacheFileName = "robotsCache_\(scheme):\(host):\(port)"
        NiftyUtilitySwift.FileCachedHttpGet(url: targetURL, cacheFileName: cacheFileName, expireTimeinterval: fileCacheTimeoutSecond, canRecoverOldFile: true, successAction: { (data) in
            completion?(RobotsCache.Decode(robotsURL: targetURL, data: data))
        }) { (err) in
            // リクエストに失敗した場合、404 などの 4** なら arrow だけれど、ネットワークエラーやサーバエラー(5**)なら disarrow らしいんだけどどうしたら
            completion?(nil)
        }
    }
    
    private func addCache(cache:RobotsCache){
        #if false
        print("robots.txt cache adding.")
        print("\(cache.robotsURL.absoluteString)")
        for group in cache.userAgentGroupArray {
            print("  \(group.userAgent.joined(separator: "\n  "))")
            for directive in group.directiveArray {
                print("    \(directive.isAllow ? "allow" : "disallow"): \(directive.pathPattern)")
            }
        }
        #endif
        lock.lock()
        robotsCacheArray[cache.robotsURL] = cache
        lock.unlock()
    }
    
    private func clearExpiredCache() {
        lock.lock()
        let cacheExpireDate = Date(timeIntervalSinceNow: -memoryCacheTimeoutSecond)
        var expiredArray:[URL] = []
        for cache in robotsCacheArray {
            if cache.value.createdDate < cacheExpireDate {
                expiredArray.append(cache.key)
            }
        }
        for url in expiredArray {
            robotsCacheArray.removeValue(forKey: url)
        }
        lock.unlock()
    }
    
    func CheckRobotsTxt(url:URL, userAgentString:String, resultHandler:((_ isAllow:Bool) -> Void)?) {
        clearExpiredCache()
        let cacheExpireDate = Date(timeIntervalSinceNow: -memoryCacheTimeoutSecond)
        guard let robotsURL = RobotsFileTool.URLToRobotsURL(url: url) else { resultHandler?(true); return }
        lock.lock()
        if let robotsCache = robotsCacheArray.filter({ $0.value.robotsURL == robotsURL }).first?.value, robotsCache.createdDate > cacheExpireDate {
            lock.unlock()
            // キャッシュにあったのでそれを使います
            if let group = robotsCache.SearchTargetUserAgentGroup(userAgent: userAgentString) {
                resultHandler?(group.isAllow(url: url))
            }else{
                // グループに指定が無い場合は allow です
                resultHandler?(true)
            }
            return
        }
        lock.unlock()
        RobotsFileTool.GetRobotsText(url: url) { (cache) in
            guard let cache = cache else {
                // cache が無いなら全部 allow な cache を作って入れておきます
                let allowCache = RobotsCache(robotsURL: robotsURL, createdDate: Date(), userAgentGroupArray: [])
                self.addCache(cache: allowCache)
                resultHandler?(true)
                return
            }
            self.addCache(cache: cache)
            if let group = cache.SearchTargetUserAgentGroup(userAgent: userAgentString) {
                resultHandler?(group.isAllow(url: url))
                return
            }
            resultHandler?(true)
        }
    }
}
