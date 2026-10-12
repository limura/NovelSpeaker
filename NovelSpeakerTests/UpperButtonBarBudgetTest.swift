import XCTest
@testable import NovelSpeaker

final class UpperButtonBarBudgetTest: XCTestCase {
    func testSpeechReservesBackAndSystemSpaceWithoutFixedCap() {
        for width in [CGFloat(320), 375, 669, 951] {
            let available = UpperButtonBarBudget.speechWidth(
                safe: CGRect(x: 0, y: 0, width: width, height: 58), obstruction: nil,
                leadingReserve: 44, systemReserve: 160)
            XCTAssertEqual(available, max(0, width - 248))
        }
    }

    func testSpeechWideBarsRestoreAllActionsWhileDuoKeepsBackReservation() {
        let widths = Array(repeating: CGFloat(28), count: 15)
        func selection(_ width: CGFloat) -> UpperButtonBarBudget.Selection {
            let available = UpperButtonBarBudget.speechWidth(
                safe: CGRect(x: 0, y: 0, width: width, height: 58), obstruction: nil,
                leadingReserve: 44, systemReserve: 160)
            return UpperButtonBarBudget.select(widths: widths, spacing: 8, available: available)
        }
        XCTAssertEqual(selection(1180).visible.count, 15)
        XCTAssertTrue(selection(1180).overflow.isEmpty)
        XCTAssertEqual(selection(669).visible.count, 10) // 「…」込みで11個
        XCTAssertLessThanOrEqual(selection(669).width, 421)
    }

    func testSpeechAccountsForLeftTabRegionAndNarrowBars() {
        let safe = CGRect(x: 84, y: 0, width: 316, height: 58)
        let available = UpperButtonBarBudget.speechWidth(
            safe: safe, obstruction: CGRect(x: 0, y: -24, width: 132, height: 466), leadingReserve: 88)
        XCTAssertEqual(available, 152)
        XCTAssertEqual(UpperButtonBarBudget.speechWidth(
            safe: CGRect(x: 0, y: 0, width: 100, height: 58), obstruction: nil, leadingReserve: 88), 0)
    }

    func testSEPortraitFitsEightSlotsIncludingOverflow() {
        let available = UpperButtonBarBudget.speechWidth(
            safe: CGRect(x: 0, y: 0, width: 375, height: 54), obstruction: nil, leadingReserve: 44,
            layoutFrame: CGRect(x: 16, y: 0, width: 343, height: 54))
        XCTAssertEqual(available, 287)
        let selection = UpperButtonBarBudget.select(widths: Array(repeating: 28, count: 15), spacing: 8, available: available)
        XCTAssertEqual(selection.visible.count, 7)
        XCTAssertFalse(selection.overflow.isEmpty)
        XCTAssertEqual(selection.width, 280)
    }

    func testSELandscapeReservesExtraSpaceForCompactHeight() {
        let available = UpperButtonBarBudget.speechWidth(
            safe: CGRect(x: 0, y: 0, width: 667, height: 54), obstruction: nil, leadingReserve: 44,
            layoutFrame: CGRect(x: 20, y: 0, width: 627, height: 54), compactHeight: true)
        XCTAssertEqual(available, 523)
        for spacing in [CGFloat(8), 14] {
            let selection = UpperButtonBarBudget.select(
                widths: Array(repeating: 28, count: 15), spacing: spacing, available: available)
            XCTAssertLessThanOrEqual(selection.width, available)
            // 今回観測された右端625ptを使った回帰確認。戻る領域と間隔を確保できる。
            XCTAssertGreaterThanOrEqual(625 - selection.width, 44 + 44 + 12)
        }
    }

    func testSpeechDoesNotDoubleCountSafeAreaInsideMargins() {
        let safe = CGRect(x: 84, y: 0, width: 583, height: 54)
        XCTAssertEqual(UpperButtonBarBudget.speechWidth(
            safe: safe, obstruction: nil, leadingReserve: 44,
            layoutFrame: CGRect(x: 84, y: 0, width: 563, height: 54)), 491)
    }



    @MainActor
    func testLeadingGroupHasMenuAndRetainsIdentity() throws {
        guard #available(iOS 16.0, *) else { return }
        let controller = BookShelfTreeViewController()
        controller.assignLeftBarButtons(showsInlineTitle: true, searchWidth: 104, titleWidth: 32)
        let group = try XCTUnwrap(controller.navigationItem.leadingItemGroups.first)
        let item = try XCTUnwrap(group.barButtonItems.first)
        let container = try XCTUnwrap(item.customView)
        let width = try XCTUnwrap(container.constraints.first { $0.identifier == "BookshelfLeadingWidth" })
        XCTAssertEqual(width.constant, 184)
        XCTAssertEqual(width.priority, UILayoutPriority(999))
        XCTAssertTrue(container.subviews.first is UIStackView)
        let menu = try XCTUnwrap(group.menuRepresentation as? UIMenu)
        XCTAssertEqual(menu.children.count, 2)
        XCTAssertTrue(menu.children.allSatisfy { $0 is UIAction })
        XCTAssertNil(group.representativeItem)
        if #available(iOS 27.0, *) {
            XCTAssertEqual(item.visibilityPriority, .high)
        }
        controller.assignLeftBarButtons(showsInlineTitle: false, searchWidth: 160, titleWidth: 32)
        XCTAssertEqual(width.constant, 196)
        controller.assignLeftBarButtons(showsInlineTitle: true, searchWidth: 319, titleWidth: 32)
        XCTAssertEqual(width.constant, 399)
        XCTAssertTrue(item.customView === container)
        XCTAssertTrue(controller.navigationItem.leadingItemGroups.first === group)
        XCTAssertTrue(group.barButtonItems.first === item)
    }

    private func allocation(width: CGFloat, search: CGFloat = 800, center: CGRect? = nil,
                            buttons: [CGFloat] = [28, 28, 28, 28, 28, 30]) -> UpperButtonBarBudget.Allocation {
        UpperButtonBarBudget.allocate(
            usable: CGRect(x: 24, y: 0, width: width - 48, height: 44),
            center: center, titleWidth: 36, searchPreferred: search, searchMaximum: 88,
            filterWidth: 36, gap: 12, buttonWidths: buttons, spacing: 8)
    }

    func testClosedDuoUsesFormerlyReservedCenter() {
        let budget = allocation(width: 382)
        XCTAssertEqual(budget.searchWidth, 88)
        XCTAssertEqual(budget.selection.visible.count + 1, 4)
        XCTAssertLessThanOrEqual(budget.searchWidth + 36 + 36 + 24 + budget.selection.width, 334)
    }

    func testSearchStaysCompactAndShortTextUsesOnlyItsIntrinsicWidth() {
        XCTAssertEqual(allocation(width: 594).searchWidth, 88)
        XCTAssertEqual(allocation(width: 867).searchWidth, 88)
        XCTAssertEqual(allocation(width: 820, search: 34).searchWidth, 34)
        XCTAssertEqual(allocation(width: 820, search: 0).searchWidth, 0)
    }

    func testUpperTabsRemainProtected() {
        let center = CGRect(x: 230, y: 0, width: 360, height: 44)
        let budget = allocation(width: 820, center: center)
        XCTAssertLessThanOrEqual(24 + budget.searchWidth + 36 + 12, center.minX)
        XCTAssertLessThanOrEqual(budget.searchWidth, 88)
        XCTAssertLessThanOrEqual(center.maxX + 12 + budget.selection.width, 796)
    }

    func testScaledSearchMaximumIsRespected() {
        let result = UpperButtonBarBudget.allocate(
            usable: CGRect(x: 24, y: 0, width: 800, height: 44),
            center: nil, titleWidth: 48, searchPreferred: 800, searchMaximum: 132,
            filterWidth: 36, gap: 12, buttonWidths: [28, 30], spacing: 8)
        XCTAssertEqual(result.searchWidth, 132)
    }

    func testFewerButtonsDoNotExpandSearch() {
        for count in 0...6 {
            XCTAssertEqual(allocation(width: 669, buttons: Array(repeating: 28, count: count)).searchWidth, 88)
        }
    }

    func testAllocationFitsAcrossWidthsAndButtonCounts() {
        for width in [CGFloat(320), 375, 382, 594, 669, 867] {
            for count in 0...12 {
                let result = allocation(width: width, buttons: Array(repeating: 28, count: count))
                XCTAssertGreaterThanOrEqual(result.searchWidth, 88)
                XCTAssertLessThanOrEqual(result.searchWidth + 36 + 36 + 24 + result.selection.width, width - 48)
                XCTAssertEqual(Array(result.selection.overflow) + Array(result.selection.visible), Array(0..<count))
            }
        }
    }

    func testMenuOnlyWhenLastButtonDoesNotFit() {
        let result = UpperButtonBarBudget.select(widths: [28, 28, 48], spacing: 8, available: 40)
        XCTAssertTrue(result.visible.isEmpty)
        XCTAssertEqual(result.overflow, 0..<3)
        XCTAssertEqual(result.width, 28)
    }

    func testTextButtonWidthIsIncluded() {
        let result = UpperButtonBarBudget.select(widths: [28, 28, 60], spacing: 8, available: 100)
        XCTAssertEqual(result.visible, 2..<3)
        XCTAssertEqual(result.overflow, 0..<2)
        XCTAssertEqual(result.width, 96)
    }

    func testGrowthRestoresButtonsWithoutPreviousLayoutState() {
        let widths: [CGFloat] = [28, 28, 28, 28, 32]
        let small = UpperButtonBarBudget.select(widths: widths, spacing: 8, available: 100)
        let large = UpperButtonBarBudget.select(widths: widths, spacing: 8, available: 300)
        let smallAgain = UpperButtonBarBudget.select(widths: widths, spacing: 8, available: 100)
        XCTAssertEqual(large.visible, 0..<5)
        XCTAssertTrue(large.overflow.isEmpty)
        XCTAssertEqual(small.visible, smallAgain.visible)
        XCTAssertEqual(small.width, smallAgain.width)
    }

    func testSelectionFitsAndPreservesEveryAction() {
        for count in 0...12 {
            for spacing in [CGFloat(0), 8, 24] {
                for available in stride(from: CGFloat(28), through: 600, by: 7) {
                    let widths = (0..<count).map { $0 == count - 1 ? CGFloat(50) : 28 }
                    let result = UpperButtonBarBudget.select(widths: widths, spacing: spacing, available: available)
                    XCTAssertLessThanOrEqual(result.width, available)
                    XCTAssertEqual(Array(result.overflow) + Array(result.visible), Array(0..<count))
                }
            }
        }
    }
}

final class UpperTabSideSpaceTest: XCTestCase {
    func testObservedPortraitRegionKeepsEachSideSeparate() {
        let spaces = UpperButtonBarBudget.tabSideSpaces(usable: CGRect(x: 20, y: 0, width: 780, height: 108),
            occupied: CGRect(x: 240.5, y: 0, width: 339, height: 44))
        XCTAssertEqual(spaces.leading, 208)
        XCTAssertEqual(spaces.trailing, 208)
    }

    func testObservedLandscapeRegionDoesNotSubtractBackReserveFromTrailingSide() {
        let spaces = UpperButtonBarBudget.tabSideSpaces(usable: CGRect(x: 20, y: 0, width: 1140, height: 108),
            occupied: CGRect(x: 420.5, y: 0, width: 339, height: 44))
        XCTAssertEqual(spaces.leading, 388)
        XCTAssertEqual(spaces.trailing, 388)
    }

    func testNoSpaceAndInvalidGeometryDoNotExpandToFullWidth() {
        let usable = CGRect(x: 0, y: 0, width: 320, height: 44)
        XCTAssertEqual(UpperButtonBarBudget.tabSideSpaces(usable: usable, occupied: usable),
                       .init(leading: 0, trailing: 0))
        XCTAssertEqual(UpperButtonBarBudget.tabSideSpaces(usable: usable, occupied: .zero),
                       .init(leading: 0, trailing: 0))
        XCTAssertEqual(UpperButtonBarBudget.tabSideSpaces(usable: usable, occupied: CGRect(x: 10, y: 100, width: 100, height: 44)),
                       .init(leading: 0, trailing: 0))
    }
}


@MainActor
final class UpperTabRegionDetectionTest: XCTestCase {
    private let titles: Set<String> = ["Shelf", "Settings"]

    private func fixture() -> (UIWindow, UIView, UINavigationBar, UITabBar, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
        window.isHidden = false
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let bar = UINavigationBar(frame: CGRect(x: 0, y: 30, width: 900, height: 100))
        root.addSubview(bar)
        let lower = UITabBar(frame: CGRect(x: 0, y: 1120, width: 900, height: 80))
        root.addSubview(lower)
        let outer = UIView(frame: CGRect(x: 290, y: 32, width: 320, height: 46))
        let inner = UIView(frame: CGRect(x: 4, y: 0, width: 312, height: 46))
        outer.addSubview(inner)
        for (index, name) in titles.sorted().enumerated() {
            let label = UILabel(frame: CGRect(x: 20 + index * 150, y: 10, width: 100, height: 22))
            label.text = name
            inner.addSubview(label)
        }
        root.addSubview(outer)
        return (window, root, bar, lower, outer)
    }

    func testDetectsOuterRegionInBarCoordinatesAndRemeasuresAfterResize() throws {
        let (window, root, bar, lower, outer) = fixture()
        defer { window.isHidden = true }
        func region() throws -> CGRect {
            guard case let .upper(rect) = NovelSpeakerUtility.findUpperTabRegion(
                in: root, excluding: [bar], titles: titles, window: window, bar: bar,
                lowerTabBar: lower, lineHeight: 22) else { XCTFail("upper region missing"); return .zero }
            return rect
        }
        XCTAssertEqual(try region(), CGRect(x: 290, y: 2, width: 320, height: 46))
        window.frame.size.width = 1200
        root.frame = window.bounds
        bar.frame.size.width = 1200
        outer.frame.origin.x = 440
        XCTAssertEqual(try region(), CGRect(x: 440, y: 2, width: 320, height: 46))
        let unrelated = UIView(frame: outer.frame)
        let duplicate = UILabel(frame: unrelated.bounds)
        duplicate.text = "Shelf"
        unrelated.addSubview(duplicate)
        window.addSubview(unrelated) // Tab controllerの外にあるoverlayは検索しない。
        XCTAssertEqual(try region().minX, 440)
    }

    func testRejectsHiddenIncompleteAndAmbiguousTitles() {
        let (window, root, bar, lower, outer) = fixture()
        defer { window.isHidden = true }
        func isUnknown() -> Bool {
            if case .unknown = NovelSpeakerUtility.findUpperTabRegion(
                in: root, excluding: [bar], titles: titles, window: window, bar: bar,
                lowerTabBar: lower, lineHeight: 22) { return true }
            return false
        }
        outer.isHidden = true
        XCTAssertTrue(isUnknown())
        outer.isHidden = false
        let duplicate = UILabel(frame: CGRect(x: 310, y: 44, width: 100, height: 22))
        duplicate.text = "Shelf"
        root.addSubview(duplicate)
        XCTAssertTrue(isUnknown())
        duplicate.isHidden = true
        XCTAssertFalse(isUnknown())
        outer.subviews.first?.subviews.first?.removeFromSuperview()
        XCTAssertTrue(isUnknown())
    }

    func testMeasuredRegionFitsMaximumSuffixAndRetainsEveryAction() {
        for tabWidth in [CGFloat(280), 390, 500] {
            let usable = CGRect(x: 24, y: 0, width: 786, height: 108)
            let center = CGRect(x: 417 - tabWidth / 2, y: 0, width: tabWidth, height: 49)
            let result = UpperButtonBarBudget.allocate(usable: usable, center: center,
                titleWidth: 40, searchPreferred: 500, searchMaximum: 132,
                filterWidth: 36, gap: 12, buttonWidths: Array(repeating: 28, count: 9), spacing: 8)
            XCTAssertLessThanOrEqual(usable.minX + result.searchWidth + 36 + 12, center.minX)
            XCTAssertLessThanOrEqual(center.maxX + 12 + result.selection.width, usable.maxX)
            XCTAssertEqual(result.selection.visible.count + result.selection.overflow.count, 9)
            XCTAssertFalse(result.selection.overflow.isEmpty)
            XCTAssertGreaterThan(result.selection.width + 36, result.trailingWidth)
        }
    }
}

final class SpeechViewButtonImageCompatibilityTest: XCTestCase {
    func testUnavailableNewSymbolsUseRenderableOldSymbols() {
        for (type, preferred, fallback) in [(SpeechViewButtonTypes.detail, "book.pages", "book"), (.addPageToOtherNovel, "book.badge.plus", "plus.square")] {
            var requested: [String] = []
            let image = NovelSpeakerUtility.speechViewButtonImage(type) { name in
                requested.append(name)
                return name == preferred ? nil : UIImage(systemName: name)
            }
            XCTAssertEqual(requested, [preferred, fallback])
            XCTAssertNotNil(image)
        }
    }

    func testAvailableNewSymbolsKeepTheirExistingAppearance() {
        for type in [SpeechViewButtonTypes.detail, .addPageToOtherNovel] {
            var requested: [String] = []
            let marker = UIImage()
            let image = NovelSpeakerUtility.speechViewButtonImage(type) { name in
                requested.append(name)
                return marker
            }
            XCTAssertTrue(image === marker)
            XCTAssertEqual(requested.count, 1)
        }
    }
}
