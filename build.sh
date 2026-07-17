#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUNDLE_NAME="HyperspaceBloom"
BUNDLE_DIR="${BUNDLE_NAME}.saver"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SETTINGS_NAME="HyperspaceBloomSettings"
SETTINGS_APP="Hyperspace Bloom Settings.app"
SETTINGS_CONTENTS_DIR="${SETTINGS_APP}/Contents"
SETTINGS_MACOS_DIR="${SETTINGS_CONTENTS_DIR}/MacOS"
MANDELBROT_SOURCE_DIR="${SCRIPT_DIR}/Mandelbrot"
MANDELBROT_BUNDLE_NAME="MandelbrotSaver"
MANDELBROT_BUNDLE_DIR="${MANDELBROT_BUNDLE_NAME}.saver"
MANDELBROT_CONTENTS_DIR="${MANDELBROT_BUNDLE_DIR}/Contents"
MANDELBROT_MACOS_DIR="${MANDELBROT_CONTENTS_DIR}/MacOS"
MANDELBROT_RESOURCES_DIR="${MANDELBROT_CONTENTS_DIR}/Resources"
MODULE_CACHE_DIR="${TMPDIR:-/tmp}/hyperspace-bloom-module-cache"
BUILD_DIR="${TMPDIR:-/tmp}/hyperspace-bloom-build"

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

if ! xcrun -sdk macosx metal -v >/dev/null 2>&1; then
    echo "❌ Error: Metal toolchain is not installed."
    echo ""
    echo "Install it with:"
    echo "  xcodebuild -downloadComponent MetalToolchain"
    exit 1
fi

echo "🔨 Building Hyperspace Bloom..."
echo "   Using: $DEVELOPER_DIR"

# Clean previous build
rm -rf "$BUNDLE_DIR"
rm -rf "$SETTINGS_APP"
rm -rf "$MANDELBROT_BUNDLE_DIR"
rm -rf "$BUILD_DIR"

# Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$SETTINGS_MACOS_DIR"
mkdir -p "$MANDELBROT_MACOS_DIR"
mkdir -p "$MANDELBROT_RESOURCES_DIR"

# Copy Info.plist
cp Info.plist "${CONTENTS_DIR}/"
cp SettingsInfo.plist "${SETTINGS_CONTENTS_DIR}/Info.plist"
cp "${MANDELBROT_SOURCE_DIR}/Info.plist" "${MANDELBROT_CONTENTS_DIR}/Info.plist"

# Copy thumbnail images
if [ -f "thumbnail.png" ]; then
    cp thumbnail.png "${RESOURCES_DIR}/"
fi
if [ -f "thumbnail@2x.png" ]; then
    cp thumbnail@2x.png "${RESOURCES_DIR}/"
fi
cp "${MANDELBROT_SOURCE_DIR}/thumbnail.png" "${MANDELBROT_RESOURCES_DIR}/"
cp "${MANDELBROT_SOURCE_DIR}/thumbnail@2x.png" "${MANDELBROT_RESOURCES_DIR}/"

# Compile Metal shader to .air then to .metallib
echo "📐 Compiling Metal shader..."
xcrun -sdk macosx metal -O2 -ffast-math -fmodules-cache-path="$MODULE_CACHE_DIR" -c Mandala.metal -o Mandala.air
xcrun -sdk macosx metallib Mandala.air -o "${RESOURCES_DIR}/default.metallib"
rm Mandala.air

echo "📐 Compiling Mandelbrot shader..."
xcrun -sdk macosx metal -O2 -ffast-math -fmodules-cache-path="$MODULE_CACHE_DIR" -c "${MANDELBROT_SOURCE_DIR}/Mandelbrot.metal" -o "${BUILD_DIR}/Mandelbrot.air"
xcrun -sdk macosx metallib "${BUILD_DIR}/Mandelbrot.air" -o "${MANDELBROT_RESOURCES_DIR}/default.metallib"

# Compile Swift code (Apple Silicon only)
echo "🔧 Compiling Swift code..."
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_SOURCES=(
    Preferences.swift
    MandalaScene.swift
    ConfigureSheetController.swift
    MandalaView.swift
)

swiftc \
    -O \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -target "arm64-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    -emit-library \
    -o "${MACOS_DIR}/${BUNDLE_NAME}" \
    -module-name "${BUNDLE_NAME}" \
    -Xlinker -rpath -Xlinker @loader_path/../Frameworks \
    -Xlinker -install_name -Xlinker "@rpath/${BUNDLE_NAME}" \
    -framework ScreenSaver \
    -framework Metal \
    -framework AppKit \
    -framework Foundation \
    -framework IOKit \
    "${SWIFT_SOURCES[@]}"

echo "🔧 Compiling Mandelbrot Saver..."
MANDELBROT_SWIFT_SOURCES=(
    "${MANDELBROT_SOURCE_DIR}/Preferences.swift"
    "${MANDELBROT_SOURCE_DIR}/DoubleDouble.swift"
    "${MANDELBROT_SOURCE_DIR}/FractalTargets.swift"
    "${MANDELBROT_SOURCE_DIR}/ConfigureSheetController.swift"
    "${MANDELBROT_SOURCE_DIR}/MandelbrotView.swift"
)

swiftc \
    -O \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -target "arm64-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    -emit-library \
    -o "${MANDELBROT_MACOS_DIR}/${MANDELBROT_BUNDLE_NAME}" \
    -module-name "${MANDELBROT_BUNDLE_NAME}" \
    -Xlinker -rpath -Xlinker @loader_path/../Frameworks \
    -Xlinker -install_name -Xlinker "@rpath/${MANDELBROT_BUNDLE_NAME}" \
    -framework ScreenSaver \
    -framework Metal \
    -framework AppKit \
    -framework Foundation \
    -framework IOKit \
    "${MANDELBROT_SWIFT_SOURCES[@]}"

echo "⚙️  Compiling settings app..."
swiftc \
    -O \
    -parse-as-library \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -target "arm64-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    -o "${SETTINGS_MACOS_DIR}/${SETTINGS_NAME}" \
    -module-name "${SETTINGS_NAME}" \
    -framework AppKit \
    -framework ScreenSaver \
    -framework Foundation \
    Preferences.swift \
    ConfigureSheetController.swift \
    SettingsApp.swift

# Ad-hoc sign so macOS allows Metal access in sandboxed screensaver process
echo "🔏 Code signing..."
codesign --force --sign - "${BUNDLE_DIR}"
codesign --force --sign - "${SETTINGS_APP}"
codesign --force --sign - "${MANDELBROT_BUNDLE_DIR}"

echo "✅ Build complete: ${BUNDLE_DIR}, ${MANDELBROT_BUNDLE_DIR}, and ${SETTINGS_APP}"

# Optional: Install to user's Screen Savers folder
if [[ "${1:-}" == "--install" ]]; then
    INSTALL_DIR="$HOME/Library/Screen Savers"
    SETTINGS_INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$SETTINGS_INSTALL_DIR"
    rm -rf "${INSTALL_DIR}/${BUNDLE_DIR}"
    rm -rf "${INSTALL_DIR}/${MANDELBROT_BUNDLE_DIR}"
    rm -rf "${SETTINGS_INSTALL_DIR}/${SETTINGS_APP}"
    cp -R "$BUNDLE_DIR" "$INSTALL_DIR/"
    cp -R "$MANDELBROT_BUNDLE_DIR" "$INSTALL_DIR/"
    cp -R "$SETTINGS_APP" "$SETTINGS_INSTALL_DIR/"
    echo "📦 Installed to: ${INSTALL_DIR}/${BUNDLE_DIR}"
    echo "📦 Installed to: ${INSTALL_DIR}/${MANDELBROT_BUNDLE_DIR}"
    echo "⚙️  Settings: ${SETTINGS_INSTALL_DIR}/${SETTINGS_APP}"
    echo ""
    echo "Open System Settings > Screen Saver to select 'Hyperspace Bloom'"
fi
