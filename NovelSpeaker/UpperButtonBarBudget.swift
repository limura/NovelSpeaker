import Foundation

/// 右端の安定確認と、左側の予約を除いた上部ボタンの幅配分。
/// 予約幅はアプリの配置方針であり、NavigationBarの内部余白を取得するAPIではない。
enum UpperButtonBarBudget {
    // 幅ではなく右端だけを比較する。内容を減らしても最大予算は縮まない。
    struct StableRightEdge {
        private var context: String?
        private var previous: CGFloat?
        mutating func observe(_ edge: CGFloat?, context: String) -> CGFloat? {
            guard let edge, edge.isFinite else {
                self.context = nil
                previous = nil
                return nil
            }
            let stable = self.context == context && previous == edge
            self.context = context
            previous = edge
            return stable ? edge : nil
        }
    }

    enum LeadingMeasurement: Equatable {
        case noBack
        case owned(CGRect)
        case backSameRow(CGRect)
        case backSeparateRow(CGRect)
        // 戻るなしではない。完全探索で観測したcontrolが配分範囲外にある。
        case observedOutsideRight(CGRect)

        // 所有leftの幅は今回の配分結果。左anchorだけを安定確認し、縮小を最大予算へ反映しない。
        var stabilityKey: String {
            switch self {
            case .noBack: return "noBack"
            case .owned(let r): return "owned:\(r.minX),\(r.minY),\(r.height)"
            case .backSameRow(let r): return "backSameRow:\(r)"
            case .backSeparateRow(let r): return "backSeparateRow:\(r)"
            case .observedOutsideRight(let r): return "observedOutsideRight:\(r)"
            }
        }
    }

    struct StableLeadingMeasurement {
        private var context: String?
        private var previous: String?
        private var matches = 0
        mutating func observe(_ value: LeadingMeasurement?, context: String) -> LeadingMeasurement? {
            guard let value else { self.context = nil; previous = nil; matches = 0; return nil }
            let key = value.stabilityKey
            matches = self.context == context && previous == key ? matches + 1 : 1
            self.context = context; previous = key
            return matches >= 3 ? value : nil
        }
    }

    // 観測した38/44/48ptの戻ると高さ21〜25.3ptのタイトルを区別する経験的guard。
    // 未対応の大きさを戻ると推測せずfallbackへ渡す。UIKitの保証値ではない。
    static func quantizedLeadingRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let x = (rect.minX * scale).rounded() / scale, y = (rect.minY * scale).rounded() / scale
        // 14pt直下の浮動小数誤差で13.5ptに変わらない。外側辺だけ保守的に丸める。
        let maxX = ceil(rect.maxX * scale - 0.00001) / scale
        let maxY = ceil(rect.maxY * scale - 0.00001) / scale
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    static func isBackControlShape(_ rect: CGRect) -> Bool {
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }),
              rect.width >= 28, rect.width <= 72, rect.height >= 28, rect.height <= 72 else { return false }
        return (0.75...1.5).contains(rect.width / rect.height)
    }

    static func sameControlRow(_ a: CGRect, _ b: CGRect) -> Bool {
        guard a.height > 0, b.height > 0 else { return false }
        let overlap = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        // 隣接行/影の微小交差は同じ行としない。
        return overlap >= min(a.height, b.height) * 0.5
    }

    static func classifyBackRectangles(_ candidates: [CGRect], right: CGRect, complete: Bool, stableRightEdge: CGFloat? = nil) -> LeadingMeasurement? {
        guard complete else { return nil }
        var distinct: [CGRect] = []
        for rect in candidates where isBackControlShape(rect) {
            if !distinct.contains(where: { abs($0.minX - rect.minX) <= 0.5 && abs($0.minY - rect.minY) <= 0.5 && abs($0.maxX - rect.maxX) <= 0.5 && abs($0.maxY - rect.maxY) <= 0.5 }) { distinct.append(rect) }
        }
        guard !distinct.isEmpty else { return nil }
        let sameRow = distinct.filter { sameControlRow($0, right) }
        let separate = distinct.filter { !sameControlRow($0, right) }
        // 半端な交差は非占有と断定しない。独立した戻る行の既存判定も維持する。
        guard separate.allSatisfy({ $0.minY >= right.maxY + 4 || $0.maxY <= right.minY - 4 }) else { return nil }
        if sameRow.isEmpty {
            guard distinct.count == 1 else { return nil }
            return .backSeparateRow(distinct[0])
        }
        // 同じボタン行を観測できた場合だけ、別行のtab controlを一意性判定から外す。
        // 右端も同一世代で安定済みの値だけを使う。境界をまたぐcontrolは除外しない。
        let edge = stableRightEdge.flatMap { $0.isFinite && $0 > right.minX && $0 <= right.maxX + 0.5 ? $0 : nil }
        let outside = sameRow.filter { rect in edge.map { rect.minX >= $0 } ?? false }
        let remaining = sameRow.filter { rect in !outside.contains(rect) }
        if remaining.isEmpty {
            guard edge != nil, !outside.isEmpty else { return nil }
            return .observedOutsideRight(outside.dropFirst().reduce(outside[0]) { $0.union($1) })
        }
        guard remaining.count == 1, let rect = remaining.first, rect.maxX + 4 <= right.minX else { return nil }
        return .backSameRow(rect)
    }

    static func leadingEdge(_ value: LeadingMeasurement?, safe: CGRect,
                            fallbackReserve: CGFloat, gap: CGFloat = 12) -> CGFloat {
        switch value {
        case .noBack?, .backSeparateRow?, .observedOutsideRight?: return safe.minX + 16
        case .owned(let rect)?: return max(safe.minX, rect.maxX + gap)
        case .backSameRow(let rect)?: return max(safe.minX + 16, rect.maxX + gap)
        case nil: return safe.minX + fallbackReserve
        }
    }

    static func anchoredWidth(right: CGFloat, left: CGFloat) -> CGFloat {
        guard right.isFinite, left.isFinite else { return 0 }
        return floor(max(0, right - left))
    }

    /// 戻る操作・余白・システム表示の予約を除いた残りを操作ボタンへ配分する。
    /// systemReserveはsafe areaとは別の保守的な方針値で、実測値でも保証値でもない。
    static func speechWidth(safe: CGRect, obstruction: CGRect?, leadingReserve: CGFloat,
                            systemReserve: CGFloat = 0, layoutFrame: CGRect? = nil,
                            compactHeight: Bool = false) -> CGFloat {
        // safe areaとlayoutMarginsは同じバー座標で比較し、含まれる余白を二重に加算しない。
        // 高さcompactでの追加24pt/辺は配置方針。UIKit内部余白の仕様値ではない。
        let extra: CGFloat = compactHeight ? 24 : 0
        var left = max(safe.minX + 16, layoutFrame?.minX ?? safe.minX) + extra + leadingReserve + 12
        var right = min(safe.maxX - 16, layoutFrame?.maxX ?? safe.maxX) - extra
        if let obstruction, obstruction.intersects(safe) {
            if obstruction.midX <= safe.midX {
                left = max(left, obstruction.maxX + 12 + leadingReserve)
            } else {
                right = min(right, obstruction.minX - 12)
            }
        }
        return floor(max(0, right - left - max(0, systemReserve)))
    }

    struct TabSideSpaces: Equatable {
        let leading: CGFloat
        let trailing: CGFloat
    }

    // 中央の実占有領域を横切らない連続空間。戻る予約を右側から再度引かない。
    static func tabSideSpaces(usable: CGRect, occupied: CGRect, gap: CGFloat = 12) -> TabSideSpaces {
        guard usable.width > 0, occupied.width > 0, occupied.height > 0, occupied.intersects(usable) else {
            return TabSideSpaces(leading: 0, trailing: 0)
        }
        return TabSideSpaces(leading: floor(max(0, min(occupied.minX, usable.maxX) - usable.minX - max(0, gap))),
                             trailing: floor(max(0, usable.maxX - max(occupied.maxX, usable.minX) - max(0, gap))))
    }

    struct Allocation {
        let searchWidth: CGFloat
        let trailingWidth: CGFloat
        let selection: Selection
    }

    /// 中央タブがある場合だけ左右を分割する。それ以外は左寄せタイトルを含む合計幅で配分。
    /// 検索は短い上限で省略し、右側を減らしても余白いっぱいには伸ばさない。
    /// 上限はアプリの表示方針であり、システムの非表示化を防ぐ保証値ではない。
    static func allocate(usable: CGRect, center: CGRect?, titleWidth: CGFloat,
                         searchPreferred: CGFloat, searchMaximum: CGFloat,
                         filterWidth: CGFloat, gap: CGFloat,
                         buttonWidths: [CGFloat], spacing: CGFloat) -> Allocation {
        let preferred = max(0, min(searchPreferred, searchMaximum))
        let search: CGFloat
        let trailing: CGFloat
        let selection: Selection
        if let center {
            let spaces = tabSideSpaces(usable: usable, occupied: center, gap: gap)
            search = floor(max(0, min(preferred, spaces.leading - filterWidth)))
            trailing = spaces.trailing
            selection = select(widths: buttonWidths, spacing: spacing, available: trailing)
        } else {
            let pool = max(0, usable.width - filterWidth - titleWidth - 2 * gap)
            search = floor(min(preferred, max(0, pool - (buttonWidths.isEmpty ? 0 : 28))))
            trailing = floor(max(0, pool - search))
            selection = select(widths: buttonWidths, spacing: spacing, available: trailing)
        }
        return Allocation(searchWidth: search, trailingWidth: trailing, selection: selection)
    }

    struct Selection {
        let visible: Range<Int>
        let overflow: Range<Int>
        let width: CGFloat
    }

    // 本文の28pt固定ボタン用。bootstrap/trimで1枠なら全操作を「…」へ入れる。
    // 表示済みの個数を入力にしないため、予算が戻れば末尾側の操作を再表示する。
    static func speechSelection(buttonCount: Int, maximumSlots: Int, spacing: CGFloat) -> Selection {
        let slots = max(1, maximumSlots)
        let available = CGFloat(slots) * 28 + CGFloat(slots - 1) * max(0, spacing)
        return select(widths: Array(repeating: 28, count: max(0, buttonCount)),
                      spacing: spacing, available: available)
    }

    /// 末尾側を優先。末尾+メニューも入らない場合は全項目をアプリ自身のメニューに入れる。
    static func select(widths: [CGFloat], spacing: CGFloat, available: CGFloat,
                       menuWidth: CGFloat = 28) -> Selection {
        let gap = max(0, spacing)
        let allWidth = widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1))
        if allWidth <= available {
            return Selection(visible: 0..<widths.count, overflow: 0..<0, width: allWidth)
        }
        var start = widths.count
        var used = menuWidth
        while start > 0 && used + gap + widths[start - 1] <= available {
            start -= 1
            used += gap + widths[start]
        }
        return Selection(visible: start..<widths.count, overflow: 0..<start, width: used)
    }
}
