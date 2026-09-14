#!/bin/bash
# Downloads the brand typefaces (OFL) from the Google Fonts repository into the UI resource bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="Sources/MiracleShotUI/Resources/fonts"
# Pinned to one google/fonts commit so a re-run reproduces the committed files.
BASE="https://github.com/google/fonts/raw/809e4d8b8d7e9364a914909bb777679606c178b8/ofl"
mkdir -p "$DEST"
curl -fsSL "$BASE/onest/Onest%5Bwght%5D.ttf" -o "$DEST/Onest-Variable.ttf"
curl -fsSL "$BASE/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf" -o "$DEST/JetBrainsMono-Variable.ttf"
curl -fsSL "$BASE/geologica/Geologica%5BCRSV,SHRP,slnt,wght%5D.ttf" -o "$DEST/Geologica-Variable.ttf"
ls -la "$DEST"
