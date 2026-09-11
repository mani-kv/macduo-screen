#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
installation_dir="${MACFOLD_INSTALL_DIR:-/Applications}"
if [[ ! -w "$installation_dir" && -z "${MACFOLD_INSTALL_DIR:-}" ]]; then
  installation_dir="$HOME/Applications"
fi
mkdir -p "$installation_dir"
app_path="$installation_dir/MacFold.app"
if [[ -d "$app_path" ]]; then
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Contents/Info.plist")"
  if [[ "$bundle_id" != "com.macfold.app" ]]; then
    echo "A different app already exists at $app_path." >&2
    exit 1
  fi
fi
# Stop this app's previous processes before replacing its executable.
while IFS= read -r pid; do
  [[ -z "$pid" ]] || kill "$pid"
done < <(pgrep -x MacFold || true)
ditto dist/MacFold.app "$app_path"
codesign --verify --strict "$app_path"
open "$app_path" --args --settings "$@"
echo "Installed and opened $app_path"
