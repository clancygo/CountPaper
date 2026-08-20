#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
developer_dir="/Applications/Xcode.app/Contents/Developer"

if [[ ! -d "$developer_dir" ]]; then
  developer_dir="$(xcode-select -p)"
fi

test_binary="$(mktemp /private/tmp/CountPaperTests.XXXXXX)"
trap 'rm -f "$test_binary"' EXIT

setopt null_glob
# Keep the direct app workflow tests in sync with the production build.  UI
# support types are intentionally split into their own folder, but the tests
# still compile the AppDelegate to exercise document save/open behaviour.
test_sources=("$script_dir/CountPaper.swift" "$script_dir"/Ledger*.swift "$script_dir"/App/*.swift "$script_dir"/Core/*.swift "$script_dir"/Documents/*.swift "$script_dir"/Features/**/*.swift "$script_dir"/UI/*.swift "$script_dir"/Tests/macOS/*.swift)
DEVELOPER_DIR="$developer_dir" xcrun swiftc -O -framework Cocoa \
  -module-cache-path "$script_dir/build/module-cache" \
  "${test_sources[@]}" \
  -o "$test_binary"
"$test_binary"

# CountPaperCore deliberately has no AppKit dependency. Exercise its package
# target separately so future iOS reuse cannot regress behind a green macOS
# application build.
DEVELOPER_DIR="$developer_dir" CLANG_MODULE_CACHE_PATH="$script_dir/build/swiftpm-module-cache" \
  swift test --disable-sandbox --scratch-path "$script_dir/build/swiftpm"

"$script_dir/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$script_dir/build/CountPaper.app"
echo "CountPaper verification passed."
