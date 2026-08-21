//
//  VoicevoxAccentSettingViewController.swift
//  NovelSpeaker
//
//  「読みの修正」1行に対して、VOICEVOX での読みとアクセントを決める画面。
//
//  ★数値では選べない。
//  「橋」なのか「箸」なのかは無意識に言い分けているもので、
//  「アクセント核は1です」と言われて分かる人はほとんどいない。
//  候補を並べて、押したらその場で鳴らして、耳で選んでもらう。
//
//  ★候補を鳴らす時は助詞を付ける。
//  平板(0)と尾高(モーラ数と同じ値)は、その語だけでは**まったく同じ音**になる。
//  違うのは後ろに付く助詞が下がるかどうかだけなので、単独で鳴らすと
//  「同じ音しか出ない」という状態になる(実物で確認済み・VoicevoxAccentTest)。
//
//  読み(カタカナ)は VOICEVOX 自身に出させる。同じ解析器が出した答えなので、
//  こちらで変換規則を持つ必要が無く、しかも本当に使われる読みが手に入る。
//

import UIKit
import Eureka

protocol VoicevoxAccentSettingDelegate: AnyObject {
    /// - Parameters:
    ///   - pronunciation: VOICEVOX に渡す読み(カタカナ)。空 = この行では辞書を使わない。
    func voicevoxAccentSettingDidChange(pronunciation: String, accentType: Int, priority: Int)
}

class VoicevoxAccentSettingViewController: FormViewController {

    /// VOICEVOX が実際に目にする文字列(読み替え後、または読み替え前)。
    /// **呼び出し側が決めて渡す。** どちらになるかは、その読み替えが
    /// VOICEVOX に適用されるかどうかで変わる(VoicevoxUserDictionary 参照)。
    var surface: String = ""
    var pronunciation: String = ""
    var accentType: Int = 0
    var priority: Int = VoicevoxUserDictionaryEntry.defaultPriority
    weak var delegate: VoicevoxAccentSettingDelegate?

    /// 今の読みを解析して得たモーラ列。候補の数はこれで決まる。
    private var moras: [String] = []
    /// 候補の行。選び直した時に印だけ付け替えるために持っておく。
    private var accentRows: [(row: LabelRow, accentType: Int)] = []
    /// この内容で VOICEVOX が受け付けてくれるか。
    private var isRegistrable = true
    private let speaker = SpeechBlockSpeaker()
    /// 聞き比べのために一時的に差し替える前の、本来の辞書。
    private var savedDictionaryEntries: [VoicevoxUserDictionaryEntry] = []
    private var isPreviewDictionaryApplied = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("VoicevoxAccentSettingViewController_Title", comment: "VOICEVOX での読みとアクセント")
        savedDictionaryEntries = VoicevoxUserDictionary.shared.entries
        // ★解析の結果を待ってから画面を作ってはいけない。
        //
        // VOICEVOX は actor なので、結果を待つにはセマフォ等で主スレッドを止める事になる。
        // それをやると、actor へ入ろうとしている側と主スレッドが互いを待って**固まる**
        // (実際に画面を開いた瞬間にアプリ全体が反応しなくなった)。
        // 先に空の状態で画面を出し、解析が終わってから書き換える。
        createCells()
        refreshFromVoicevox(loadPronunciationIfEmpty: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        speaker.StopSpeech()
        restoreDictionaryIfNeeded()
        delegate?.voicevoxAccentSettingDidChange(pronunciation: pronunciation, accentType: accentType, priority: priority)
    }

    // MARK: - VOICEVOX に読ませる

    /// VOICEVOX に解析させて、読みとモーラ列を取り直す。
    ///
    /// - Parameter loadPronunciationIfEmpty: 読みが空の時に、VOICEVOX の読み方を初期値として入れるか。
    ///   初めて開いた時はこれで埋まるので、たいていは直す必要があるのはアクセントだけになる。
    private func refreshFromVoicevox(loadPronunciationIfEmpty: Bool, forceLoadPronunciation: Bool = false) {
        let surface = self.surface
        let currentPronunciation = self.pronunciation
        Task { [weak self] in
            var loadedPronunciation: String? = nil
            var loadedAccentType: Int? = nil
            if forceLoadPronunciation || (loadPronunciationIfEmpty && currentPronunciation.isEmpty) {
                if surface.isEmpty == false,
                   let phrases = try? await VoicevoxCore.shared.analyze(text: surface),
                   phrases.isEmpty == false {
                    loadedPronunciation = phrases.kana
                    // 複数のアクセント句に分かれる事があるが、辞書に登録するのは1語なので
                    // 最初の句のアクセントを採る(利用者が聞いて直せる)。
                    loadedAccentType = phrases.first?.accent ?? 0
                }
            }
            let pronunciationToAnalyze = (loadedPronunciation ?? currentPronunciation)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var moras:[String] = []
            if pronunciationToAnalyze.isEmpty == false,
               let phrases = try? await VoicevoxCore.shared.analyze(text: pronunciationToAnalyze) {
                moras = phrases.allMoras.map({ $0.text })
            }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                let previousMoraCount = self.moras.count
                if let loadedPronunciation = loadedPronunciation {
                    self.pronunciation = loadedPronunciation
                    if let loadedAccentType = loadedAccentType { self.accentType = loadedAccentType }
                    if let row = self.form.rowBy(tag: "PronunciationRow") as? TextRow {
                        row.value = loadedPronunciation
                        row.updateCell()
                    }
                }
                self.moras = moras
                if moras.isEmpty {
                    // 解析できない読み(カタカナでない等)。候補は出せないが、
                    // 保存はできるようにしておく。
                    self.accentType = 0
                } else if self.accentType > moras.count {
                    self.accentType = moras.count
                }
                self.updateRegistrableWarning()
                if moras.count == previousMoraCount {
                    // 候補の顔ぶれは変わらないので、印だけ付け替える(スクロール位置を保つ)。
                    self.updateAccentCheckmarks()
                } else {
                    self.reloadAccentSection()
                }
            }
        }
    }

    // MARK: - 画面

    private func createCells() {
        form +++ Section(NSLocalizedString("VoicevoxAccentSettingViewController_SurfaceSectionHeader", comment: "VOICEVOX が読む文字列"))
        <<< LabelRow() {
            $0.title = surface
            $0.cell.textLabel?.numberOfLines = 0
        }

        form +++ Section() {
            $0.footer = HeaderFooterView(stringLiteral: NSLocalizedString("VoicevoxAccentSettingViewController_PronunciationFooter", comment: "カタカナで入力してください。空にすると、この読みの修正では VOICEVOX の辞書を使わなくなります。"))
        }
        <<< TextRow("PronunciationRow") {
            $0.title = NSLocalizedString("VoicevoxAccentSettingViewController_PronunciationTitle", comment: "読み")
            $0.value = pronunciation
            $0.cell.textField.clearButtonMode = .always
            $0.cell.textField.borderStyle = .roundedRect
            $0.cell.accessibilityHint = NSLocalizedString("VoicevoxAccentSettingViewController_PronunciationHint", comment: "VOICEVOX に渡す読みをカタカナで指定します。空にすると辞書を使いません。")
        }.onChange({ [weak self] row in
            guard let self = self else { return }
            self.pronunciation = row.value ?? ""
            self.refreshFromVoicevox(loadPronunciationIfEmpty: false)
        })
        <<< LabelRow("PronunciationWarningRow") { row in
            row.title = NSLocalizedString("VoicevoxAccentSettingViewController_NotRegistrableWarning", comment: "この読みは VOICEVOX に受け付けてもらえません。カタカナで入力してください。")
            row.cell.textLabel?.numberOfLines = 0
            row.cell.textLabel?.textColor = .systemRed
            row.hidden = true
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("VoicevoxAccentSettingViewController_LoadFromVoicevox", comment: "VOICEVOX の読み方を取り込む")
        }.onCellSelection({ [weak self] _, _ in
            self?.refreshFromVoicevox(loadPronunciationIfEmpty: false, forceLoadPronunciation: true)
        })

        form +++ accentSection()

        form +++ Section(NSLocalizedString("VoicevoxAccentSettingViewController_PrioritySectionHeader", comment: "優先度")) {
            $0.footer = HeaderFooterView(stringLiteral: NSLocalizedString("VoicevoxAccentSettingViewController_PriorityFooter", comment: "「黒剣」と「黒剣騎士団」のように、登録した語同士が重なる時にだけ触ってください。長い方が自動的に選ばれる訳ではありません。"))
        }
        <<< SegmentedRow<String>("PriorityRow") {
            $0.options = [
                NSLocalizedString("VoicevoxAccent_PriorityNormal", comment: "ふつう"),
                NSLocalizedString("VoicevoxAccent_PriorityPreferred", comment: "優先する"),
            ]
            $0.value = priority >= VoicevoxUserDictionaryEntry.preferredPriority ? $0.options?.last : $0.options?.first
            $0.cell.accessibilityHint = NSLocalizedString("VoicevoxAccentSettingViewController_PriorityHint", comment: "登録した語同士が重なる時に、こちらを先に使うようにします。")
        }.onChange({ [weak self] row in
            guard let self = self, let options = row.options else { return }
            self.priority = (row.value == options.last)
                ? VoicevoxUserDictionaryEntry.preferredPriority
                : VoicevoxUserDictionaryEntry.defaultPriority
        })
    }

    private static let accentSectionTag = "AccentSection"

    private func accentSection() -> Section {
        let section = Section(NSLocalizedString("VoicevoxAccentSettingViewController_AccentSectionHeader", comment: "アクセント")) {
            $0.tag = Self.accentSectionTag
            $0.footer = HeaderFooterView(stringLiteral: NSLocalizedString("VoicevoxAccentSettingViewController_AccentFooter", comment: "行を選ぶと、その読み方で鳴らします。「が」を付けて鳴らしているのは、平板と尾高が語だけでは同じ音になるためです。"))
        }
        accentRows.removeAll()
        let candidates = VoicevoxAccentDisplay.candidates(moraCount: moras.count)
        if candidates.isEmpty {
            section <<< LabelRow() {
                $0.title = NSLocalizedString("VoicevoxAccentSettingViewController_NoCandidates", comment: "読みをカタカナで入れると、アクセントを選べるようになります。")
                $0.cell.textLabel?.numberOfLines = 0
            }
            return section
        }
        for candidate in candidates {
            let labelRow = LabelRow() { row in
                row.title = VoicevoxAccentDisplay.markedKana(moras: moras, accentType: candidate)
                row.value = VoicevoxAccentDisplay.typeName(accentType: candidate, moraCount: moras.count)
                row.cell.textLabel?.numberOfLines = 0
                row.cell.accessoryType = (candidate == accentType) ? .checkmark : .none
                // VoiceOver では ꜜ が読まれないので、型の名前で分かるようにしておく。
                row.cell.accessibilityLabel = String(format: NSLocalizedString(
                    "VoicevoxAccentSettingViewController_CandidateAccessibilityFormat",
                    comment: "%1$@型 %2$@"),
                    VoicevoxAccentDisplay.typeName(accentType: candidate, moraCount: moras.count),
                    moras.joined())
                row.cell.accessibilityHint = NSLocalizedString("VoicevoxAccentSettingViewController_CandidateHint", comment: "選ぶと、この読み方で鳴らします。")
            }.onCellSelection({ [weak self] _, _ in
                guard let self = self else { return }
                self.accentType = candidate
                // ★ここで節ごと作り直してはいけない。
                // 作り直すと一覧が先頭までスクロールで戻ってしまい、
                // 候補を順に聞き比べる操作(この画面で一番よくやる事)ができなくなる。
                // 印を付け替えるだけにする。
                self.updateAccentCheckmarks()
                self.preview(accentType: candidate)
            })
            accentRows.append((labelRow, candidate))
            section <<< labelRow
        }
        return section
    }

    /// 「登録できない読み」を出しておく。
    ///
    /// ★ここが無いと一番分かりにくい壊れ方をする。
    /// カタカナ以外を入れても、置換の方は効くので**発話は普通にできてしまう**。
    /// 利用者からは「アクセントだけ効かない」と見え、原因に辿り着けない。
    /// 実際に「ケいケンチ」と入れて気付けなかった、という報告があった。
    private func updateRegistrableWarning() {
        let pronunciation = self.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = self.surface
        let accentType = self.accentType
        guard pronunciation.isEmpty == false, surface.isEmpty == false else {
            setWarning(hidden: true)
            return
        }
        Task { [weak self] in
            let canRegister = await VoicevoxCore.shared.canRegisterUserDictWord(
                surface: surface, pronunciation: pronunciation, accentType: accentType)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                // 待っている間に書き換わっていたら、古い結果は捨てる。
                guard self.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines) == pronunciation else { return }
                self.isRegistrable = canRegister
                self.setWarning(hidden: canRegister)
            }
        }
    }

    private func setWarning(hidden: Bool) {
        guard let row = form.rowBy(tag: "PronunciationWarningRow") else { return }
        guard row.isHidden != hidden else { return }
        if hidden { row.evaluateHidden() }
        row.hidden = Condition(booleanLiteral: hidden)
        row.evaluateHidden()
    }

    private func updateAccentCheckmarks() {
        for (row, candidate) in accentRows {
            row.cell.accessoryType = (candidate == accentType) ? .checkmark : .none
        }
    }

    /// 読みが変わってモーラの数が変わった時だけ、候補の一覧を作り直す。
    private func reloadAccentSection() {
        guard let index = form.allSections.firstIndex(where: { $0.tag == Self.accentSectionTag }) else { return }
        form.remove(at: index)
        form.insert(accentSection(), at: index)
    }

    // MARK: - 聞き比べ

    /// 選んだアクセントで鳴らす。
    ///
    /// 保存前に鳴らすので、本来の辞書を**一時的に**差し替える。
    /// 画面を離れる時に必ず戻す(戻し忘れると、保存していない設定のまま
    /// 読み上げが続いてしまう)。
    private func preview(accentType: Int) {
        let text = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        var entries = savedDictionaryEntries.filter({ $0.surface != surface })
        entries.append(VoicevoxUserDictionaryEntry(surface: text,
                                                   pronunciation: text,
                                                   accentType: accentType,
                                                   priority: VoicevoxUserDictionaryEntry.preferredPriority))
        isPreviewDictionaryApplied = true
        let previewText = VoicevoxAccentDisplay.previewText(kana: text)
        Task { [weak self] in
            await VoicevoxCore.shared.applyUserDictionary(entries)
            await MainActor.run { self?.speak(text: previewText) }
        }
    }

    private func speak(text: String) {
        guard let speakerSetting = Self.previewSpeakerSetting() else {
            DispatchQueue.main.async {
                NiftyUtility.EasyDialogMessageDialog(
                    viewController: self,
                    message: NSLocalizedString("VoicevoxAccentSettingViewController_NoVoiceModel", comment: "音声モデルが1つも取得されていないため、鳴らして確かめる事ができません。読みとアクセントの設定はそのまま保存できます。"))
            }
            return
        }
        speaker.StopSpeech()
        speaker.SetText(content: text, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max,
                        defaultSpeaker: speakerSetting, sectionConfigList: [], waitConfigList: [], speechModArray: [])
        speaker.StartSpeech()
    }

    /// 聞き比べに使う話者。
    ///
    /// **必ず VOICEVOX の話者にする。** 既定の話者が端末の音声だと、
    /// アクセントの指定が何も効かない音が出て、選びようが無くなる。
    private static func previewSpeakerSetting() -> SpeakerSetting? {
        let defaultSpeaker:SpeakerSetting? = RealmUtil.RealmBlock { (realm) -> SpeakerSetting? in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm),
                  let realmDefaultSpeaker = globalState.defaultSpeakerWith(realm: realm) else { return nil }
            return SpeakerSetting(from: realmDefaultSpeaker)
        }
        if let defaultSpeaker = defaultSpeaker, defaultSpeaker.type == "VOICEVOX" {
            return defaultSpeaker
        }
        // 既定が VOICEVOX でないなら、取得済みの話者の1人目で鳴らす。
        guard let style = VoicevoxCore.cachedStyles.first else { return nil }
        return SpeakerSetting(type: "VOICEVOX", voiceIdentifier: "\(style.styleId)")
    }

    private func restoreDictionaryIfNeeded() {
        guard isPreviewDictionaryApplied else { return }
        isPreviewDictionaryApplied = false
        let entries = savedDictionaryEntries
        Task {
            await VoicevoxCore.shared.applyUserDictionary(entries)
            // 聞き比べで作った音は、保存していない設定で作られている。
            // 本文と同じ文字列になる事はまず無いが、混ざったままにはしない。
            VoicevoxCore.shared.schedulePrefetchCacheClear()
        }
    }
}
