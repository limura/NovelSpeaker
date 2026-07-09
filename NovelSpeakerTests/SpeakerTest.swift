//
//  SpeakerTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import XCTest
import UIKit
import AVFoundation
import RealmSwift
@testable import NovelSpeaker

class SpeakerTest: XCTestCase {
    var speaker = SpeechBlockSpeaker()

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        speaker = SpeechBlockSpeaker()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

}

// ナビバー右上ボタン群のクリップ検出ロジック(NovelSpeakerUtility.UpperButtonBarLayout)の検証。
// 実アプリと同じ「customView(container) + UIStackView(28pt ボタン)」構造を実ウインドウに載せて
// レイアウトさせ、rightmostButtonOverflow がクリップの有無を実測から正しく返すことを確認する。
class UpperButtonBarLayoutTest: XCTestCase {
    private var window: UIWindow!

    private func makeButton() -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "circle"), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        let w = b.widthAnchor.constraint(equalToConstant: 28); w.priority = UILayoutPriority(999); w.isActive = true
        let h = b.heightAnchor.constraint(equalToConstant: 28); h.priority = UILayoutPriority(999); h.isActive = true
        return b
    }

    // 実アプリの assignUpperButtons と同じ構造でナビバーを組み立ててレイアウトし、
    // (navBar, stack, container) を返す。
    private func layoutNavBar(title: String, buttonCount: Int, screenWidth: CGFloat) -> (UINavigationBar, UIStackView, UIView) {
        let root = UIViewController()
        root.navigationItem.title = title

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<buttonCount { stack.addArrangedSubview(makeButton()) }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let cap = container.widthAnchor.constraint(lessThanOrEqualToConstant: screenWidth * 0.76)
        cap.priority = UILayoutPriority(999); cap.isActive = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        root.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: container)

        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: screenWidth, height: 800))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        // 実レイアウトを確定させる
        nav.view.setNeedsLayout()
        nav.view.layoutIfNeeded()
        nav.navigationBar.setNeedsLayout()
        nav.navigationBar.layoutIfNeeded()
        return (nav.navigationBar, stack, container)
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // 少数ボタン(2個)は iPhone 幅で必ず収まるので、はみ出し量は 0 以下(=クリップ無し)であること。
    func testFewButtonsDoNotOverflow() throws {
        let (navBar, stack, container) = layoutNavBar(title: "テスト小説", buttonCount: 2, screenWidth: 390)
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        let value = try XCTUnwrap(overflow, "window に載っていれば実測できるはず")
        XCTAssertLessThanOrEqual(value, 0.5, "2個のボタンはクリップされないこと(overflow=\(value))")
    }

    // 多数ボタン(10個=約 316pt)は iPhone 幅(390pt)にタイトル込みでは収まらず、
    // 最右ボタンがはみ出す(=クリップされる)ので overflow > 0 になること。
    // これが検出できることが本修正の肝(黙ってクリップされるのを検知して「…」へ退避する)。
    func testManyButtonsOverflow() throws {
        let (navBar, stack, container) = layoutNavBar(title: "とても長めのタイトル文字列です", buttonCount: 10, screenWidth: 390)
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        let value = try XCTUnwrap(overflow, "window に載っていれば実測できるはず")
        XCTAssertGreaterThan(value, 0.5, "10個のボタンは収まらず最右がクリップされること(overflow=\(value))")
    }

    // 読書画面(SpeechViewController)相当の構成: 戻るボタン付き(=nav stack に2枚)+ タイトル + 右5個。
    // iPhone 標準幅では 5個(検索/詳細/編集/再生/addPage 相当)が収まるはずで、over-trim しない
    // (overflow <= 0)ことを確認する。実機で 5→2 のような過剰削減が起きないことの回帰テスト。
    private func layoutReadingLikeNavBar(title: String, buttonCount: Int, screenWidth: CGFloat) -> (UINavigationBar, UIStackView, UIView) {
        let root = UIViewController()
        root.navigationItem.title = "本棚"

        let page = UIViewController()
        page.navigationItem.title = title
        let stack = UIStackView()
        stack.axis = .horizontal; stack.alignment = .center; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<buttonCount { stack.addArrangedSubview(makeButton()) }
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let cap = container.widthAnchor.constraint(lessThanOrEqualToConstant: screenWidth * 0.76)
        cap.priority = UILayoutPriority(999); cap.isActive = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        page.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: container)

        let nav = UINavigationController(rootViewController: root)
        nav.pushViewController(page, animated: false) // 戻るボタンを出す
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: screenWidth, height: 800))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        nav.view.setNeedsLayout(); nav.view.layoutIfNeeded()
        nav.navigationBar.setNeedsLayout(); nav.navigationBar.layoutIfNeeded()
        return (nav.navigationBar, stack, container)
    }

    func testReadingScreenFiveButtonsFit() throws {
        let (navBar, stack, container) = layoutReadingLikeNavBar(title: "クロード本文A改題テスト", buttonCount: 5, screenWidth: 390)
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        let value = try XCTUnwrap(overflow)
        // 5個は iPhone(390pt)+戻るボタン+12文字タイトルで収まる想定。over-trim しないこと。
        XCTAssertLessThanOrEqual(value, 0.5, "5個は収まるので削らないこと(overflow=\(value))")
    }

    // 本文画面の方針(タイトルは潰してでもボタン数を優先)の回帰テスト。
    // 長いタイトルでも、ナビバーがタイトルを truncate してボタン群にフル幅を譲るので、
    // iPhone 標準幅(390pt)で 7 個までは全ボタンが収まる(overflow <= 0)。
    // 以前はタイトル幅を差し引いた見積もりで「…」込み3個まで減っていた退行の防止。
    func testLongTitleTruncatesForManyButtons() throws {
        for count in [5, 6, 7] {
            let (navBar, stack, container) = layoutReadingLikeNavBar(
                title: "とても長い小説のタイトルですあいうえおかきくけこさしすせそ", buttonCount: count, screenWidth: 390)
            let overflow = try XCTUnwrap(NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container))
            XCTAssertLessThanOrEqual(overflow, 0.5, "長いタイトルでも \(count) 個は収まる(タイトルが truncate される)こと。overflow=\(overflow)")
        }
    }

    // window に載っていない container では測定不能(nil)を返し、呼び出し側が再試行できること。
    func testReturnsNilWhenNotInWindow() {
        let stack = UIStackView()
        stack.addArrangedSubview(makeButton())
        let container = UIView()
        container.addSubview(stack)
        let navBar = UINavigationBar()
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        XCTAssertNil(overflow, "window に載っていなければ nil(測定不能)を返すこと")
    }
}

// 青空文庫HTMLのルビ変換で閉じ <rp>）</rp> の「）」が残らないことの回帰テスト。
class RubyTagConvertTest: XCTestCase {
    // 青空文庫形式(rb + 開き/閉じ rp + rt)。閉じ rp の「）」が残っていた不具合の再現。
    func testAozoraRubyClosingRpRemoved() {
        let html = "<ruby><rb>親譲</rb><rp>（</rp><rt>おやゆず</rt><rp>）</rp></ruby>りの"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: html)
        XCTAssertEqual(result, "|親譲(おやゆず)りの", "閉じ <rp>）</rp> の「）」が残らないこと")
    }

    // rb 無し・開き/閉じ rp 付きのルビも「）」が残らないこと。
    func testRubyWithoutRbClosingRpRemoved() {
        let html = "<ruby>無鉄砲<rp>（</rp><rt>むてっぽう</rt><rp>）</rp></ruby>"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: html)
        XCTAssertEqual(result, "|無鉄砲(むてっぽう)", "rb 無しでも閉じ rp が残らないこと")
    }

    // rp を持たない素朴なルビは従来通り変換できること(退行防止)。
    func testSimpleRubyStillWorks() {
        let html = "<ruby>漢字<rt>かんじ</rt></ruby>"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: html)
        XCTAssertEqual(result, "|漢字(かんじ)", "rp 無しの素朴なルビも変換できること")
    }
}
