//
//  ReadingPositionBreadcrumb.swift
//  NovelSpeaker
//
//  「強制終了された時に、読み上げ位置を章の頭まで巻き戻さない」ための控え。
//
//  背景:
//  読み上げ中に栞(RealmBookmark / RealmNovel)へ書いているのは、実は
//  **章の切れ目とユーザー操作の時だけ**で、章の中では一切書いていない。
//  そのため背面CPU上限などでプロセスが殺されると、再起動後は章の頭に戻る。
//  実機のログでも、殺された直後の再起動で「この先の貯金が20秒」の地点から
//  始まっていた(=事前生成音声も効かない位置に戻っていた)。
//
//  ではブロック単位で栞を書けばよいかというと、そうもいかない。
//  iCloud 同期を使っている場合、栞の書き込みは IceCream 経由でそのまま
//  CloudKit の操作になる。しかも IceCream は型ごとに Realm を監視しているので、
//  RealmBookmark と RealmNovel を同時に書く栞の更新は **1回の書き込みで2操作**出る。
//  ブロック単位にすると1章あたり40〜240操作になり、モバイル通信でも容赦なく飛ぶ
//  (allowsCellularAccess は既定の true のままで、避ける手段が無い)。
//
//  そこで、**Realm には今までどおりの頻度でしか書かず**、
//  ブロック境界の位置だけをここ(UserDefaults)に控えておく。
//  読み戻すのは**起動時の1回だけ**なので、それ以外の場面の挙動は今までと全く変わらない。
//
//  なぜ Realm に「同期しないモデル」を足さないのか:
//  それでも実現できるが、Realm のスキーマ版を上げる事になる。スキーマ版は
//  RealmCloudVersionChecker 経由で iCloud にも書かれるため、古いバイナリに
//  「アプリを更新してください」と出てしまう。純粋にローカルな控えの為には割に合わない。
//  また将来 Core Data へ移った後は「同期しないストア」を持てば済むので、
//  Realm 側に特別扱いを作り込むと移行時にそのまま写せない。
//
//  ★移行後(Core Data + NSPersistentCloudKitContainer)には、この仕組みは要らなくなる。
//   あちらは変更をまとめて自分のタイミングで送るので、栞をブロック単位で書いてよい。
//

import Foundation

struct ReadingPositionBreadcrumb: Codable, Equatable {
    let novelID: String
    /// どの章か。これが今の栞と食い違っていたら、この控えは使わない。
    let storyID: String
    /// 章の中の位置(ブロックの先頭)。
    let location: Int
    let savedAt: Date
}

enum ReadingPositionBreadcrumbStore {
    static let userDefaultsKey = "NovelSpeaker.ReadingPositionBreadcrumb"

    /// これより古い控えは使わない。
    /// 古い物を蘇らせると、その後に他の端末や手動操作で動かした位置を巻き戻しかねない。
    static let expirationSeconds: TimeInterval = 24 * 60 * 60

    static var userDefaults: UserDefaults = UserDefaults.standard

    static func save(_ breadcrumb: ReadingPositionBreadcrumb) {
        guard let data = try? JSONEncoder().encode(breadcrumb) else { return }
        userDefaults.set(data, forKey: userDefaultsKey)
    }

    static func load() -> ReadingPositionBreadcrumb? {
        guard let data = userDefaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(ReadingPositionBreadcrumb.self, from: data)
    }

    static func clear() {
        userDefaults.removeObject(forKey: userDefaultsKey)
    }

    /// この控えを栞へ書き戻してよいか。
    ///
    /// **判断に時刻の新旧は使わない。** 他の端末で読み進めていた場合、iCloud からの
    /// 反映は起動後に非同期で届くので、起動時点の時刻を比べても正しい答えにならない。
    /// 代わりに「今の栞と同じ章を指していて、かつその先にいる」時だけ書き戻す。
    ///
    ///  - 別の章に移っていた(他端末で読み進めた等) → 章が違うので使わない
    ///  - 同じ章で、栞の方が先にいる → 使わない(進んでいる方を残す)
    ///  - 同じ章で、控えの方が先にいる → これが殺された時に失った分なので書き戻す
    ///
    /// - Parameters:
    ///   - currentStoryID: 今 Realm が指している章。
    ///   - currentLocation: 今 Realm が持っている章内の位置。
    ///   - now: 判定時刻(テスト用)。
    static func shouldApply(_ breadcrumb: ReadingPositionBreadcrumb,
                            currentStoryID: String,
                            currentLocation: Int,
                            now: Date = Date()) -> Bool {
        if now.timeIntervalSince(breadcrumb.savedAt) > expirationSeconds { return false }
        if now.timeIntervalSince(breadcrumb.savedAt) < 0 { return false }
        guard breadcrumb.storyID == currentStoryID else { return false }
        return breadcrumb.location > currentLocation
    }
}
