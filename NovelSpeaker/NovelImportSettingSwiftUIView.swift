//
//  NovelImportSettingViewSwiftUI.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2026/04/28.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import SwiftUI
import RealmSwift

private struct LazyNavigationDestination<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
    }
}

// MARK: - Main View (サイト一覧)
struct NovelImportSettingSwiftUIView: View {
    static let settingDidChangeNotification = Notification.Name("NovelImportSettingSwiftUIView.settingDidChangeNotification")
    let sites: [StorySiteInfo]
    let scopeType: RealmNovelImportSetting.ScopeType
    let novelID: String?
    @ObservedResults(RealmNovelImportSetting.self) var settings
    @Environment(\.realmConfiguration) var realmConfig
    @State private var effectiveSelectedCounts:[String:Int] = [:]

    init(sites: [StorySiteInfo], scopeType: RealmNovelImportSetting.ScopeType = .site, novelID: String? = nil) {
        self.sites = sites
        self.scopeType = scopeType
        self.novelID = novelID
    }

    var body: some View {
        List(sites) { site in
            let settingId = RealmNovelImportSetting.CreateUniqueID(scopeType: scopeType, siteInfoId: site.id, novelID: novelID)
            let setting = settings.first(where: { $0.id == settingId && !$0.isDeleted })

            NavigationLink(destination: LazyNavigationDestination {
                NovelImportSettingTargetSelectionView(site: site, scopeType: scopeType, novelID: novelID, setting: setting?.thaw()).environment(\.realmConfiguration, realmConfig)
            }) {
                HStack {
                    Text(site.name ?? "?")
                    Spacer()

                    if let count = effectiveSelectedCounts[settingId] {
                        let format = NSLocalizedString("NovelImportSettingSwiftUIView_selected_label", comment: "%d 選択中")
                        if count > 0 {
                            Text(String(format: format, count))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .navigationTitle(scopeType == .novel ? NSLocalizedString("NovelImportSettingSwiftUIView_novel_title", comment: "この小説の取込設定") : NSLocalizedString("NovelImportSettingSwiftUIView_title", comment: "Webサイト毎の取込設定"))
        .onAppear {
            refreshEffectiveSelectedCounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: NovelImportSettingSwiftUIView.settingDidChangeNotification)) { _ in
            refreshEffectiveSelectedCounts()
        }
    }

    private func refreshEffectiveSelectedCounts() {
        effectiveSelectedCounts = RealmUtil.RealmBlock { realm in
            var result:[String:Int] = [:]
            for site in sites {
                let settingId = RealmNovelImportSetting.CreateUniqueID(scopeType: scopeType, siteInfoId: site.id, novelID: novelID)
                guard let setting = realm.object(ofType: RealmNovelImportSetting.self, forPrimaryKey: settingId), !setting.isDeleted else { continue }
                result[settingId] = effectiveSelectedCount(site: site, setting: setting)
            }
            return result
        }
    }

    private func effectiveSelectedCount(site: StorySiteInfo, setting: RealmNovelImportSetting) -> Int {
        let currentKeys = Set(site.pageElementDict.keys)
        let selectedCurrentKeys = Set(setting.targets).intersection(currentKeys)
        let newKeys = setting.seenTargets.isEmpty ? Set<String>() : currentKeys.subtracting(Set(setting.seenTargets))
        return selectedCurrentKeys.union(newKeys).count
    }
}

struct NovelImportSettingTargetSelectionView: View {
    let site: StorySiteInfo
    let scopeType: RealmNovelImportSetting.ScopeType
    let novelID: String?

    // 特定の1つのオブジェクトを監視対象として受け取る
    // ObservedObjectにすることで、内部の targets (List) の変更が確実に反映されます
    @ObservedObject var setting: RealmNovelImportSetting

    // 設定がない場合（新規用）を考慮してイニシャライザを調整する場合
    init(site: StorySiteInfo, scopeType: RealmNovelImportSetting.ScopeType = .site, novelID: String? = nil, setting: RealmNovelImportSetting?) {
        self.site = site
        self.scopeType = scopeType
        self.novelID = novelID
        if let managedSetting = setting {
            self.setting = managedSetting
        } else {
            // 親(body)は isDeleted=false のものだけを探して、無ければ setting=nil で渡してくる。
            // しかし同じ主キーのレコードが Realm に残っていることがある:
            //   ・ソフト削除済み(isDeleted=true。CloudKit トゥームストーンとして主キーを占有し続ける)
            //   ・SwiftUI の init が複数回走り、@ObservedResults 反映前に再生成された分
            //   ・CloudKit 同期で降ってきた同一主キー
            // ここで素の realm.add()(insert)すると主キー重複でクラッシュする。
            // かといって update:.modified は既存の選択(targets)を初期値で上書きして壊すので使わない。
            // 「あれば再利用、無ければ作る」(get-or-create)にする。
            let settingId = RealmNovelImportSetting.CreateUniqueID(scopeType: scopeType, siteInfoId: site.id, novelID: novelID)
            let initialSetting = RealmUtil.WriteReturn { realm -> RealmNovelImportSetting in
                if let existing = realm.object(ofType: RealmNovelImportSetting.self, forPrimaryKey: settingId) {
                    // 親が「無い扱い」で来た経路なので、ソフト削除されていたら復活させる(選択内容は壊さない)。
                    if existing.isDeleted { existing.isDeleted = false }
                    return existing
                }
                let initialSetting = RealmNovelImportSetting.Create(scopeType: scopeType, siteInfoId: site.id, novelID: novelID)
                initialSetting.targets.append(objectsIn: site.pageElementDict.keys.sorted())
                initialSetting.seenTargets.append(objectsIn: site.pageElementDict.keys.sorted())
                realm.add(initialSetting)
                return initialSetting
            }
            self.setting = initialSetting
        }
    }

    var body: some View {
        VStack {
            Text(NSLocalizedString("NovelImportSettingTargetSelectionView_info_text", comment: "何も選択されていない場合はすべてが選択されたものとして動作します")).font(.footnote)
            Text(NSLocalizedString("NovelImportSettingTargetSelectionView_new_element_info_text", comment: "SiteInfo に新しい項目が追加された場合は、確認するまで取り込み対象として扱われます。")).font(.footnote)
            List(site.pageElementDict.keys.sorted(), id: \.self) { key in
                Button(action: {
                    toggleSelection(key)
                }) {
                    HStack {
                        Text(getDisplayTitle(for: key))
                            .foregroundColor(.primary)
                        Spacer()

                        // setting は ObservedObject なので、ここの contains 変更で再描画が走る
                        if isSelected(key) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    // VoiceOver 対応周り
                    .contentShape(Rectangle())// タップ領域を行全体に広げる
                }
                //.buttonStyle(.plain) // ボタン標準のハイライト挙動を抑制したい場合
                .accessibilityElement(children: .combine) // 子要素（TextとImage）を1つにまとめる
                //.accessibilityLabel(getDisplayTitle(for: key)) // ラベルを指定
                //.accessibilityAddTraits(setting.targets.contains(key) ? .isSelected : []) // 「選択中」という特性を付与
                //.accessibilityValue(setting.targets.contains(key) ? "選択中" : "未選択") // 明示的に状態を読み上げさせる
            }
        }
        .onAppear {
            normalizeSelectionIfNeeded()
        }
        .navigationTitle(site.name ?? "-")
    }

    private func toggleSelection(_ key: String) {
        // settingがRealmに管理されているか確認
        if let realm = setting.realm {
            // すでに保存済みのオブジェクトを更新
            try? realm.write {
                if isSelected(key) {
                    guard let index = setting.targets.firstIndex(of: key) else {
                        updateSeenTargets()
                        return
                    }
                    setting.targets.remove(at: index)
                } else {
                    setting.targets.append(key)
                }
                updateSeenTargets()
                if setting.targets.isEmpty {
                    if scopeType == .site {
                        StoryHtmlDecoder.shared.updateNovelImportEnableSettings(id: site.id, targetKeys: [])
                    }
                    setting.delete(realm: realm)
                }else{
                    realm.add(setting, update: .modified)
                    if scopeType == .site {
                        StoryHtmlDecoder.shared.updateNovelImportEnableSettings(id: site.id, targetKeys: Array(setting.targets))
                    }
                }
            }
            notifySettingDidChange()
        } else {
            // まだRealmに保存されていない(新規)の場合
            guard let realm = try? RealmUtil.GetRealm() else { return }
            try? realm.write {
                if isSelected(key) {
                    guard let index = setting.targets.firstIndex(of: key) else {
                        updateSeenTargets()
                        return
                    }
                    setting.targets.remove(at: index)
                } else {
                    setting.targets.append(key)
                }
                updateSeenTargets()
                if setting.targets.isEmpty {
                    if scopeType == .site {
                        StoryHtmlDecoder.shared.updateNovelImportEnableSettings(id: site.id, targetKeys: [])
                    }
                }else{
                    // 未管理(setting.realm==nil)の新規を保存する経路。素の add(insert) だと
                    // 同一主キーのレコード(ソフト削除済み/同期分)が居るとクラッシュするため upsert にする。
                    // setting はこのPKに対するユーザ自身の編集対象なので .modified で上書きして問題ない。
                    realm.add(setting, update: .modified)
                    if scopeType == .site {
                        StoryHtmlDecoder.shared.updateNovelImportEnableSettings(id: site.id, targetKeys: Array(setting.targets))
                    }
                }
            }
            notifySettingDidChange()
        }
    }

    private func notifySettingDidChange() {
        NotificationCenter.default.post(name: NovelImportSettingSwiftUIView.settingDidChangeNotification, object: nil)
    }

    private func updateSeenTargets() {
        setting.seenTargets.removeAll()
        setting.seenTargets.append(objectsIn: site.pageElementDict.keys.sorted())
    }

    private func normalizeSelectionIfNeeded() {
        guard let realm = setting.realm else { return }
        let currentKeys = Set(site.pageElementDict.keys)
        let seenKeys = Set(setting.seenTargets)
        if seenKeys.isEmpty && !setting.targets.isEmpty {
            try? realm.write {
                updateSeenTargets()
                realm.add(setting, update: .modified)
            }
            return
        }
        let newKeys = currentKeys.subtracting(seenKeys)
        guard !newKeys.isEmpty else { return }
        try? realm.write {
            for key in newKeys.sorted() {
                if !setting.targets.contains(key) {
                    setting.targets.append(key)
                }
            }
            updateSeenTargets()
            realm.add(setting, update: .modified)
        }
    }

    private func isSelected(_ key: String) -> Bool {
        if setting.targets.contains(key) {
            return true
        }
        if setting.realm != nil && !setting.seenTargets.contains(key) {
            return true
        }
        return false
    }

    // 現在のシステム言語に対応するタイトルの取得ロジック
    private func getDisplayTitle(for key: String) -> String {
        return site.displayTitleForPageElement(key: key)
    }
}
