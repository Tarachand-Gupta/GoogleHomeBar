#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GoogleHomeBar"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_TO_APPS=false

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL_TO_APPS=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

cd "$ROOT_DIR"

echo "Building $APP_NAME (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Error: Built binary not found at $BIN_PATH"
    exit 1
fi

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Generate crisp app icon using AppKit/SF Symbols + iconutil
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift - "$ICONSET_DIR" << 'SWIFT'
import AppKit
import Foundation

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    let inset = CGFloat(px) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(px) * 0.22
    let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.17, green: 0.49, blue: 0.96, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.09, green: 0.30, blue: 0.78, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -90)

    if let symbol = NSImage(systemSymbolName: "house.fill", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.44, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let styled = symbol.withSymbolConfiguration(cfg) {
            let symSize = styled.size
            let drawRect = NSRect(
                x: (CGFloat(px) - symSize.width) / 2,
                y: (CGFloat(px) - symSize.height) / 2,
                width: symSize.width,
                height: symSize.height
            )
            styled.draw(in: drawRect)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: iconsetPath).appendingPathComponent(name))
}
SWIFT

iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "Code-signing (ad-hoc) $APP_BUNDLE..."
codesign --force --deep --sign - --identifier "com.playground.GoogleHomeBar" "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"

if [[ "$INSTALL_TO_APPS" == true ]]; then
    echo "Installing to /Applications/$APP_NAME.app..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "Installed: /Applications/$APP_NAME.app"
fi
