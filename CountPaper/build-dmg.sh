#!/bin/zsh
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$script_dir/build"
app_path="$build_dir/CountPaper.app"
stage_dir="$build_dir/dmg-stage"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$script_dir/Info.plist")"
dmg_path="$build_dir/CountPaper-${version}.dmg"
developer_dir="/Applications/Xcode.app/Contents/Developer"
if [[ ! -d "$developer_dir" ]]; then
  developer_dir="$(xcode-select -p)"
fi
rm -rf "$app_path" "$stage_dir"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$stage_dir"
DEVELOPER_DIR="$developer_dir" xcrun swiftc -O -framework Cocoa -module-cache-path "$build_dir/module-cache" "$script_dir/CountPaper.swift" "$script_dir/AppMain.swift" -o "$app_path/Contents/MacOS/CountPaper"
cp "$script_dir/Info.plist" "$app_path/Contents/Info.plist"
if [[ -f "$script_dir/Assets/CountPaperIcon.icns" ]]; then
  cp "$script_dir/Assets/CountPaperIcon.icns" "$app_path/Contents/Resources/CountPaperIcon.icns"
fi
codesign --force --sign - "$app_path"
cp -R "$app_path" "$stage_dir/"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname "CountPaper" -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path"
echo "Created: $dmg_path"
