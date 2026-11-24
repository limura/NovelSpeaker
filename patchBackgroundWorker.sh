#!/bin/sh

cd "$(dirname "$0")" || exit $?
ruby scripts/patch_icecream_worker_startup.rb || exit $?
(cd Pods/RATreeView/RATreeView/RATreeView/Private\ Files; patch RATreeView+Enums.m ../../../../../RATreeView_RATreeView+Enums.m.patch)
