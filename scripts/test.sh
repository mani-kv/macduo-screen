#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
framework_dir="${DEVELOPER_DIR:-}/Library/Developer/Frameworks"
if [[ -d "$framework_dir/Testing.framework" ]]; then
  ./scripts/swift.sh test --disable-xctest -Xswiftc -F -Xswiftc "$framework_dir" \
    -Xlinker -rpath -Xlinker "$framework_dir" \
    -Xlinker -rpath -Xlinker "$DEVELOPER_DIR/Library/Developer/usr/lib"
else
  ./scripts/swift.sh test --disable-xctest
fi
