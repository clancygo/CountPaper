#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$script_dir/build"
app_path="$build_dir/CountPaper.app"
developer_dir="/Applications/Xcode.app/Contents/Developer"
sign_identity="${CODE_SIGN_IDENTITY:--}"
sign_entitlements="${CODE_SIGN_ENTITLEMENTS:-}"

if [[ ! -d "$developer_dir" ]]; then
  developer_dir="$(xcode-select -p)"
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$build_dir/module-cache"
setopt null_glob
swift_sources=("$script_dir"/*.swift "$script_dir"/App/*.swift "$script_dir"/Core/*.swift "$script_dir"/Documents/*.swift "$script_dir"/Features/**/*.swift "$script_dir"/UI/*.swift)
DEVELOPER_DIR="$developer_dir" xcrun swiftc -O -framework Cocoa -module-cache-path "$build_dir/module-cache" "${swift_sources[@]}" -o "$app_path/Contents/MacOS/CountPaper"
cp "$script_dir/Info.plist" "$app_path/Contents/Info.plist"
if [[ -f "$script_dir/Assets/CountPaperIcon.icns" ]]; then
  cp "$script_dir/Assets/CountPaperIcon.icns" "$app_path/Contents/Resources/CountPaperIcon.icns"
fi
if [[ "$sign_identity" == "-" ]]; then
  codesign --force --sign - "$app_path"
  echo "Signed ad-hoc for local development."
else
  sign_args=(--force --options runtime --timestamp --sign "$sign_identity")
  if [[ -n "$sign_entitlements" ]]; then
    sign_args+=(--entitlements "$sign_entitlements")
  fi
  codesign "${sign_args[@]}" "$app_path"
  echo "Signed with identity: $sign_identity"
fi
echo "Created app: $app_path"
