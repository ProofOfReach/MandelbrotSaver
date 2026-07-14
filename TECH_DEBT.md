# Tech Debt

Last updated: 2026-07-14

## Further room for improvement (not yet done)

- **Governor floor may still miss 30fps on weaker GPUs.** The performance governor (added 2026-07-14
  after live dives kept aborting: deep frames measured up to ~1s on an M4 at 3024×1964, tripping the
  slow-frame bailout) steps supersampling off and internal resolution down to 0.375× but never touches
  iteration budgets, since those change the audited image. On the M4 the floor's worst frame is 28ms;
  an M1 at 5K could still sit below 30fps at maximum depth. If that shows up, the next rung is a
  per-target iteration hint (below), not a global budget cut.

- **Per-target iteration hints.** Each curated `interestingPoints` entry could carry an audited
  "expected p90 escape iterations" value instead of relying on the generic depth-based formula — would
  tighten the iteration cap per-target rather than using one global cap for all of them.
- **Julia perturbation glitches.** Mandelbrot dives now use Zhuoran-style rebasing (glitch-free, and
  the reference orbit's escape no longer caps the frame budget). Julia references start at the boundary
  anchor rather than 0, where index-0 rebasing doesn't apply, so deep Julia frames can still show a
  smooth wrong-color blob from reference divergence (observed: San Marco at scale 3e-5). A critical-orbit
  Julia reference would enable rebasing but costs per-pixel delta precision at end-of-dive scales in
  float32; revisit only if the artifact shows up noticeably in live runs. (The per-step residual
  `ref.zw` is computed in double since 2026-07-14 — previously ~90% of it was Float32 rounding
  noise — which removes one error source but not the underlying no-rebasing limitation.)
- **Julia constant morphing is un-audited.** `juliaCx/Cy` orbit the curated constant on a circle of
  radius `min(0.004, 0.15 * scale)`. The dive-structure audit checks the static constant only; the
  scale-bounded radius keeps boundary displacement under ~15% of a view height, and the perturbation
  budget clamps to the (per-frame) orbit escape length so a fast-escaping morph phase renders shallow
  rather than wrong — but a live soak is the real test.
- **Adaptive supersampling only triggers on exterior-centered pixels.** Interior-centered boundary
  pixels keep a single sample; the analytic edge AA already fades the exterior side of the silhouette
  toward the interior color, so the visible edge stays smooth. Revisit only if silhouettes shimmer in
  live runs.
- **P3 gamut expansion ("Vivid") not implemented.** The layer is now extended-linear sRGB with EDR
  headroom (band-free, correct color, brighter-than-SDR highlights), but palettes still target sRGB
  primaries. An opt-in "treat palette values as P3" saturation boost remains possible if wanted.
- **Live on-screen verification still pending.** All changes were verified offline (build, render
  probes, CPU escape-time audit at every half-decade of every dive, GPU end-of-dive renders across
  shading modes × iteration policies, and a full-dive GPU frame-time sweep at native resolution).
  Not yet tested on a live display: ProMotion pacing at 120Hz, EDR headroom behavior on XDR vs SDR
  panels, freeze-dissolve pacing, governor level transitions (visible resolution steps?),
  battery/Low Power Mode transitions, and the overall visual impression over an extended run.
