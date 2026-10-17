#!/bin/zsh
# Builds build/Fringe.app: release binary, Info.plist, stable code signature.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Fringe
staging="$(mktemp -d "${TMPDIR:-/tmp}/fringe-app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Fringe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Fringe" "$app/Contents/MacOS/Fringe"
[[ -f Assets/AppIcon.icns ]] && cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Fringe</string>
<key>CFBundleDisplayName</key><string>Fringe</string>
<key>CFBundleIdentifier</key><string>local.daniil.fringe</string>
<key>CFBundleExecutable</key><string>Fringe</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>ru</string>
<key>CFBundleLocalizations</key><array><string>ru</string><string>en</string></array>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Fringe shows your upcoming events in the notch. / Fringe показывает ближайшие события в шторке.</string>
<key>NSDesktopFolderUsageDescription</key><string>Fringe shows your recent screenshots. / Fringe показывает последние скриншоты.</string>
</dict></plist>
PLIST
# The same Apple Development identity as Switchboard keeps the designated requirement stable,
# so macOS privacy grants (Calendar, Desktop) survive rebuilds. Ad-hoc grants reset every build.
identity="${FRINGE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning | awk '/"Apple Development: /{print $2; exit}')"
fi
if [[ -n "$identity" && "$identity" != "-" ]]; then
  codesign --force --timestamp=none --sign "$identity" "$app"
else
  print -u2 "warning: no Apple Development identity; signing ad-hoc, so macOS privacy grants reset on every build"
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
mkdir -p build
rm -rf build/Fringe.previous.app
[[ -d build/Fringe.app ]] && mv build/Fringe.app build/Fringe.previous.app
mv "$app" build/Fringe.app
rm -rf build/Fringe.previous.app
print "Updated: $PWD/build/Fringe.app"
