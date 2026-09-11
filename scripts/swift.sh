#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use Command Line Tools when available, without changing xcode-select globally.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
exec /usr/bin/xcrun swift "$@"
