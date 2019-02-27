//
//  BugReportViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/02/26.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit
import MessageUI
import Eureka

struct BugReportViewInputData {
    var TimeOfOccurence = Date.init(timeIntervalSinceNow: 60*60*24) // 1日後にしておく(DatePickerで日付を一回戻すだけでいいので)
    var DescriptionOfTheProblem = ""
    var ProblemOccurenceProcedure = ""
    var IsNeedResponse = NSLocalizedString("BugReportViewController_IsNeedResponse_Maybe", comment: "あっても良い")
    var DescriptionOfNewFeature = ""
    var IsEnabledLogSend = false
}

class BugReportViewController: FormViewController, MFMailComposeViewControllerDelegate {
    static var value = BugReportViewInputData();
    
    /// 最新のプライバシーポリシーを読んだことがあるか否かを判定して、読んだことがなければ表示して同意を求めます
    func CheckAndDisplayPrivacyPolicy(){
        if let privacyPolicyUrl = GlobalDataSingleton.getInstance().getPrivacyPolicyURL() {
            NiftyUtilitySwift.cashedHTTPGet(url: privacyPolicyUrl, delay: 60*60, successAction: { (data) in
                guard let currentPrivacyPolicy = String(data: data, encoding: .utf8) else {
                    return
                }
                let readedPrivacyPolicy = GlobalDataSingleton.getInstance().getReadedPrivacyPolicy()
                if currentPrivacyPolicy == readedPrivacyPolicy {
                    return
                }
                DispatchQueue.main.async {
                    EasyDialog.Builder(self)
                    .text(content: NSLocalizedString("BugReportViewController_PrivacyPolicyAgreementNeeded", comment: "ことせかい のプライバシーポリシーについての同意が必要です"))
                    .textView(content: currentPrivacyPolicy, heightMultiplier: 0.5)
                    .addButton(title: NSLocalizedString("Disagree_Button", comment:"同意しない"), callback: { dialog in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false)
                            self.navigationController?.popViewController(animated: true)
                        }
                    })
                    .addButton(title: NSLocalizedString("Agree_Button", comment:"同意する"), callback: {dialog in
                        DispatchQueue.main.async {
                            GlobalDataSingleton.getInstance().setPrivacyPolicyIsReaded(currentPrivacyPolicy)
                            dialog.dismiss(animated: true, completion: nil)
                        }
                    })
                    .build().show()
                }
            }, failedAction: nil)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        CheckAndDisplayPrivacyPolicy()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "BugReportViewController viewDidLoad", data: [:])

        // 日付は LOGGER_ENABLED であれば ViewDidLoad のたびに上書きで不正な値にしておきます。
        if BehaviorLogger.LOGGER_ENABLED {
            BugReportViewController.value.TimeOfOccurence = Date.init(timeIntervalSinceNow: 60*60*24) // 1日後にしておく(DatePickerで日付を一回戻すだけでいいので)
        }else{
            BugReportViewController.value.TimeOfOccurence = Date.init(timeIntervalSinceNow: 0) // 今
        }

        // Do any additional setup after loading the view.
        form +++ Section(NSLocalizedString("BugReportViewController_HiddenImportantInformationSectionHeader", comment: "お知らせ")) {
                $0.hidden = true
                $0.tag = "HiddenImportantInformationSectionHeader"
            }
            <<< LabelRow("HiddenImportantInformationLabelRow") {
                $0.title = ""
                $0.hidden = true
                $0.cell.textLabel?.numberOfLines = 0
            }
            +++ Section()
            <<< AlertRow<String>() {
                $0.title = NSLocalizedString("BugReportViewController_TypeSelectTitle", comment: "お問い合わせの種類")
                $0.selectorTitle = NSLocalizedString("BugReportViewController_TypeSelectTitle", comment: "お問い合わせの種類")
                $0.options = [
                    NSLocalizedString("BugReportViewController_TypeSelect_NewFeature", comment: "新機能等のご提案"),
                    NSLocalizedString("BugReportViewController_TypeSelect_BugReport", comment: "不都合報告")
                ]
                $0.value = NSLocalizedString("BugReportViewController_TypeSelect_BugReport", comment: "不都合報告")
                }.onChange({ (row) in
                    if let value = row.value {
                        if value == NSLocalizedString("BugReportViewController_TypeSelect_BugReport", comment: "不都合報告") {
                            let bugReportSection = self.form.sectionBy(tag: "Section_BugReport")
                            let newFeatureSection = self.form.sectionBy(tag: "Section_NewFeature")
                            bugReportSection?.hidden = false
                            bugReportSection?.evaluateHidden()
                            newFeatureSection?.hidden = true
                            newFeatureSection?.evaluateHidden()
                        }else if value == NSLocalizedString("BugReportViewController_TypeSelect_NewFeature", comment: "新機能等のご提案") {
                            let bugReportSection = self.form.sectionBy(tag: "Section_BugReport")
                            let newFeatureSection = self.form.sectionBy(tag: "Section_NewFeature")
                            bugReportSection?.hidden = true
                            bugReportSection?.evaluateHidden()
                            newFeatureSection?.hidden = false
                            newFeatureSection?.evaluateHidden()
                        }
                    }
                })
            +++ Section(NSLocalizedString("BugReportViewController_NewFeatureSectionHeader", comment: "新機能等のご提案")) {
                $0.tag = "Section_NewFeature"
                $0.hidden = true
            }
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_InformationForNewFeatureSending", comment: "ことせかい は個人開発のアプリになりますので、開発力はとても低いです。提案された機能で簡単に実装できるものは実装されることが多いですが、実装しないと判断されるものも多くあります。それらについては以下のURL(サポートサイトの下部にリンクがあります)にて解説しておりますので、新機能をご提案なされる前に一度目を通しておいていただければ幸いです。")
                $0.cell.textLabel?.font = .systemFont(ofSize: 14.0)
                $0.cell.textLabel?.numberOfLines = 0
            }
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GoToSupportSite", comment: "サポートサイトを開く")
                }.onCellSelection({ (buttonCellof, buttonRow) in
                    if let url = URL(string: "https://limura.github.io/NovelSpeaker/") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            })
            <<< TextAreaRow(){
                $0.add(rule: RuleRequired())
                $0.placeholder = NSLocalizedString("BugReportViewController_NewFeatureTextArePlaceHolder", comment: "既存の機能の改善案や新機能のご提案など、不都合以外のお問い合わせを書いてください。")
                $0.value = BugReportViewController.value.DescriptionOfNewFeature
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 110)
                }.onChange({ (row) in
                    if let value = row.value {
                        BugReportViewController.value.DescriptionOfNewFeature = value
                    }
                })
            <<< AlertRow<String>() { row in
                row.title = NSLocalizedString("BugReportViewController_IsNeedResponse", comment: "報告への返事")
                row.selectorTitle = NSLocalizedString("BugReportViewController_IsNeedResponse", comment: "報告への返事")
                let never = NSLocalizedString("BugReportViewController_IsNeedResponse_Never", comment: "必要無い")
                let maybe = NSLocalizedString("BugReportViewController_IsNeedResponse_Maybe", comment: "あっても良い")
                let must = NSLocalizedString("BugReportViewController_IsNeedResponse_Must", comment: "必ず欲しい")
                row.options = [maybe, must, never]
                row.value = BugReportViewController.value.IsNeedResponse
                }.onChange({ (row) in
                    if let value = row.value {
                        BugReportViewController.value.IsNeedResponse = value
                    }
                })
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_InformationForIsNeedResponse", comment: "返事が欲しいと設定されている場合には開発者から送信元のメールアドレスへ返信を行います。返信は遅くなる可能性があります。また、@gmail.com からのメールを受け取れるようにしていない場合など、返信が届かない場合があります。")
                $0.cell.textLabel?.font = .systemFont(ofSize: 12.0)
                $0.cell.textLabel?.numberOfLines = 0
            }
            <<< ButtonRow() {
                $0.title = NSLocalizedString("BugReportViewController_SendNewFeatureButtonTitle",   comment: "ご提案mailを作成する")
            }.onCellSelection({ (butonCellof, buttonRow) in
                let description = BugReportViewController.value.DescriptionOfNewFeature
                let needResponse = BugReportViewController.value.IsNeedResponse
                if BugReportViewController.value.DescriptionOfNewFeature == "" {
                    EasyDialog.Builder(self)
                        .title(title: NSLocalizedString("BugReportViewController_ErrorDialog", comment: "問題のある入力項目があります"))
                        .label(text: NSLocalizedString("BugReportViewController_NoDescriptionOfTheNewFeature", comment: "ご提案の内容が空になっています"), textAlignment: .left)
                        .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false, completion: nil)
                            }
                        })
                        .build().show()
                    return;
                }
                self.sendNewFeatureMail(description: description, needResponse: needResponse)
            })
            +++ Section(NSLocalizedString("BugReportViewController_SectionHeader", comment: "不都合の報告")){
                $0.tag = "Section_BugReport"
            }
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_BugReportTitle", comment:"不都合がある場合にはこのフォームから入力して報告できます。")
                $0.cell.textLabel?.numberOfLines = 0
            } <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_InformationOfTheTime", comment: "不都合の発生日時はできるだけ正確に入力してください。単に1日前にずらしただけの情報では何の意味もありませんが、そのような値での報告が大変多く寄せられております。特に、操作ログを添付して頂ける場合には操作ログの該当の日時辺りのログを参照する事で確認作業が捗りますため、なるべく近い日時を入力してくださいますようお願い致します。")
                $0.cell.textLabel?.font = .systemFont(ofSize: 12.0)
                $0.cell.textLabel?.numberOfLines = 0

            } <<< DateTimeRow() {
                $0.title = NSLocalizedString("BugReportViewController_TimeOfOccurrence", comment: "問題発生日時")
                $0.value = BugReportViewController.value.TimeOfOccurence
            }.onChange({ (row) in
                if let value = row.value {
                    BugReportViewController.value.TimeOfOccurence = value
                }
            })
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_DescriptionOfTheProblem", comment: "問題の説明")
            } <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_InformationOfTheProblemWriting", comment: "不都合の再現手順についてはご自身でもう一度アプリを起動したところから同じ操作をして不都合が発生することをお確かめの上、ご報告ください。ご報告頂いた不都合再現手順では再現しない不都合報告が大変多く寄せられております。開発者の手元で再現できないご報告は誠に残念ですが対応できかねます。不都合の再現手順に自信が無い場合は「この報告への返事が欲しい」をONにして送信して頂けますと、後ほど開発者の側から詳しいヒアリングのお返事をさしあげられるため、おすすめです。ただ、開発者側としましては返信を認めるのにも結構な時間を取られてしまっております。返信の要が減るだけでもとても助かりますので、以下の「問題の説明」の入力欄に「不都合が再現しなかった場合のみメールでの返信を希望します」と書き添えておいて頂けると助かります。")
                $0.cell.textLabel?.font = .systemFont(ofSize: 12.0)
                $0.cell.textLabel?.numberOfLines = 0
            } <<< TextAreaRow() {
                $0.add(rule: RuleRequired())
                $0.placeholder = NSLocalizedString("BugReportViewController_DescriptionOfTheProblemPlaceHolder", comment: "起こっている問題を説明してください")
                $0.value = BugReportViewController.value.DescriptionOfTheProblem
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 110)
            }.onChange({ (row) in
                if let value = row.value {
                    BugReportViewController.value.DescriptionOfTheProblem = value
                }
            })
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_ProblemOccurrenceProcedure", comment: "問題発生手順")
            } <<< TextAreaRow() {
                $0.placeholder = NSLocalizedString("BugReportViewController_ProblemOccurrenceProcedurePlaceHolder", comment: "問題が発生するまでの操作手順を書いてください")
                $0.value = BugReportViewController.value.ProblemOccurenceProcedure
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 110)
            }.onChange({ (row) in
                if let value = row.value {
                    BugReportViewController.value.ProblemOccurenceProcedure = value
                }
            })
            <<< SwitchRow("IsEnableLogSend") {
                $0.title = NSLocalizedString("BugReportViewController_IsEnableLogSend", comment: "内部に保存されている操作ログを添付する")
                $0.value = BugReportViewController.value.IsEnabledLogSend
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    let judge = row.value
                    if judge! {
                        EasyDialog.Builder(self)
                            .title(title: NSLocalizedString("BugReportViewController_ConfirmEnableLogSend_title", comment:"確認"))
                            .textView(content: NSLocalizedString("BugReportViewController_ConfirmEnableLogSend", comment:"ことせかい 内部に保存されている操作ログを不都合報告mailに添付しますか？\n\n操作ログにはダウンロードされた小説の詳細(URL等)が含まれるため、開発者に公開されてしまっては困るような情報を ことせかい に含めてしまっている場合にはOFFのままにしておく必要があります。\nなお、操作ログが添付されておりませんと、開発者側で状況の再現が取りにくくなるため、対応がしにくくなる可能性があります。(添付して頂いても対応できない場合もあります)"), heightMultiplier: 0.6)
                            .addButton(title: NSLocalizedString("Cancel_button", comment: "cancel"), callback: { dialog in
                                row.value = false
                                BugReportViewController.value.IsEnabledLogSend = false
                                row.updateCell()
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: true, completion: nil)
                                }
                            })
                            .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                                BugReportViewController.value.IsEnabledLogSend = true
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: true)
                                }
                            })
                            .build().show()
                    }else{
                        BugReportViewController.value.IsEnabledLogSend = false
                    }
                })
            <<< AlertRow<String>() { row in
                row.title = NSLocalizedString("BugReportViewController_IsNeedResponse", comment: "報告への返事")
                row.selectorTitle = NSLocalizedString("BugReportViewController_IsNeedResponse", comment: "報告への返事")
                let never = NSLocalizedString("BugReportViewController_IsNeedResponse_Never", comment: "必要無い")
                let maybe = NSLocalizedString("BugReportViewController_IsNeedResponse_Maybe", comment: "あっても良い")
                let must = NSLocalizedString("BugReportViewController_IsNeedResponse_Must", comment: "必ず欲しい")
                row.options = [maybe, must, never]
                row.value = BugReportViewController.value.IsNeedResponse
            }.onChange({ (row) in
                if let value = row.value {
                    BugReportViewController.value.IsNeedResponse = value
                }
            })
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_InformationForIsNeedResponse", comment: "返事が許可されている場合には開発者から送信元のメールアドレスへ返信を行います。返信は遅くなる可能性があります。また、@gmail.com からのメールを受け取れるようにしていない場合など、返信が届かない場合があります。")
                $0.cell.textLabel?.font = .systemFont(ofSize: 12.0)
                $0.cell.textLabel?.numberOfLines = 0
            } <<< ButtonRow() {
            $0.title = NSLocalizedString("BugReportViewController_SendBugReportButtonTitle", comment: "不都合報告mailを作成する")
            }.onCellSelection({ (butonCellof, buttonRow) in
                var warningMessage = ""
                if BugReportViewController.value.TimeOfOccurence > Date.init(timeIntervalSinceNow: 0) {
                    warningMessage += NSLocalizedString("BugReportViewController_InvalidTimeOfOccurence", comment: "できるだけ正確な日時を指定してください。なお、未来の日時は指定できません。")
                }
                if BugReportViewController.value.DescriptionOfTheProblem == "" {
                    if warningMessage.count > 0 {
                        warningMessage += "\n"
                    }
                    warningMessage += NSLocalizedString("BugReportViewController_NoDescriptonOfTheProblem", comment: "問題の説明欄が空欄になっています。")
                }
                if warningMessage.count > 0 {
                    EasyDialog.Builder(self)
                        .title(title: NSLocalizedString("BugReportViewController_ErrorDialog", comment: "問題のある入力項目があります"))
                        .label(text: warningMessage, textAlignment: .left)
                        .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false, completion: nil)
                            }
                        })
                        .build().show()
                    return;
                }
                if BehaviorLogger.LOGGER_ENABLED {
                    EasyDialog.Builder(self)
                        .label(text: NSLocalizedString("BugReportViewController_AddBehaviourLogAnnounce", comment: "ことせかい 内部に保存されている操作ログを不都合報告mailに添付しますか？\n\n操作ログにはダウンロードされた小説の詳細(URL等)が含まれるため、開発者に公開されてしまっては困るような情報を ことせかい に含めてしまっている場合には「いいえ」を選択する必要があります。\nまた、操作ログが添付されておりませんと、開発者側で状況の再現が取りにくくなるため、対応がしにくくなる可能性があります。(添付して頂いても対応できない場合もあります)"), textAlignment: .left)
                        .addButton(title: NSLocalizedString("BugReportViewController_NO", comment: "いいえ"), callback: { (dialog) in
                            self.sendBugReportMail(log: nil, description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse)
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false, completion: nil)
                            }
                        })
                        .addButton(title: NSLocalizedString("BugReportViewController_YES", comment: "はい"), callback: { (dialog) in
                            self.sendBugReportMail(log: BehaviorLogger.LoadLog(), description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse)
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false, completion: nil)
                            }
                        })
                    .build().show()
                }else{
                    if BugReportViewController.value.IsEnabledLogSend {
                        self.sendBugReportMail(log: NiftyUtilitySwift.getLogText(searchString: nil), description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse)
                    }else{
                        self.sendBugReportMail(log: nil, description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse)
                    }
                }
                self.navigationController?.popViewController(animated: true)
            })
        

        if let url = URL(string: "https://limura.github.io/NovelSpeaker/ImportantInformation.txt") {
            NiftyUtilitySwift.cashedHTTPGet(url: url, delay: 60*60,
                successAction: { (data) in
                    if let str = String(data: data, encoding: .utf8) {
                        var text = ""
                        str.enumerateLines(invoking: { (line, inOut) in
                            if line.count > 0 && line[line.startIndex] != "#" {
                                text += line + "\n"
                            }
                        })
                        if text == "" {
                            return
                        }
                        text = String(text.prefix(text.count - 1))
                        DispatchQueue.main.async {
                            if let labelRow = self.form.rowBy(tag: "HiddenImportantInformationLabelRow") as? LabelRow {
                                labelRow.title = text
                                labelRow.hidden = false
                                labelRow.evaluateHidden()
                                if let section = self.form.sectionBy(tag: "HiddenImportantInformationSectionHeader") {
                                    section.hidden = false
                                    section.evaluateHidden()
                                }
                            }
                        }
                    }
            }, failedAction: nil)
        }

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    @discardableResult
    func sendNewFeatureMail(description:String, needResponse:String) -> Bool {
        if !MFMailComposeViewController.canSendMail() {
            return false;
        }
        let appVersionString = NiftyUtilitySwift.GetAppVersionString()
        
        let picker = MFMailComposeViewController()
        picker.mailComposeDelegate = self;
        picker.setSubject(NSLocalizedString("BugReportViewController_SendNewFeatureMailSubject", comment:"ことせかい 新機能等の提案"))
        picker.setToRecipients(["limuraproducts@gmail.com"])
        picker.setMessageBody(
            description
            + NSLocalizedString("BugReportViewController_SendNewFeatureMailInformation", comment: "\n\n===============\nここより下の行は編集しないでください。\n\n")
            + NSLocalizedString("BugReportViewController_SendBugReport_IsNeedResponse", comment: "返信") + ": " + needResponse
            + "\niOS version: " + UIDevice.current.systemVersion
            + "\nmodel: " + UIDevice.modelName
            + "\nApp version:" + appVersionString
        , isHTML: false)
        present(picker, animated: true, completion: nil)
        return true;

    }

    @discardableResult
    func sendBugReportMail(log:String?, description:String, procedure:String, date:Date, needResponse:String) -> Bool {
        if !MFMailComposeViewController.canSendMail() {
            return false;
        }
        var appVersionString = "*"
        if let infoDictionary = Bundle.main.infoDictionary, let bundleVersion = infoDictionary["CFBundleVersion"] as? String, let shortVersion = infoDictionary["CFBundleShortVersionString"] as? String {
            appVersionString = String.init(format: "%@(%@)", shortVersion, bundleVersion)
        }
        
        let picker = MFMailComposeViewController()
        picker.mailComposeDelegate = self;
        picker.setSubject(NSLocalizedString("BugReportViewController_SendBugReportMailSubject", comment:"ことせかい 不都合報告"))
        picker.setToRecipients(["limuraproducts@gmail.com"])
        picker.setMessageBody(
            NSLocalizedString("BugReportViewController_SendBugReportMailInformation", comment: "\n\n===============\nここより下の行は編集しないでください。\nなお、問題の発生している場面のスクリーンショットなどを添付して頂けると、より対応しやすくなるかと思われます。")
            + "\n"
            + "\n" + NSLocalizedString("BugReportViewController_SendBugReport_IsNeedResponse", comment: "返信を希望する") + ": " + needResponse
            + "\niOS version: " + UIDevice.current.systemVersion
            + "\nmodel: " + UIDevice.modelName
            + "\nApp version:" + appVersionString
            + "\n" + NSLocalizedString("BugReportViewController_TimeOfOccurrence", comment: "問題発生日時") + ": " + date.description(with: Locale.init(identifier: "ja_JP"))
            + "\n-----\n" + NSLocalizedString("BugReportViewController_SendBugReport_Description", comment: "不都合の概要") + ":\n" + description
            + "\n-----\n" + NSLocalizedString("BugReportViewController_SendBugReport_Procedure", comment: "不都合の再現方法") + ":\n" + procedure
            , isHTML: false)
        if let log = log {
            if let data = log.data(using: .utf8) {
                picker.addAttachmentData(data, mimeType: "text/plain", fileName: "operation_log.txt")
            }
        }
        present(picker, animated: true, completion: nil)
        return true;
    }
    // MFMailComposeViewController でmailアプリ終了時に呼び出されるのでこのタイミングで viewController を取り戻します
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)
    }
    
}
