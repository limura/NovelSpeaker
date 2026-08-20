//
//  BookshelfView.swift
//  NovelSpeakerWatch
//
//  ③本棚。iPhone から送られた全小説のメタデータを一覧し、転送状態を表示する。
//  タップ時: 本文が Watch に揃っていれば再生画面へ。
//  未転送・章が足りない(iPhone側で更新された)場合は選択ダイアログを出す。
//
//  並び順は左上のボタンから選べる(Watch ローカル設定。iPhone へは書き戻さない)。
//  選択肢と表示(フォルダ分けの有無・フォルダ内の順)は iPhone の本棚と同じ挙動に揃える。
//  iPhone にあって Watch に無いのは「タグ名順」(タグ情報が未同期。20万行規模になり得るため
//  同期は見送り)。iPhone がタグ名順の時は grouping "keywordTag" が届くので、
//  「iPhoneと同じ」では小説名順で表示しつつ非対応の案内を出す。
//  「iPhoneと同じ」は iPhone の現在の並び順(グループ分け込み)をそのまま再現する。
//

import SwiftUI

/// Watch 側の本棚の並び順(Watch ローカル設定)。
/// 画面が小さい Watch では「探しやすさ優先」の並びにしたい動機が iPhone とは独立なので、
/// iPhone の本棚設定には書き戻さない。表示文言・並び・グループ分けは iPhone の同名設定と同じ
enum WatchBookshelfSortType: String, CaseIterable {
    case phoneOrder             // iPhoneと同じ(受信した並び+iPhoneのグループ分けを再現)
    case writer                 // 作者名順(作者のグループ)
    case title                  // 小説名順
    case updatedDate            // 最終ダウンロード日時順
    case folder                 // 自作フォルダ順(フォルダのグループ)
    case updatedDateWithFolder  // 最終ダウンロード日時順(フォルダ分類版)
    case lastReadDate           // 小説を開いた日時順
    case likeLevel              // お気に入り順
    case webSite                // Webサイト順(サイトのグループ)
    case createdDate            // 本棚登録順
    case pageCount              // ページ数順
    case lastReadDateWithFolder // 小説を開いた日時順(フォルダ分類版)
    case unreadChapterCount     // 未読章数別
    case watchTransferState     // Apple Watch転送状況別

    var localizedName: String {
        switch self {
        case .phoneOrder:
            return NSLocalizedString("Watch_BookshelfSort_PhoneOrder", comment: "iPhoneと同じ")
        case .writer:
            return NSLocalizedString("Watch_BookshelfSort_Writer", comment: "作者名順")
        case .title:
            return NSLocalizedString("Watch_BookshelfSort_TitleOrder", comment: "小説名順")
        case .updatedDate:
            return NSLocalizedString("Watch_BookshelfSort_Updated", comment: "最終ダウンロード日時順")
        case .folder:
            return NSLocalizedString("Watch_BookshelfSort_Folder", comment: "自作フォルダ順")
        case .updatedDateWithFolder:
            return NSLocalizedString("Watch_BookshelfSort_UpdatedWithFolder", comment: "最終ダウンロード日時順(フォルダ分類版)")
        case .lastReadDate:
            return NSLocalizedString("Watch_BookshelfSort_LastRead", comment: "小説を開いた日時順")
        case .likeLevel:
            return NSLocalizedString("Watch_BookshelfSort_LikeLevel", comment: "お気に入り順")
        case .webSite:
            return NSLocalizedString("Watch_BookshelfSort_WebSite", comment: "Webサイト順")
        case .createdDate:
            return NSLocalizedString("Watch_BookshelfSort_CreatedDate", comment: "本棚登録順")
        case .pageCount:
            return NSLocalizedString("Watch_BookshelfSort_PageCount", comment: "ページ数順")
        case .lastReadDateWithFolder:
            return NSLocalizedString("Watch_BookshelfSort_LastReadWithFolder", comment: "小説を開いた日時順(フォルダ分類版)")
        case .unreadChapterCount:
            return NSLocalizedString("Watch_BookshelfSort_UnreadChapterCount", comment: "未読章数別")
        case .watchTransferState:
            return NSLocalizedString("Watch_BookshelfSort_WatchTransferState", comment: "Apple Watch転送状況別")
        }
    }
}

struct BookshelfView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    /// タップで再生ページへ移動するための親タブ selection
    @Binding var tabSelection: Int
    @AppStorage("BookshelfSortType") private var sortTypeRawValue = WatchBookshelfSortType.phoneOrder.rawValue
    @State private var isSortDialogPresented = false
    // 並べ替え・グループ化の結果はキャッシュしておく。body の再評価(ダイアログの開閉等)の
    // たびに計算すると、本棚が大きい時に古い機種で数秒固まる(Series 4 実機で確認)
    @State private var displayNovels: [WatchNovelSummary] = []
    @State private var displayGroups: [BookshelfGroup] = []

    /// フォルダ・作者・サイト・日付などのグループ1つ分(ドリルダウン表示用)
    struct BookshelfGroup: Identifiable {
        let id: String
        let name: String
        let iconSystemName: String
        let novels: [WatchNovelSummary]
    }

    private var sortType: WatchBookshelfSortType {
        return WatchBookshelfSortType(rawValue: sortTypeRawValue) ?? .phoneOrder
    }

    /// iPhone の並び順が Watch 非対応(タグ名順)の時に「iPhoneと同じ」表示で出す案内。
    /// この場合 iPhone からは小説名降順(=小説名順と同じ)の平坦な一覧が届いている
    private var phoneOrderFallbackNotice: String? {
        guard sortType == .phoneOrder, session.phoneSortGrouping == "keywordTag" else { return nil }
        return NSLocalizedString("Watch_Bookshelf_TagOrderNotice", comment: "iPhone側で「タグ名順」が選択されていますが、Watchでは非対応のため小説名順で表示しています。")
    }

    /// 順番選択の並び。iPhone の順番選択と同じく表示文字列の昇順にする
    /// (「iPhoneと同じ」だけは iPhone に無い項目なので先頭に固定)
    private var sortDialogOptions: [WatchBookshelfSortType] {
        let others = WatchBookshelfSortType.allCases.filter { $0 != .phoneOrder }
            .sorted { $0.localizedName < $1.localizedName }
        return [.phoneOrder] + others
    }

    var body: some View {
        Group {
            if displayGroups.isEmpty {
                BookshelfNovelList(novels: displayNovels, tabSelection: $tabSelection, showSyncingRow: session.isNovelListSyncing, headerNotice: phoneOrderFallbackNotice)
            } else {
                groupList
            }
        }
        .navigationTitle(NSLocalizedString("Watch_Bookshelf_Title", comment: "本棚"))
        .toolbar {
            // 右上は OS の時計が占有するので左上に置く
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isSortDialogPresented = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel(NSLocalizedString("Watch_AX_SortOrder", comment: "順番"))
            }
        }
        .confirmationDialog(
            NSLocalizedString("Watch_Bookshelf_Sort_Title", comment: "順番"),
            isPresented: $isSortDialogPresented,
            titleVisibility: .visible
        ) {
            ForEach(sortDialogOptions, id: \.rawValue) { type in
                Button((type == sortType ? "✓ " : "") + type.localizedName) {
                    sortTypeRawValue = type.rawValue
                }
            }
            Button(NSLocalizedString("Watch_Cancel", comment: "キャンセル"), role: .cancel) {}
        }
        .onAppear {
            // 本棚が空(再インストール直後など)なら iPhone に一覧を要求する。
            // iPhone 側は requestStatus を受けると重複抑止を飛ばして必ず送り返す
            if session.novels.isEmpty {
                session.send(.requestStatus, quiet: true)
            }
            recomputeDisplay(novels: session.novels)
        }
        .onChange(of: sortTypeRawValue) { _ in
            recomputeDisplay(novels: session.novels)
        }
        .onReceive(session.$novels) { novels in
            recomputeDisplay(novels: novels)
        }
        // 「iPhoneと同じ」のグループ分けは iPhone の並び順設定に追従する
        .onReceive(session.$phoneSortGrouping) { grouping in
            if sortType == .phoneOrder {
                recomputeDisplay(novels: session.novels, phoneGrouping: grouping)
            }
        }
        // フォルダ・お気に入り順の一覧は発話設定ファイルに相乗りしているので、その更新でも組み直す
        .onReceive(NotificationCenter.default.publisher(for: WatchSpeechSettingsStorage.didUpdateNotification)) { _ in
            recomputeDisplay(novels: session.novels)
        }
        // 「Apple Watch転送状況別」は転送済み一覧の変化でも組み直す
        .onReceive(session.$storedNovelIDs) { _ in
            if sortType == .watchTransferState || session.phoneSortGrouping == "watchTransferState" {
                recomputeDisplay(novels: session.novels)
            }
        }
    }

    /// 並べ替え・グループ化を計算して @State に置く(並び順・小説一覧が変わった時だけ呼ぶ)。
    /// 本棚が大きくても main thread を止めないよう、計算は裏で行って結果だけ反映する
    private func recomputeDisplay(novels: [WatchNovelSummary], phoneGrouping: String? = nil) {
        let sortType = self.sortType
        let phoneGrouping = phoneGrouping ?? session.phoneSortGrouping
        let settings = WatchSpeechSettingsStorage.current()
        let folders = settings.novelFolders ?? []
        let likeOrder = settings.novelLikeOrder ?? []
        let storedNovelIDs = session.storedNovelIDs
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.computeDisplay(novels: novels, sortType: sortType,
                                             phoneGrouping: phoneGrouping,
                                             folders: folders, likeOrder: likeOrder,
                                             storedNovelIDs: storedNovelIDs)
            DispatchQueue.main.async {
                displayNovels = result.novels
                displayGroups = result.groups
            }
        }
    }

    /// 並べ替えとグループ化の本体(pure function)。iPhone の各ツリー生成と同じ結果になるようにする
    private static func computeDisplay(
        novels: [WatchNovelSummary],
        sortType: WatchBookshelfSortType,
        phoneGrouping: String,
        folders: [WatchSpeechSettings.Folder],
        likeOrder: [String],
        storedNovelIDs: Set<String>
    ) -> (novels: [WatchNovelSummary], groups: [BookshelfGroup]) {
        switch sortType {
        case .phoneOrder:
            // 並びは iPhone が送ってきた順のまま、グループ分けだけ iPhone の設定に合わせて再現する
            switch phoneGrouping {
            case "folder":
                return ([], folderGroups(novels: novels, folders: folders))
            case "writer":
                return ([], writerGroups(novels: novels))
            case "website":
                return ([], websiteGroups(novels: novels))
            case "readDateBuckets":
                return ([], dateBucketGroups(novels: novels, dateOf: { $0.lastReadDate }))
            case "downloadDateBuckets":
                return ([], dateBucketGroups(novels: novels, dateOf: { $0.lastDownloadDate }))
            case "unreadBuckets":
                return ([], unreadBucketGroups(novels: novels))
            case "watchTransferState":
                return ([], watchTransferStateGroups(novels: novels, storedNovelIDs: storedNovelIDs))
            default:
                return (novels, [])
            }
        case .writer:
            return ([], writerGroups(novels: novels))
        case .title:
            // iPhone の小説名順は降順
            return (novels.sorted { $0.title > $1.title }, [])
        case .updatedDate:
            return (novels.sorted { $0.lastDownloadDate > $1.lastDownloadDate }, [])
        case .folder:
            return ([], folderGroups(novels: novels, folders: folders))
        case .updatedDateWithFolder:
            return ([], dateBucketGroups(novels: novels, dateOf: { $0.lastDownloadDate }))
        case .lastReadDate:
            return (novels.sorted { $0.lastReadDate > $1.lastReadDate }, [])
        case .likeLevel:
            // お気に入り順(novelLikeOrder の順)。お気に入りでない小説は受信順のまま後ろへ
            var likeIndexMap: [String: Int] = [:]
            for (index, novelID) in likeOrder.enumerated() {
                likeIndexMap[novelID] = index
            }
            let liked = novels.filter { likeIndexMap[$0.novelID] != nil }
                .sorted { (likeIndexMap[$0.novelID] ?? 0) < (likeIndexMap[$1.novelID] ?? 0) }
            let notLiked = novels.filter { likeIndexMap[$0.novelID] == nil }
            return (liked + notLiked, [])
        case .webSite:
            return ([], websiteGroups(novels: novels))
        case .createdDate:
            return (novels.sorted { $0.createdDate > $1.createdDate }, [])
        case .pageCount:
            return (novels.sorted { $0.chapterCount > $1.chapterCount }, [])
        case .lastReadDateWithFolder:
            return ([], dateBucketGroups(novels: novels, dateOf: { $0.lastReadDate }))
        case .unreadChapterCount:
            return ([], unreadBucketGroups(novels: novels))
        case .watchTransferState:
            // iPhone と同じく中身は「小説を開いた日時順」
            return ([], watchTransferStateGroups(
                novels: novels.sorted { $0.lastReadDate > $1.lastReadDate },
                storedNovelIDs: storedNovelIDs))
        }
    }

    /// Apple Watch への転送状況のグループ(iPhone の「Apple Watch転送状況別」と同じ2分割)
    private static func watchTransferStateGroups(novels: [WatchNovelSummary], storedNovelIDs: Set<String>) -> [BookshelfGroup] {
        let transferred = novels.filter { storedNovelIDs.contains($0.novelID) }
        let notTransferred = novels.filter { !storedNovelIDs.contains($0.novelID) }
        var groups: [BookshelfGroup] = []
        if !transferred.isEmpty {
            groups.append(BookshelfGroup(
                id: "watchTransfer:transferred",
                name: NSLocalizedString("Watch_WatchBucket_Transferred", comment: "Apple Watchに転送済み"),
                iconSystemName: "applewatch", novels: transferred))
        }
        if !notTransferred.isEmpty {
            groups.append(BookshelfGroup(
                id: "watchTransfer:notTransferred",
                name: NSLocalizedString("Watch_WatchBucket_NotTransferred", comment: "未転送"),
                iconSystemName: "applewatch.slash", novels: notTransferred))
        }
        return groups
    }

    /// 自作フォルダのグループ(フォルダ名は iPhone から名前昇順で届く。フォルダ内は登録順)
    private static func folderGroups(novels: [WatchNovelSummary], folders: [WatchSpeechSettings.Folder]) -> [BookshelfGroup] {
        var novelMap: [String: WatchNovelSummary] = [:]
        for novel in novels {
            novelMap[novel.novelID] = novel
        }
        var groups: [BookshelfGroup] = []
        var categorized = Set<String>()
        for folder in folders {
            categorized.formUnion(folder.novelIDs)
            let members = folder.novelIDs.compactMap { novelMap[$0] }
            guard !members.isEmpty else { continue }
            groups.append(BookshelfGroup(id: "folder:\(folder.name)", name: folder.name,
                                         iconSystemName: "folder", novels: members))
        }
        let uncategorized = novels.filter { !categorized.contains($0.novelID) }
        if !uncategorized.isEmpty {
            // iPhone と同じく未分類は小説名の降順
            groups.append(BookshelfGroup(
                id: "folder:(uncategorized)",
                name: NSLocalizedString("Watch_Bookshelf_Uncategorized", comment: "(未分類)"),
                iconSystemName: "folder",
                novels: uncategorized.sorted { $0.title > $1.title }))
        }
        return groups
    }

    /// 作者名のグループ(作者名昇順、作者内は小説名昇順。iPhone の作者名順と同じ)
    private static func writerGroups(novels: [WatchNovelSummary]) -> [BookshelfGroup] {
        var novelsByWriter: [String: [WatchNovelSummary]] = [:]
        for novel in novels {
            novelsByWriter[novel.writer, default: []].append(novel)
        }
        return novelsByWriter.keys.sorted { $0 < $1 }.map { writer in
            BookshelfGroup(
                id: "writer:\(writer)",
                name: writer.isEmpty ? NSLocalizedString("Watch_Bookshelf_UnknownWriter", comment: "(作者名不明)") : writer,
                iconSystemName: "person",
                novels: (novelsByWriter[writer] ?? []).sorted { $0.title < $1.title })
        }
    }

    /// Webサイトのグループ(サイト名昇順、サイト内は小説名昇順。iPhone のWebサイト順と同じ)
    private static func websiteGroups(novels: [WatchNovelSummary]) -> [BookshelfGroup] {
        func siteName(novelID: String) -> String {
            guard let host = URL(string: novelID)?.host else {
                return NSLocalizedString("Watch_Bookshelf_Uncategorized", comment: "(未分類)")
            }
            // iPhone の HostStringToLocalizedString と同じ読み替え
            if host == "novelspeaker.example.com" {
                return NSLocalizedString("Watch_Bookshelf_SelfMadeNovel", comment: "自作小説")
            }
            return host
        }
        var novelsBySite: [String: [WatchNovelSummary]] = [:]
        for novel in novels {
            novelsBySite[siteName(novelID: novel.novelID), default: []].append(novel)
        }
        return novelsBySite.keys.sorted { $0 < $1 }.map { site in
            BookshelfGroup(
                id: "website:\(site)",
                name: site,
                iconSystemName: "globe",
                novels: (novelsBySite[site] ?? []).sorted { $0.title < $1.title })
        }
    }

    /// 日付のバケツ分け(iPhone の「〜(フォルダ分類版)」と同じ区切り。バケツ内は新しい順)
    private static func dateBucketGroups(novels: [WatchNovelSummary], dateOf: (WatchNovelSummary) -> Date) -> [BookshelfGroup] {
        let buckets: [(title: String, date: Date)] = [
            (NSLocalizedString("Watch_Bucket_UpTo1DayAgo", comment: "1日前まで"), Date(timeIntervalSinceNow: -60 * 60 * 24)),
            (NSLocalizedString("Watch_Bucket_UpTo7DayAgo", comment: "7日前まで"), Date(timeIntervalSinceNow: -60 * 60 * 24 * 7)),
            (NSLocalizedString("Watch_Bucket_UpTo30DayAgo", comment: "30日前まで"), Date(timeIntervalSinceNow: -60 * 60 * 24 * 30)),
            (NSLocalizedString("Watch_Bucket_UpTo6MonthsAgo", comment: "6ヶ月前まで"), Date(timeIntervalSinceNow: -60 * 60 * 24 * 30 * 6)),
            (NSLocalizedString("Watch_Bucket_UpTo1YearAgo", comment: "1年前まで"), Date(timeIntervalSinceNow: -60 * 60 * 24 * 365)),
            (NSLocalizedString("Watch_Bucket_BeforeThat", comment: "それ以前"), Date(timeIntervalSinceNow: -60 * 60 * 24 * 365 * 100)),
        ]
        var bucketNovels: [[WatchNovelSummary]] = Array(repeating: [], count: buckets.count)
        var bucketIndex = 0
        for novel in novels.sorted(by: { dateOf($0) > dateOf($1) }) {
            let date = dateOf(novel)
            while bucketIndex < buckets.count - 1 && date <= buckets[bucketIndex].date {
                bucketIndex += 1
            }
            bucketNovels[bucketIndex].append(novel)
        }
        return buckets.enumerated().compactMap { (index, bucket) in
            guard !bucketNovels[index].isEmpty else { return nil }
            return BookshelfGroup(id: "dateBucket:\(index)", name: bucket.title,
                                  iconSystemName: "clock", novels: bucketNovels[index])
        }
    }

    /// 未読章数のバケツ分け(iPhone の「未読章数別」と同じ区切り。バケツ内は未読が多い順)
    private static func unreadBucketGroups(novels: [WatchNovelSummary]) -> [BookshelfGroup] {
        // iPhone 側 BookShelfTreeViewController.unreadChapterCount と同じ判定
        // (最終章は「本文の残りが10文字以内なら読了」= 読了ゲージが紫になる判定と同じ)
        func unreadCount(_ novel: WatchNovelSummary) -> Int {
            let lastChapter = novel.chapterCount
            let readingChapter = novel.readingChapterNumber
            if readingChapter <= 0 {
                // 一度も開いていない = 全部未読として扱う
                return max(0, lastChapter)
            }
            if readingChapter == lastChapter {
                let contentCount = novel.readingChapterContentCount > 0 ? novel.readingChapterContentCount : 1
                if contentCount <= novel.readingChapterReadingPoint + 10 {
                    return 0  // 読了
                }
                return 1  // 最終章の途中
            }
            if readingChapter > lastChapter {
                // 栞が最終章より先に進んでいる壊れ気味のデータ。iPhone と同じく読了扱いにしない
                return 1
            }
            return lastChapter - readingChapter
        }
        let buckets: [(title: String, lowerBound: Int)] = [
            (NSLocalizedString("Watch_UnreadBucket_100Plus", comment: "未読 100章以上"), 100),
            (NSLocalizedString("Watch_UnreadBucket_10To99", comment: "未読 10〜99章"), 10),
            (NSLocalizedString("Watch_UnreadBucket_1To9", comment: "未読 1〜9章"), 1),
            (NSLocalizedString("Watch_UnreadBucket_CaughtUp", comment: "追いついている"), 0),
        ]
        var bucketNovels: [[WatchNovelSummary]] = Array(repeating: [], count: buckets.count)
        var bucketIndex = 0
        for novel in novels.map({ ($0, unreadCount($0)) }).sorted(by: { $0.1 > $1.1 }) {
            while bucketIndex < buckets.count - 1 && novel.1 < buckets[bucketIndex].lowerBound {
                bucketIndex += 1
            }
            bucketNovels[bucketIndex].append(novel.0)
        }
        return buckets.enumerated().compactMap { (index, bucket) in
            guard !bucketNovels[index].isEmpty else { return nil }
            return BookshelfGroup(id: "unreadBucket:\(index)", name: bucket.title,
                                  iconSystemName: "book", novels: bucketNovels[index])
        }
    }

    // MARK: - グループ(フォルダ・作者・サイト・日付など)表示

    private var groupList: some View {
        ScrollViewReader { proxy in
            List {
                if session.isNovelListSyncing {
                    syncingRow
                }
                ForEach(displayGroups) { group in
                    NavigationLink {
                        BookshelfNovelList(novels: group.novels, tabSelection: $tabSelection, showSyncingRow: false)
                            .navigationTitle(group.name)
                    } label: {
                        groupRow(group: group)
                    }
                }
            }
            .toolbar {
                // 一番上へ戻るボタン(watchOS には iPhone の「画面上部タップで先頭へ」が無いため)。
                // 位置は本文ページと同じ左下に揃える(画面によって場所が動くと迷うため)
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button {
                            if let first = displayGroups.first {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        } label: {
                            Image(systemName: "arrow.up.to.line")
                        }
                        .accessibilityLabel(NSLocalizedString("Watch_AX_ScrollToTop", comment: "一番上へ"))
                        Spacer()
                    }
                }
            }
        }
    }

    private func groupRow(group: BookshelfGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.iconSystemName)
                .font(.system(size: 14))
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            Text(group.name)
                .font(.footnote)
                .lineLimit(2)
            Spacer()
            Text("\(group.novels.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        // 冊数が別の Text に分かれていて「◯◯、12」としか読まれないので、
        // 行をひとまとまりにして「◯◯、12冊」と読ませる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name), " + String(format: NSLocalizedString(
            "Watch_Bookshelf_GroupNovelCountFormat", comment: "%d冊"), group.novels.count))
    }

    private var syncingRow: some View {
        HStack(spacing: 6) {
            ProgressView()
                .frame(width: 12, height: 12)
            Text(NSLocalizedString("Watch_Bookshelf_Syncing", comment: "iPhoneと同期中…"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// 小説の行の一覧(本棚のルートとグループの中身で共用)。
/// タップ時: 本文が Watch に揃っていれば再生画面へ。
/// 未転送・章が足りない(iPhone側で更新された)場合は選択ダイアログを出す。
struct BookshelfNovelList: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    let novels: [WatchNovelSummary]
    @Binding var tabSelection: Int
    /// 小説一覧の同期中表示を出すか(本棚のルートでだけ true)
    var showSyncingRow: Bool = false
    /// 一覧の先頭に出す案内(iPhone の並び順が Watch 非対応の時など)。本棚のルートでだけ使う
    var headerNotice: String? = nil
    @State private var dialogNovel: WatchNovelSummary?

    var body: some View {
        ScrollViewReader { proxy in
            novelList
                .toolbar {
                    // 一番上へ戻るボタン(watchOS には iPhone の「画面上部タップで先頭へ」が無いため)。
                    // 位置は本文ページと同じ左下に揃える(画面によって場所が動くと迷うため)
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button {
                                if let first = novels.first {
                                    proxy.scrollTo(first.novelID, anchor: .top)
                                }
                            } label: {
                                Image(systemName: "arrow.up.to.line")
                            }
                            .accessibilityLabel(NSLocalizedString("Watch_AX_ScrollToTop", comment: "一番上へ"))
                            Spacer()
                        }
                    }
                }
        }
    }

    private var novelList: some View {
        List {
            if showSyncingRow && session.isNovelListSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .frame(width: 12, height: 12)
                    Text(NSLocalizedString("Watch_Bookshelf_Syncing", comment: "iPhoneと同期中…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if let headerNotice = headerNotice {
                Text(headerNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if novels.isEmpty {
                Text(NSLocalizedString("Watch_Bookshelf_EmptyMessage", comment: "iPhoneの ことせかい を一度起動すると、本棚がここに表示されます。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(novels, id: \.novelID) { staleNovel in
                // novels は push 時のスナップショットなので、表示は最新の summary で行う
                // (iPhone 側の更新→転送で章数が変わった時に、開いたままの一覧でも数字が追従する)
                let novel = session.novelsByID[staleNovel.novelID] ?? staleNovel
                Button {
                    if transferState(novel: novel) == .complete {
                        openNovel(novel)
                    } else {
                        dialogNovel = novel
                    }
                } label: {
                    HStack(spacing: 6) {
                        transferStateIcon(novel: novel)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(novel.title)
                                .font(.footnote)
                                .lineLimit(2)
                            Text(chapterText(novel: novel))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if novel.isLiked {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.pink)
                                .accessibilityLabel(NSLocalizedString("Watch_AX_Liked", comment: "お気に入り"))
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            dialogNovel?.title ?? "",
            isPresented: Binding(
                get: { dialogNovel != nil },
                set: { presented in
                    if !presented { dialogNovel = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: dialogNovel
        ) { novel in
            Button(transferButtonLabel(novel: novel)) {
                session.requestTransfer(novelID: novel.novelID)
            }
            Button(NSLocalizedString("Watch_Bookshelf_GoToPlayer", comment: "再生画面へ移動")) {
                openNovel(novel)
            }
            Button(NSLocalizedString("Watch_Cancel", comment: "キャンセル"), role: .cancel) {}
        } message: { novel in
            Text(dialogMessage(novel: novel))
        }
    }

    private func openNovel(_ novel: WatchNovelSummary) {
        // Watch 単体再生モード中で本文が転送済みなら、Watch 側のプレイヤーに開く
        // (未転送なら iPhone モードへ戻して従来どおり iPhone 側に開かせる)
        let player = WatchSpeechPlayer.shared
        if player.isSelectedAsSource {
            if player.open(novelID: novel.novelID, fallbackTitle: novel.title) {
                tabSelection = 1
                return
            }
            player.isSelectedAsSource = false
        }
        // iPhone に繋がっていない(ランニング中・別の Watch が接続中など)場合でも、
        // 本文が転送済みなら Watch 単体モードへ切り替えて開く(小説を替えられないと困る)
        if !session.isReachable, openAsWatchSourceFallback(novel) { return }
        session.send(.openNovel, args: [WatchMessage.Arg.novelID: novel.novelID]) { ok in
            if !ok, openAsWatchSourceFallback(novel) {
                // 単体モードで開けたのでエラーアラートは出さない
                // (エラー文言は completion の直前にセットされるため、ここで消せば表示前に消える)
                session.lastErrorMessage = nil
            }
        }
        tabSelection = 1
    }

    /// iPhone に開かせられない時のフォールバック。転送済みなら Watch 単体モードで開いて true
    private func openAsWatchSourceFallback(_ novel: WatchNovelSummary) -> Bool {
        let player = WatchSpeechPlayer.shared
        guard player.open(novelID: novel.novelID, fallbackTitle: novel.title) else { return false }
        player.isSelectedAsSource = true
        player.refreshComplication()
        tabSelection = 1
        return true
    }

    // MARK: - 転送状態

    private enum TransferState {
        case complete   // 全章が Watch にある
        case partial    // 転送済みだが iPhone 側の方が章が多い(更新された)
        case none       // 未転送
        case requested  // 特急転送を依頼中
    }

    private func transferState(novel: WatchNovelSummary) -> TransferState {
        if session.transferRequestedNovelIDs.contains(novel.novelID) { return .requested }
        guard let storedCount = session.storedChapterCounts[novel.novelID] else { return .none }
        if novel.chapterCount > 0 && storedCount < novel.chapterCount { return .partial }
        return .complete
    }

    @ViewBuilder private func transferStateIcon(novel: WatchNovelSummary) -> some View {
        // VoiceOver は行全体を読むので、アイコンには転送状態の説明を持たせる
        switch transferState(novel: novel) {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_Complete", comment: "転送済み"))
        case .partial:
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_Partial", comment: "iPhone側で更新あり"))
        case .requested:
            ProgressView()
                .frame(width: 12, height: 12)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_Requested", comment: "転送依頼中"))
        case .none:
            Image(systemName: "cloud")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_None", comment: "未転送"))
        }
    }

    private func transferButtonLabel(novel: WatchNovelSummary) -> String {
        if let storedCount = session.storedChapterCounts[novel.novelID] {
            return String(format: NSLocalizedString("Watch_Bookshelf_TransferUpdates", comment: "更新分を転送 (%1$d→%2$d章)"), storedCount, novel.chapterCount)
        }
        return NSLocalizedString("Watch_Bookshelf_TransferBody", comment: "本文をWatchへ転送")
    }

    private func dialogMessage(novel: WatchNovelSummary) -> String {
        if session.storedChapterCounts[novel.novelID] != nil {
            return NSLocalizedString("Watch_Bookshelf_UpdatedOnPhone", comment: "この小説はiPhone側で更新されています。")
        }
        return NSLocalizedString("Watch_Bookshelf_NotTransferred", comment: "この小説の本文はまだWatchにありません。")
    }

    private func chapterText(novel: WatchNovelSummary) -> String {
        if novel.chapterCount > 0 {
            return String(format: NSLocalizedString("Watch_Bookshelf_ChapterProgress", comment: "%1$d/%2$d章"), novel.readingChapterNumber, novel.chapterCount)
        }
        return ""
    }
}
