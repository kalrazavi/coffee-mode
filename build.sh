#!/bin/zsh
# Rebuilds Coffee Mode.app from src/main.swift and installs it in /Applications.
set -e
cd "$(dirname "$0")"
mkdir -p build preview
swiftc -swift-version 5 -O -o build/CoffeeMode src/main.swift -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement
./build/CoffeeMode --render "$PWD/preview"
APP="build/Coffee Mode.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/CoffeeMode "$APP/Contents/MacOS/CoffeeMode"
rm -rf build/icon.iconset; mkdir build/icon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s preview/icon_1024.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) preview/icon_1024.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Coffee Mode</string>
<key>CFBundleDisplayName</key><string>Coffee Mode</string>
<key>CFBundleIdentifier</key><string>local.coffeemode</string>
<key>CFBundleExecutable</key><string>CoffeeMode</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP"
pkill -x CoffeeMode 2>/dev/null || true
rm -rf "/Applications/Coffee Mode.app"
cp -R "$APP" "/Applications/Coffee Mode.app"
echo "installed"
