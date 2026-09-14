#!/bin/bash
# Builds "Miracle Shot.app" from the SwiftPM executable with a stable ad-hoc signature,
# so the Screen Recording permission survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Miracle Shot"
BUNDLE_ID="agency.blackbloom.miracleshot"
OUT="build/$APP_NAME.app"

swift build -c release --product MiracleShot
BIN="$(swift build -c release --show-bin-path)/MiracleShot"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/MiracleShot"

# SwiftPM resource bundles sit next to the binary; copy them into Resources.
for bundle in "$(dirname "$BIN")"/MiracleShot_*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$OUT/Contents/Resources/"
done

# App icon: drawn by scripts/make-icon.swift so no binary lives in the repo.
swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MiracleShot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Miracle Shot needs screen recording access to take screenshots.</string>
</dict>
</plist>
PLIST

# Prefer the self-signed "Miracle Shot Dev" identity (see scripts/make-signing-cert.sh): its designated requirement
# is identifier + certificate, so TCC permissions survive rebuilds. Ad-hoc signing binds them to one build's cdhash.
if security find-identity -v -p codesigning | grep -q "Miracle Shot Dev"; then
  codesign --force --sign "Miracle Shot Dev" --identifier "$BUNDLE_ID" "$OUT"
  echo "Signed with Miracle Shot Dev"
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT"
  echo "Signed ad-hoc (run scripts/make-signing-cert.sh once to keep permissions across rebuilds)"
fi
echo "Built $OUT"
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$OUT" /Applications/
  echo "Installed to /Applications/$APP_NAME.app"
fi
