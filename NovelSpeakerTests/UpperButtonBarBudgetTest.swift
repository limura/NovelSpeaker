import XCTest
import WebKit
@testable import NovelSpeaker

final class UpperButtonBarBudgetTest: XCTestCase {
    func testSpeechBootstrapKeepsEveryActionInOneMenuAndExpands() {
        let bootstrap = UpperButtonBarBudget.speechSelection(buttonCount: 14, maximumSlots: 1, spacing: 8)
        XCTAssertTrue(bootstrap.visible.isEmpty)
        XCTAssertEqual(bootstrap.overflow, 0..<14)
        XCTAssertEqual(bootstrap.width, 28)
        let partial = UpperButtonBarBudget.speechSelection(buttonCount: 14, maximumSlots: 8, spacing: 8)
        XCTAssertEqual(partial.visible, 7..<14)
        XCTAssertEqual(Array(partial.overflow) + Array(partial.visible), Array(0..<14))
        XCTAssertEqual(partial.width, 280)
        let expanded = UpperButtonBarBudget.speechSelection(buttonCount: 14, maximumSlots: 14, spacing: 8)
        XCTAssertEqual(expanded.visible, 0..<14)
        XCTAssertTrue(expanded.overflow.isEmpty)
        let bootstrapAgain = UpperButtonBarBudget.speechSelection(buttonCount: 14, maximumSlots: 1, spacing: 8)
        XCTAssertEqual(bootstrapAgain.overflow, bootstrap.overflow)
        XCTAssertEqual(bootstrapAgain.width, bootstrap.width)
        let onlyAction = UpperButtonBarBudget.speechSelection(buttonCount: 1, maximumSlots: 1, spacing: 8)
        XCTAssertEqual(onlyAction.visible, 0..<1)
        XCTAssertTrue(onlyAction.overflow.isEmpty)
    }

    func testRightEdgeRequiresConsecutiveValidSamplesInSameGeometry() {
        var probe = UpperButtonBarBudget.StableRightEdge()
        XCTAssertNil(probe.observe(531, context: "open-P"))
        XCTAssertEqual(probe.observe(531, context: "open-P"), 531)
        XCTAssertNil(probe.observe(590, context: "closed-L-safeRight"))
        XCTAssertEqual(probe.observe(590, context: "closed-L-safeRight"), 590)
        // 同じ678x466でもsafe areaの側が違えば再確認する。
        XCTAssertNil(probe.observe(654, context: "closed-L-safeLeft"))
        XCTAssertNil(probe.observe(nil, context: "closed-L-safeLeft"))
        XCTAssertNil(probe.observe(654, context: "closed-L-safeLeft"))
        XCTAssertEqual(probe.observe(654, context: "closed-L-safeLeft"), 654)
        XCTAssertNil(probe.observe(.infinity, context: "closed-L-safeLeft"))
    }

    func testAnchoredBudgetProtectsBackAndExpandsAfterNarrowLayout() {
        let buttons = Array(repeating: CGFloat(28), count: 14)
        func selected(right: CGFloat, left: CGFloat = 88) -> UpperButtonBarBudget.Selection {
            UpperButtonBarBudget.select(widths: buttons, spacing: 8,
                available: UpperButtonBarBudget.anchoredWidth(right: right, left: left))
        }
        let portrait = selected(right: 531)
        XCTAssertFalse(portrait.overflow.isEmpty)
        XCTAssertGreaterThanOrEqual(531 - portrait.width, 88)
        let narrow = selected(right: 378)
        XCTAssertLessThan(narrow.visible.count, portrait.visible.count)
        let landscape = selected(right: 863)
        XCTAssertEqual(landscape.visible.count, 14)
        XCTAssertTrue(landscape.overflow.isEmpty)
        XCTAssertEqual(selected(right: 531).visible, portrait.visible)
        XCTAssertEqual(UpperButtonBarBudget.anchoredWidth(right: 820, left: 599), 221)
        XCTAssertEqual(UpperButtonBarBudget.anchoredWidth(right: 35, left: 88), 0)
        XCTAssertEqual(UpperButtonBarBudget.anchoredWidth(right: .nan, left: 88), 0)
    }

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


@MainActor
final class RightEdgeProbeRecoveryTest: XCTestCase {
    private final class RetryQueue {
        var jobs: [() -> Void] = []
        var scheduled = 0
        func enqueue(_ work: @escaping () -> Void) { scheduled += 1; jobs.append(work) }
        func drain(file: StaticString = #filePath, line: UInt = #line) {
            var count = 0
            while !jobs.isEmpty && count < 100 {
                count += 1
                jobs.removeFirst()()
            }
            XCTAssertTrue(jobs.isEmpty, "retry queue must terminate", file: file, line: line)
        }
    }
    private func fixture() -> (UIWindow, UINavigationController, UIViewController, UIView) {
        let controller = UIViewController()
        let custom = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: custom)
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.rootViewController = navigation
        window.isHidden = false
        navigation.view.frame = window.bounds
        navigation.view.layoutIfNeeded()
        let bar = navigation.navigationBar
        bar.addSubview(custom)
        custom.frame = CGRect(x: bar.bounds.maxX - 48, y: 8, width: 28, height: 28)
        XCTAssertTrue(controller.view.window === window)
        XCTAssertTrue(bar.window === window)
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertTrue(bar.topItem === controller.navigationItem)
        XCTAssertNil(navigation.transitionCoordinator)
        return (window, navigation, controller, custom)
    }
    private func latch(_ probe: NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe,
                       controller: UIViewController, queue: RetryQueue) {
        var callbacks = 0
        func request() {
            XCTAssertNil(probe.resolve(controller: controller) { callbacks += 1; request() })
        }
        request()
        queue.drain()
        XCTAssertEqual(callbacks, 6)
        XCTAssertTrue(probe.usesBootstrap)
    }
    private func confirm(_ probe: NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe,
                         controller: UIViewController, queue: RetryQueue) {
        XCTAssertNil(probe.resolve(controller: controller) {})
        XCTAssertNotNil(probe.resolve(controller: controller) {})
        XCTAssertFalse(probe.usesBootstrap)
        queue.drain()
    }

    func testLateValidFrameRecoversInSameContextOnlyAfterTwoSamples() {
        let (window, navigation, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        custom.isHidden = true
        latch(probe, controller: controller, queue: queue)
        let geometry = navigation.navigationBar.convert(navigation.navigationBar.bounds, to: window)
        custom.isHidden = false
        XCTAssertNotNil(NovelSpeakerUtility.UpperButtonBarLayout.trailingRightEdge(controller: controller))
        XCTAssertNil(probe.resolve(controller: controller) {})
        XCTAssertTrue(probe.usesBootstrap, "one valid sample is not yet stable")
        XCTAssertNotNil(probe.resolve(controller: controller) {})
        XCTAssertFalse(probe.usesBootstrap)
        XCTAssertEqual(navigation.navigationBar.convert(navigation.navigationBar.bounds, to: window), geometry)
        queue.drain()
    }

    func testMissingFramesStopAtSixRetriesAndDoNotPollWhileInBootstrap() {
        let (window, _, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        custom.isHidden = true
        latch(probe, controller: controller, queue: queue)
        for _ in 0..<20 { XCTAssertNil(probe.resolve(controller: controller) { XCTFail("no polling") }) }
        XCTAssertEqual(queue.scheduled, 6)
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertTrue(probe.usesBootstrap)
    }

    func testRepeatedMissingAndValidFramesRecoverMoreThanOnceInSameContext() {
        let (window, _, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        for _ in 0..<3 {
            custom.isHidden = true
            latch(probe, controller: controller, queue: queue)
            custom.isHidden = false
            confirm(probe, controller: controller, queue: queue)
        }
    }

    func testAutomaticRecoveryBurstsAreFiniteAndExternalEventReopensBudget() {
        let (window, _, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        for _ in 0..<6 {
            custom.isHidden = true
            latch(probe, controller: controller, queue: queue)
            custom.isHidden = false
            confirm(probe, controller: controller, queue: queue)
        }
        custom.isHidden = true
        latch(probe, controller: controller, queue: queue)
        custom.isHidden = false
        let scheduled = queue.scheduled
        for _ in 0..<20 { XCTAssertNil(probe.resolve(controller: controller) { XCTFail("loop must stop") }) }
        XCTAssertEqual(queue.scheduled, scheduled)
        XCTAssertTrue(probe.usesBootstrap)
        probe.restartAfterExternalEvent()
        confirm(probe, controller: controller, queue: queue)
        // 次の一時失敗も、同じcontextで再び回復できる。
        custom.isHidden = true
        latch(probe, controller: controller, queue: queue)
        custom.isHidden = false
        confirm(probe, controller: controller, queue: queue)
    }

    func testExternalEventRestartsFailureBudgetAndDiscardsOldPendingCallback() {
        let (window, _, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        custom.isHidden = true
        var oldCallbacks = 0
        XCTAssertNil(probe.resolve(controller: controller) { oldCallbacks += 1 })
        XCTAssertEqual(queue.jobs.count, 1)
        probe.restartAfterExternalEvent()
        latch(probe, controller: controller, queue: queue)
        XCTAssertEqual(oldCallbacks, 0)
        probe.restartAfterExternalEvent()
        XCTAssertFalse(probe.usesBootstrap)
        latch(probe, controller: controller, queue: queue)
        custom.isHidden = false
        confirm(probe, controller: controller, queue: queue)
    }

    func testGeometryChangeReopensBudgetAndRequiresTwoNewSamples() {
        let (window, navigation, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        custom.isHidden = true
        latch(probe, controller: controller, queue: queue)
        navigation.navigationBar.frame.origin.y += 1
        XCTAssertNil(probe.resolve(controller: controller) {})
        XCTAssertFalse(probe.usesBootstrap)
        queue.drain()
        custom.isHidden = false
        confirm(probe, controller: controller, queue: queue)
    }

    func testPendingRetryDoesNotCallInactiveController() {
        let (window, navigation, controller, custom) = fixture()
        defer { window.isHidden = true; window.rootViewController = nil }
        let queue = RetryQueue()
        let probe = NovelSpeakerUtility.UpperButtonBarLayout.RightEdgeProbe(scheduleRetry: queue.enqueue)
        custom.isHidden = true
        var callbacks = 0
        XCTAssertNil(probe.resolve(controller: controller) { callbacks += 1 })
        navigation.pushViewController(UIViewController(), animated: false)
        queue.drain()
        XCTAssertEqual(callbacks, 0)
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


final class LeadingBoundaryBudgetTest: XCTestCase {
    func testSubpixelRoundoffDoesNotMoveOwnedAnchor() {
        let a=UpperButtonBarBudget.quantizedLeadingRect(CGRect(x:14.000000000000004,y:7,width:66,height:30),scale:2)
        let b=UpperButtonBarBudget.quantizedLeadingRect(CGRect(x:13.999999999999996,y:7,width:124,height:30),scale:2)
        XCTAssertEqual(a.minX,14);XCTAssertEqual(b.minX,14)
        XCTAssertEqual(UpperButtonBarBudget.LeadingMeasurement.owned(a).stabilityKey,UpperButtonBarBudget.LeadingMeasurement.owned(b).stabilityKey)
    }
    func testObservedShortTitlesAreRejectedWhileBackControlsPass() {
        for size in [CGSize(width: 16, height: 21), CGSize(width: 35.67, height: 23.33), CGSize(width: 19.67, height: 25.33)] {
            XCTAssertFalse(UpperButtonBarBudget.isBackControlShape(CGRect(origin: .zero, size: size)))
        }
        for size in [CGFloat(38), 44, 48] { XCTAssertTrue(UpperButtonBarBudget.isBackControlShape(CGRect(x: 20, y: 0, width: size, height: size))) }
    }
    func testAmbiguousIncompleteAndRightSideControlsAreNotMeasured() {
        let a = CGRect(x: 16, y: 0, width: 44, height: 44), b = CGRect(x: 80, y: 0, width: 32, height: 32)
        let right = CGRect(x: 150, y: 4, width: 180, height: 40)
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([a,b], right: right, complete: true))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([a], right: right, complete: false))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([], right: right, complete: true))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([CGRect(x: 280,y: 0,width: 44,height: 44)], right: right, complete: true))
        XCTAssertEqual(UpperButtonBarBudget.classifyBackRectangles([a,a], right: right, complete: true), .backSameRow(a))
    }
    func testSeparateRowIsSuccessWithoutLeadingReservation() {
        let back = CGRect(x: 879,y: 96,width: 48,height: 48), right = CGRect(x: 367,y: 4,width: 496,height: 40)
        let result = UpperButtonBarBudget.classifyBackRectangles([back], right: right, complete: true)
        XCTAssertEqual(result, .backSeparateRow(back))
        let safe = CGRect(x: 0,y: 0,width: 867,height: 58)
        XCTAssertEqual(UpperButtonBarBudget.leadingEdge(result, safe: safe, fallbackReserve: 88), 16)
        XCTAssertEqual(UpperButtonBarBudget.leadingEdge(nil, safe: safe, fallbackReserve: 88), 88)
    }
    func testDuoClosedRightExcludesObservedTabRowBeforeUniqueness() {
        let right = CGRect(x: 16, y: 4, width: 574, height: 40)
        let back = CGRect(x: 606, y: 0, width: 48, height: 48)
        let tab = CGRect(x: 608, y: 150, width: 44, height: 58)
        let result = UpperButtonBarBudget.classifyBackRectangles([back, tab, tab], right: right, complete: true, stableRightEdge: 590)
        XCTAssertEqual(result, .observedOutsideRight(back))
        XCTAssertEqual(UpperButtonBarBudget.leadingEdge(result, safe: CGRect(x: 0,y: 0,width: 594,height: 58), fallbackReserve: 88), 16)
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([back,tab],right:right,complete:true))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([],right:right,complete:true,stableRightEdge:590))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([back,tab],right:right,complete:false,stableRightEdge:590))
    }
    func testRowExclusionRetainsSameRowBackAndSeparateBack() {
        let right = CGRect(x: 150,y: 4,width: 180,height: 40)
        let back = CGRect(x: 16,y: 0,width: 44,height: 44)
        let tab = CGRect(x: 200,y: 150,width: 44,height: 44)
        XCTAssertEqual(UpperButtonBarBudget.classifyBackRectangles([tab,back,tab],right:right,complete:true,stableRightEdge:330), .backSameRow(back))
        XCTAssertEqual(UpperButtonBarBudget.classifyBackRectangles([tab],right:right,complete:true,stableRightEdge:330), .backSeparateRow(tab))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([tab,CGRect(x:250,y:150,width:44,height:44)],right:right,complete:true,stableRightEdge:330))
    }
    func testOutsideRightCannotHideOverlapOrAmbiguity() {
        let right = CGRect(x: 150,y: 4,width: 180,height: 40)
        let outside = CGRect(x: 340,y: 0,width: 44,height: 44)
        let back = CGRect(x: 16,y: 0,width: 44,height: 44)
        XCTAssertEqual(UpperButtonBarBudget.classifyBackRectangles([back,outside],right:right,complete:true,stableRightEdge:330), .backSameRow(back))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([CGRect(x:310,y:0,width:44,height:44)],right:right,complete:true,stableRightEdge:330))
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([back,CGRect(x:80,y:0,width:44,height:44),outside],right:right,complete:true,stableRightEdge:330))
        for invalid in [CGFloat.nan, .infinity, 100, 400] {
            XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([outside],right:right,complete:true,stableRightEdge:invalid))
        }
    }
    func testOutsideRightNeedsFreshStableGeometryAndMissingReturnsFallback() {
        var samples=UpperButtonBarBudget.StableLeadingMeasurement()
        let value=UpperButtonBarBudget.LeadingMeasurement.observedOutsideRight(CGRect(x:606,y:0,width:48,height:48))
        XCTAssertNil(samples.observe(value,context:"right590"));XCTAssertNil(samples.observe(value,context:"right590"));XCTAssertEqual(samples.observe(value,context:"right590"),value)
        XCTAssertNil(samples.observe(value,context:"right580"))
        XCTAssertNil(samples.observe(nil,context:"right580"))
        XCTAssertEqual(UpperButtonBarBudget.leadingEdge(nil,safe:CGRect(x:0,y:0,width:590,height:58),fallbackReserve:88),88)
    }
    func testTinyRowIntersectionIsAmbiguous() {
        let back=CGRect(x:16,y:40,width:44,height:44), right=CGRect(x:100,y:4,width:100,height:40)
        XCTAssertNil(UpperButtonBarBudget.classifyBackRectangles([back],right:right,complete:true))
    }
    func testOwnedAnchorStableDespiteAllocatedWidthAndChangesInvalidate() {
        var samples=UpperButtonBarBudget.StableLeadingMeasurement()
        XCTAssertNil(samples.observe(.owned(CGRect(x:14,y:7,width:66,height:30)),context:"a"))
        XCTAssertNil(samples.observe(.owned(CGRect(x:14,y:7,width:124,height:30)),context:"a"))
        XCTAssertNotNil(samples.observe(.owned(CGRect(x:14,y:7,width:66,height:30)),context:"a"))
        XCTAssertNil(samples.observe(.owned(CGRect(x:24,y:7,width:66,height:30)),context:"a"))
        XCTAssertNil(samples.observe(.owned(CGRect(x:24,y:7,width:66,height:30)),context:"rotated"))
        XCTAssertNil(samples.observe(nil,context:"rotated"))
    }
    func testBackNeedsThreeMatchesAndNoBackIsDistinctFromUnavailable() {
        var samples=UpperButtonBarBudget.StableLeadingMeasurement()
        let back=UpperButtonBarBudget.LeadingMeasurement.backSameRow(CGRect(x:16,y:0,width:44,height:44))
        XCTAssertNil(samples.observe(back,context:"a"));XCTAssertNil(samples.observe(back,context:"a"));XCTAssertEqual(samples.observe(back,context:"a"),back)
        XCTAssertNil(samples.observe(.noBack,context:"a"));XCTAssertNil(samples.observe(.noBack,context:"a"));XCTAssertEqual(samples.observe(.noBack,context:"a"),.noBack)
        XCTAssertNil(samples.observe(nil,context:"a"))
    }
}

final class LeadingBoundaryProbeRecoveryTest: XCTestCase {
    private final class Queue {
        var jobs:[()->Void]=[]
        func enqueue(_ job:@escaping()->Void){jobs.append(job)}
        func drain(){var count=0;while !jobs.isEmpty && count<100 {count += 1;jobs.removeFirst()()};XCTAssertTrue(jobs.isEmpty)}
    }
    func testFallbackStopsAndLateValueRecoversWithThreeSamples() {
        let q=Queue(),p=NovelSpeakerUtility.UpperButtonBarLayout.LeadingProbe(scheduleRetry:q.enqueue)
        var value:UpperButtonBarBudget.LeadingMeasurement?,result:UpperButtonBarBudget.LeadingMeasurement?
        func run(){result=p.resolve(context:"a",value:value,active:{true},retry:run)}
        run();q.drain();XCTAssertTrue(p.usesFallback);XCTAssertNil(result)
        for _ in 0..<20 {run()};XCTAssertTrue(q.jobs.isEmpty)
        value = .noBack;run();XCTAssertNil(result);q.drain();XCTAssertEqual(result,.noBack);XCTAssertFalse(p.usesFallback)
        value=nil;run();q.drain();XCTAssertTrue(p.usesFallback)
        value = .noBack;run();q.drain();XCTAssertEqual(result,.noBack)
    }
    func testEpochAndInactiveControllerDiscardQueuedRetry() {
        let q=Queue(),p=NovelSpeakerUtility.UpperButtonBarLayout.LeadingProbe(scheduleRetry:q.enqueue)
        var calls=0,active=true
        _=p.resolve(context:"a",value:nil,active:{active},retry:{calls += 1})
        p.restartAfterExternalEvent();q.drain();XCTAssertEqual(calls,0)
        _=p.resolve(context:"a",value:nil,active:{active},retry:{calls += 1})
        active=false;q.drain();XCTAssertEqual(calls,0)
    }
    func testAutomaticRecoveryIsFiniteAndExternalEventReopensIt() {
        let q=Queue(),p=NovelSpeakerUtility.UpperButtonBarLayout.LeadingProbe(scheduleRetry:q.enqueue)
        var value:UpperButtonBarBudget.LeadingMeasurement?
        func run(){_=p.resolve(context:"a",value:value,active:{true},retry:run)}
        run();q.drain()
        for _ in 0..<6 {value = .noBack;run();q.drain();XCTAssertFalse(p.usesFallback);value=nil;run();q.drain();XCTAssertTrue(p.usesFallback)}
        value = .noBack;run();XCTAssertTrue(p.usesFallback);XCTAssertTrue(q.jobs.isEmpty)
        p.restartAfterExternalEvent();run();q.drain();XCTAssertFalse(p.usesFallback)
    }
    func testContextChangeRequiresFreshSamples() {
        let p=NovelSpeakerUtility.UpperButtonBarLayout.LeadingProbe(scheduleRetry:{_ in})
        for _ in 0..<3 {_=p.resolve(context:"old",value:.noBack,active:{true},retry:{})}
        XCTAssertNil(p.resolve(context:"new",value:.noBack,active:{true},retry:{}))
    }
}

@MainActor
final class LeadingBoundaryUIKitTest: XCTestCase {
    private func fixture()->(UIWindow,UINavigationController,UIViewController){
        let c=UIViewController(),n=UINavigationController(),w=UIWindow(frame:CGRect(x:0,y:0,width:375,height:667))
        n.setViewControllers([c],animated:false);w.rootViewController=n;w.isHidden=false;n.view.frame=w.bounds;n.view.layoutIfNeeded()
        return(w,n,c)
    }
    func testRootHasNoBackRatherThanMissingMeasurement(){
        let(w,_,c)=fixture();defer{w.isHidden=true}
        XCTAssertEqual(NovelSpeakerUtility.UpperButtonBarLayout.leadingMeasurement(controller:c).value,.noBack)
    }
    func testLegacyOwnedCustomViewPathMeasuresAndRejectsClipping(){
        let(w,n,c)=fixture();defer{w.isHidden=true}
        let v=UIView(frame:CGRect(x:20,y:7,width:66,height:30));c.navigationItem.leftBarButtonItem=UIBarButtonItem(customView:v)
        n.navigationBar.addSubview(v);v.frame=CGRect(x:20,y:7,width:66,height:30)
        guard case .owned(let rect)?=NovelSpeakerUtility.UpperButtonBarLayout.leadingMeasurement(controller:c,preferPublicItemFrames:false).value else{return XCTFail("legacy custom coordinates unavailable")}
        XCTAssertEqual(rect.minX,20,accuracy:0.5)
        let clip=UIView(frame:CGRect(x:20,y:7,width:30,height:30));clip.clipsToBounds=true;n.navigationBar.addSubview(clip);clip.addSubview(v);v.frame=CGRect(x:0,y:0,width:66,height:30)
        XCTAssertNil(NovelSpeakerUtility.UpperButtonBarLayout.leadingMeasurement(controller:c,preferPublicItemFrames:false).value)
    }
    func testLeadingGroupPathUsesOwnedAnchor(){
        let(w,n,c)=fixture();defer{w.isHidden=true}
        guard #available(iOS 16.0,*) else{return}
        let v=UIView(frame:CGRect(x:14,y:7,width:124,height:30));let item=UIBarButtonItem(customView:v)
        c.navigationItem.leadingItemGroups=[.fixedGroup(representativeItem:nil,items:[item])];n.navigationBar.addSubview(v);v.frame=CGRect(x:14,y:7,width:124,height:30)
        guard case .owned(let rect)?=NovelSpeakerUtility.UpperButtonBarLayout.leadingMeasurement(controller:c,preferPublicItemFrames:false).value else{return XCTFail("leading group unavailable")}
        XCTAssertEqual(rect.minX,14,accuracy:0.5)
        v.isHidden=true;XCTAssertNil(NovelSpeakerUtility.UpperButtonBarLayout.leadingMeasurement(controller:c,preferPublicItemFrames:false).value)
    }
}

@MainActor
final class WebReaderFullscreenTest: XCTestCase {
    private func makeReader() -> (UIWindow, CustomWKWebView, WebSpeechViewTool) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        let web = CustomWKWebView(frame: CGRect(x: 0, y: 0, width: 700, height: 450), configuration: WKWebViewConfiguration())
        controller.view.addSubview(web)
        return (window, web, WebSpeechViewTool())
    }

    func testFullscreenMarginRestoresAndSurvivesChapterReload() {
        let (window, web, tool) = makeReader()
        defer { window.isHidden = true }
        let done = expectation(description: "generated chapter styling")
        func checkMargin(_ expected: String, then: @escaping () -> Void) {
            web.evaluateJavaScript("getComputedStyle(document.body).marginTop") { value, error in
                XCTAssertNil(error)
                XCTAssertEqual(value as? String, expected)
                then()
            }
        }
        func load(_ text: String, then: @escaping () -> Void) {
            tool.applyFromNovelSpeakerString(webView: web, content: text, foregroundColor: .black, backgroundColor: .white, font: .systemFont(ofSize: 18), viewType: .webViewVertical, lineSpacingDisplayValue: 3, baseURL: nil, completionHandler: then)
        }
        load("最初の章の本文です。") {
            checkMargin("8px") {
                tool.isReaderFullscreen = true
                tool.updateReaderFullscreenStyle {
                    checkMargin("0px") {
                        load("次の短い章です。") {
                            checkMargin("0px") {
                                tool.isReaderFullscreen = false
                                tool.updateReaderFullscreenStyle { checkMargin("8px") { done.fulfill() } }
                            }
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 15)
    }

    func testVerticalVisibleAnchorSurvivesViewportResize() { checkAnchorResize(.webViewVertical) }
    func testHorizontalVisibleAnchorSurvivesViewportResize() { checkAnchorResize(.webViewHorizontal) }

    private func checkAnchorResize(_ type: RealmDisplaySetting.ViewType) {
        let (window, web, tool) = makeReader()
        defer { window.isHidden = true }
        tool.isReaderFullscreen = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.contentInset = .zero
        let done = expectation(description: "same character after viewport resize")
        let text = String(repeating: "これは回転前後の可視文字の位置を確認するための長い本文です。", count: 400)
        tool.applyFromNovelSpeakerString(webView: web, content: text, foregroundColor: .black, backgroundColor: .white, font: .systemFont(ofSize: 18), viewType: type, lineSpacingDisplayValue: 3, baseURL: nil) {
            let vertical = type == .webViewVertical
            // 生成本文の既存スクロールAPIで確実に途中の文字へ移動する。
            // 読込直後のnative contentSizeはまだ更新途中の場合がある。
            tool.scrollToIndex(location: 400, length: 1, scrollRatio: 0.95)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                tool.getReaderVisibleAnchor { anchor in
                    guard let anchor else { XCTFail("visible character missing"); done.fulfill(); return }
                    XCTAssertGreaterThan(anchor.index, 0)
                    web.frame.size = CGSize(width: 450, height: 650)
                    web.layoutIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        tool.restoreReaderVisibleAnchor(anchor) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                tool.evaluateJsToStringDoubleDictionary(jsString: "GetReaderAnchorRect(\(anchor.index));") { rect in
                                    guard let rect else { XCTFail("saved character missing"); done.fulfill(); return }
                                    let actual = vertical ? rect["x"]! : rect["y"]!
                                    let expected = vertical ? anchor.xRatio * Double(web.bounds.width) : anchor.yRatio * Double(web.bounds.height)
                                    XCTAssertEqual(actual, expected, accuracy: 1.5)
                                    done.fulfill()
                                }
                            }
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 15)
    }
}
