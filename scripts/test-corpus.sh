#!/bin/bash
# Runs the scroll-capture corpus test in an optimized build (the matcher is ~60x slower unoptimized).
set -euo pipefail
cd "$(dirname "$0")/.."
swift test -c release -Xswiftc -enable-testing --filter ImageStitcherCorpusTests
