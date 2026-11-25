#!/bin/bash
set -euo pipefail
tests="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$tests/../.." && pwd)"
classes="$root/Pods/IceCream/IceCream/Classes"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
common=(-D ICECREAM_OFFLINE_ACK_TESTS -swift-version 5 -module-cache-path "$work/modules")
sed '/^import RealmSwift$/d' "$classes/Syncable.swift" > "$work/Syncable.swift"
sdkparts=()
for f in PrivateDatabaseManager SyncEngine DatabaseManagerProtocol ErrorHandler PublicDatabaseManager Notification+Name; do
  sdkparts+=("$classes/$f.swift")
done
for test in replay checkpoints cold-start; do
  cp "$tests/$test.swift" "$work/main.swift"
  if ! xcrun swiftc "${common[@]}" "$work/Syncable.swift" "${sdkparts[@]}" "$work/main.swift" -o "$work/run" > "$work/build.log" 2>&1; then
    cat "$work/build.log" >&2; exit 1
  fi
  "$work/run" > "$work/result"
  grep '^PASS ' "$work/result"
done

# Optional running simulator test: no launch/create/install of any app or sim.
# Pass an *already booted disposable* simulator, and its local iOS build
# products containing Realm/Realm.framework and RealmSwift/RealmSwift.framework.
if [[ $# -eq 2 ]]; then
  sim="$1"; products="$2"
  sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  cp "$tests/realm-apply.swift" "$work/main.swift"
  if ! xcrun swiftc "${common[@]}" -target arm64-apple-ios15.0-simulator -sdk "$sdk" \
      -F "$products/Realm" -F "$products/RealmSwift" -framework Realm -framework RealmSwift \
      -Xlinker -rpath -Xlinker "$products/Realm" -Xlinker -rpath -Xlinker "$products/RealmSwift" \
      "$classes"/*.swift "$work/main.swift" -o "$work/realm-runner" > "$work/build.log" 2>&1; then
    cat "$work/build.log" >&2; exit 1
  fi
  SIMCTL_CHILD_REALM_DISABLE_UPDATE_CHECKER=1 xcrun simctl spawn "$sim" "$work/realm-runner" "$work/realm-result"
  cat "$work/realm-result"
  grep -q '^UPDATE-CHECKER-DISABLED$' "$work/realm-result"
  grep -q '^PASS_ASSET$' "$work/realm-result"
  grep -q '^PASS_REALM$' "$work/realm-result"
  grep -q '^PASS_EMPTY_STRING_LIST$' "$work/realm-result"
elif [[ $# -ne 0 ]]; then
  echo 'Usage: run.sh [BOOTED_DISPOSABLE_SIMULATOR_UDID LOCAL_IOS_BUILD_PRODUCTS]' >&2
  exit 2
fi
