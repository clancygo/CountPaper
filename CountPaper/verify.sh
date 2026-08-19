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
test_sources=("$script_dir/CountPaper.swift" "$script_dir"/Ledger*.swift "$script_dir"/Core/*.swift "$script_dir/Tests/LedgerParserTests.swift")
DEVELOPER_DIR="$developer_dir" xcrun swiftc -O -framework Cocoa \
  -module-cache-path "$script_dir/build/module-cache" \
  "${test_sources[@]}" \
  -o "$test_binary"
"$test_binary"

"$script_dir/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$script_dir/build/CountPaper.app"
echo "CountPaper verification passed."
