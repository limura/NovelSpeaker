#!/bin/sh

# Apply the WKWebView main-thread diagnostic fix after pod install.
ruby "$(dirname "$0")/scripts/patch_erik_main_thread.rb" || exit $?

(cd Pods/IceCream/IceCream/Classes/; patch BackgroundWorker.swift ../../../../IceCream_BackgroundWorker.swift.patch)
patch Pods/IceCream/IceCream/Classes/CKRecordConvertible.swift IceCream_CKRecordConvertible.swift.patch
#(cd Pods/RATreeView/RATreeView/RATreeView/Private\ Files; patch RATreeView+Enums.m ../../../../../RATreeView_RATreeView+Enums.m.patch)
