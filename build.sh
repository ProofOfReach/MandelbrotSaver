#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUNDLE_NAME="MandelbrotSaver"
BUNDLE_DIR="${BUNDLE_NAME}.saver"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Check for Xcode (required for Metal compiler)
if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [ -d "/Applications/Xcode-beta.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
else
    echo "❌ Error: Xcode is required to compile Metal shaders."
    echo ""
    echo "Please install Xcode from the Mac App Store:"
    echo "  https://apps.apple.com/app/xcode/id497799835"
    echo ""
    echo "After installing, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

echo "🔨 Building Mandelbrot Screensaver..."
echo "   Using: $DEVELOPER_DIR"

# Clean previous build
rm -rf "$BUNDLE_DIR"

# Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Info.plist
cp Info.plist "${CONTENTS_DIR}/"

# Copy thumbnail images
if [ -f "thumbnail.png" ]; then
    cp thumbnail.png "${RESOURCES_DIR}/"
fi
if [ -f "thumbnail@2x.png" ]; then
    cp thumbnail@2x.png "${RESOURCES_DIR}/"
fi

# Compile Metal shader to .air then to .metallib
echo "📐 Compiling Metal shader..."
xcrun -sdk macosx metal -c Mandelbrot.metal -o Mandelbrot.air
xcrun -sdk macosx metallib Mandelbrot.air -o "${RESOURCES_DIR}/default.metallib"
rm Mandelbrot.air

# Compile Swift code into a dynamic library
echo "🔧 Compiling Swift code..."
swiftc \
    -O \
    -target arm64-apple-macosx12.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -emit-library \
    -o "${MACOS_DIR}/${BUNDLE_NAME}" \
    -module-name "${BUNDLE_NAME}" \
    -Xlinker -rpath -Xlinker @loader_path/../Frameworks \
    -Xlinker -install_name -Xlinker "@rpath/${BUNDLE_NAME}" \
    -framework ScreenSaver \
    -framework Metal \
    -framework MetalKit \
    -framework AppKit \
    -framework Foundation \
    Preferences.swift \
    DoubleDouble.swift \
    ConfigureSheetController.swift \
    MandelbrotView.swift

echo "✅ Build complete: ${BUNDLE_DIR}"

# Optional: Install to user's Screen Savers folder
if [[ "$1" == "--install" ]]; then
    INSTALL_DIR="$HOME/Library/Screen Savers"
    mkdir -p "$INSTALL_DIR"
    rm -rf "${INSTALL_DIR}/${BUNDLE_DIR}"
    cp -R "$BUNDLE_DIR" "$INSTALL_DIR/"
    echo "📦 Installed to: ${INSTALL_DIR}/${BUNDLE_DIR}"
    echo ""
    echo "Open System Settings > Screen Saver to select 'Mandelbrot'"
fi
