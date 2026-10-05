#!/bin/zsh
# Baut MED2MIDI als Release und legt es nach /Applications.
#
# Dorthin, nicht nach ~/Applications: Wer ein Programm sucht, sucht dort, wo
# Programme liegen. Die Rechtefrage ist das kleinere Problem.
set -e
cd "$(dirname "$0")/.."

./Werkzeuge/bundle.sh release

ZIEL="/Applications/MED2MIDI.app"
if [[ -d "$ZIEL" ]]; then
  echo "Ersetze $ZIEL"
  rm -rf "$ZIEL"
fi
cp -R .build/MED2MIDI.app "$ZIEL"

# Die Signatur neu setzen, sonst meint Gatekeeper, das Bündel sei verändert
# worden — beim Kopieren ändern sich Zeitstempel und Attribute.
codesign --force --deep --sign - "$ZIEL" 2>/dev/null || true
xattr -dr com.apple.quarantine "$ZIEL" 2>/dev/null || true

echo "$ZIEL  ($(du -sh "$ZIEL" | cut -f1))"
