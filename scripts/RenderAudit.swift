import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private struct MandalaUniforms {
    var viewport: SIMD4<Float>
    var scene: SIMD4<Float>
    var motion: SIMD4<Float>
    var palette: SIMD4<Float>
    var quality: SIMD4<Float>
}

private struct AuditCase {
    let name: String
    let seed: Float
    let symmetry: Int
    let motif: Int
    let palette: Int
    let time: Float
    let sceneTime: Float
}

private struct Metrics {
    let mean: Double
    let standardDeviation: Double
    let darkFraction: Double
    let brightFraction: Double
    let colorfulFraction: Double
    let sharpEdgeFraction: Double
    let centerMean: Double
    let centerRingMean: Double
}

private enum AuditFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

private let cases = [
    AuditCase(name: "cosmic-orchid-bloom", seed: 173, symmetry: 8, motif: 0, palette: 0, time: 18, sceneTime: 31),
    AuditCase(name: "electric-lotus-temple", seed: 991, symmetry: 10, motif: 1, palette: 1, time: 47, sceneTime: 24),
    AuditCase(name: "solar-temple-weave", seed: 2047, symmetry: 7, motif: 2, palette: 2, time: 73, sceneTime: 42),
    AuditCase(name: "abyssal-cyan-oracle", seed: 311, symmetry: 12, motif: 3, palette: 3, time: 29, sceneTime: 36),
    AuditCase(name: "woven-vision", seed: 3701, symmetry: 6, motif: 2, palette: 4, time: 91, sceneTime: 51),
    AuditCase(name: "pearl-void", seed: 1429, symmetry: 8, motif: 3, palette: 5, time: 58, sceneTime: 29),
]

private let width = 960
private let height = 600
private let renderTimeOffset: Float = CommandLine.arguments.count > 2
    ? (Float(CommandLine.arguments[2]) ?? 0.0)
    : 0.0

private func offsetCase(_ auditCase: AuditCase) -> AuditCase {
    guard renderTimeOffset != 0.0 else { return auditCase }
    let sceneTime = (auditCase.sceneTime + renderTimeOffset)
        .truncatingRemainder(dividingBy: 65.0)
    return AuditCase(
        name: auditCase.name,
        seed: auditCase.seed,
        symmetry: auditCase.symmetry,
        motif: auditCase.motif,
        palette: auditCase.palette,
        time: auditCase.time + renderTimeOffset,
        sceneTime: sceneTime
    )
}

private func render(
    auditCase: AuditCase,
    pipeline: MTLComputePipelineState,
    device: MTLDevice,
    queue: MTLCommandQueue,
    sampleCount: Float = 1.0,
    heldPixels: [UInt8]? = nil,
    heldWeight: Float = 0.0
) throws -> (pixels: [UInt8], gpuTime: Double) {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm_srgb,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .shared
    guard let output = device.makeTexture(descriptor: descriptor) else {
        throw AuditFailure.message("Could not allocate output texture")
    }

    let heldDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm_srgb,
        width: heldPixels == nil ? 1 : width,
        height: heldPixels == nil ? 1 : height,
        mipmapped: false
    )
    heldDescriptor.usage = [.shaderRead]
    heldDescriptor.storageMode = .shared
    guard let held = device.makeTexture(descriptor: heldDescriptor),
          let commandBuffer = queue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder() else {
        throw AuditFailure.message("Could not create Metal command resources")
    }
    if let heldPixels {
        heldPixels.withUnsafeBytes { bytes in
            held.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4
            )
        }
    }

    var uniforms = MandalaUniforms(
        viewport: SIMD4<Float>(
            auditCase.time,
            auditCase.sceneTime,
            min(max(auditCase.sceneTime / 65.0, 0.0), 1.0),
            Float(width) / Float(height)
        ),
        scene: SIMD4<Float>(Float(auditCase.seed), Float(auditCase.symmetry), Float(auditCase.motif), 1.0),
        motion: SIMD4<Float>(1.0, 0.92, 0.88, 1.0),
        palette: SIMD4<Float>(Float(auditCase.palette), 0.0, 0.12, 1.0),
        quality: SIMD4<Float>(sampleCount, heldWeight, 1.0, 0.96)
    )

    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(output, index: 0)
    encoder.setTexture(held, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<MandalaUniforms>.size, index: 0)
    let threads = MTLSize(width: 16, height: 16, depth: 1)
    let groups = MTLSize(
        width: (width + threads.width - 1) / threads.width,
        height: (height + threads.height - 1) / threads.height,
        depth: 1
    )
    encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    if let error = commandBuffer.error {
        throw AuditFailure.message("Metal command failed: \(error)")
    }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    output.getBytes(
        &pixels,
        bytesPerRow: width * 4,
        from: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0
    )
    return (pixels, max(commandBuffer.gpuEndTime - commandBuffer.gpuStartTime, 0.0))
}

private func metrics(for pixels: [UInt8]) -> Metrics {
    var sum = 0.0
    var sumSquared = 0.0
    var dark = 0
    var bright = 0
    var colorful = 0
    var sharpEdges = 0
    var centerSum = 0.0
    var centerCount = 0
    var rimSum = 0.0
    var rimCount = 0
    let centerX = Double(width - 1) * 0.5
    let centerY = Double(height - 1) * 0.5

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let b = Double(pixels[offset]) / 255.0
            let g = Double(pixels[offset + 1]) / 255.0
            let r = Double(pixels[offset + 2]) / 255.0
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            sum += luminance
            sumSquared += luminance * luminance
            if luminance < 0.045 { dark += 1 }
            if luminance > 0.58 { bright += 1 }
            if max(r, max(g, b)) - min(r, min(g, b)) > 0.16, luminance > 0.045 {
                colorful += 1
            }

            if x + 1 < width, y + 1 < height {
                let rightOffset = offset + 4
                let downOffset = offset + width * 4
                let rightLuminance = 0.2126 * Double(pixels[rightOffset + 2]) / 255.0
                    + 0.7152 * Double(pixels[rightOffset + 1]) / 255.0
                    + 0.0722 * Double(pixels[rightOffset]) / 255.0
                let downLuminance = 0.2126 * Double(pixels[downOffset + 2]) / 255.0
                    + 0.7152 * Double(pixels[downOffset + 1]) / 255.0
                    + 0.0722 * Double(pixels[downOffset]) / 255.0
                if max(abs(luminance - rightLuminance), abs(luminance - downLuminance)) > 0.12 {
                    sharpEdges += 1
                }
            }

            let dx = Double(x) - centerX
            let dy = Double(y) - centerY
            let radius = sqrt(dx * dx + dy * dy)
            if radius < 8.0 {
                centerSum += luminance
                centerCount += 1
            } else if radius >= 15.0, radius <= 27.0 {
                rimSum += luminance
                rimCount += 1
            }
        }
    }

    let count = Double(width * height)
    let mean = sum / count
    let variance = max(sumSquared / count - mean * mean, 0.0)
    return Metrics(
        mean: mean,
        standardDeviation: sqrt(variance),
        darkFraction: Double(dark) / count,
        brightFraction: Double(bright) / count,
        colorfulFraction: Double(colorful) / count,
        sharpEdgeFraction: Double(sharpEdges) / Double((width - 1) * (height - 1)),
        centerMean: centerSum / Double(max(centerCount, 1)),
        centerRingMean: rimSum / Double(max(rimCount, 1))
    )
}

private func savePNG(_ pixels: [UInt8], to url: URL) throws {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        throw AuditFailure.message("Could not create image provider")
    }
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        .init(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )
    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    ),
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw AuditFailure.message("Could not create PNG destination at \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw AuditFailure.message("Could not write PNG at \(url.path)")
    }
}

private func validate(
    _ metrics: Metrics,
    auditCase: AuditCase,
    minimumDeviation: Double = 0.045,
    minimumDarkFraction: Double = 0.10,
    minimumSharpEdgeFraction: Double = 0.010
) -> [String] {
    var failures: [String] = []
    if metrics.mean < 0.025 || metrics.mean > 0.42 {
        failures.append("mean luminance \(metrics.mean) is outside 0.025...0.42")
    }
    if metrics.standardDeviation < minimumDeviation {
        failures.append("luminance deviation \(metrics.standardDeviation) is too low")
    }
    if metrics.darkFraction < minimumDarkFraction || metrics.darkFraction > 0.92 {
        failures.append("dark fraction \(metrics.darkFraction) is outside \(minimumDarkFraction)...0.92")
    }
    if metrics.brightFraction < 0.0001 {
        failures.append("no meaningful highlights were found")
    }
    if auditCase.palette != 5, metrics.colorfulFraction < 0.025 {
        failures.append("colorful fraction \(metrics.colorfulFraction) is too low")
    }
    if metrics.sharpEdgeFraction < minimumSharpEdgeFraction {
        failures.append("sharp edge fraction \(metrics.sharpEdgeFraction) is too low")
    }
    if metrics.centerRingMean < metrics.centerMean * 1.25 + 0.006 {
        failures.append("central portal rim is not visibly brighter than its void")
    }
    return failures
}

private func meanAbsolutePixelDifference(_ first: [UInt8], _ second: [UInt8]) -> Double {
    precondition(first.count == second.count)
    var total = 0.0
    var count = 0
    for index in stride(from: 0, to: first.count, by: 4) {
        total += abs(Double(first[index]) - Double(second[index])) / 255.0
        total += abs(Double(first[index + 1]) - Double(second[index + 1])) / 255.0
        total += abs(Double(first[index + 2]) - Double(second[index + 2])) / 255.0
        count += 3
    }
    return total / Double(max(count, 1))
}

do {
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".codex-outputs/render-audit")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue() else {
        throw AuditFailure.message("Metal is unavailable")
    }

    let libraryURL = URL(fileURLWithPath: "HyperspaceBloom.saver/Contents/Resources/default.metallib")
    let library = try device.makeLibrary(URL: libraryURL)
    guard let function = library.makeFunction(name: "mandalaKernel") else {
        throw AuditFailure.message("mandalaKernel is missing from default.metallib")
    }
    let pipeline = try device.makeComputePipelineState(function: function)

    let renderedCases = cases.map(offsetCase)
    var allFailures: [String] = []
    var firstPixels: [UInt8]?
    for auditCase in renderedCases {
        let result = try render(auditCase: auditCase, pipeline: pipeline, device: device, queue: queue)
        let imageMetrics = metrics(for: result.pixels)
        let failures = renderTimeOffset == 0.0
            ? validate(imageMetrics, auditCase: auditCase)
            : validate(
                imageMetrics,
                auditCase: auditCase,
                minimumDeviation: 0.030,
                minimumDarkFraction: 0.030,
                minimumSharpEdgeFraction: 0.002
            )
        allFailures += failures.map { "\(auditCase.name): \($0)" }
        let outputURL = outputDirectory.appendingPathComponent("\(auditCase.name).png")
        try savePNG(result.pixels, to: outputURL)

        print(String(
            format: "%@ mean=%.3f sd=%.3f dark=%.3f bright=%.4f colorful=%.3f sharp=%.3f center=%.3f rim=%.3f gpu=%.2fms",
            auditCase.name,
            imageMetrics.mean,
            imageMetrics.standardDeviation,
            imageMetrics.darkFraction,
            imageMetrics.brightFraction,
            imageMetrics.colorfulFraction,
            imageMetrics.sharpEdgeFraction,
            imageMetrics.centerMean,
            imageMetrics.centerRingMean,
            result.gpuTime * 1000.0
        ))
        if firstPixels == nil { firstPixels = result.pixels }
    }

    // Identical uniforms must produce identical pixels; this protects seeded
    // scene replay and catches accidental time/random dependencies.
    let replay = try render(auditCase: renderedCases[0], pipeline: pipeline, device: device, queue: queue)
    if replay.pixels != firstPixels {
        allFailures.append("deterministic replay produced different pixels")
    }

    // Exercise the Ultra four-sample path as a separate pipeline workload.
    let ultra = try render(
        auditCase: renderedCases[0],
        pipeline: pipeline,
        device: device,
        queue: queue,
        sampleCount: 4.0
    )
    try savePNG(ultra.pixels, to: outputDirectory.appendingPathComponent("cosmic-orchid-bloom-ultra.png"))
    print(String(format: "ultra four-sample gpu=%.2fms", ultra.gpuTime * 1000.0))

    // Sample a full ten-minute virtual run at 25-second intervals. This is a
    // fast soak of shader time, scene progress, motifs, and palettes; every
    // sampled frame must preserve contrast and the central-jewel invariant.
    for index in 0..<24 {
        let base = cases[index % cases.count]
        let elapsed = Float(index * 25)
        let soakCase = AuditCase(
            name: "soak-\(index)",
            seed: base.seed,
            symmetry: base.symmetry,
            motif: base.motif,
            palette: base.palette,
            time: elapsed,
            sceneTime: elapsed.truncatingRemainder(dividingBy: 65.0)
        )
        let soak = try render(auditCase: soakCase, pipeline: pipeline, device: device, queue: queue)
        let soakFailures = validate(
            metrics(for: soak.pixels),
            auditCase: soakCase,
            minimumDeviation: 0.030,
            minimumDarkFraction: 0.030,
            minimumSharpEdgeFraction: 0.002
        )
        if !soakFailures.isEmpty {
            try savePNG(
                soak.pixels,
                to: outputDirectory.appendingPathComponent("soak-failure-\(index).png")
            )
        }
        allFailures += soakFailures.map { "ten-minute soak frame \(index): \($0)" }
    }

    // Motion must be continuous from one display frame to the next. The
    // shader intentionally avoids integer symmetry morphs inside a scene;
    // those happen only beneath a captured-texture dissolve.
    for base in renderedCases.prefix(4) {
        let adjacent = AuditCase(
            name: "\(base.name)-adjacent",
            seed: base.seed,
            symmetry: base.symmetry,
            motif: base.motif,
            palette: base.palette,
            time: base.time + 1.0 / 60.0,
            sceneTime: base.sceneTime + 1.0 / 60.0
        )
        let first = try render(auditCase: base, pipeline: pipeline, device: device, queue: queue)
        let second = try render(auditCase: adjacent, pipeline: pipeline, device: device, queue: queue)
        let difference = meanAbsolutePixelDifference(first.pixels, second.pixels)
        if difference > 0.016 {
            allFailures.append("\(base.name): adjacent-frame difference \(difference) indicates a pop")
        }
    }

    // A scene can be mathematically animated yet look static if every layer
    // drifts only a fraction of a feature width. One second of normal motion
    // must produce a clearly perceptible image change without becoming a cut.
    for base in renderedCases.prefix(4) {
        let moved = AuditCase(
            name: "\(base.name)-one-second",
            seed: base.seed,
            symmetry: base.symmetry,
            motif: base.motif,
            palette: base.palette,
            time: base.time + 1.0,
            sceneTime: base.sceneTime + 1.0
        )
        let first = try render(auditCase: base, pipeline: pipeline, device: device, queue: queue)
        let second = try render(auditCase: moved, pipeline: pipeline, device: device, queue: queue)
        let difference = meanAbsolutePixelDifference(first.pixels, second.pixels)
        print(String(format: "%@ one-second motion=%.5f", base.name, difference))
        if difference < 0.010 {
            allFailures.append("\(base.name): one-second motion \(difference) is visually static")
        } else if difference > 0.225 {
            allFailures.append("\(base.name): one-second motion \(difference) is too abrupt")
        }
    }

    // Verify the same held-texture path used for scene changes: a full held
    // weight reproduces the outgoing frame, and a midpoint remains valid.
    let outgoing = try render(auditCase: renderedCases[0], pipeline: pipeline, device: device, queue: queue)
    let held = try render(
        auditCase: renderedCases[1],
        pipeline: pipeline,
        device: device,
        queue: queue,
        heldPixels: outgoing.pixels,
        heldWeight: 1.0
    )
    let heldDifference = meanAbsolutePixelDifference(outgoing.pixels, held.pixels)
    if heldDifference > 0.002 {
        allFailures.append("held-texture transition did not preserve the outgoing frame (difference \(heldDifference))")
    }
    let midpoint = try render(
        auditCase: renderedCases[1],
        pipeline: pipeline,
        device: device,
        queue: queue,
        heldPixels: outgoing.pixels,
        heldWeight: 0.5
    )
    let midpointMetrics = metrics(for: midpoint.pixels)
    if midpointMetrics.standardDeviation < 0.045 || midpointMetrics.mean < 0.025 {
        allFailures.append("transition midpoint lost visible structure")
    }

    if !allFailures.isEmpty {
        throw AuditFailure.message("Render audit failed:\n- " + allFailures.joined(separator: "\n- "))
    }
    print("Render audit passed (palettes, motifs, deterministic replay, Ultra, ten-minute soak, continuity, dissolve).")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
