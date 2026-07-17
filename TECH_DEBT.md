# Technical Debt

Last updated: 2026-07-14

- **Live EDR tuning remains display-dependent.** Offline renders verify linear-light output and soft-knee bounds, but the final perceived highlight strength should be checked on both SDR and XDR panels.
- **The governor has only been profiled on the development Mac.** Its floor is 0.67× internal resolution with supersampling disabled, and it favors 30 fps over dropping below that sharper floor. Older Apple Silicon driving a 5K or 6K panel may need a user-selectable performance mode.
- **Analytic glow is single-pass.** A separable bloom pass could produce softer halos, but would add two full-screen dispatches and intermediate textures. The current distance-field glow is deliberate until live viewing proves the extra cost worthwhile.
- **Apple Silicon only.** The build script targets arm64. Universal packaging would require compiling and signing an x86_64 slice and validating Metal behavior on an Intel Mac.
- **No interactive scene scrubber.** Scene seeds are deterministic and covered by the render audit, but the configuration sheet does not expose a manual “next scene” control.
