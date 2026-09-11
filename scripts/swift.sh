#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use Command Line Tools when available, without changing xcode-select globally.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
swift_binary="$(/usr/bin/xcrun --find swift)"
test_library_dir="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}/Library"
if [[ -d "${DEVELOPER_DIR:-}/Platforms/MacOSX.platform/Developer/Library" ]]; then
  test_library_dir="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library"
fi
# Some CLT installations contain mismatched SwiftPM frameworks. Xcode's
# standalone toolchain can still use the CLT SDK without invoking xcodebuild.
if [[ "${DEVELOPER_DIR:-}" == /Library/Developer/CommandLineTools ]]; then
  test_library_dir="$DEVELOPER_DIR/Library/Developer"
  # SwiftPM otherwise picks the highest SDK directory, which may be a stale
  # beta newer than the installed compiler. Follow the selected SDK symlink.
  export SDKROOT="${SDKROOT:-$DEVELOPER_DIR/SDKs/MacOSX.sdk}"
  xcode_swift=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
  if ! { "$swift_binary" package --version >/dev/null 2>&1; } 2>/dev/null; then
    if [[ -x "$xcode_swift" ]] && "$xcode_swift" package --version >/dev/null 2>&1; then
      echo "Using Xcode's standalone Swift toolchain with the Command Line Tools SDK." >&2
      swift_binary="$xcode_swift"
      test_library_dir=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library
    else
      echo "Swift Package Manager is unavailable. Repair or reinstall the developer tools." >&2
      exit 1
    fi
  fi
fi
# Testing's macros and runtime must come from the same toolchain release.
if [[ "${1:-}" == test && -d "$test_library_dir/Frameworks/Testing.framework" ]]; then
  shift
  exec "$swift_binary" test "$@" -Xswiftc -F -Xswiftc "$test_library_dir/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_library_dir/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_library_dir/usr/lib"
fi
exec "$swift_binary" "$@"
