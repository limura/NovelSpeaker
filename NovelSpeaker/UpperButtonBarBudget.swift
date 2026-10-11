import Foundation

/// UIKitの配置結果を入力に戻さない、上部ボタンの幅予算と選別。
/// 予約幅はアプリの配置方針であり、NavigationBarの内部余白を取得するAPIではない。
enum UpperButtonBarBudget {
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
