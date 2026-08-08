#!/bin/bash
# build-app.sh
# Rôle : compile ChessnutAir en release et empaquette une application macOS
# « Chessnut Air » avec l'Info.plist déclarant l'accès Bluetooth (NSBluetoothAlwaysUsageDescription),
# indispensable pour que le scan/l'échiquier Chessnut fonctionne.

set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="ChessnutAir.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"

cp "$BIN_DIR/ChessnutAir" "$MACOS/ChessnutAir"
# Le bundle de ressources doit se trouver là où resource_bundle_accessor le cherche
# (Bundle.main.bundleURL appending "ChessnutAir_ChessnutAir.bundle").
cp -R "$BIN_DIR/ChessnutAir_ChessnutAir.bundle" "$APP/ChessnutAir_ChessnutAir.bundle"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Chessnut Air</string>
    <key>CFBundleDisplayName</key>
    <string>Chessnut Air</string>
    <key>CFBundleExecutable</key>
    <string>ChessnutAir</string>
    <key>CFBundleIdentifier</key>
    <string>app.chessnut.air</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>L'accès Bluetooth est utilisé pour détecter, se connecter et communiquer avec votre échiquier Chessnut.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>L'accès Bluetooth est utilisé pour détecter, se connecter et communiquer avec votre échiquier Chessnut.</string>
</dict>
</plist>
PLIST

echo "Créé : $(pwd)/$APP"
