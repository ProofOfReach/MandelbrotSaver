#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_DIR"

BUNDLE_NAME="MandelbrotSaver"
BUNDLE_DIR="${BUNDLE_NAME}.saver"
EXECUTABLE="${BUNDLE_DIR}/Contents/MacOS/${BUNDLE_NAME}"
INFO_PLIST="${BUNDLE_DIR}/Contents/Info.plist"
METALLIB="${BUNDLE_DIR}/Contents/Resources/default.metallib"

echo "Running smoke test..."

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    ./build.sh
fi

test -d "$BUNDLE_DIR"
test -f "$EXECUTABLE"
test -f "$INFO_PLIST"
test -f "$METALLIB"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$BUNDLE_ID" != "com.proofofreach.MandelbrotSaver" ]]; then
    echo "Unexpected bundle identifier: $BUNDLE_ID"
    exit 1
fi

ARCHES="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHES" != *"arm64"* ]]; then
    echo "Expected arm64 binary, got: $ARCHES"
    exit 1
fi

codesign --verify "$BUNDLE_DIR"

PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mandelbrot-smoke.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT

cat > "${PROBE_DIR}/MetalProbe.swift" <<'SWIFT'
import Foundation
import Metal
import simd

struct ShaderUniforms {
    var geometry: SIMD4<Float>
    var palette: SIMD4<Float>
    var view: SIMD4<Float>
    var mode: SIMD4<Float>
    var quality: SIMD4<Float>
    var extra: SIMD4<Float>
}

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: MetalProbe <metallib>")
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal device unavailable")
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let library = try device.makeLibrary(URL: url)

var usePerturbation = false
let constants = MTLFunctionConstantValues()
constants.setConstantValue(&usePerturbation, type: .bool, index: 0)

let function = try library.makeFunction(name: "mandelbrotKernel", constantValues: constants)

let pipeline = try device.makeComputePipelineState(function: function)
guard let queue = device.makeCommandQueue(),
      let commandBuffer = queue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder() else {
    fatalError("unable to create Metal command objects")
}

let width = 96
let height = 64
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm_srgb,
    width: width,
    height: height,
    mipmapped: false
)
descriptor.usage = [.shaderWrite, .shaderRead]
descriptor.storageMode = .shared

guard let texture = device.makeTexture(descriptor: descriptor),
      let referenceBuffer = device.makeBuffer(length: 16, options: .storageModeShared) else {
    fatalError("unable to allocate render probe resources")
}

// 1x1 black stand-in for the freeze-dissolve held-frame texture (blend
// weight is 0, so it is bound but never blended).
let heldDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba16Float,
    width: 1,
    height: 1,
    mipmapped: false
)
heldDescriptor.usage = [.shaderRead]
heldDescriptor.storageMode = .shared
guard let heldDummy = device.makeTexture(descriptor: heldDescriptor) else {
    fatalError("unable to allocate held-frame stand-in texture")
}
var heldZero: UInt64 = 0
withUnsafeBytes(of: &heldZero) { bytes in
    heldDummy.replace(
        region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
        withBytes: bytes.baseAddress!, bytesPerRow: 8)
}

var uniforms = ShaderUniforms(
    geometry: SIMD4<Float>(-0.5, 0.0, 3.0, 160.0),
    palette: SIMD4<Float>(0.0, Float(width) / Float(height), 0.0, 0.0),
    view: SIMD4<Float>(0.0, 0.0, 0.0, 0.0),
    mode: SIMD4<Float>(0.0, 0.0, 0.0, 0.0),
    quality: SIMD4<Float>(1.0, 1.0, 1.0, 0.0),
    extra: SIMD4<Float>(1.0, 0.0, 0.0, 0.0)
)

encoder.setComputePipelineState(pipeline)
encoder.setTexture(texture, index: 0)
encoder.setTexture(heldDummy, index: 1)
encoder.setBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
encoder.setBuffer(referenceBuffer, offset: 0, index: 1)
encoder.dispatchThreadgroups(
    MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
)
encoder.endEncoding()
commandBuffer.commit()
commandBuffer.waitUntilCompleted()

if let error = commandBuffer.error {
    fatalError("render probe failed: \(error)")
}

var pixels = [UInt8](repeating: 0, count: width * height * 4)
texture.getBytes(
    &pixels,
    bytesPerRow: width * 4,
    from: MTLRegionMake2D(0, 0, width, height),
    mipmapLevel: 0
)

let nonBlack = stride(from: 0, to: pixels.count, by: 4).contains { offset in
    pixels[offset] > 4 || pixels[offset + 1] > 4 || pixels[offset + 2] > 4
}

if !nonBlack {
    fatalError("render probe produced a blank frame")
}
SWIFT

swiftc \
    -target "$(uname -m)-apple-macosx12.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework Foundation \
    -framework Metal \
    "${PROBE_DIR}/MetalProbe.swift" \
    -o "${PROBE_DIR}/MetalProbe"

"${PROBE_DIR}/MetalProbe" "$METALLIB"

swiftc \
    -target "$(uname -m)-apple-macosx12.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework Foundation \
    -framework Metal \
    Mandelbrot/DoubleDouble.swift \
    Mandelbrot/FractalTargets.swift \
    Mandelbrot/RenderAudit.swift \
    -o "${PROBE_DIR}/RenderAudit"

"${PROBE_DIR}/RenderAudit" "$METALLIB"

cat > "${PROBE_DIR}/BundleProbe.swift" <<'SWIFT'
import AppKit
import Foundation
import ScreenSaver

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: BundleProbe <bundle>")
}

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bundle = Bundle(url: bundleURL) else {
    fatalError("bundle not found")
}

guard bundle.load() else {
    fatalError("bundle failed to load")
}

guard let viewClass = bundle.principalClass as? ScreenSaverView.Type else {
    fatalError("principal class is not a ScreenSaverView")
}

guard let view = viewClass.init(frame: NSRect(x: 0, y: 0, width: 640, height: 480), isPreview: false) else {
    fatalError("unable to instantiate screensaver view")
}

guard view.hasConfigureSheet else {
    fatalError("hasConfigureSheet is false")
}

guard let sheet = view.configureSheet else {
    fatalError("configureSheet returned nil")
}

if sheet.frame.width < 360 || sheet.frame.height < 340 {
    fatalError("configureSheet has an unexpected size: \(sheet.frame)")
}

func popupItemCounts(in view: NSView) -> [Int] {
    var counts: [Int] = []
    if let popup = view as? NSPopUpButton {
        counts.append(popup.numberOfItems)
    }
    for subview in view.subviews {
        counts.append(contentsOf: popupItemCounts(in: subview))
    }
    return counts
}

let counts = sheet.contentView.map { popupItemCounts(in: $0) } ?? []
guard counts.contains(6), counts.contains(2), counts.contains(4) else {
    fatalError("configureSheet missing expected palette/quality/shading controls: \(counts)")
}
SWIFT

swiftc \
    -target "$(uname -m)-apple-macosx12.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework AppKit \
    -framework Foundation \
    -framework ScreenSaver \
    "${PROBE_DIR}/BundleProbe.swift" \
    -o "${PROBE_DIR}/BundleProbe"

"${PROBE_DIR}/BundleProbe" "$BUNDLE_DIR"

echo "Mandelbrot smoke test passed."
