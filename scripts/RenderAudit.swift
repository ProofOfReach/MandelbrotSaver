import Foundation
import Metal
import simd
import Darwin

private struct ShaderUniforms {
  var geometry: SIMD4<Float>
  var palette: SIMD4<Float>
  var view: SIMD4<Float>
  var mode: SIMD4<Float>
  var quality: SIMD4<Float>
  var extra: SIMD4<Float>
}

private struct Metrics {
  let standardDeviation: Double
  let neighborDifference: Double
  let darkRatio: Double
}

// Mirrors MandelbrotView.updateReferenceOrbit: Mandelbrot orbits seed z = 0
// with c at the dive center; Julia orbits seed z at the dive center with the
// fixed constant c.
private func makeReferenceOrbit(
  startX: DoubleDouble, startY: DoubleDouble,
  cRe: DoubleDouble, cIm: DoubleDouble, count: Int
) -> (
  [SIMD4<Float>], Int
) {
  var orbit = [SIMD4<Float>](repeating: .zero, count: count)
  var zr = startX
  var zi = startY
  let two = DoubleDouble(2.0)
  var validLength = count

  for i in 0..<count {
    let fzr = Float(zr.hi)
    let fzi = Float(zi.hi)
    let zr2 = zr * zr
    let zi2 = zi * zi
    // Escape radius 256, matching MandelbrotView.updateReferenceOrbit and
    // the shader's smooth-coloring bailout.
    if zr2.hi + zi2.hi > 65536.0 {
      validLength = i
      break
    }

    let nextZI = (zr * zi * two) + cIm
    let nextZR = (zr2 - zi2) + cRe
    let iterZR = fzr * fzr - fzi * fzi + Float(cRe.hi)
    let iterZI = 2.0 * fzr * fzi + Float(cIm.hi)
    orbit[i] = SIMD4<Float>(fzr, fzi, iterZR - Float(nextZR.hi), iterZI - Float(nextZI.hi))
    zr = nextZR
    zi = nextZI
  }
  return (orbit, validLength)
}

// MARK: - Dive structure audit (CPU)
// The GPU pass below only renders the end-of-dive frame; a target can pass it
// while spending whole decades of the zoom in a featureless exterior gradient
// ("splash of color with no set in view"). This CPU pass checks escape-time
// structure at every half-decade of each target's dive using the renderer's
// effective iteration budget.

private let diveAspect = 16.0 / 9.0
private let diveGridW = 48
private let diveGridH = 27

private struct AuditPolicy {
  let name: String
  let maxFloatIterations: Int
  let maxPerturbationIterations: Int
}

// Mirrors MandelbrotView.renderPolicy for both quality settings. Power mode
// lowers frame rate, render scale, and AA, but deliberately keeps iteration
// caps intact: reducing them removes the fractal from some Julia windows.
private let auditPolicies = [
  AuditPolicy(name: "Standard", maxFloatIterations: 450, maxPerturbationIterations: 1000),
  AuditPolicy(name: "Ultra", maxFloatIterations: 650, maxPerturbationIterations: 1600),
  AuditPolicy(name: "Standard+power", maxFloatIterations: 450, maxPerturbationIterations: 1000),
  AuditPolicy(name: "Ultra+power", maxFloatIterations: 650, maxPerturbationIterations: 1600),
]

// Julia dives always run 3.0 -> 3e-5 toward a boundary anchor from the shared
// JuliaAnchor search (MandelbrotView.selectRandomTarget), so auditing that
// anchor audits the exact dynamic targets production selects.
private let juliaDiveStartScale = 3.0
private let juliaDiveMinScale = 3e-5

private func escapeIteration(
  zx0: Double, zy0: Double, cx: Double, cy: Double, cap: Int
) -> Int {
  var zx = zx0, zy = zy0
  for i in 0..<cap {
    if zx * zx + zy * zy > 65536.0 { return i }
    let nzx = zx * zx - zy * zy + cx
    let nzy = 2 * zx * zy + cy
    zx = nzx
    zy = nzy
  }
  return cap
}

// Escape iteration plus the shader's edge-AA coverage: the kernel multiplies
// each escaped pixel by clamp(0.5*log(mag_sq)*|z|/|dz| / pixelSpan, 0, 1) and
// renders cap-hitting pixels black, so mean coverage over a window is a
// faithful proxy for how bright the frame actually renders. Generalized over
// both fractal modes exactly like the kernel: Mandelbrot tracks dz/dc
// (derivSeed 0, derivAdd 1); Julia tracks dz/dz0 (derivSeed 1, derivAdd 0).
private func escapeCoverage(
  zx0: Double, zy0: Double, cx: Double, cy: Double,
  derivSeed: Double, derivAdd: Double, cap: Int, pixelSpan: Double
) -> (iter: Int, coverage: Double) {
  var zx = zx0, zy = zy0
  var dx = derivSeed, dy = 0.0
  for i in 0..<cap {
    let magSq = zx * zx + zy * zy
    if magSq > 65536.0 {
      let dmag = max(sqrt(dx * dx + dy * dy), 1e-20)
      let de = 0.5 * log(magSq) * sqrt(magSq) / dmag
      return (i, min(max(de / pixelSpan, 0.0), 1.0))
    }
    let ndx = 2 * (zx * dx - zy * dy) + derivAdd
    let ndy = 2 * (zx * dy + zy * dx)
    dx = ndx
    dy = ndy
    let nzx = zx * zx - zy * zy + cx
    let nzy = 2 * zx * zy + cy
    zx = nzx
    zy = nzy
  }
  return (cap, 0.0)
}

// The renderer's iteration budget at a zoom scale, mirroring
// MandelbrotView.planFrame: the float path grows with depth for Mandelbrot
// but runs at the full float budget for Julia (near-parabolic Julia regions
// need most of the anchor's escape time mid-dive); the handoff to
// perturbation is ULP/resolution-aware; past it the budget continues the
// float ramp and doubles per decade of depth. Julia perturbation frames still
// clamp to the reference orbit's pre-escape length (Julia references can't
// rebase); Mandelbrot frames wrap via rebasing and don't clamp.
private func effectiveCap(
  scale: Double, anchorEscape: Int, julia: Bool, anchorMagnitude: Double,
  policy: AuditPolicy
) -> Int {
  func floatBudget(at s: Double) -> Int {
    if julia { return policy.maxFloatIterations }
    let depth = max(0.0, log10(3.0 / s))
    return min(policy.maxFloatIterations, 220 + Int(depth * 24.0))
  }

  let ulp = Double(Float(anchorMagnitude + scale).ulp)
  let handoffScale = min(5e-3, max(1e-4, 8.0 * ulp * 2160.0))
  if scale > handoffScale {
    return floatBudget(at: scale)
  }
  let decadesPast = max(0.0, log10(handoffScale / max(scale, 1e-300)))
  let ramp = Double(floatBudget(at: handoffScale)) * pow(2.0, decadesPast)
  var cap = min(policy.maxPerturbationIterations, max(Int(ramp), 64))
  if julia {
    // No 64-iteration floor: exceeding the orbit's pre-escape length would
    // silently drop c from the perturbation recurrence (see planFrame).
    cap = min(cap, max(anchorEscape, 1))
  }
  return cap
}

// One dive to audit, independent of fractal mode. `sample` maps a pixel
// coordinate to escape iteration + rendered-brightness coverage.
private struct DiveSpec {
  let name: String
  let anchorX: Double
  let anchorY: Double
  let startScale: Double
  let minScale: Double
  let anchorEscape: Int
  let julia: Bool
  let sample: (Double, Double, Int, Double) -> (iter: Int, coverage: Double)
}

private func diveStructureFailures(_ spec: DiveSpec) -> [String] {
  let renderHeight = 2160.0  // representative fullscreen pixel height

  var scales: [Double] = []
  var scale = spec.startScale
  while scale > spec.minScale * 1.5 {
    scales.append(scale)
    scale *= pow(10.0, -0.5)
  }
  scales.append(spec.minScale * 2.0)  // fade-out trigger window

  var failures: [String] = []
  let anchorMagnitude = max(abs(spec.anchorX), abs(spec.anchorY))
  for policy in auditPolicies {
    for scale in scales {
      let cap = effectiveCap(
        scale: scale, anchorEscape: spec.anchorEscape, julia: spec.julia,
        anchorMagnitude: anchorMagnitude, policy: policy)
    let pixelSpan = scale / renderHeight
    var interior = 0
    var edgeSamples = 0
    var escaped: [Int] = []
    var coverageSum = 0.0
    for gy in 0..<diveGridH {
      for gx in 0..<diveGridW {
        let px = spec.anchorX + (Double(gx) / Double(diveGridW - 1) - 0.5) * scale * diveAspect
        let py = spec.anchorY + (Double(gy) / Double(diveGridH - 1) - 0.5) * scale
        let sample = spec.sample(px, py, cap, pixelSpan)
        coverageSum += sample.coverage
        if sample.iter >= cap {
          interior += 1
        } else {
          escaped.append(sample.iter)
          if sample.coverage < 0.5 { edgeSamples += 1 }
        }
      }
    }
    let sampleCount = Double(diveGridW * diveGridH)
    let interiorFrac = Double(interior) / sampleCount
    let edgeFrac = Double(edgeSamples) / sampleCount
    let meanCoverage = coverageSum / sampleCount
    // Frame renders essentially black: set interior and edge-AA-darkened
    // boundary pixels dominate ("zoomed into a black region between bodies").
    if meanCoverage < 0.05 {
      failures.append(
        String(
          format: "%@ [%@] scale=%.2e (mean rendered brightness %.3f, %.0f%% interior)",
          spec.name, policy.name, scale, meanCoverage, interiorFrac * 100))
      continue
    }
    if scale <= spec.minScale * 2.5 && interiorFrac > 0.97 {
      failures.append(
        String(
          format: "%@ [%@] scale=%.2e (%.0f%% interior at end of dive)",
          spec.name, policy.name, scale, interiorFrac * 100))
      continue
    }
    guard !escaped.isEmpty else { continue }
    let sorted = escaped.sorted()
    let p05 = sorted[Int(Double(sorted.count - 1) * 0.05)]
    let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
    // No pixel reaches the set, escape times span a handful of palette bands,
    // AND no samples sit near enough the set for the edge AA to draw its
    // silhouette: the window renders as a flat color wash with no visible
    // fractal. The edge-sample clause matters for hyperbolic (dust) Julia
    // sets, whose escape times stay low at every depth but whose silhouette
    // carries the structure (render-probe verified).
    if interior == 0 && p95 - p05 < 40 && edgeFrac < 0.02 {
      failures.append(
        String(
          format: "%@ [%@] scale=%.2e (escape spread %d..%d, no interior, %.1f%% edge)",
          spec.name, policy.name, scale, p05, p95, edgeFrac * 100))
    }
  }
  }
  return failures
}

private func diveStructureFailures(for target: MandelbrotTarget) -> [String] {
  guard let cx = Double(target.x), let cy = Double(target.y),
    let minScale = Double(target.minScale),
    let startScale = Double(target.startScale)
  else {
    return ["\(target.name): unparseable coordinates"]
  }
  guard startScale <= 3.0, startScale >= minScale * 100 else {
    return ["\(target.name): startScale \(target.startScale) out of range"]
  }
  let anchorEscape = escapeIteration(zx0: 0.0, zy0: 0.0, cx: cx, cy: cy, cap: 20_000)
  return diveStructureFailures(
    DiveSpec(
      name: target.name,
      anchorX: cx, anchorY: cy,
      startScale: startScale, minScale: minScale,
      anchorEscape: anchorEscape, julia: false,
      sample: { px, py, cap, pixelSpan in
        escapeCoverage(
          zx0: 0.0, zy0: 0.0, cx: px, cy: py,
          derivSeed: 0.0, derivAdd: 1.0, cap: cap, pixelSpan: pixelSpan)
      }))
}

private func diveStructureFailures(
  for constant: JuliaConstant, anchor: (x: Double, y: Double)
) -> [String] {
  let anchorEscape = escapeIteration(
    zx0: anchor.x, zy0: anchor.y, cx: constant.cx, cy: constant.cy, cap: 20_000)
  return diveStructureFailures(
    DiveSpec(
      name: "Julia \(constant.name)",
      anchorX: anchor.x, anchorY: anchor.y,
      startScale: juliaDiveStartScale, minScale: juliaDiveMinScale,
      anchorEscape: anchorEscape, julia: true,
      sample: { px, py, cap, pixelSpan in
        escapeCoverage(
          zx0: px, zy0: py, cx: constant.cx, cy: constant.cy,
          derivSeed: 1.0, derivAdd: 0.0, cap: cap, pixelSpan: pixelSpan)
      }))
}

private func metrics(for pixels: [UInt8], width: Int, height: Int) -> Metrics {
  var luminance = [Double](repeating: 0, count: width * height)
  var sum = 0.0
  var dark = 0
  for i in 0..<(width * height) {
    let offset = i * 4
    let b = Double(pixels[offset]) / 255.0
    let g = Double(pixels[offset + 1]) / 255.0
    let r = Double(pixels[offset + 2]) / 255.0
    let value = 0.2126 * r + 0.7152 * g + 0.0722 * b
    luminance[i] = value
    sum += value
    if value < 0.025 { dark += 1 }
  }

  let mean = sum / Double(luminance.count)
  let variance = luminance.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luminance.count)
  var difference = 0.0
  var pairs = 0
  for y in 0..<height {
    for x in 0..<width {
      let i = y * width + x
      if x + 1 < width {
        difference += abs(luminance[i] - luminance[i + 1])
        pairs += 1
      }
      if y + 1 < height {
        difference += abs(luminance[i] - luminance[i + width])
        pairs += 1
      }
    }
  }
  return Metrics(
    standardDeviation: sqrt(variance),
    neighborDifference: difference / Double(pairs),
    darkRatio: Double(dark) / Double(luminance.count)
  )
}

@main
private enum RenderAudit {
  static func main() throws {
    guard (2...3).contains(CommandLine.arguments.count) else {
      fatalError("usage: RenderAudit <metallib> [case-name-filter]")
    }
    let caseFilter = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : nil
    guard let device = MTLCreateSystemDefaultDevice() else {
      fatalError("Metal device unavailable")
    }

    let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
    var usePerturbation = false
    let floatConstants = MTLFunctionConstantValues()
    floatConstants.setConstantValue(&usePerturbation, type: .bool, index: 0)
    let floatFunction = try library.makeFunction(
      name: "mandelbrotKernel", constantValues: floatConstants)
    let floatPipeline = try device.makeComputePipelineState(function: floatFunction)

    usePerturbation = true
    let perturbationConstants = MTLFunctionConstantValues()
    perturbationConstants.setConstantValue(&usePerturbation, type: .bool, index: 0)
    let perturbationFunction = try library.makeFunction(
      name: "mandelbrotKernel", constantValues: perturbationConstants)
    let perturbationPipeline = try device.makeComputePipelineState(function: perturbationFunction)
    guard let queue = device.makeCommandQueue() else {
      fatalError("unable to create command queue")
    }

    let width = 160
    let height = 100
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm_srgb,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite, .shaderRead]
    descriptor.storageMode = .shared

    // 1x1 black stand-in for the freeze-dissolve held-frame texture; the
    // audit renders with blend weight 0 so it is bound but never blended.
    let heldDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
    heldDescriptor.usage = [.shaderRead]
    heldDescriptor.storageMode = .shared
    guard let heldDummy = device.makeTexture(descriptor: heldDescriptor) else {
      fatalError("unable to create held-frame stand-in texture")
    }
    var heldZero: UInt64 = 0
    withUnsafeBytes(of: &heldZero) { bytes in
      heldDummy.replace(
        region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
        withBytes: bytes.baseAddress!, bytesPerRow: 8)
    }

    // Julia anchors are dynamic in production; run the shared search once
    // here so the CPU and GPU passes audit identical dives.
    let juliaAnchors = FractalTargets.julia.map {
      JuliaAnchor.boundaryPoint(cx: $0.cx, cy: $0.cy)
    }

    var structureFailures: [String] = []
    for target in FractalTargets.mandelbrot
    where caseFilter == nil || target.name.localizedCaseInsensitiveContains(caseFilter!) {
      structureFailures.append(contentsOf: diveStructureFailures(for: target))
    }
    for (constant, anchor) in zip(FractalTargets.julia, juliaAnchors) {
      guard caseFilter == nil
        || "Julia \(constant.name)".localizedCaseInsensitiveContains(caseFilter!)
      else { continue }
      structureFailures.append(contentsOf: diveStructureFailures(for: constant, anchor: anchor))
    }
    if structureFailures.isEmpty {
      print(
        "Dive structure audit passed (\(FractalTargets.mandelbrot.count) Mandelbrot targets, "
          + "\(FractalTargets.julia.count) Julia constants).")
    } else {
      print("CPU structure failures: \(structureFailures.joined(separator: ", "))")
    }

    // End-of-dive GPU render, one case per production dive target.
    struct RenderCase {
      let name: String
      let centerX: DoubleDouble
      let centerY: DoubleDouble
      let endScale: Double
      let juliaC: (cx: Double, cy: Double)?  // nil = Mandelbrot
    }
    var renderCases = FractalTargets.mandelbrot.filter { target in
      caseFilter == nil || target.name.localizedCaseInsensitiveContains(caseFilter!)
    }.map { target in
      RenderCase(
        name: target.name,
        centerX: DoubleDouble(target.x), centerY: DoubleDouble(target.y),
        endScale: (Double(target.minScale) ?? 1e-5) * 2.0,
        juliaC: nil)
    }
    for (constant, anchor) in zip(FractalTargets.julia, juliaAnchors) {
      guard caseFilter == nil
        || "Julia \(constant.name)".localizedCaseInsensitiveContains(caseFilter!)
      else { continue }
      renderCases.append(
        RenderCase(
          name: "Julia \(constant.name)",
          centerX: DoubleDouble(anchor.x), centerY: DoubleDouble(anchor.y),
          endScale: juliaDiveMinScale * 2.0,
          juliaC: (constant.cx, constant.cy)))
    }

    // A filtered run is the tight diagnosis loop. Render every half-decade
    // through both kernels under every production policy so CPU-vs-GPU and
    // float-vs-perturbation disagreements are explicit in the output.
    if caseFilter != nil {
      for renderCase in renderCases {
        var probeScales: [Double] = []
        var probeScale = 3.0
        while probeScale > renderCase.endScale * 1.5 {
          probeScales.append(probeScale)
          probeScale *= pow(10.0, -0.5)
        }
        probeScales.append(renderCase.endScale)

        let julia = renderCase.juliaC != nil
        let anchorEscape: Int
        if let juliaC = renderCase.juliaC {
          anchorEscape = escapeIteration(
            zx0: renderCase.centerX.hi, zy0: renderCase.centerY.hi,
            cx: juliaC.cx, cy: juliaC.cy, cap: 20_000)
        } else {
          anchorEscape = escapeIteration(
            zx0: 0.0, zy0: 0.0,
            cx: renderCase.centerX.hi, cy: renderCase.centerY.hi, cap: 20_000)
        }
        let anchorMagnitude = max(abs(renderCase.centerX.hi), abs(renderCase.centerY.hi))

        for scale in probeScales {
          for policy in auditPolicies {
            let requestCount = policy.maxPerturbationIterations
            let orbit: [SIMD4<Float>]
            let validLength: Int
            if let juliaC = renderCase.juliaC {
              (orbit, validLength) = makeReferenceOrbit(
                startX: renderCase.centerX, startY: renderCase.centerY,
                cRe: DoubleDouble(juliaC.cx), cIm: DoubleDouble(juliaC.cy), count: requestCount)
            } else {
              (orbit, validLength) = makeReferenceOrbit(
                startX: DoubleDouble(0.0), startY: DoubleDouble(0.0),
                cRe: renderCase.centerX, cIm: renderCase.centerY, count: requestCount)
            }
            let frameCap = effectiveCap(
              scale: scale, anchorEscape: anchorEscape, julia: julia,
              anchorMagnitude: anchorMagnitude, policy: policy)

            guard let orbitBuffer = device.makeBuffer(
              bytes: orbit, length: orbit.count * MemoryLayout<SIMD4<Float>>.stride)
            else { fatalError("unable to allocate diagnostic orbit") }

            for (pathName, pathPipeline) in [
              ("float", floatPipeline), ("perturb", perturbationPipeline),
            ] {
              guard let texture = device.makeTexture(descriptor: descriptor),
                let commandBuffer = queue.makeCommandBuffer(),
                let encoder = commandBuffer.makeComputeCommandEncoder()
              else { fatalError("unable to create diagnostic render resources") }

              var uniforms = ShaderUniforms(
                geometry: SIMD4<Float>(
                  Float(renderCase.centerX.hi), Float(renderCase.centerY.hi),
                  Float(scale), Float(frameCap)),
                palette: SIMD4<Float>(0.0, Float(width) / Float(height), 0.0, 0.0),
                view: SIMD4<Float>(
                  Float(renderCase.centerX.lo), Float(renderCase.centerY.lo), 0.0, 0.0),
                mode: SIMD4<Float>(
                  0.0, julia ? 1.0 : 0.0,
                  Float(renderCase.juliaC?.cx ?? 0.0), Float(renderCase.juliaC?.cy ?? 0.0)),
                quality: SIMD4<Float>(1.0, 2.0, 1.0, 0.0),
                extra: SIMD4<Float>(Float(max(validLength, 1)), 0.0, 0.0, 0.0)
              )
              encoder.setComputePipelineState(pathPipeline)
              encoder.setTexture(texture, index: 0)
              encoder.setTexture(heldDummy, index: 1)
              encoder.setBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
              encoder.setBuffer(orbitBuffer, offset: 0, index: 1)
              encoder.dispatchThreadgroups(
                MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
              encoder.endEncoding()
              commandBuffer.commit()
              commandBuffer.waitUntilCompleted()
              if let error = commandBuffer.error { fatalError("diagnostic render failed: \(error)") }

              var pixels = [UInt8](repeating: 0, count: width * height * 4)
              texture.getBytes(
                &pixels, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
              let result = metrics(for: pixels, width: width, height: height)
              print(
                String(
                  format: "probe %@ [%@] scale=%.2e %@ cap=%d orbit=%d/%d std=%.4f edge=%.4f dark=%.1f%%",
                  renderCase.name, policy.name, scale, pathName, frameCap,
                  validLength, requestCount, result.standardDeviation,
                  result.neighborDifference, result.darkRatio * 100.0))
            }
          }
        }
      }
    }

    var failures: [String] = []
    for renderCase in renderCases {
      for iterationCap in [700, 1600] {
        for shadingMode in 0...3 {
          let orbit: [SIMD4<Float>]
          let validLength: Int
          if let juliaC = renderCase.juliaC {
            (orbit, validLength) = makeReferenceOrbit(
              startX: renderCase.centerX, startY: renderCase.centerY,
              cRe: DoubleDouble(juliaC.cx), cIm: DoubleDouble(juliaC.cy), count: iterationCap)
          } else {
            (orbit, validLength) = makeReferenceOrbit(
              startX: DoubleDouble(0.0), startY: DoubleDouble(0.0),
              cRe: renderCase.centerX, cIm: renderCase.centerY, count: iterationCap)
          }
          guard let texture = device.makeTexture(descriptor: descriptor),
            let orbitBuffer = device.makeBuffer(
              bytes: orbit, length: orbit.count * MemoryLayout<SIMD4<Float>>.stride),
            let commandBuffer = queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
          else {
            fatalError("unable to create render resources")
          }

          // Mirror MandelbrotView.planFrame: Julia budgets clamp to the
          // reference orbit's pre-escape length; Mandelbrot budgets run the
          // full cap and wrap the reference via rebasing.
          let maxIterations =
            renderCase.juliaC == nil
            ? iterationCap
            : max(min(validLength, iterationCap), 64)
          var uniforms = ShaderUniforms(
            geometry: SIMD4<Float>(
              Float(renderCase.centerX.hi), Float(renderCase.centerY.hi),
              Float(renderCase.endScale), Float(maxIterations)),
            palette: SIMD4<Float>(0.0, Float(width) / Float(height), 0.0, 0.0),
            view: SIMD4<Float>(
              Float(renderCase.centerX.lo), Float(renderCase.centerY.lo), Float(shadingMode), 0.0),
            mode: SIMD4<Float>(
              0.0, renderCase.juliaC == nil ? 0.0 : 1.0,
              Float(renderCase.juliaC?.cx ?? 0.0), Float(renderCase.juliaC?.cy ?? 0.0)),
            quality: SIMD4<Float>(1.0, 2.0, 1.0, 0.0),
            extra: SIMD4<Float>(Float(max(validLength, 1)), 0.0, 0.0, 0.0)
          )
          encoder.setComputePipelineState(perturbationPipeline)
          encoder.setTexture(texture, index: 0)
          encoder.setTexture(heldDummy, index: 1)
          encoder.setBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
          encoder.setBuffer(orbitBuffer, offset: 0, index: 1)
          encoder.dispatchThreadgroups(
            MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
          )
          encoder.endEncoding()
          commandBuffer.commit()
          commandBuffer.waitUntilCompleted()
          if let error = commandBuffer.error { fatalError("render failed: \(error)") }

          var pixels = [UInt8](repeating: 0, count: width * height * 4)
          texture.getBytes(
            &pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)
          let result = metrics(for: pixels, width: width, height: height)
          if shadingMode == 0 {
            print(
              String(
                format: "%7.4f std  %7.4f edge  %6.1f%% dark  %4d/%4d iter  %@",
                result.standardDeviation, result.neighborDifference, result.darkRatio * 100.0,
                validLength, iterationCap, renderCase.name))
          }

          // A solid, black, or near-solid palette field is the reported failure. Its
          // luminance variance stays at noise level even while the global hue changes.
          if result.standardDeviation < 0.035 {
            failures.append(
              "\(renderCase.name) (\(iterationCap)-iteration policy, shading \(shadingMode))")
          }
        }
      }
    }

    let allFailures = structureFailures + failures
    if !allFailures.isEmpty {
      fflush(stdout)
      fatalError("targets rendered without fractal structure: \(allFailures.joined(separator: ", "))")
    }
  }
}
