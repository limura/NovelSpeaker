//
//  NovelImportSettingViewSwiftUI.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2026/04/28.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import SwiftUI
import RealmSwift

// MARK: - Main View (サイト一覧)
struct NovelImportSettingSwiftUIView: View {
    let sites: [StorySiteInfo]
    @ObservedResults(RealmNovelImportSetting.self) var settings
    @Environment(\.realmConfiguration) var realmConfig
    
    var body: some View {
        List(sites) { site in
            let setting = settings.first(where: { $0.id == site.id })
            
            NavigationLink(destination: NovelImportSettingTargetSelectionView(site: site, setting: setting?.thaw()).environment(\.realmConfiguration, realmConfig)) {
                HStack {
                    Text(site.name ?? "?")
                    Spacer()
                    
                    if let setting = setting, !setting.targets.isEmpty {
                        let count = setting.targets.count
                        let format = NSLocalizedString("NovelImportSettingSwiftUIView_selected_label", comment: "%d 選択中")
                        Text(String(format: format, count))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("NovelImportSettingSwiftUIView_title", comment: "Webサイト毎の取込設定"))
    }
}

struct NovelImportSettingTargetSelectionView: View {
    let site: StorySiteInfo
    
    // 特定の1つのオブジェクトを監視対象として受け取る
    // ObservedObjectにすることで、内部の targets (List) の変更が確実に反映されます
    @ObservedObject var setting: RealmNovelImportSetting
    
    // 設定がない場合（新規用）を考慮してイニシャライザを調整する場合
    init(site: StorySiteInfo, setting: RealmNovelImportSetting?) {
        self.site = site
        // nil の場合はダミー（未保存）を一時的に持たせるなどの工夫
        self.setting = setting ?? RealmNovelImportSetting(value: ["id": site.id])
    }
    
    var body: some View {
        VStack {
            Text(NSLocalizedString("NovelImportSettingTargetSelectionView_info_text", comment: "何も選択されていない場合はすべてが選択されたものとして動作します")).font(.footnote)
            List(site.pageElementDict.keys.sorted(), id: \.self) { key in
                Button(action: {
                    toggleSelection(key)
                }) {
                    HStack {
                        Text(getDisplayTitle(for: key))
                            .foregroundColor(.primary)
                        Spacer()
                        
                        // setting は ObservedObject なので、ここの contains 変更で再描画が走る
                        if setting.targets.contains(key) {
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
        .navigationTitle(site.name ?? "-")
    }
    
    private func toggleSelection(_ key: String) {
        // settingがRealmに管理されているか確認
        if let realm = setting.realm {
            // すでに保存済みのオブジェクトを更新
            try? realm.write {
                if let index = setting.targets.firstIndex(of: key) {
                    setting.targets.remove(at: index)
                } else {
                    setting.targets.append(key)
                }
                StoryHtmlDecoder.shared.updateNovelImportEnableSettings(id: site.id, targetKeys: Array(setting.targets))
            }
        } else {
            // まだRealmに保存されていない(新規)の場合
            guard let realm = try? RealmUtil.GetRealm() else { return }
            try? realm.write {
                setting.targets.append(key)
                realm.add(setting)
                StoryHtmlDecoder.shared.updateNovelImportEnableSettings(id: site.id, targetKeys: [key])
            }
        }
    }
    
    // 現在のシステム言語に対応するタイトルの取得ロジック
    private func getDisplayTitle(for key: String) -> String {
        guard let element = site.pageElementDict[key] else { return key }
        
        // アプリの現在の言語（簡易的にLocaleから判定、または環境変数から）
        // ここでは StorySiteInfo.Language.Japanse をデフォルトと仮定
        let currentLang: StorySiteInfo.Language = Locale.current.languageCode == "ja" ? .Japanse : .English
        
        // 該当する言語のタイトルを探し、なければ最初のものを返す
        return element.0.first(where: { $0.lang == currentLang })?.title ?? element.0.first?.title ?? key
    }
}
