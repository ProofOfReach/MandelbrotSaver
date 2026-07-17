import Foundation

struct MandelbrotTarget {
  let x: String
  let y: String
  let minScale: String
  let name: String
  // Scale the dive opens at. Most targets start at the full set (3.0); targets
  // whose approach crosses a black bottleneck (e.g. the cardioid/period-2
  // pinch, where the frame is >95% set interior for whole decades) start below
  // it so no shown window renders as a black screen.
  var startScale: String = "3.0"
}

struct JuliaConstant {
  let cx: Double
  let cy: Double
  let name: String
}

enum FractalTargets {
  // Curated for dense structure, low empty-center risk, and stable real-time depth.
  //
  // Every anchor is refined onto the set boundary (exterior distance estimate
  // << minScale) so the boundary stays inside the view at every zoom level of
  // the dive — an anchor that drifts off-boundary ends the dive in a
  // featureless exterior gradient. Anchors whose orbit escapes within the
  // 1600-iteration perturbation request also clamp the whole frame's budget
  // (renderer uses referenceOrbitValidLength), so escape times were pushed as
  // high as the region allows. scripts/RenderAudit.swift verifies every
  // half-decade of each dive (from startScale down): windows must not be a
  // featureless color wash, and their shader-faithful rendered brightness
  // (edge-AA coverage) must clear a black-screen bar. Rerun it after touching
  // this table.
  static let mandelbrot = [
    MandelbrotTarget(
      x: "-0.7445388635959773", y: "0.1217247190726782", minScale: "2e-6",
      name: "Seahorse Valley Deep Spiral"),
    MandelbrotTarget(
      x: "-0.74519687999999995", y: "0.10186948500000009", minScale: "1e-6",
      name: "Seahorse Valley Classic"),
    MandelbrotTarget(
      x: "-0.74645742386692826", y: "0.11019386660182796", minScale: "1e-5",
      name: "Seahorse Valley Wide"),
    MandelbrotTarget(
      x: "0.27773240090831197", y: "0.0073446122718611832", minScale: "1e-6",
      name: "Elephant Trunk"),
    MandelbrotTarget(
      x: "0.33698444655759424", y: "0.048778219736009501", minScale: "1e-6",
      name: "Elephant Eye"),
    MandelbrotTarget(
      x: "-0.087603302820561293", y: "0.65508020694739977", minScale: "1e-6",
      name: "Triple Spiral Valley"),
    MandelbrotTarget(
      x: "-0.53606677755277998", y: "-0.5255257775712241", minScale: "1e-6", name: "Turbulence"),
    MandelbrotTarget(
      x: "-0.22163951090127437", y: "-0.7115537848292754", minScale: "1e-6", name: "LSD Spiral"),
    MandelbrotTarget(
      x: "-0.77468061062690385", y: "0.1374168856037867", minScale: "1e-6",
      name: "Double Spiral Valley"),
    MandelbrotTarget(
      x: "0.35787087025640801", y: "-0.10813992613434703", minScale: "1e-6",
      name: "Carousel Spirals"),
    MandelbrotTarget(
      x: "-0.16070033672676085", y: "1.0375663161605602", minScale: "1e-5", name: "Sunburst"),
    MandelbrotTarget(
      x: "-1.2506602882461879", y: "0.020120460721365852", minScale: "1e-6",
      name: "Scepter Valley"),
    MandelbrotTarget(
      x: "-0.15279855076423288", y: "1.0397060429613145", minScale: "1e-5",
      name: "Period-3 Boundary"),
    MandelbrotTarget(
      x: "-0.37401139851178283", y: "-0.65978154081499085", minScale: "1e-5",
      name: "Starfish Filament"),
    MandelbrotTarget(
      x: "-0.74976917676699995", y: "0.020115113112999999", minScale: "1e-5",
      name: "Triple Spiral Tendril", startScale: "3e-3"),
    MandelbrotTarget(
      x: "-1.2497832500000001", y: "0.029353000000000001", minScale: "1e-6",
      name: "Scepter Double-Hook"),
    MandelbrotTarget(
      x: "-1.24949887", y: "0.030333012499999999", minScale: "1e-7", name: "Scepter Hook Core"),
    MandelbrotTarget(
      x: "-0.75284067971468949", y: "0.043162652168357921", minScale: "1e-6",
      name: "Hidden Teddy Boundary", startScale: "1e-2"),
    MandelbrotTarget(
      x: "0.36023265079055072", y: "-0.64137424503986562", minScale: "1e-6",
      name: "Eye of the Universe"),
    MandelbrotTarget(
      x: "0.27024949999999998", y: "0.48049599999999998", minScale: "1e-5",
      name: "Quad Spiral Cusp"),
  ]

  static let julia = [
    JuliaConstant(cx: -0.7, cy: 0.27015, name: "Classic Spiral"),
    JuliaConstant(cx: -0.4, cy: 0.6, name: "Dendrite"),
    JuliaConstant(cx: 0.285, cy: 0.01, name: "Snail Shell"),
    JuliaConstant(cx: -0.8, cy: 0.156, name: "Rabbit"),
    JuliaConstant(cx: -0.70176, cy: -0.3842, name: "Dragon"),
    JuliaConstant(cx: 0.285, cy: 0.535, name: "Galaxy"),
    JuliaConstant(cx: -0.835, cy: -0.2321, name: "Lightning"),
    JuliaConstant(cx: -0.1, cy: 0.651, name: "Seahorse Tail"),
    JuliaConstant(cx: -0.74543, cy: 0.11301, name: "Seahorse Julia"),
    JuliaConstant(cx: 0.0, cy: -0.8, name: "San Marco"),
    JuliaConstant(cx: -1.476, cy: 0.0, name: "Cauliflower"),
    JuliaConstant(cx: -0.12, cy: -0.77, name: "Starfish"),
    JuliaConstant(cx: 0.28, cy: 0.008, name: "Siegel Disk"),
    JuliaConstant(cx: -0.194, cy: 0.6557, name: "Pinwheel"),
    JuliaConstant(cx: -0.12, cy: 0.74, name: "Spiral Galaxy"),
    JuliaConstant(cx: 0.3, cy: 0.5, name: "Feathers"),
  ]
}

/// Boundary-anchor search for Julia dives. Deterministic for a given
/// constant, and shared between the saver (MandelbrotView target selection)
/// and scripts/RenderAudit.swift so the audit exercises the exact anchors
/// production dives into.
enum JuliaAnchor {
  /// Finds a visually rich zoom target on the Julia set boundary for
  /// constant c. Strategy: locate the boundary along sample rays, then home
  /// in on a point whose escape time sits in a band comfortably inside the
  /// iteration cap — close enough to the set for fractal structure at the
  /// end-of-dive scale, far enough that surrounding pixels still escape
  /// within budget. A cheap end-window probe gates the result, retrying
  /// with rotated rays. A few ms of CPU per call.
  static func boundaryPoint(cx: Double, cy: Double) -> (x: Double, y: Double) {
    let maxIter = 2000
    let bandLo = 700  // anchor escape-time sweet spot: rich detail
    let bandHi = 1300  // yet safely below the 1600 iteration cap
    let samplesPerRay = 240

    func escapeIteration(_ zx0: Double, _ zy0: Double) -> Int {
      var zx = zx0, zy = zy0
      for i in 0..<maxIter {
        // Escape radius 256, matching the renderer (smooth-coloring bailout).
        if zx * zx + zy * zy > 65536.0 { return i }
        (zx, zy) = (zx * zx - zy * zy + cx, 2.0 * zx * zy + cy)
      }
      return maxIter
    }

    func anchorAlongRays(_ rayAngles: [Double]) -> (x: Double, y: Double)? {
      var bestExterior = (x: 0.0, y: 0.0, iter: -1)
      var bestPair: (ix: Double, iy: Double, ex: Double, ey: Double, score: Int)? = nil
      for angle in rayAngles {
        let dirX = cos(angle), dirY = sin(angle)
        var previous: (x: Double, y: Double, iter: Int)? = nil
        for s in 1...samplesPerRay {
          let r = 1.8 * Double(s) / Double(samplesPerRay)
          let px = r * dirX, py = r * dirY
          let iter = escapeIteration(px, py)
          if iter < maxIter, iter > bestExterior.iter {
            bestExterior = (px, py, iter)
          }
          if let prev = previous {
            let bestScore = bestPair?.score ?? -1
            if iter >= maxIter, prev.iter < maxIter, prev.iter > bestScore {
              bestPair = (px, py, prev.x, prev.y, prev.iter)
            } else if iter < maxIter, prev.iter >= maxIter, iter > bestScore {
              bestPair = (prev.x, prev.y, px, py, iter)
            }
          }
          previous = (px, py, iter)
        }
      }

      if var pair = bestPair {
        // Tighten the interior/exterior bracket until the exterior
        // endpoint's escape time enters the band; that endpoint is the
        // anchor. (Escape time rises toward the boundary.)
        for _ in 0..<48 {
          if escapeIteration(pair.ex, pair.ey) >= bandLo {
            return (pair.ex, pair.ey)
          }
          let mx = (pair.ix + pair.ex) * 0.5
          let my = (pair.iy + pair.ey) * 0.5
          if escapeIteration(mx, my) >= maxIter {
            pair.ix = mx
            pair.iy = my
          } else {
            pair.ex = mx
            pair.ey = my
          }
        }
        return (pair.ex, pair.ey)
      }

      if bestExterior.iter >= 0 {
        // Dust set (no interior found): walk the escape-time peak
        // along the anchor ray. Escape time diverges toward the set,
        // so recentering on the local max homes in; stop once inside
        // the band.
        let radius = sqrt(bestExterior.x * bestExterior.x + bestExterior.y * bestExterior.y)
        let dirX = bestExterior.x / radius, dirY = bestExterior.y / radius
        var lo = radius - 1.8 / Double(samplesPerRay)
        var hi = radius + 1.8 / Double(samplesPerRay)
        for _ in 0..<14 {
          var localBest = (r: radius, iter: -1)
          for s in 0...24 {
            let r = lo + (hi - lo) * Double(s) / 24.0
            let iter = escapeIteration(r * dirX, r * dirY)
            if iter < maxIter, iter > localBest.iter {
              localBest = (r, iter)
            }
          }
          if localBest.iter >= bandLo || hi - lo < 1e-9 {
            return (localBest.r * dirX, localBest.r * dirY)
          }
          let span = (hi - lo) * 0.125
          lo = localBest.r - span
          hi = localBest.r + span
        }
        return (bestExterior.x, bestExterior.y)
      }
      return nil
    }

    /// End-of-dive window probe: is there visible structure around this
    /// anchor, renderable within the iteration cap?
    func windowIsRich(_ p: (x: Double, y: Double)) -> Bool {
      let window = 6e-5
      var escaped: [Int] = []
      var interior = 0
      for gy in 0..<5 {
        for gx in 0..<5 {
          let px = p.x + (Double(gx) / 4.0 - 0.5) * window
          let py = p.y + (Double(gy) / 4.0 - 0.5) * window
          let iter = escapeIteration(px, py)
          if iter >= maxIter { interior += 1 } else { escaped.append(iter) }
        }
      }
      guard !escaped.isEmpty else { return false }
      let s = escaped.sorted()
      guard s[s.count / 2] <= bandHi else { return false }
      // Structure = interior/exterior mix, or a wide escape-time spread.
      return interior > 0 || (s[s.count - 1] - s[0]) >= 25
    }

    var fallback: (x: Double, y: Double)? = nil
    for attempt in 0..<4 {
      let base = 0.13 + Double(attempt) * 0.41
      let angles = (0..<6).map { base + Double($0) * (2.0 * Double.pi / 6.0) + Double($0 % 3) * 0.07 }
      if let anchor = anchorAlongRays(angles) {
        if windowIsRich(anchor) { return anchor }
        if fallback == nil { fallback = anchor }
      }
    }
    return fallback ?? (0.0, 0.0)
  }
}
