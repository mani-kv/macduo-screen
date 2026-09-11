#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
./scripts/swift.sh build -c "$configuration" --product MacFold
binary_dir="$(./scripts/swift.sh build -c "$configuration" --show-bin-path)"
app_path="$PWD/dist/MacFold.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/MacFold" "$app_path/Contents/MacOS/MacFold"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
resource_bundle="$binary_dir/MacFold_MacFold.bundle"
if [[ ! -d "$resource_bundle" ]]; then
  echo "Missing Swift resource bundle: $resource_bundle" >&2
  exit 1
fi
ditto "$resource_bundle" "$app_path/Contents/Resources/MacFold_MacFold.bundle"
# Stable bundle identity for local use. Distribution requires Developer ID
# signing and notarization; pass SIGNING_IDENTITY to use an installed identity.
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app_path"
codesign --verify --strict "$app_path"
echo "Built $app_path"
