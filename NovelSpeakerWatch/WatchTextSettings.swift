//
//  WatchTextSettings.swift
//  NovelSpeakerWatch
//
//  本文画面の表示設定(文字サイズ・文字色・背景色・フォント)。
//  UserDefaults(@AppStorage) に保存する。Watch 間の同期はしない
//  (端末ごとに画面サイズが違いフォントサイズは変えたくなるため)。
//

import SwiftUI

enum TextDisplayDefaults {
    static let fontSizeKey = "TextPage_fontSize"
    static let textColorKey = "TextPage_textColor"
    static let backgroundColorKey = "TextPage_backgroundColor"
    // フォント選択は一度実装したが、watchOS の日本語書体は実質ヒラギノ角ゴのみで
    // Font.Design 切替が日本語に効かなかったため削除した (2026-07-07)

    static let textColors: [(name: String, color: Color)] = [
        ("white", .white),
        ("lightGray", Color(white: 0.75)),
        ("yellow", .yellow),
        ("orange", .orange),
        ("green", .green),
        ("cyan", .cyan),
        ("black", .black),
    ]

    static let backgroundColors: [(name: String, color: Color)] = [
        ("black", .black),
        ("darkGray", Color(white: 0.15)),
        ("navy", Color(red: 0.05, green: 0.08, blue: 0.20)),
        ("sepia", Color(red: 0.30, green: 0.24, blue: 0.15)),
        ("white", .white),
    ]

    static func textColor(named name: String) -> Color {
        return textColors.first(where: { $0.name == name })?.color ?? .white
    }

    static func backgroundColor(named name: String) -> Color {
        return backgroundColors.first(where: { $0.name == name })?.color ?? .black
    }

    /// 読み上げ位置ハイライト(マーカー)の色。背景色に埋もれないよう背景側で選ぶ
    static func highlightColor(backgroundName name: String) -> Color {
        return name == "white" ? Color.yellow.opacity(0.55) : Color.blue.opacity(0.45)
    }
}

struct TextSettingsView: View {
    @AppStorage(TextDisplayDefaults.fontSizeKey) private var fontSize: Double = 14
    @AppStorage(TextDisplayDefaults.textColorKey) private var textColorName: String = "white"
    @AppStorage(TextDisplayDefaults.backgroundColorKey) private var backgroundColorName: String = "black"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("メロスは激怒した。")
                    .font(.system(size: fontSize))
                    .foregroundStyle(TextDisplayDefaults.textColor(named: textColorName))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(TextDisplayDefaults.backgroundColor(named: backgroundColorName))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("文字サイズ").font(.footnote)
                    Spacer()
                    Text("\(Int(fontSize))").font(.footnote).foregroundStyle(.secondary)
                }
                Slider(value: $fontSize, in: 10...28, step: 1)

                Text("文字色").font(.footnote)
                colorRow(palette: TextDisplayDefaults.textColors, selectedName: $textColorName)

                Text("背景色").font(.footnote)
                colorRow(palette: TextDisplayDefaults.backgroundColors, selectedName: $backgroundColorName)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("本文の表示")
    }

    private func colorRow(palette: [(name: String, color: Color)], selectedName: Binding<String>) -> some View {
        HStack(spacing: 6) {
            ForEach(palette, id: \.name) { entry in
                Button {
                    selectedName.wrappedValue = entry.name
                } label: {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(
                                selectedName.wrappedValue == entry.name ? Color.green : Color.gray.opacity(0.5),
                                lineWidth: selectedName.wrappedValue == entry.name ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
