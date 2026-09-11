#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

# Release archives always contain an optimized build for the host architecture.
CONFIGURATION=release ./scripts/build-app.sh
app_path="$PWD/dist/MacFold.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
architecture="$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/MacFold")"
case "$architecture" in
  arm64|x86_64) ;;
  *) echo "Unsupported release architecture: $architecture" >&2; exit 1 ;;
esac

archive="MacFold-${version}-macOS-${architecture}.zip"
codesign --verify --deep --strict "$app_path"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$PWD/dist/$archive"
cd dist
/usr/bin/shasum -a 256 "$archive" > "$archive.sha256"
echo "Release archive: $PWD/$archive"
echo "Checksum: $PWD/$archive.sha256"
echo "Signing and notarization status must be disclosed in the release notes."
