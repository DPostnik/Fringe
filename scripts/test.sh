#!/bin/zsh
# Runs the app's unit tests and the protocol package's tests. Extra arguments go to `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test "$@"
(cd Packages/FringeProtocol && swift test "$@")
