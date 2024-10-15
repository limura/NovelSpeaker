//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by 飯村卓司 on 2022/09/22.
//  Copyright © 2022 IIMURA Takuji. All rights reserved.
//

import UIKit
import Social
import UniformTypeIdentifiers


extension Data {
    // From http://stackoverflow.com/a/40278391
    init?(fromHexEncodedString string: String) {
        func decodeNibble(u: UInt16) -> UInt8? {
            switch(u) {
            case 0x30 ... 0x39:
                return UInt8(u - 0x30)
            case 0x41 ... 0x46:
                return UInt8(u - 0x41 + 10)
            case 0x61 ... 0x66:
                return UInt8(u - 0x61 + 10)
            default:
                return nil
            }
        }

        self.init(capacity: string.utf16.count/2)
        var even = true
        var byte: UInt8 = 0
        for c in string.utf16 {
            guard let val = decodeNibble(u: c) else { return nil }
            if even {
                byte = val << 4
            } else {
                byte += val
                self.append(byte)
            }
            even = !even
        }
        guard even else { return nil }
    }
}

class ShareViewController: UIViewController {
    var targetURL:URL? = nil
    let customSchemeAndHost = "novelspeaker://shareurl/"
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var importButton: UIButton!
    @IBOutlet var baseWindowView: UIView!
    @IBOutlet weak var floatingWindowView: UIView!
    
    override func viewDidLoad() {
        baseWindowView.backgroundColor = UIColor.clear.withAlphaComponent(0)
        baseWindowView.layer.cornerRadius = 0
        baseWindowView.layer.shadowRadius = 0
        floatingWindowView.layer.cornerRadius = 10
        floatingWindowView.layer.borderWidth = 2
        floatingWindowView.layer.borderColor =  UIColor.separator.cgColor
        floatingWindowView.layer.shadowColor = UIColor.label.cgColor
        floatingWindowView.layer.shadowOpacity = 1
        floatingWindowView.layer.shadowRadius = 8
        floatingWindowView.layer.shadowOffset = CGSize(width: 4, height: 4)
        setupButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: {
            UIAccessibility.post(notification: .screenChanged, argument: self)
        })
    }

    @IBAction func openButtonClicked(_ sender: Any) {
        guard let url = self.targetURL else {
            print("can not load url. url is nil.")
            self.extensionContext?.cancelRequest(withError: ShareViewController.createErrorString(domain: "invalid argument", code: 2, description: "invalid argument. not URL set."))
            return
        }
        guard let customUrlSchemeURL = URL(string: "\(customSchemeAndHost)\(url.absoluteString)") else {
            print("can not create custom url scheme url: \(customSchemeAndHost)\(url.absoluteString)")
            self.extensionContext?.cancelRequest(withError: ShareViewController.createErrorString(domain: "invalid argument", code: 2, description: "invalid argument. can not create custom URL scheme."))
            return
        }
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                let selector = sel_registerName("openURL:")
                // application.perform(...) を使うと古いAPIを使ってしまうみたいなので open() に変えます。
                // というかこういうエラーが出ていた。(´・ω・`)
                // BUG IN CLIENT OF UIKIT: The caller of UIApplication.openURL(_:) needs to migrate to the non-deprecated UIApplication.open(_:options:completionHandler:). Force returning false (NO).
                //application.perform(selector, with: customUrlSchemeURL)
                application.open(customUrlSchemeURL)
                break
            }
            responder = responder?.next
        }
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    @IBAction func cancelButtonClicked(_ sender: Any) {
        self.extensionContext?.completeRequest(returningItems: [])
    }
    
    static func createErrorString(domain: String, code: Int, description: String) -> NSError {
        print("createErrorString: \(domain), \(code), \(description)")
        return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey.description: description])
    }
    
    func setupButtons() {
        
        func nsSecureCodingURLConvert(url:NSSecureCoding?, error:Error?) {
#if targetEnvironment(macCatalyst)
            // from https://stackoverflow.com/questions/71428481/how-to-get-the-page-url-shared-via-the-share-button-on-macos
            // なんでこんな事しないと駄目なんだ(´・ω・`)
            let hexUrl = url.debugDescription
                .replacingOccurrences(of: "Optional(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: ">", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard let urlData = Data(fromHexEncodedString: hexUrl), let urlString = String(data: urlData, encoding: .utf8), let resultURL = URL(string: urlString) else {
                self.extensionContext?.cancelRequest(withError: ShareViewController.createErrorString(domain: "invalid argument", code: 2, description: "invalid argument. can not convert NSSecureCoding to URL string"))
                return
            }
            self.targetURL = resultURL
#else
            guard let url = url as? NSURL else {
                self.extensionContext?.cancelRequest(withError: ShareViewController.createErrorString(domain: "invalid argument", code: 3, description: "invalid arguments. itemProvider has no contains URL type data.(1)"))
                return
            }
            self.targetURL = url as URL
#endif
        }
        
        guard let item = self.extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = item.attachments?.first else {
            self.extensionContext?.cancelRequest(withError: ShareViewController.createErrorString(domain: "invalid argument", code: 1, description: "invalid arguments. not found inputItems.first or not found itemProvider in first item."))
            return
        }
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (url, error) in
                nsSecureCodingURLConvert(url: url, error: error)
            }
        }else if itemProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (url, error) in
                nsSecureCodingURLConvert(url: url, error: error)
            }
        }else{
            self.extensionContext?.cancelRequest(withError: ShareViewController.createErrorString(domain: "invalid argument", code: 4, description: "invalid arguments. itemProvider has no contains URL type data.(3)"))
            return
        }
    }
}
