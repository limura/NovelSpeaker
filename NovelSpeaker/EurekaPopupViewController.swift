//
//  EurekaPopupViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/04/14.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import Eureka

extension UINavigationController {
    func popViewController(animated: Bool, completion: (() -> Void)? = nil) {
        popViewController(animated: animated)
        if animated, let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                completion?()
            }
        } else {
            completion?()
        }
    }
}

// class を作るまでもない位のEurekaを使った ViewController を作る時の utility
class EurekaViewController: FormViewController {
    var formSetupMethod:((_ form:EurekaViewController)->Void)? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        formSetupMethod?(self)
    }
    
    static func CreateEurekaViewController(formSetupMethod:@escaping (_ form:EurekaViewController)->Void) -> EurekaViewController {
        let obj = EurekaViewController()
        obj.formSetupMethod = formSetupMethod
        return obj
    }
}

// Eurekaを使った popup を作る時の utility
class EurekaPopupViewController: FormViewController, UIPopoverPresentationControllerDelegate {
    var formSetupMethod:((_ form:EurekaPopupViewController)->Void)? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.modalPresentationStyle = .popover
        self.popoverPresentationController?.delegate = self
        formSetupMethod?(self)
        //self.preferredContentSize = self.view.intrinsicContentSize
    }
    
    func close(animated:Bool, completion:(()->Void)?) {
        if let navigationController = self.navigationController {
            navigationController.popViewController(animated: animated, completion: completion)
        }else{
            self.dismiss(animated: animated, completion: completion)
        }
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }

    // 画面を回転させられた時に self.preferredContentSize に適切な値を入れようかと思ったんだけれど、
    // どうやら大きさは勝手に変えてくれるというのと、
    // 上下の幅が画面より短い場合になんとかするのが大変そうだった
    // (.preferredContentSize に入れる値を viewDidLoad の時点で計算させるのが大変そうだった)
    // ので諦めますた。
    /*
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        print("transition detected.")
        //self.preferredContentSize = ...
        super.viewWillTransition(to: size, with: coordinator)
    }
     */
    
    // viewDidLoad 時に form を作成させる部分を外注するだけでできる位の物であれば
    // FormViewController を継承した class を作るまでもなく呼び出し側で定義できそうだったので
    // そのような事をする method を作っておきます。
    static func RunSimplePopupViewController(formSetupMethod:@escaping (_ form:EurekaPopupViewController)->Void, parentViewController:UIViewController, animated:Bool, completion:(()->Void)?) {
        let obj = EurekaPopupViewController()
        obj.formSetupMethod = formSetupMethod
        parentViewController.present(obj, animated: animated, completion: completion)
    }
}

