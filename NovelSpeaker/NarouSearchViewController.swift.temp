//
//  NarouSearchViewController.swift
//  
//
//  Created by 飯村卓司 on 2019/05/24.
//

import UIKit

class NarouSearchViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        textView.text = NSLocalizedString("NarouSearchViewController_NarouSearchTabDeletedAnnounceText", comment: "「なろう検索」タブ終了のお知らせ\n\n以前からお知らせしておりました通り、「なろう検索」タブ関連の機能は削除されました。今後は「Web取込」機能をご活用ください。\n「なろう検索」と同様の検索機能は 小説家になろう様 側にあります検索ページをご利用ください。「Web取込」機能で取り込まれた小説は概ね「なろう検索」経由で取り込んだ小説と同様の使い勝手になっています。「Web取込」タブでの小説の取り込み方は、概ね\n\n『取り込みたい小説の本文が表示されている状態にした上で、右下の「取り込み」ボタンを押す』\n\n事で行えます。「Web取込」機能による小説の取り込み方の詳しい使い方につきましてはサポートサイト下部にあります「Web取込機能について」のページをご参照ください。")
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    func openURLInWebImportTab(url:URL) {
        let tabIndex = 2 // TODO: 謎の固定値 2 が書いてある
        guard let targetViewController = self.tabBarController?.viewControllers?[tabIndex] as? ImportFromWebPageViewController else {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            return
        }
        targetViewController.openTargetUrl = url
        self.tabBarController?.selectedIndex = tabIndex
    }

    @IBAction func goToNarouSearchButtonClicked(_ sender: Any) {
        guard let url = URL(string: "https://yomou.syosetu.com/search.php") else { return }
        openURLInWebImportTab(url: url)
    }
    @IBAction func webImportUsageButtonClicked(_ sender: Any) {
        guard let url = URL(string: "https://limura.github.io/NovelSpeaker/WebImport.html?utm_source=KotosekaiApp&utm_medium=InAppBrowser&utm_campaign=FromSearchTabDeletedAnnounce") else { return }
        openURLInWebImportTab(url: url)
    }
}
