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
    var IsEnabledBackupFileSend = false
    var TargetNovelNameSet:Set<RealmNovel> = Set<RealmNovel>()
}

class BugReportViewController: FormViewController, MFMailComposeViewControllerDelegate {
    var additionalHintString:String? = nil
    
    static var value = BugReportViewInputData();
    
    /// 最新のプライバシーポリシーを読んだことがあるか否かを判定して、読んだことがなければ表示して同意を求めます
    func CheckAndDisplayPrivacyPolicy(){
        if let privacyPolicyUrl = NovelSpeakerUtility.privacyPolicyURL {
            NiftyUtility.cashedHTTPGet(url: privacyPolicyUrl, delay: 60*60, successAction: { (data, encoding) in
                guard let currentPrivacyPolicy = String(data: data, encoding: encoding ?? .utf8) else {
                    return
                }
                let readedPrivacyPolicy = NovelSpeakerUtility.GetReadedPrivacyPolicy()
                if currentPrivacyPolicy == readedPrivacyPolicy {
                    return
                }
                DispatchQueue.main.async {
                    NiftyUtility.EasyDialogBuilder(self)
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
                            NovelSpeakerUtility.SetPrivacyPolicyIsReaded(readedText: currentPrivacyPolicy)
                            dialog.dismiss(animated: true, completion: nil)
                        }
                    })
                    .build(isForMessageDialog: true).show()
                }
            }, failedAction: nil)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        CheckAndDisplayPrivacyPolicy()
    }
    
    func checkCanSendEmailWithMFMailComposeViewController(){
        print("checkCanSendEmailWithMFMailComposeViewController")
        if MFMailComposeViewController.canSendMail() {
            print("can send mail")
            return
        }
        print("can not send mail")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NiftyUtility.EasyDialogBuilder(self)
            .title(title: NSLocalizedString("BugReportViewController_NoEMailApp_Title", comment: "メールが送信できません"))
            .textView(content: NSLocalizedString("BugReportViewController_NoEMailApp_Message", comment: "メールを送信する事ができないようです。\nメールアプリにメールアドレスを設定していないか、メールアプリが削除されていると思われます。\nことせかい へのお問い合わせにはe-mailをご利用頂く事が必要となりますので適切に設定して頂けますようお願い致します。"), heightMultiplier: 0.65)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
                dialog.dismiss(animated: false, completion: {
                    _ = self.navigationController?.popViewController(animated: true)
                })
            }
            .build().show()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let isUserSupportDisabled = false
        checkCanSendEmailWithMFMailComposeViewController()
        BehaviorLogger.AddLog(description: "BugReportViewController viewDidLoad", data: [:])

        // 日付は LOGGER_ENABLED であれば ViewDidLoad のたびに上書きで不正な値にしておきます。
        if BehaviorLogger.LOGGER_ENABLED {
            BugReportViewController.value.TimeOfOccurence = Date.init(timeIntervalSinceNow: 60*60*24) // 1日後にしておく(DatePickerで日付を一回戻すだけでいいので)
        }else{
            BugReportViewController.value.TimeOfOccurence = Date.init(timeIntervalSinceNow: 0) // 今
        }

        // Do any additional setup after loading the view.
        form
            +++ Section({ (section) in
                section.tag = "Section_BugReportDisabled"
                section.hidden = isUserSupportDisabled ? false : true
            })
            <<< LabelRow("BugReportDisabledLabelRow") {
                $0.title = NSLocalizedString("BugReportViewController_BugReportIsDisabledNowLabel", comment: "ことせかい ユーザサポート停止中のお知らせ\n\nことせかい は現在ユーザサポートを停止しています。\nこれは、ユーザサポートへの対応業務にかかる時間を捻出するのが大変というのもさることながら、開発者側がお問い合わせ(ユーザ側で発生している何らかの問題)を認識してしまうと、そのお問い合わせに書かれている問題を解決しないと心が休まらないために、「お問い合わせを無視する」という対応が取れない事が問題で、お問い合わせを受ける事だけで心の負担が大きいためです。\nそのため、お問い合わせを受け付けること自体が問題となっており、これを排除するという対応を取ることにしました。\n酷い言い方をしますと、ユーザ様側で何らかの問題が発生していたとしましても、開発者の側で認識されなければ上記の問題を発生させませんため、そのユーザ様側で発生している問題を開発者側に伝える手段を止める、という対応になります。\nこの対応により、ことせかい で発生している不都合が直る頻度が激減する事が予想されるなど、ご不便をおかけすることになるかと思いますが、ご理解いただけますと幸いです。\nなお、ここで書いても読まれないかとは思いながら書きますが、AppStoreのレビュー欄にてお問い合わせを書かれましても、(少なくともユーザサポート停止中の間は、)開発者はAppStoreのレビュー欄を確認致しませんので対応はされない事をご理解下さい。(なお、ことせかい においてはAppStoreのレビュー欄にお問い合わせを書かれる事は、元々非推奨とさせていただいています)")
                $0.cell.textLabel?.numberOfLines = 0
            }
            +++ Section(NSLocalizedString("BugReportViewController_HiddenImportantInformationSectionHeader", comment: "お知らせ")) {
                $0.hidden = true
                $0.tag = "HiddenImportantInformationSectionHeader"
            }
            <<< LabelRow("HiddenImportantInformationLabelRow") {
                $0.title = ""
                $0.hidden = true
                $0.cell.textLabel?.numberOfLines = 0
            }
            +++ Section({ (section) in
                section.tag = "Section_Type"
                section.hidden = isUserSupportDisabled ? true : false
            })
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
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
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
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .caption2)
                $0.cell.textLabel?.numberOfLines = 0
            }
            <<< ButtonRow() {
                $0.title = NSLocalizedString("BugReportViewController_SendNewFeatureButtonTitle",   comment: "ご提案mailを作成する")
            }.onCellSelection({ (butonCellof, buttonRow) in
                let description = BugReportViewController.value.DescriptionOfNewFeature
                let needResponse = BugReportViewController.value.IsNeedResponse
                if BugReportViewController.value.DescriptionOfNewFeature == "" {
                    NiftyUtility.EasyDialogBuilder(self)
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
                $0.hidden = isUserSupportDisabled ? true : false
            }
            <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_BugReportTitle", comment:"不都合がある場合にはこのフォームから入力して報告できます。")
                $0.cell.textLabel?.numberOfLines = 0
            } <<< LabelRow() {
                $0.title = NSLocalizedString("BugReportViewController_InformationOfTheTime", comment: "不都合の発生日時はできるだけ正確に入力してください。単に1日前にずらしただけの情報では何の意味もありませんが、そのような値での報告が大変多く寄せられております。特に、操作ログを添付して頂ける場合には操作ログの該当の日時辺りのログを参照する事で確認作業が捗りますため、なるべく近い日時を入力してくださいますようお願い致します。")
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .caption2)
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
                $0.cell.textLabel?.font = .preferredFont(forTextStyle: .caption2)
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
            <<< MultipleSelectorRow<RealmNovel>("TargetNovelAlertRow") { (row) in
                row.title = NSLocalizedString("BugReportViewController_TargetNovelName", comment: "問題が発生する小説(もしあれば)")
                row.selectorTitle = NSLocalizedString("BugReportViewController_TargetNovelName_SelectorTitle", comment: "問題が発生する小説")
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let novelArray = RealmNovel.GetAllObjectsWith(realm: realm) {
                        row.options = Array(novelArray)
                    }
                }
                row.value = BugReportViewController.value.TargetNovelNameSet
            }.onPresent { from, to in
                to.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: from, action: #selector(self.multipleSelectorDone(_:)))
            }.onChange { row in
                if let value = row.value {
                    BugReportViewController.value.TargetNovelNameSet = value
                }else{
                    BugReportViewController.value.TargetNovelNameSet = []
                }
            }
            <<< SwitchRow("IsEnableLogSend") {
                $0.title = NSLocalizedString("BugReportViewController_IsEnableLogSend", comment: "内部に保存されている操作ログを添付する")
                $0.value = BugReportViewController.value.IsEnabledLogSend
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    let judge = row.value
                    if judge! {
                        NiftyUtility.EasyDialogBuilder(self)
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
            <<< SwitchRow("IsEnableBackupFileSend") {
                $0.title = NSLocalizedString("BugReportViewController_IsEnableBackupFileSend", comment: "軽量バックアップファイルを添付する")
                $0.value = BugReportViewController.value.IsEnabledBackupFileSend
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    let judge = row.value
                    if judge! {
                        NiftyUtility.EasyDialogBuilder(self)
                            .title(title: NSLocalizedString("BugReportViewController_ConfirmEnableBackupFileSend_title", comment:"確認"))
                            .textView(content: NSLocalizedString("BugReportViewController_ConfirmEnableBackupFileSend", comment:"ことせかい の軽量バックアップファイルを不都合報告mailに添付しますか？\n\n軽量バックアップファイルにはダウンロードされた小説の詳細(URL等)が含まれるため、開発者に公開されてしまっては困るような情報を ことせかい に含めてしまっている場合にはOFFのままにしておく必要があります。\nなお、軽量バックアップファイルが添付されておりませんと、開発者側で状況の再現が取りにくくなるため、対応がしにくくなる可能性があります。(添付して頂いても対応できない場合もあります)"), heightMultiplier: 0.6)
                            .addButton(title: NSLocalizedString("Cancel_button", comment: "cancel"), callback: { dialog in
                                row.value = false
                                BugReportViewController.value.IsEnabledBackupFileSend = false
                                row.updateCell()
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: true, completion: nil)
                                }
                            })
                            .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                                BugReportViewController.value.IsEnabledBackupFileSend = true
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: true)
                                }
                            })
                            .build().show()
                    }else{
                        BugReportViewController.value.IsEnabledBackupFileSend = false
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
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .caption2)
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
                    NiftyUtility.EasyDialogBuilder(self)
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
                    NiftyUtility.EasyDialogBuilder(self)
                        .label(text: NSLocalizedString("BugReportViewController_AddBehaviourLogAnnounce", comment: "ことせかい 内部に保存されている操作ログを不都合報告mailに添付しますか？\n\n操作ログにはダウンロードされた小説の詳細(URL等)が含まれるため、開発者に公開されてしまっては困るような情報を ことせかい に含めてしまっている場合には「いいえ」を選択する必要があります。\nまた、操作ログが添付されておりませんと、開発者側で状況の再現が取りにくくなるため、対応がしにくくなる可能性があります。(添付して頂いても対応できない場合もあります)"), textAlignment: .left)
                        .addButton(title: NSLocalizedString("BugReportViewController_NO", comment: "いいえ"), callback: { (dialog) in
                            self.sendBugReportMail(log: nil, description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse, targetNovelSet: BugReportViewController.value.TargetNovelNameSet, isNeedBackupFile: BugReportViewController.value.IsEnabledBackupFileSend, completion: {
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: nil)
                                }
                            })
                        })
                        .addButton(title: NSLocalizedString("BugReportViewController_YES", comment: "はい"), callback: { (dialog) in
                            self.sendBugReportMail(log: BehaviorLogger.LoadLog(), description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse, targetNovelSet: BugReportViewController.value.TargetNovelNameSet, isNeedBackupFile: BugReportViewController.value.IsEnabledBackupFileSend, completion: {
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: nil)
                                }
                            })
                        })
                    .build().show()
                }else{
                    if BugReportViewController.value.IsEnabledLogSend {
                        self.sendBugReportMail(log: NiftyUtility.getLogText(searchString: nil), description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse, targetNovelSet: BugReportViewController.value.TargetNovelNameSet, isNeedBackupFile: BugReportViewController.value.IsEnabledBackupFileSend)
                    }else{
                        self.sendBugReportMail(log: nil, description: BugReportViewController.value.DescriptionOfTheProblem, procedure: BugReportViewController.value.ProblemOccurenceProcedure, date: BugReportViewController.value.TimeOfOccurence, needResponse: BugReportViewController.value.IsNeedResponse, targetNovelSet: BugReportViewController.value.TargetNovelNameSet, isNeedBackupFile: BugReportViewController.value.IsEnabledBackupFileSend)
                    }
                }
            })

        if let url = URL(string: "https://limura.github.io/NovelSpeaker/ImportantInformation.txt") {
            NiftyUtility.cashedHTTPGet(url: url, delay: 60*60,
                successAction: { (data, encoding) in
                    if let str = String(data: data, encoding: encoding ?? .utf8) {
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
    
    @objc func multipleSelectorDone(_ item:UIBarButtonItem) {
        _ = navigationController?.popViewController(animated: true)
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
        let appVersionString = NiftyUtility.GetAppVersionString()
        let isBackgroundFetchEnabled = RealmUtil.RealmBlock { (realm) -> Bool in
            return RealmGlobalState.GetInstanceWith(realm: realm)?.isBackgroundNovelFetchEnabled ?? false
        }
        let additionalHint:String
        if let hint = self.additionalHintString {
            additionalHint = "\n\(hint)"
        }else{
            additionalHint = ""
        }
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
            + "\nuse iCloud sync: \(RealmUtil.IsUseCloudRealm())"
            + "\nAutomatic updates for novels: \(isBackgroundFetchEnabled)"
            + additionalHint
        , isHTML: false)
        present(picker, animated: true, completion: nil)
        return true;

    }

    @discardableResult
    func sendBugReportMail(log:String?, description:String, procedure:String, date:Date, needResponse:String, targetNovelSet:Set<RealmNovel>, isNeedBackupFile:Bool, completion:(() -> Void)? = nil) -> Bool {
        if !MFMailComposeViewController.canSendMail() {
            return false;
        }
        var appVersionString = "*"
        if let infoDictionary = Bundle.main.infoDictionary, let bundleVersion = infoDictionary["CFBundleVersion"] as? String, let shortVersion = infoDictionary["CFBundleShortVersionString"] as? String {
            appVersionString = String.init(format: "%@(%@)", shortVersion, bundleVersion)
        }
        let novelData = targetNovelSet.map { (content) -> String in
            return content.title + "\n" + content.novelID
        }.joined(separator: "\n---\n")
        let isBackgroundFetchEnabled = RealmUtil.RealmBlock { (realm) -> Bool in
            return RealmGlobalState.GetInstanceWith(realm: realm)?.isBackgroundNovelFetchEnabled ?? false
        }
        let additionalHint:String
        if let hint = self.additionalHintString {
            additionalHint = "\n\(hint)"
        }else{
            additionalHint = ""
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
            + "\nuse iCloud sync: \(RealmUtil.IsUseCloudRealm())"
            + "\nAutomatic updates for novels: \(isBackgroundFetchEnabled)"
            + additionalHint
            + "\n" + NSLocalizedString("BugReportViewController_TimeOfOccurrence", comment: "問題発生日時") + ": " + date.description(with: Locale.init(identifier: "ja_JP"))
            + "\n-----\n" + NSLocalizedString("BugReportViewController_SendBugReport_Description", comment: "不都合の概要") + ":\n" + description
            + "\n-----\n" + NSLocalizedString("BugReportViewController_SendBugReport_Procedure", comment: "不都合の再現方法") + ":\n" + procedure
            + "\n-----\n" + NSLocalizedString("BugReportViewController_SendBugReport_TargetNovelNameList", comment: "問題の起こった小説:") + "\n\n" + novelData
            , isHTML: false)
        if let log = log {
            if let data = log.data(using: .utf8) {
                picker.addAttachmentData(data, mimeType: "text/plain", fileName: "operation_log.txt")
            }
        }
        if isNeedBackupFile == true {
            DispatchQueue.main.async {
                let labelTag = 100
                let dialog = NiftyUtility.EasyDialogBuilder(self)
                    .label(text: NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……"), textAlignment: NSTextAlignment.center, tag: labelTag)
                    .build()
                dialog.show()
                DispatchQueue.global(qos: .userInitiated).async {
                    if let backupDataURL = NovelSpeakerUtility.CreateBackupData(withAllStoryContent: false, progress: { (description) in
                        DispatchQueue.main.async {
                            if let label = dialog.view.viewWithTag(labelTag) as? UILabel {
                                label.text = NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……") + "\r\n"
                                    + description
                            }
                        }
                    }), let backupData = try? Data(contentsOf: backupDataURL) {
                        let mimeType:String
                        if backupDataURL.pathExtension == "novelspeaker-backup-json" {
                            mimeType = "application/json; charset=utf-8"
                        }else{
                            mimeType = "application/zip"
                        }
                        picker.addAttachmentData(backupData, mimeType: mimeType, fileName: backupDataURL.lastPathComponent)
                    }
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            DispatchQueue.main.async {
                                self.present(picker, animated: true, completion: completion)
                            }
                        }
                    }
                }
            }
        }else{
            present(picker, animated: true, completion: completion)
        }
        return true;
    }
    // MFMailComposeViewController でmailアプリ終了時に呼び出されるのでこのタイミングで viewController を取り戻します
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)
    }
    
}
