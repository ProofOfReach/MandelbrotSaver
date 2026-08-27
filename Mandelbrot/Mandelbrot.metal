#include <metal_stdlib>
using namespace metal;

// ============================================================================
// COLOR PALETTES - Inspired by classic fractal art
// Authored as sRGB display values; sampled with wrap-around Catmull-Rom so the
// gradient is cyclic (no palette[15] -> palette[0] seam) and C1-smooth (no
// terracing at the 16 control points).
// ============================================================================

// Ultra Fractal style - rich and vibrant
constant float3 palette_ultra[16] = {
    float3(0.00, 0.00, 0.00),
    float3(0.10, 0.00, 0.20),
    float3(0.20, 0.00, 0.40),
    float3(0.00, 0.20, 0.60),
    float3(0.00, 0.40, 0.80),
    float3(0.00, 0.60, 0.80),
    float3(0.00, 0.80, 0.60),
    float3(0.20, 0.90, 0.40),
    float3(0.50, 1.00, 0.20),
    float3(0.80, 1.00, 0.00),
    float3(1.00, 0.90, 0.00),
    float3(1.00, 0.70, 0.00),
    float3(1.00, 0.50, 0.00),
    float3(1.00, 0.30, 0.20),
    float3(0.80, 0.10, 0.30),
    float3(0.50, 0.00, 0.30)
};

// Ember palette - warm and intense
constant float3 palette_fire[16] = {
    float3(0.00, 0.00, 0.00),
    float3(0.10, 0.00, 0.00),
    float3(0.25, 0.00, 0.00),
    float3(0.40, 0.00, 0.00),
    float3(0.55, 0.05, 0.00),
    float3(0.70, 0.10, 0.00),
    float3(0.85, 0.20, 0.00),
    float3(0.95, 0.35, 0.00),
    float3(1.00, 0.50, 0.00),
    float3(1.00, 0.65, 0.10),
    float3(1.00, 0.80, 0.20),
    float3(1.00, 0.90, 0.40),
    float3(1.00, 0.95, 0.60),
    float3(1.00, 1.00, 0.80),
    float3(1.00, 1.00, 0.95),
    float3(1.00, 1.00, 1.00)
};

// Abyss palette - cool and deep
constant float3 palette_ocean[16] = {
    float3(0.00, 0.00, 0.05),
    float3(0.00, 0.02, 0.10),
    float3(0.00, 0.05, 0.20),
    float3(0.00, 0.10, 0.35),
    float3(0.00, 0.20, 0.50),
    float3(0.00, 0.35, 0.60),
    float3(0.00, 0.50, 0.65),
    float3(0.10, 0.65, 0.70),
    float3(0.20, 0.75, 0.75),
    float3(0.40, 0.85, 0.80),
    float3(0.60, 0.90, 0.85),
    float3(0.75, 0.95, 0.90),
    float3(0.85, 0.98, 0.95),
    float3(0.95, 1.00, 1.00),
    float3(0.80, 0.95, 1.00),
    float3(0.50, 0.80, 0.95)
};

// Neon palette - saturated cyan, violet, and acid green
constant float3 palette_electric[16] = {
    float3(0.00, 0.00, 0.00),
    float3(0.05, 0.00, 0.15),
    float3(0.10, 0.00, 0.30),
    float3(0.20, 0.00, 0.50),
    float3(0.35, 0.00, 0.70),
    float3(0.50, 0.00, 0.85),
    float3(0.70, 0.00, 1.00),
    float3(0.85, 0.20, 1.00),
    float3(1.00, 0.40, 1.00),
    float3(1.00, 0.60, 0.80),
    float3(1.00, 0.80, 0.60),
    float3(0.00, 1.00, 1.00),
    float3(0.00, 1.00, 0.60),
    float3(0.00, 1.00, 0.30),
    float3(0.30, 1.00, 0.00),
    float3(0.60, 1.00, 0.00)
};

// Aurora palette - northern lights
constant float3 palette_aurora[16] = {
    float3(0.00, 0.05, 0.10),
    float3(0.00, 0.15, 0.20),
    float3(0.00, 0.30, 0.30),
    float3(0.00, 0.45, 0.35),
    float3(0.00, 0.60, 0.40),
    float3(0.10, 0.75, 0.45),
    float3(0.30, 0.85, 0.50),
    float3(0.50, 0.90, 0.55),
    float3(0.70, 0.95, 0.60),
    float3(0.85, 0.80, 0.90),
    float3(0.75, 0.50, 0.85),
    float3(0.60, 0.30, 0.75),
    float3(0.45, 0.15, 0.60),
    float3(0.30, 0.10, 0.45),
    float3(0.15, 0.08, 0.30),
    float3(0.05, 0.05, 0.15)
};

// Graphite palette - grayscale with subtle blue
constant float3 palette_monochrome[16] = {
    float3(0.00, 0.00, 0.02),
    float3(0.05, 0.05, 0.07),
    float3(0.10, 0.10, 0.12),
    float3(0.18, 0.18, 0.20),
    float3(0.25, 0.25, 0.28),
    float3(0.35, 0.35, 0.38),
    float3(0.45, 0.45, 0.48),
    float3(0.55, 0.55, 0.58),
    float3(0.65, 0.65, 0.68),
    float3(0.75, 0.75, 0.77),
    float3(0.85, 0.85, 0.87),
    float3(0.92, 0.92, 0.94),
    float3(0.97, 0.97, 0.98),
    float3(0.88, 0.88, 0.90),
    float3(0.70, 0.70, 0.73),
    float3(0.45, 0.45, 0.48)
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Escape radius 256 (squared). The classic radius-2 bailout leaves visible
// periodic ripple in the smooth-iteration estimate; at R=256 the log-log
// formula is essentially exact for a few extra iterations of cost. The CPU
// reference orbit uses the same radius so perturbation indices line up.
constant float BAILOUT_SQ = 65536.0f;

float3 srgbToLinear(float3 c) {
    float3 lo = c / 12.92f;
    float3 hi = pow((c + 0.055f) / 1.055f, float3(2.4f));
    return select(hi, lo, c <= 0.04045f);
}

// Wrap-around Catmull-Rom through the 16 control points (16 segments).
float3 samplePalette(constant float3* palette, float t) {
    float x = fract(t) * 16.0f;
    int i1 = int(x) & 15;
    float f = x - floor(x);
    int i0 = (i1 + 15) & 15;
    int i2 = (i1 + 1) & 15;
    int i3 = (i1 + 2) & 15;
    float3 p0 = palette[i0];
    float3 p1 = palette[i1];
    float3 p2 = palette[i2];
    float3 p3 = palette[i3];
    float3 b = p2 - p0;
    float3 c = 2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3;
    float3 d = -p0 + 3.0f * (p1 - p2) + p3;
    float3 v = p1 + 0.5f * f * (b + f * (c + f * d));
    return clamp(v, 0.0f, 1.0f);
}

// Sample curated palette by index. Returns sRGB display values.
float3 samplePaletteByIndex(int paletteIndex, float t) {
    switch (paletteIndex) {
        case 0: return samplePalette(palette_ultra, t);
        case 1: return samplePalette(palette_fire, t);
        case 2: return samplePalette(palette_ocean, t);
        case 3: return samplePalette(palette_electric, t);
        case 4: return samplePalette(palette_aurora, t);
        case 5: return samplePalette(palette_monochrome, t);
        default: return samplePalette(palette_ultra, t);
    }
}

// Palettes are authored in sRGB; decode each with the exact sRGB EOTF and do
// the palette-to-palette crossfade in linear light so mid-blends don't go
// muddy the way sRGB-space mixes do. All downstream math is linear; the
// drawable (rgba16Float + linear colorspace, or _srgb fallback) handles
// display encoding.
float3 getPaletteColor(float t, int paletteIndex, float paletteMix) {
    int totalPalettes = 6;
    int nextPalette = (paletteIndex + 1) % totalPalettes;

    float3 c1 = srgbToLinear(samplePaletteByIndex(paletteIndex, t));
    float3 c2 = srgbToLinear(samplePaletteByIndex(nextPalette, t));
    return mix(c1, c2, paletteMix);
}

// Identity below the knee, exponential shoulder asymptoting at `peak`.
// Keeps lighting sums > 1 from hard-clipping per channel (hue shift); on EDR
// displays `peak` is the panel's actual headroom so highlights really glow.
float3 tonemapSoftKnee(float3 c, float peak) {
    float knee = 0.75f * peak;
    float3 over = max(c - knee, 0.0f);
    float3 soft = knee + (peak - knee) * (1.0f - exp(-over / (peak - knee)));
    return select(soft, c, c <= knee);
}

// ============================================================================
// MAIN KERNEL
// ============================================================================

constant bool usePerturbation [[function_constant(0)]];

struct ShaderUniforms {
    float4 geometry; // centerX_hi, centerY_hi, scale, maxIterations
    float4 palette;  // colorOffset, aspectRatio, paletteIndex, paletteMix
    float4 view;     // centerX_lo, centerY_lo, shadingMode, time
    float4 mode;     // heldBlendWeight, juliaMode, juliaCx, juliaCy
    float4 quality;  // aaSamples, lightingQuality, edrHeadroom, rotationAngle
    float4 extra;    // referenceOrbitValidLength, reserved, reserved, reserved
};

struct FractalResult {
    float iteration;
    float dzx;
    float dzy;
    float final_zx;
    float final_zy;
    float mag_sq;
    float trapMinMagSq;
};

// Complex math helpers on float2
inline float2 cmul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

inline float2 csqr(float2 a) {
    return float2(a.x * a.x - a.y * a.y, 2.0f * a.x * a.y);
}

FractalResult evaluateFractal(
    float2 sampleOffset,
    constant ShaderUniforms &uniforms,
    device float4 *referenceOrbit,
    uint2 gid,
    uint width,
    uint height
) {
    float centerX_hi = uniforms.geometry.x;
    float centerY_hi = uniforms.geometry.y;
    float scale = uniforms.geometry.z;
    float maxIterations = uniforms.geometry.w;
    float aspectRatio = uniforms.palette.y;
    float centerX_lo = uniforms.view.x;
    float centerY_lo = uniforms.view.y;
    bool juliaMode = uniforms.mode.y > 0.5f;
    float juliaCx = uniforms.mode.z;
    float juliaCy = uniforms.mode.w;

    float invWidth = 1.0f / float(width);
    float invHeight = 1.0f / float(height);
    float px = ((float(gid.x) + 0.5f + sampleOffset.x) * invWidth - 0.5f) * scale * aspectRatio;
    float py = ((float(gid.y) + 0.5f + sampleOffset.y) * invHeight - 0.5f) * scale;

    // Slow view rotation, applied in complex-plane units. For the
    // perturbation path this rotates dc, which is exactly a rotation of the
    // window around the reference anchor.
    float angle = uniforms.quality.w;
    if (angle != 0.0f) {
        float ca = cos(angle);
        float sa = sin(angle);
        float2 pr = float2(px * ca - py * sa, px * sa + py * ca);
        px = pr.x;
        py = pr.y;
    }

    FractalResult result;
    result.iteration = 0.0f;
    // Derivative for distance estimation / 3D normals.
    // Mandelbrot tracks dz/dc (init 0, +1 each step); Julia tracks dz/dz0 (init 1, no additive term).
    result.dzx = juliaMode ? 1.0f : 0.0f;
    result.dzy = 0.0f;
    float derivAdd = juliaMode ? 0.0f : 1.0f;
    result.final_zx = 0.0f;
    result.final_zy = 0.0f;
    result.mag_sq = 0.0f;
    result.trapMinMagSq = 1e30f;

    if (usePerturbation) {
        float2 dc = float2(px, py);
        float2 dz = float2(0.0f, 0.0f);

        if (juliaMode) {
            dz = float2(px, py);
            dc = float2(0.0f, 0.0f);
        }

        // Zhuoran-style rebasing (Mandelbrot only, since its reference starts
        // at Z0 = 0): when the full orbit z = Z + dz comes closer to zero
        // than the delta, restart the delta from the full value at reference
        // index 0. This removes the classic wrong-color glitch blobs from
        // reference-orbit divergence AND lets the pixel budget run past the
        // reference orbit's own escape (the index wraps via rebase), so the
        // anchor's escape time no longer caps the frame. Julia references
        // start at the anchor (Z0 != 0), where a rebase target of index 0
        // doesn't exist; the Swift side keeps clamping Julia budgets to the
        // orbit's pre-escape length instead.
        uint validLength = uint(max(uniforms.extra.x, 1.0f));
        uint m = 0;
        for (int i = 0; i < int(maxIterations); i++) {
            uint referenceIndex = min(m, validLength - 1);
            float4 ref = referenceOrbit[referenceIndex];
            float2 Z = ref.xy;

            float2 z = Z + dz;
            float mag_sq = dot(z, z);
            // Orbit trap skips the seed (z0 = 0 for Mandelbrot would pin the
            // minimum to zero and flatten the interior glow).
            if (i > 0) {
                result.trapMinMagSq = min(result.trapMinMagSq, mag_sq);
            }
            if (mag_sq > BAILOUT_SQ) {
                result.final_zx = z.x;
                result.final_zy = z.y;
                result.mag_sq = mag_sq;
                break;
            }

            float new_dzx = 2.0f * (z.x * result.dzx - z.y * result.dzy) + derivAdd;
            float new_dzy = 2.0f * (z.x * result.dzy + z.y * result.dzx);
            result.dzx = new_dzx;
            result.dzy = new_dzy;

            if (!juliaMode && (m + 1 >= validLength || mag_sq < dot(dz, dz))) {
                dz = z;
                m = 0;
                ref = referenceOrbit[0];
                Z = ref.xy;
            }

            float2 term1 = cmul(2.0f * Z, dz);
            float2 term2 = csqr(dz);
            dz = term1 + term2 + dc + ref.zw;
            m++;

            result.iteration += 1.0f;
        }
    } else {
        float cx_f = centerX_hi + centerX_lo + px;
        float cy_f = centerY_hi + centerY_lo + py;

        float zx, zy, cx, cy;

        if (juliaMode) {
            zx = cx_f;
            zy = cy_f;
            cx = juliaCx;
            cy = juliaCy;
        } else {
            zx = 0.0f;
            zy = 0.0f;
            cx = cx_f;
            cy = cy_f;
        }

        float q = (cx - 0.25f) * (cx - 0.25f) + cy * cy;
        bool inCardioid = !juliaMode && (q * (q + (cx - 0.25f)) <= 0.25f * cy * cy);
        bool inBulb = !juliaMode && ((cx + 1.0f) * (cx + 1.0f) + cy * cy <= 0.0625f);

        if (inCardioid || inBulb) {
            result.iteration = maxIterations;
            result.trapMinMagSq = min(cx * cx + cy * cy, 1.0f);
        } else {
            while (result.iteration < maxIterations) {
                float zx_sq = zx * zx;
                float zy_sq = zy * zy;

                float mag_sq = zx_sq + zy_sq;
                // Skip the seed sample, matching the perturbation path.
                if (result.iteration > 0.5f) {
                    result.trapMinMagSq = min(result.trapMinMagSq, mag_sq);
                }
                if (mag_sq > BAILOUT_SQ) {
                    result.final_zx = zx;
                    result.final_zy = zy;
                    result.mag_sq = mag_sq;
                    break;
                }

                float new_dzx = 2.0f * (zx * result.dzx - zy * result.dzy) + derivAdd;
                float new_dzy = 2.0f * (zx * result.dzy + zy * result.dzx);
                result.dzx = new_dzx;
                result.dzy = new_dzy;

                float new_zy = 2.0f * zx * zy + cy;
                float new_zx = zx_sq - zy_sq + cx;

                zx = new_zx;
                zy = new_zy;
                result.iteration += 1.0f;
            }
        }
    }

    return result;
}

float3 colorFractal(FractalResult result, constant ShaderUniforms &uniforms, float pixelSpan) {
    float maxIterations = uniforms.geometry.w;
    float colorOffset = uniforms.palette.x;
    int paletteIndex = int(uniforms.palette.z);
    float paletteMix = uniforms.palette.w;
    int shadingMode = int(uniforms.view.z);
    float time = uniforms.view.w;
    float lightingQuality = uniforms.quality.y;

    if (result.iteration >= maxIterations) {
        // Interior: a very subtle |z|-min orbit-trap glow instead of dead
        // black, so set-dominated frames keep faint structure. Peak
        // luminance stays under ~3% to preserve the near-black look.
        float trapDist = sqrt(max(result.trapMinMagSq, 0.0f));
        float glow = exp(-3.5f * trapDist);
        float tInterior = trapDist * 1.7f + colorOffset * 0.004f;
        float3 base = getPaletteColor(tInterior, paletteIndex, paletteMix);
        return base * (0.028f * glow);
    }

    float mag_sq = max(result.mag_sq, 1.000001f);
    float log_zn = 0.5f * log(mag_sq);
    float nu = log2(max(log_zn * 1.44269504089f, 1e-6f));
    float smoothIter = result.iteration + 1.0f - nu;

    float t = (smoothIter + colorOffset) * 0.02f;
    float3 color = getPaletteColor(t, paletteIndex, paletteMix);

    if (shadingMode == 1) {
        // Milnor slope normal: u = z / z' is scale-invariant, so the relief
        // holds up at every zoom depth. (Raw (dzx, dzy) normals collapse into
        // the xy-plane once |z'| dwarfs the height term, which flattened the
        // lighting precisely in deep frames.)
        float3 N = float3(0.0f, 0.0f, 1.0f);
        float2 dzv = float2(result.dzx, result.dzy);
        float dz2 = dot(dzv, dzv);
        if (isfinite(dz2) && dz2 > 1e-30f) {
            float2 dzn = dzv * rsqrt(dz2);
            float2 u = cmul(float2(result.final_zx, result.final_zy), float2(dzn.x, -dzn.y));
            float ulen = length(u);
            if (ulen > 1e-20f) {
                u /= ulen;
                N = normalize(float3(u.x, u.y, 1.4f));
            }
        }
        float3 V = float3(0.0f, 0.0f, 1.0f);

        float lightAngle = time * 0.5f;
        float3 primaryLightDir = normalize(float3(
            cos(lightAngle) * 1.5f,
            sin(lightAngle) * 0.8f - 1.0f,
            2.0f
        ));
        float3 primaryLightColor = float3(1.0f, 0.95f, 0.85f);

        float3 secondaryLightDir = normalize(float3(
            -cos(lightAngle) * 1.2f,
            -sin(lightAngle) * 0.6f + 0.5f,
            1.5f
        ));
        float3 secondaryLightColor = float3(0.4f, 0.5f, 0.7f);

        float diffuse1 = max(dot(N, primaryLightDir), 0.0f);
        float diffuse2 = max(dot(N, secondaryLightDir), 0.0f);
        float specular1 = 0.0f;
        float specular2 = 0.0f;
        float rim = 0.0f;

        if (lightingQuality >= 2.0f || smoothIter > 12.0f) {
            float shininess = 32.0f;
            float3 H1 = normalize(primaryLightDir + V);
            float3 H2 = normalize(secondaryLightDir + V);
            specular1 = pow(max(dot(N, H1), 0.0f), shininess);
            specular2 = pow(max(dot(N, H2), 0.0f), shininess * 0.5f);
            float rimBase = 1.0f - max(dot(N, V), 0.0f);
            rim = rimBase * rimBase * rimBase;
        }

        float ao = 1.0f - smoothstep(50.0f, maxIterations * 0.5f, smoothIter) * 0.4f;

        float3 lighting = float3(0.15f) * ao;
        lighting += primaryLightColor * (diffuse1 * 0.6f + specular1 * 0.3f);
        lighting += secondaryLightColor * (diffuse2 * 0.3f + specular2 * 0.15f);
        lighting += float3(0.6f, 0.7f, 1.0f) * rim * 0.4f;

        color *= lighting;
    } else if (shadingMode == 2) {
        float angle = atan2(result.final_zy, result.final_zx);
        float shade = 0.5f + 0.5f * sin(angle * 8.0f + time);
        color *= 0.6f + 0.4f * shade;
    } else if (shadingMode == 3) {
        float stripe = 0.5f + 0.5f * sin(smoothIter * 0.5f + time * 2.0f);
        color = mix(color, color * 0.3f, stripe * 0.3f);
    }

    // Analytic edge anti-aliasing: the distance estimate |z|·ln|z| / |z'|
    // tells how far this sample is from the set boundary. Fading to the
    // interior color within one pixel of the boundary smooths the fractal
    // edge without supersampling.
    float dz_mag_de = max(sqrt(result.dzx * result.dzx + result.dzy * result.dzy), 1e-20f);
    float z_mag_de = sqrt(mag_sq);
    float distanceEstimate = 0.5f * log(mag_sq) * z_mag_de / dz_mag_de;
    float edgeCoverage = clamp(distanceEstimate / max(pixelSpan, 1e-30f), 0.0f, 1.0f);
    color *= edgeCoverage;

    return color;
}

kernel void mandelbrotKernel(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::read> heldFrame [[texture(1)]],
    constant ShaderUniforms &uniforms [[buffer(0)]],
    device float4 *referenceOrbit [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();

    if (gid.x >= width || gid.y >= height) return;

    float invWidth = 1.0f / float(width);
    float invHeight = 1.0f / float(height);
    float2 uv = float2(float(gid.x) * invWidth, float(gid.y) * invHeight);
    float pixelSpan = uniforms.geometry.z * invHeight;

    FractalResult centerResult = evaluateFractal(float2(0.0f), uniforms, referenceOrbit, gid, width, height);
    float3 color = colorFractal(centerResult, uniforms, pixelSpan);

    // Adaptive supersampling: only pixels within a couple of pixels of the
    // set boundary carry sub-pixel filament detail that shimmers during the
    // zoom, so gate 4 extra rotated-grid samples on the distance estimate.
    // Everywhere else the smooth-iteration gradient is already band-free.
    int aaSamples = int(uniforms.quality.x);
    if (aaSamples >= 4 && centerResult.iteration < uniforms.geometry.w) {
        float dzm = max(sqrt(centerResult.dzx * centerResult.dzx + centerResult.dzy * centerResult.dzy), 1e-20f);
        float magc = max(centerResult.mag_sq, 1.000001f);
        float de = 0.5f * log(magc) * sqrt(magc) / dzm;
        if (de < 2.0f * pixelSpan) {
            const float2 offsets[4] = {
                float2( 0.125f,  0.375f),
                float2( 0.375f, -0.125f),
                float2(-0.125f, -0.375f),
                float2(-0.375f,  0.125f)
            };
            for (int k = 0; k < 4; k++) {
                FractalResult s = evaluateFractal(offsets[k], uniforms, referenceOrbit, gid, width, height);
                color += colorFractal(s, uniforms, pixelSpan);
            }
            color *= (1.0f / 5.0f);
        }
    }

    // Aspect-corrected vignette, gentle and quadratic (flat in the middle).
    float aspectRatio = uniforms.palette.y;
    float2 vd = (uv - 0.5f) * float2(aspectRatio, 1.0f);
    float vr = length(vd) / max(length(float2(aspectRatio, 1.0f) * 0.5f), 1e-6f);
    color *= 1.0f - 0.22f * vr * vr;

    // Soft-knee tonemap into the display's EDR headroom (1.0 on SDR panels).
    color = tonemapSoftKnee(color, max(uniforms.quality.z, 1.0f));

    // Freeze-dissolve between dives: blend toward the held (already
    // tonemapped, linear) previous-dive frame. Weight 0 outside transitions.
    float heldWeight = uniforms.mode.x;
    if (heldWeight > 0.0f) {
        float3 held = heldFrame.read(gid).rgb;
        color = mix(color, held, heldWeight);
    }

    // Colors are linear end-to-end; the drawable (rgba16Float linear, or
    // _srgb 8-bit on the fallback path) applies the display encoding.
    output.write(float4(max(color, 0.0f), 1.0f), gid);
}
