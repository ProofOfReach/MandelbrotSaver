#include <metal_stdlib>
using namespace metal;

// ============================================================================
// COLOR PALETTES - Inspired by classic fractal art
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

float3 samplePalette(constant float3* palette, float t) {
    t = fract(t) * 15.0;
    int idx = int(t);
    float f = t - float(idx);
    // Smooth interpolation
    f = f * f * (3.0 - 2.0 * f);
    return mix(palette[idx], palette[(idx + 1) % 16], f);
}

// Sample curated palette by index.
float3 samplePaletteByIndex(int paletteIndex, float t) {
    switch(paletteIndex) {
        case 0:  return samplePalette(palette_ultra, t);
        case 1:  return samplePalette(palette_fire, t);
        case 2:  return samplePalette(palette_ocean, t);
        case 3:  return samplePalette(palette_electric, t);
        case 4:  return samplePalette(palette_aurora, t);
        case 5:  return samplePalette(palette_monochrome, t);
        default: return samplePalette(palette_ultra, t);
    }
}

float3 getPaletteColor(float t, int paletteIndex, float paletteMix) {
    int totalPalettes = 6;
    int nextPalette = (paletteIndex + 1) % totalPalettes;

    // Sample current and next palettes
    float3 c1 = samplePaletteByIndex(paletteIndex, t);
    float3 c2 = samplePaletteByIndex(nextPalette, t);

    return mix(c1, c2, paletteMix);
}

// ============================================================================
// MAIN KERNEL
// ============================================================================

constant bool usePerturbation [[function_constant(0)]];

struct ShaderUniforms {
    float4 geometry; // centerX_hi, centerY_hi, scale, maxIterations
    float4 palette;  // colorOffset, aspectRatio, paletteIndex, paletteMix
    float4 view;     // centerX_lo, centerY_lo, shadingMode, time
    float4 mode;     // opacity, juliaMode, juliaCx, juliaCy
    float4 quality;  // aaSamples, lightingQuality, reserved, reserved
};

struct FractalResult {
    float iteration;
    float dzx;
    float dzy;
    float final_zx;
    float final_zy;
    float mag_sq;
};

// Complex math helpers for float2
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

    FractalResult result;
    result.iteration = 0.0f;
    result.dzx = 0.0f;
    result.dzy = 0.0f;
    result.final_zx = 0.0f;
    result.final_zy = 0.0f;
    result.mag_sq = 0.0f;

    if (usePerturbation) {
        float2 dc = float2(px, py);
        float2 dz = float2(0.0f, 0.0f);

        if (juliaMode) {
            dz = float2(px, py);
            dc = float2(0.0f, 0.0f);
        }

        float2 z_saved = float2(0.0f);
        int period = 20;
        int period_counter = 0;

        for (int i = 0; i < int(maxIterations); i++) {
            float4 ref = referenceOrbit[i];
            float2 Z = ref.xy;
            float2 correction = ref.zw;

            float2 z = Z + dz;
            float mag_sq = dot(z, z);
            if (mag_sq > 4.0f) {
                result.final_zx = z.x;
                result.final_zy = z.y;
                result.mag_sq = mag_sq;
                break;
            }

            float2 diff = z - z_saved;
            if (dot(diff, diff) < 1e-12f) {
                result.iteration = maxIterations;
                result.final_zx = z.x;
                result.final_zy = z.y;
                result.mag_sq = mag_sq;
                break;
            }

            period_counter++;
            if (period_counter >= period) {
                z_saved = z;
                period_counter = 0;
                period *= 2;
                if (period > 200) period = 200;
            }

            float2 term1 = cmul(2.0f * Z, dz);
            float2 term2 = csqr(dz);
            dz = term1 + term2 + dc + correction;

            float new_dzx = 2.0f * (z.x * result.dzx - z.y * result.dzy) + 1.0f;
            float new_dzy = 2.0f * (z.x * result.dzy + z.y * result.dzx);
            result.dzx = new_dzx;
            result.dzy = new_dzy;

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
        } else {
            while (result.iteration < maxIterations) {
                float zx_sq = zx * zx;
                float zy_sq = zy * zy;

                float mag_sq = zx_sq + zy_sq;
                if (mag_sq > 4.0f) {
                    result.final_zx = zx;
                    result.final_zy = zy;
                    result.mag_sq = mag_sq;
                    break;
                }

                float new_dzx = 2.0f * (zx * result.dzx - zy * result.dzy) + 1.0f;
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

float3 colorFractal(FractalResult result, constant ShaderUniforms &uniforms, float2 uv) {
    float maxIterations = uniforms.geometry.w;
    float colorOffset = uniforms.palette.x;
    int paletteIndex = int(uniforms.palette.z);
    float paletteMix = uniforms.palette.w;
    int shadingMode = int(uniforms.view.z);
    float time = uniforms.view.w;
    float lightingQuality = uniforms.quality.y;

    if (result.iteration >= maxIterations) {
        return float3(0.0f);
    }

    float mag_sq = max(result.mag_sq, 1.000001f);
    float log_zn = 0.5f * log(mag_sq);
    float nu = log2(max(log_zn * 1.44269504089f, 1e-6f));
    float smoothIter = result.iteration + 1.0f - nu;

    float t = (smoothIter + colorOffset) * 0.02f;
    float3 color = getPaletteColor(t, paletteIndex, paletteMix);

    if (shadingMode == 1) {
        float dz_mag = sqrt(result.dzx * result.dzx + result.dzy * result.dzy);
        if (dz_mag < 1e-20f) dz_mag = 1e-20f;
        float logMagSq = log(mag_sq);
        float fz_mag = sqrt(mag_sq);
        float dist = 0.5f * logMagSq * fz_mag / dz_mag;

        float3 N = normalize(float3(result.dzx, result.dzy, dist * 100.0f));
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

    float vignette = 1.0f - 0.3f * length(uv - 0.5f);
    return color * vignette;
}

kernel void mandelbrotKernel(
    texture2d<float, access::write> output [[texture(0)]],
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
    int aaSamples = int(uniforms.quality.x);
    float3 color;

    if (aaSamples >= 4) {
        float2 offsets[4] = {
            float2(-0.25f, -0.25f),
            float2( 0.25f, -0.25f),
            float2(-0.25f,  0.25f),
            float2( 0.25f,  0.25f)
        };
        color = float3(0.0f);
        for (int i = 0; i < 4; i++) {
            FractalResult result = evaluateFractal(offsets[i], uniforms, referenceOrbit, gid, width, height);
            color += colorFractal(result, uniforms, uv);
        }
        color *= 0.25f;
    } else {
        FractalResult result = evaluateFractal(float2(0.0f), uniforms, referenceOrbit, gid, width, height);
        color = colorFractal(result, uniforms, uv);
    }

    color = pow(color, float3(0.9f));
    color *= uniforms.mode.x;

    output.write(float4(color, 1.0f), gid);
}
