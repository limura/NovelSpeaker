//
//  ActivityIndicatorManager.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/10.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import Foundation
import UIKit
import FTLinearActivityIndicator

enum ActivityIndicatorPlacement {
    static func frame(bounds: CGRect, safeArea: UIEdgeInsets, statusBarHeight: CGFloat, isPad: Bool = false) -> CGRect {
        let portrait = bounds.height >= bounds.width
        let x: CGFloat
        let y: CGFloat
        let usesSideRail = !isPad && safeArea.top == 0 && safeArea.right >= 80 && statusBarHeight >= 0 && statusBarHeight <= 2
        if usesSideRail {
            // Public side-rail insets identify this layout. UIKit does not expose
            // the individual system clock/Wi-Fi frames; stay in its empty header.
            let compact = min(bounds.width, bounds.height) < 600
            // The compact portrait side rail is system-owned and may obscure app
            // subviews even though it lies within window.bounds. Stay inside content.
            x = compact && portrait ? bounds.maxX - safeArea.right - 48 : bounds.maxX - safeArea.right / 2 - 20
            y = compact ? (portrait ? 40 : 46) : (portrait ? 24 : 14)
        } else if isPad || min(bounds.width, bounds.height) >= 600 {
            // A wide scene (including an expanded phone) uses the empty strip at the
            // bottom of its top safe area. This adds no navigation/content inset.
            x = bounds.maxX - safeArea.right - 56
            y = max(2, safeArea.top - 5)
        } else if portrait {
            // Stay on the right even with a short or hidden status bar.
            x = bounds.maxX - safeArea.right - (statusBarHeight > 24 ? 104 : 56)
            y = statusBarHeight > 24 ? min(12, max(6, (statusBarHeight - 32) / 2)) : 2
        } else {
            x = bounds.maxX - safeArea.right - 64
            y = 8
        }
        // The Duo side rail intentionally uses system-side space in some layouts.
        // Other layouts stay within horizontal safe-area insets, including narrow scenes.
        let left = min(bounds.maxX, max(bounds.minX, bounds.minX + safeArea.left + 8))
        let rightInset = usesSideRail ? 0 : safeArea.right
        let right = max(left, min(bounds.maxX, bounds.maxX - rightInset - 8))
        let width = min(40, max(0, right - left))
        let height = min(3, max(0, bounds.height))
        return CGRect(x: max(left, min(x, right - width)),
                      y: max(bounds.minY, min(bounds.minY + y, bounds.maxY - height)),
                      width: width, height: height)
    }
}
private final class SceneIndicatorHost: UIView {
    let indicator = FTLinearActivityIndicator(frame: CGRect(x: 0, y: 0, width: 40, height: 3))
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; accessibilityElementsHidden = true
        // UIKit can append presentation containers after this host. Keep the
        // noninteractive indicator above them without taking window ownership.
        layer.zPosition = 1
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        indicator.tintColor = .label; addSubview(indicator)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        indicator.frame = ActivityIndicatorPlacement.frame(bounds: bounds, safeArea: safeAreaInsets,
            statusBarHeight: window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0,
            isPad: traitCollection.userInterfaceIdiom == .pad)
    }
}

class ActivityIndicatorManager {
    static var isVisualUITesting: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-ActivityIndicatorVisualUITesting")
        #else
        return false
        #endif
    }
    private static let lock = NSLock()
    private static var enableIDSet = Set<String>()
    
    // Render inside each visible phone/tablet scene; no status-bar or navigation layout ownership.
    private static let indicators = NSMapTable<UIWindow, SceneIndicatorHost>.weakToStrongObjects()
    private static var displayObservers: [NSObjectProtocol] = []
    static func configureDisplay() {
        precondition(Thread.isMainThread)
        guard displayObservers.isEmpty else { return }
        for name in [UIApplication.didBecomeActiveNotification, UIWindow.didBecomeVisibleNotification] {
            displayObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in apply() })
        }
        apply()
    }
    private static func apply() {
        DispatchQueue.main.async {
            lock.lock(); let active = !enableIDSet.isEmpty; lock.unlock()
            guard UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad else { return }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap { $0.windows }.filter { !$0.isHidden && $0.windowLevel == .normal && $0.rootViewController != nil }
            for window in windows {
                var host = indicators.object(forKey: window)
                if host == nil && active {
                    let view = SceneIndicatorHost(frame: window.bounds)
                    window.addSubview(view); indicators.setObject(view, forKey: window); host = view
                }
                host?.setNeedsLayout(); host?.layoutIfNeeded()
                if active {
                    if host?.indicator.isAnimating == false { host?.indicator.startAnimating() }
                    host?.indicator.isHidden = false
                    if let host { window.bringSubviewToFront(host) }
                } else { host?.indicator.stopAnimating(); host?.indicator.isHidden = true }
            }
        }
    }

    static func enable(id:String) {
        lock.lock()
        if enableIDSet.contains(id) {
            lock.unlock()
            return
        }
        enableIDSet.insert(id)
        lock.unlock()
        apply()
    }
    
    static func disable(id:String) {
        lock.lock()
        if enableIDSet.contains(id) {
            enableIDSet.remove(id)
            lock.unlock()
            apply()
            return
        }
        lock.unlock()
    }
    
    static func isEnable(id:String) ->Bool {
        lock.lock(); defer { lock.unlock() }
        return enableIDSet.contains(id)
    }

    #if DEBUG && targetEnvironment(simulator)
    static var activeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return enableIDSet.count
    }
    #endif

}

#if DEBUG && targetEnvironment(simulator)
final class ActivityIndicatorVisualFixture: UIViewController {
    private var gates: [String: DispatchSemaphore] = [:]
    private let status = UILabel()
    private var timer: Timer?
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = "Indicator fixture"
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16
        for key in ["A", "B"] {
            let start = UIButton(type: .system); start.setTitle("Start " + key, for: .normal); start.accessibilityIdentifier = "IndicatorStart" + key
            start.addAction(UIAction { [weak self] _ in self?.start(key) }, for: .touchUpInside); stack.addArrangedSubview(start)
            let stop = UIButton(type: .system); stop.setTitle("Stop " + key, for: .normal); stop.accessibilityIdentifier = "IndicatorStop" + key
            stop.addAction(UIAction { [weak self] _ in self?.gates.removeValue(forKey: key)?.signal() }, for: .touchUpInside); stack.addArrangedSubview(stop)
        }
        let push = UIButton(type: .system); push.setTitle("Push dark screen", for: .normal); push.accessibilityIdentifier = "IndicatorPush"
        push.addAction(UIAction { [weak self] _ in
            let next = UIViewController(); next.view.backgroundColor = .systemBackground; next.title = "Dark fixture"
            // Use an explicit return control: Duo may relocate the navigation back button.
            let back = UIButton(type: .system)
            back.setTitle("Return to fixture", for: .normal)
            back.accessibilityIdentifier = "IndicatorReturn"
            back.addAction(UIAction { [weak next] _ in
                next?.navigationController?.popViewController(animated: false)
            }, for: .touchUpInside)
            next.view.addSubview(back)
            back.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                back.centerXAnchor.constraint(equalTo: next.view.centerXAnchor),
                back.topAnchor.constraint(equalTo: next.view.safeAreaLayoutGuide.topAnchor, constant: 30)
            ])
            self?.view.window?.overrideUserInterfaceStyle = .dark
            self?.navigationController?.pushViewController(next, animated: false)
        }, for: .touchUpInside); stack.addArrangedSubview(push)
        if ProcessInfo.processInfo.arguments.contains("-IndicatorExtendedLayoutTesting") {
            let layout = UIButton(type: .system); layout.setTitle("Present tabs", for: .normal); layout.accessibilityIdentifier = "IndicatorShowLayout"
            layout.addAction(UIAction { [weak self] _ in
                let tabs = IndicatorLayoutTabs()
                let first = IndicatorLayoutPage(); first.title = "First layout"
                let second = IndicatorLayoutPage(); second.title = "Second layout"
                let one = IndicatorLayoutNavigation(rootViewController: first), two = IndicatorLayoutNavigation(rootViewController: second)
                one.tabBarItem.title = "First"; two.tabBarItem.title = "Second"
                tabs.viewControllers = [one, two]; tabs.modalPresentationStyle = .fullScreen
                tabs.modalPresentationCapturesStatusBarAppearance = true
                self?.present(tabs, animated: false)
            }, for: .touchUpInside); stack.addArrangedSubview(layout)
        }
        status.numberOfLines = 0; status.accessibilityIdentifier = "IndicatorVisualState"; stack.addArrangedSubview(status)
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)])
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateState() }
        updateState()
    }
    private func start(_ key: String) {
        guard gates[key] == nil else { return }
        let gate = DispatchSemaphore(value: 0); gates[key] = gate
        DispatchQueue.global().async {
            let id = "indicator-fixture:" + UUID().uuidString
            ActivityIndicatorManager.enable(id: id)
            defer { ActivityIndicatorManager.disable(id: id) }
            _ = gate.wait(timeout: .now() + 60)
        }
    }
    static func visualState() -> String {
        func count(_ view: UIView) -> Int { (view is FTLinearActivityIndicator && !view.isHidden && view.alpha > 0 ? 1 : 0) + view.subviews.reduce(0) { $0 + count($1) } }
        let windows = UIApplication.shared.windows
        let sceneViews = windows.filter { $0.windowScene != nil && !$0.isHidden }.reduce(0) { $0 + count($1) }
        func drawn(_ view: UIView) -> Int {
            let own = view is FTLinearActivityIndicator && !view.isHidden && (view.layer.sublayers ?? []).contains { $0.bounds.width > 0 && $0.bounds.height > 0 }
            return (own ? 1 : 0) + view.subviews.reduce(0) { $0 + drawn($1) }
        }
        let drawnViews = windows.filter { $0.windowScene != nil && !$0.isHidden }.reduce(0) { $0 + drawn($1) }
        let orphanViews = windows.filter { $0.windowScene == nil }.reduce(0) { $0 + count($1) }
        let window = windows.first { $0.isKeyWindow && $0.windowScene != nil }
        let statusFrame = window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero
        func frames(_ view: UIView) -> [String] {
            let own = view is FTLinearActivityIndicator && !view.isHidden ? [String(describing: view.convert(view.bounds, to: window))] : []
            return own + view.subviews.flatMap { frames($0) }
        }
        let indicatorFrames = window.map { frames($0) } ?? []
        return "indicatorWindowFrames=\(indicatorFrames) active=\(ActivityIndicatorManager.activeCount) sceneViews=\(sceneViews) orphanViews=\(orphanViews) drawnViews=\(drawnViews) bounds=\(window?.bounds ?? .zero) safe=\(window?.safeAreaInsets ?? .zero) status=\(statusFrame)"
    }
    private func updateState() { status.text = Self.visualState() }
    deinit { timer?.invalidate(); for gate in gates.values { gate.signal() } }
}
private final class IndicatorLayoutNavigation: UINavigationController {
    override var childForStatusBarHidden: UIViewController? { topViewController }
}
private final class IndicatorLayoutTabs: UITabBarController {
    override var childForStatusBarHidden: UIViewController? { selectedViewController }
}
private final class IndicatorLayoutPage: UIViewController {
    private var fullScreen = false
    private let status = UILabel()
    private var timer: Timer?
    override var prefersStatusBarHidden: Bool { fullScreen }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let stack=UIStackView();stack.axis = .vertical;stack.spacing=20
        let toggle=UIButton(type:.system);toggle.setTitle("Toggle full-screen",for:.normal);toggle.accessibilityIdentifier="IndicatorToggleFullScreen"
        toggle.addAction(UIAction { [weak self] _ in
            guard let self else {return};fullScreen.toggle()
            navigationController?.setNavigationBarHidden(fullScreen,animated:false)
            tabBarController?.tabBar.isHidden=fullScreen
            setNeedsStatusBarAppearanceUpdate();navigationController?.setNeedsStatusBarAppearanceUpdate();tabBarController?.setNeedsStatusBarAppearanceUpdate()
        },for:.touchUpInside);stack.addArrangedSubview(toggle)
        let close=UIButton(type:.system);close.setTitle("Close layout",for:.normal);close.accessibilityIdentifier="IndicatorLayoutClose"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated:false) },for:.touchUpInside);stack.addArrangedSubview(close)
        status.numberOfLines=0;status.accessibilityIdentifier="IndicatorLayoutState";stack.addArrangedSubview(status)
        view.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:30),stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20)])
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in
            guard let self else {return}
            status.text=ActivityIndicatorVisualFixture.visualState()+" surface=\(Int(view.bounds.width))x\(Int(view.bounds.height)) safeTop=\(Int(view.window?.safeAreaInsets.top ?? 0))"
        }
    }
    deinit {timer?.invalidate()}
}

#endif
