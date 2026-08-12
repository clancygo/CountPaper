#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_path="${1:-$script_dir/build/CountPaper.app}"

if [[ ! -d "$app_path" ]]; then
  print -u2 "Missing app bundle: $app_path"
  exit 2
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
signature_info="$(codesign -dvv "$app_path" 2>&1)"

if [[ "$signature_info" == *"Signature=adhoc"* ]]; then
  print -u2 "Release preflight failed: the app is signed ad-hoc. Sign it with a Developer ID Application certificate first."
  exit 1
fi

if [[ "$signature_info" == *"TeamIdentifier=not set"* ]]; then
  print -u2 "Release preflight failed: no signing team identifier was found."
  exit 1
fi

if [[ "$signature_info" != *"flags=0x10000(runtime)"* && "$signature_info" != *"runtime"* ]]; then
  print -u2 "Release preflight failed: hardened runtime is not enabled."
  exit 1
fi

echo "Release signing preflight passed for: $app_path"
