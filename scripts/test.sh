#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec ./scripts/swift.sh test --disable-xctest
