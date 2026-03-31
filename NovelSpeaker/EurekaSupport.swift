import Foundation
import Eureka

#if targetEnvironment(macCatalyst)
func ConfigureCatalystSingleSelectionPushRow<T: Equatable>(_ row: PushRow<T>) {
    row.presentationMode = .show(controllerProvider: ControllerProvider.callback {
        let controller = SelectorViewController<SelectorRow<PushSelectorCell<T>>> { _ in }
        controller.enableDeselection = false
        return controller
    }, onDismiss: { vc in
        let _ = vc.navigationController?.popViewController(animated: true)
    })
}
#endif
