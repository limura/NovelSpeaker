//
//  FontSelectViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/05/02.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class FontSelectViewController: FormViewController {
    let sampleText = "老爺は、あたりをはばかる低声で、わずか答えた。「王様は、人を殺します。」"
    let fontSizeFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.title2)
    
    func CreateFontSelectRow(fontTitle:String, fontName:String, sampleText:String) -> LabelRow {
        return LabelRow("") {
            $0.title = String.init(format: "%@\n%@", fontTitle, sampleText)
            $0.cell.textLabel?.numberOfLines = 0
            
            if fontName.count > 0 {
                $0.cell.textLabel?.font = UIFont(name: fontName, size: fontSizeFont.pointSize)
            }else{
                $0.cell.textLabel?.font = UIFont.systemFont(ofSize: fontSizeFont.pointSize)
            }
            $0.tag = fontName
        }.onCellSelection { (labelCallOf, labelRow) in
            if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting, let fontID = labelRow.tag {
                RealmUtil.Write { (realm) in
                    displaySetting.fontID = fontID
                }
            }
            self.navigationController?.popViewController(animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let section = Section()
        section.append(CreateFontSelectRow(fontTitle: NSLocalizedString("FontSelectViewController_DefaultFontTitle", comment: "標準フォント"), fontName: "", sampleText: sampleText))
        for familyName in UIFont.familyNames.sorted() {
            //print(String.init(format: "- %@", familyName))
            for fontName in UIFont.fontNames(forFamilyName: familyName).sorted() {
                //print(String.init(format: "  - %@", fontName))
                let row = CreateFontSelectRow(fontTitle: String(format: "%@/%@", familyName, fontName), fontName: fontName, sampleText: sampleText)
                section.append(row)
            }
        }
        form.append(section)
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

}
