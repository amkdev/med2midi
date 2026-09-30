#!/bin/zsh
# Baut MED2MIDI und packt es in ein .app-Bündel, damit macOS es als
# vollwertiges Programm behandelt (Dock, Menüleiste, Fokus).
set -e
cd "$(dirname "$0")/.."
KONFIG=${1:-debug}
swift build -c "$KONFIG" --product MED2MIDI
APP=".build/MED2MIDI.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$KONFIG/MED2MIDI" "$APP/Contents/MacOS/MED2MIDI"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MED2MIDI</string>
  <key>CFBundleDisplayName</key><string>MED2MIDI</string>
  <key>CFBundleIdentifier</key><string>net.spume.med2midi</string>
  <key>CFBundleExecutable</key><string>MED2MIDI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>OctaMED-Modul</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>CFBundleTypeExtensions</key><array>
      <string>med</string><string>mmd</string><string>mmd0</string>
      <string>mmd1</string><string>mmd2</string><string>mmd3</string><string>*</string>
    </array>
  </dict></array>
</dict></plist>
PLIST
echo "$APP"
