#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

BUNDLE_NAME="HyperspaceBloom"
BUNDLE_DIR="${BUNDLE_NAME}.saver"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
EXECUTABLE="${CONTENTS_DIR}/MacOS/${BUNDLE_NAME}"
METAL_LIBRARY="${CONTENTS_DIR}/Resources/default.metallib"
SETTINGS_APP="Hyperspace Bloom Settings.app"
SETTINGS_CONTENTS_DIR="${SETTINGS_APP}/Contents"
SETTINGS_EXECUTABLE="${SETTINGS_CONTENTS_DIR}/MacOS/HyperspaceBloomSettings"
OUTPUT_DIR="${1:-.codex-outputs/render-audit}"

./build.sh

test -d "$BUNDLE_DIR"
test -x "$EXECUTABLE"
test -f "$METAL_LIBRARY"
test -f "${CONTENTS_DIR}/Resources/thumbnail.png"
test -f "${CONTENTS_DIR}/Resources/thumbnail@2x.png"
test -d "$SETTINGS_APP"
test -x "$SETTINGS_EXECUTABLE"

PLIST_BUDDY=/usr/libexec/PlistBuddy
[[ "$($PLIST_BUDDY -c 'Print :CFBundleExecutable' "${CONTENTS_DIR}/Info.plist")" == "$BUNDLE_NAME" ]]
[[ "$($PLIST_BUDDY -c 'Print :CFBundleIdentifier' "${CONTENTS_DIR}/Info.plist")" == "com.proofofreach.HyperspaceBloom" ]]
[[ "$($PLIST_BUDDY -c 'Print :CFBundleName' "${CONTENTS_DIR}/Info.plist")" == "Hyperspace Bloom" ]]
[[ "$($PLIST_BUDDY -c 'Print :NSPrincipalClass' "${CONTENTS_DIR}/Info.plist")" == "MandalaView" ]]
[[ "$($PLIST_BUDDY -c 'Print :CFBundleIdentifier' "${SETTINGS_CONTENTS_DIR}/Info.plist")" == "com.proofofreach.HyperspaceBloom.Settings" ]]
[[ "$($PLIST_BUDDY -c 'Print :CFBundlePackageType' "${SETTINGS_CONTENTS_DIR}/Info.plist")" == "APPL" ]]

codesign --verify --deep --strict "$BUNDLE_DIR"
codesign --verify --deep --strict "$SETTINGS_APP"
lipo "$EXECUTABLE" -verify_arch arm64
lipo "$SETTINGS_EXECUTABLE" -verify_arch arm64
"$SETTINGS_EXECUTABLE" --smoke-test

if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [ -d "/Applications/Xcode-beta.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TEST_BUILD_DIR="${TMPDIR:-/tmp}/hyperspace-bloom-tests"
mkdir -p "$TEST_BUILD_DIR"

swiftc \
    -O \
    -parse-as-library \
    -target "arm64-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    MandalaScene.swift scripts/SceneTests.swift \
    -o "${TEST_BUILD_DIR}/scene-tests"
"${TEST_BUILD_DIR}/scene-tests"

swiftc \
    -O \
    -parse-as-library \
    -target "arm64-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    -framework AppKit \
    -framework ScreenSaver \
    -framework QuartzCore \
    scripts/HostSmoke.swift \
    -o "${TEST_BUILD_DIR}/host-smoke"
"${TEST_BUILD_DIR}/host-smoke"

swiftc \
    -O \
    -target "arm64-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    -framework Metal \
    -framework CoreGraphics \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    scripts/RenderAudit.swift \
    -o "${TEST_BUILD_DIR}/render-audit"

rm -rf "$OUTPUT_DIR"
"${TEST_BUILD_DIR}/render-audit" "$OUTPUT_DIR"

PNG_COUNT="$(find "$OUTPUT_DIR" -type f -name '*.png' | wc -l | tr -d ' ')"
[[ "$PNG_COUNT" == "7" ]]

if strings "$EXECUTABLE" | grep -Eq 'mandelbrotKernel|FractalTargets|JuliaAnchor'; then
    echo "Fractal-only symbols leaked into the new executable" >&2
    exit 1
fi

SKIP_BUILD=1 ./scripts/mandelbrot-smoke-test.sh

echo "Smoke test passed: both savers, settings app, signing, architecture, controls, scenes, and Metal renders."
