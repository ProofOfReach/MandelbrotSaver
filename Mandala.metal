#include <metal_stdlib>
using namespace metal;

constant float PI = 3.14159265358979323846f;
constant int PALETTE_SIZE = 12;

// Authored as sRGB display values, then decoded to linear light before any
// glow, blending, or tonemapping. Each palette is cyclic so motion never hits
// a visible color seam.
constant float3 palette_orchid[PALETTE_SIZE] = {
    float3(0.010, 0.003, 0.030), float3(0.070, 0.010, 0.180),
    float3(0.210, 0.020, 0.430), float3(0.520, 0.030, 0.690),
    float3(0.930, 0.080, 0.700), float3(1.000, 0.260, 0.430),
    float3(1.000, 0.650, 0.160), float3(1.000, 0.930, 0.620),
    float3(0.250, 0.970, 1.000), float3(0.020, 0.540, 0.900),
    float3(0.100, 0.120, 0.500), float3(0.030, 0.010, 0.100),
};

constant float3 palette_lotus[PALETTE_SIZE] = {
    float3(0.002, 0.010, 0.025), float3(0.000, 0.170, 0.260),
    float3(0.000, 0.620, 0.700), float3(0.100, 1.000, 0.850),
    float3(0.620, 1.000, 0.120), float3(0.980, 0.950, 0.120),
    float3(1.000, 0.320, 0.180), float3(1.000, 0.050, 0.560),
    float3(0.690, 0.080, 1.000), float3(0.190, 0.080, 0.720),
    float3(0.000, 0.260, 0.560), float3(0.002, 0.025, 0.070),
};

constant float3 palette_solar[PALETTE_SIZE] = {
    float3(0.014, 0.003, 0.003), float3(0.105, 0.012, 0.004),
    float3(0.360, 0.036, 0.006), float3(0.850, 0.140, 0.010),
    float3(1.000, 0.390, 0.025), float3(1.000, 0.720, 0.100),
    float3(1.000, 0.960, 0.540), float3(1.000, 0.480, 0.440),
    float3(0.920, 0.080, 0.420), float3(0.450, 0.020, 0.280),
    float3(0.180, 0.008, 0.120), float3(0.038, 0.004, 0.026),
};

constant float3 palette_abyss[PALETTE_SIZE] = {
    float3(0.000, 0.008, 0.020), float3(0.000, 0.035, 0.090),
    float3(0.000, 0.130, 0.230), float3(0.000, 0.360, 0.490),
    float3(0.000, 0.760, 0.760), float3(0.200, 1.000, 0.900),
    float3(0.780, 1.000, 0.970), float3(0.280, 0.760, 1.000),
    float3(0.050, 0.340, 0.850), float3(0.050, 0.110, 0.480),
    float3(0.020, 0.035, 0.220), float3(0.000, 0.012, 0.055),
};

constant float3 palette_woven[PALETTE_SIZE] = {
    float3(0.012, 0.007, 0.004), float3(0.170, 0.035, 0.018),
    float3(0.540, 0.100, 0.030), float3(0.910, 0.310, 0.060),
    float3(0.960, 0.780, 0.380), float3(0.880, 0.920, 0.680),
    float3(0.080, 0.770, 0.570), float3(0.020, 0.400, 0.390),
    float3(0.080, 0.240, 0.570), float3(0.470, 0.050, 0.480),
    float3(0.800, 0.100, 0.290), float3(0.120, 0.025, 0.020),
};

constant float3 palette_pearl[PALETTE_SIZE] = {
    float3(0.002, 0.004, 0.008), float3(0.018, 0.026, 0.044),
    float3(0.060, 0.080, 0.120), float3(0.160, 0.200, 0.260),
    float3(0.340, 0.390, 0.470), float3(0.620, 0.650, 0.720),
    float3(0.940, 0.920, 0.850), float3(0.720, 0.880, 0.920),
    float3(0.390, 0.570, 0.700), float3(0.180, 0.280, 0.410),
    float3(0.060, 0.090, 0.160), float3(0.012, 0.020, 0.045),
};

struct MandalaUniforms {
    float4 viewport; // globalTime, sceneTime, sceneProgress, aspectRatio
    float4 scene;    // seed, symmetry, motif, rotationDirection
    float4 motion;   // flowSpeed, intensity, twist, tunnelRate
    float4 palette;  // paletteIndex, paletteMix, colorPhase, EDR headroom
    float4 quality;  // sampleCount, heldWeight, breathRate, exposure
};

float3 srgbToLinear(float3 c) {
    float3 low = c / 12.92f;
    float3 high = pow((c + 0.055f) / 1.055f, float3(2.4f));
    return select(high, low, c <= 0.04045f);
}

float3 paletteControlPoint(int paletteIndex, int index) {
    index = (index % PALETTE_SIZE + PALETTE_SIZE) % PALETTE_SIZE;
    switch (paletteIndex) {
        case 0: return palette_orchid[index];
        case 1: return palette_lotus[index];
        case 2: return palette_solar[index];
        case 3: return palette_abyss[index];
        case 4: return palette_woven[index];
        case 5: return palette_pearl[index];
        default: return palette_orchid[index];
    }
}

float3 samplePalette(int paletteIndex, float t) {
    float x = fract(t) * float(PALETTE_SIZE);
    int i1 = int(floor(x));
    float f = x - floor(x);
    float3 p0 = paletteControlPoint(paletteIndex, i1 - 1);
    float3 p1 = paletteControlPoint(paletteIndex, i1);
    float3 p2 = paletteControlPoint(paletteIndex, i1 + 1);
    float3 p3 = paletteControlPoint(paletteIndex, i1 + 2);
    float3 b = p2 - p0;
    float3 c = 2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3;
    float3 d = -p0 + 3.0f * (p1 - p2) + p3;
    return clamp(p1 + 0.5f * f * (b + f * (c + f * d)), 0.0f, 1.0f);
}

float3 getColor(float t, constant MandalaUniforms &uniforms) {
    int index = int(uniforms.palette.x);
    int nextIndex = (index + 1) % 6;
    float3 a = srgbToLinear(samplePalette(index, t));
    float3 b = srgbToLinear(samplePalette(nextIndex, t));
    return mix(a, b, uniforms.palette.y);
}

float3 tonemapSoftKnee(float3 color, float peak) {
    peak = max(peak, 1.0f);
    float knee = peak * 0.72f;
    float width = max(peak - knee, 0.001f);
    float3 over = max(color - knee, 0.0f);
    float3 soft = knee + width * (1.0f - exp(-over / width));
    return select(soft, color, color <= knee);
}

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

float foldAngle(float angle, float symmetry) {
    float sector = 2.0f * PI / symmetry;
    return abs(fract((angle + 0.5f * sector) / sector) * sector - 0.5f * sector);
}

float lineMask(float distance, float thickness, float antialias) {
    return 1.0f - smoothstep(thickness, thickness + max(antialias, 0.00001f), abs(distance));
}

float broadGlow(float distance, float radius) {
    float x = abs(distance) / max(radius, 0.00001f);
    return 1.0f / (1.0f + x * x);
}

float3 renderMandala(float2 p, constant MandalaUniforms &uniforms, float pixelWidth) {
    float globalTime = uniforms.viewport.x;
    float sceneTime = uniforms.viewport.y;
    float sceneProgress = uniforms.viewport.z;
    float seed = uniforms.scene.x;
    float symmetry = uniforms.scene.y;
    int motif = int(uniforms.scene.z);
    float direction = uniforms.scene.w;
    float flowSpeed = uniforms.motion.x;
    float intensity = uniforms.motion.y;
    float twist = uniforms.motion.z;
    float tunnelRate = uniforms.motion.w;
    float colorPhase = uniforms.palette.z;
    float breathRate = uniforms.quality.z;
    int paletteIndex = int(uniforms.palette.x);
    int nextPaletteIndex = (paletteIndex + 1) % 6;
    float pearlAccent = mix(
        paletteIndex == 5 ? 1.12f : 1.0f,
        nextPaletteIndex == 5 ? 1.12f : 1.0f,
        uniforms.palette.y
    );

    float t = globalTime * flowSpeed;
    float breathWave = sin(sceneTime * 0.48f * breathRate + seed * 0.017f);
    float slowBreathWave = sin(sceneTime * 0.108f + seed * 0.005f);
    float breath = 0.5f + 0.5f * breathWave;
    p /= 1.0f
        + breathWave * (0.018f + 0.020f * intensity)
        + slowBreathWave * 0.010f;

    float r = length(p);
    float angle = atan2(p.y, p.x);
    float depth = -log2(max(r, 0.006f));
    float radialAA = min(pixelWidth / max(r, 0.025f), 0.18f);

    // Two counter-rotating angular fields make the image feel assembled from
    // independently moving rings rather than a single spinning kaleidoscope.
    float vortex = twist * (
        0.115f * sin(depth * 1.72f - t * 0.34f * tunnelRate + seed * 0.031f)
        + 0.032f * sin(r * 12.0f + t * 0.22f + seed * 0.007f)
    );
    float angleA = angle + direction * t * 0.035f + vortex;
    float angleB = angle - direction * t * 0.023f - vortex * 0.72f;

    float petalWeight = 1.0f;
    float templeWeight = 0.72f;
    float weaveWeight = 0.72f;
    float eyeWeight = 0.15f;
    if (motif == 0) {
        petalWeight = 1.25f; templeWeight = 0.55f; weaveWeight = 0.42f; eyeWeight = 0.08f;
    } else if (motif == 1) {
        petalWeight = 0.72f; templeWeight = 1.28f; weaveWeight = 0.68f; eyeWeight = 0.10f;
    } else if (motif == 2) {
        petalWeight = 0.70f; templeWeight = 0.76f; weaveWeight = 1.35f; eyeWeight = 0.12f;
    } else if (motif == 3) {
        petalWeight = 0.82f; templeWeight = 0.82f; weaveWeight = 0.86f; eyeWeight = 1.25f;
    }

    float tunnelPhase = depth * 1.32f - t * 0.24f * tunnelRate + seed * 0.009f;
    float3 color = getColor(0.06f * depth + seed * 0.001f, uniforms) * 0.004f;

    // Faceted chamber walls establish the 2.5D temple before the brighter
    // linework is layered over it. Depth cells advance toward the viewer,
    // while alternating sectors light from opposite sides.
    float chamberCell = fract(tunnelPhase);
    float chamberIndex = floor(tunnelPhase);
    float chamberFold = foldAngle(angleB, symmetry) / (PI / symmetry);
    float facetLight = 0.25f + 0.75f * pow(max(cos(chamberFold * PI * 0.5f), 0.0f), 1.7f);
    float chamberBody = smoothstep(0.06f, 0.20f, chamberCell)
        * (1.0f - smoothstep(0.68f, 0.96f, chamberCell));
    float chamberPulse = 0.30f + 0.70f * pow(1.0f - chamberCell, 2.0f);
    float chamberGate = smoothstep(0.055f, 0.14f, r)
        * (1.0f - smoothstep(1.25f, 1.92f, r));
    float alternatingFacet = 0.55f + 0.45f * sin(
        symmetry * angleB + chamberIndex * PI + seed * 0.13f
    );
    float3 chamberColor = getColor(
        colorPhase + chamberIndex * 0.087f + chamberFold * 0.08f,
        uniforms
    );
    float chamberHierarchy = mix(
        1.04f,
        0.78f,
        smoothstep(0.72f, 1.70f, r)
    );
    color += chamberColor * templeWeight * chamberGate * chamberBody
        * chamberPulse * (0.030f + 0.085f * facetLight)
        * (0.72f + 0.28f * alternatingFacet) * chamberHierarchy;
    color *= 1.0f - chamberGate * (1.0f - chamberBody)
        * min(templeWeight, 1.2f) * 0.055f;

    // Five breathing, offset petal rings. Their opposing phase offsets keep
    // intersections alive instead of stacking into one repetitive rosette.
    for (int i = 0; i < 5; ++i) {
        float fi = float(i);
        float ringDrift = sin(sceneTime * 0.155f + fi * 1.73f + seed * 0.021f);
        float baseRadius = 0.155f + fi * 0.170f
            + 0.008f * breathWave * (1.0f + fi * 0.16f)
            + 0.0065f * ringDrift;
        float lobeAmplitude = 0.027f + fi * 0.010f;
        float parityDirection = (i & 1) == 0 ? 1.0f : -1.0f;
        float ringParallax = parityDirection * direction * t
            * (2.0f - fi) * 0.0038f;
        float ringAngle = ((i & 1) == 0 ? angleA : angleB) + ringParallax;
        float lobe = cos(symmetry * ringAngle + fi * 1.31f + seed * 0.011f);
        float targetRadius = baseRadius + lobeAmplitude * lobe;
        float distance = r - targetRadius;
        float core = lineMask(distance, 0.0028f + fi * 0.00035f, pixelWidth * 1.45f);
        float glow = broadGlow(distance, 0.0135f + 0.0025f * intensity);
        float paletteT = colorPhase + fi * 0.145f + lobe * 0.075f + t * 0.010f;
        float3 ringColor = getColor(paletteT, uniforms);
        float3 inlayColor = getColor(paletteT + 0.19f, uniforms);
        float hierarchy = 1.12f - fi * 0.115f;
        float ribbon = 1.0f - smoothstep(0.0f, 0.032f + 0.004f * intensity, abs(distance));
        color += ringColor * petalWeight * hierarchy
            * (core * (0.72f + 0.22f * intensity) * pearlAccent
                + ribbon * 0.055f + glow * 0.014f);

        // Twin hairline inlays turn every accepted petal contour into a
        // precise luminous ribbon. They reuse the original geometry rather
        // than adding a second visual vocabulary over it.
        float inlayOffset = 0.0080f + fi * 0.0008f;
        float inlayDistance = abs(distance) - inlayOffset;
        float inlay = lineMask(inlayDistance, 0.0011f, pixelWidth * 1.20f);
        float inlayGate = smoothstep(0.105f, 0.19f, r)
            * (1.0f - smoothstep(0.94f, 1.42f, r));
        color += inlayColor * petalWeight * hierarchy * inlay * inlayGate
            * (0.16f + 0.055f * intensity);

        // Small round jewels sit only at the radial crown of alternating
        // rings. The sparse cadence adds intricacy without becoming a field
        // of repeated glyphs.
        float crownRadial = r - (baseRadius + lobeAmplitude);
        float crownArc = 2.0f * r * abs(sin(
            0.5f * (symmetry * ringAngle + fi * 1.31f + seed * 0.011f)
        )) / symmetry;
        float jewelRadius = 0.0048f + fi * 0.00025f;
        float jewelMetric = length(float2(crownRadial, crownArc));
        float jewelDistance = jewelMetric - jewelRadius;
        float jewelRim = lineMask(jewelDistance, 0.0010f, pixelWidth * 1.35f);
        float jewelCore = 1.0f - smoothstep(
            jewelRadius * 0.20f,
            jewelRadius * 0.72f + pixelWidth,
            jewelMetric
        );
        float jewelCadence = (i == 1 || i == 3) ? 1.0f : 0.0f;
        color += (inlayColor * jewelRim * 0.72f
            + float3(0.92f, 0.96f, 1.0f) * jewelCore * 0.55f)
            * petalWeight * jewelCadence * inlayGate;
    }

    // A log-polar depth grid moves continuously into the central portal. The
    // antialias width expands toward the singularity to prevent center fizz.
    float ringWave = sin(tunnelPhase * PI);
    float tunnelCore = lineMask(ringWave, 0.0f, 0.050f + radialAA * 2.2f);
    float tunnelGlow = broadGlow(ringWave, 0.24f);
    float3 tunnelColor = getColor(colorPhase + depth * 0.105f - t * 0.009f, uniforms);
    color += tunnelColor * templeWeight * (tunnelCore * 0.54f + tunnelGlow * 0.025f);

    float folded = foldAngle(angleB + 0.035f * sin(depth * 2.0f - t * 0.3f), symmetry);
    float spokeDistance = abs(sin(folded)) * r;
    float spokeCore = lineMask(spokeDistance, 0.0022f, pixelWidth * 1.5f);
    float spokeGlow = broadGlow(spokeDistance, 0.020f);
    float spokeHierarchy = mix(1.03f, 0.82f, smoothstep(0.62f, 1.58f, r));
    color += getColor(colorPhase + 0.56f + depth * 0.035f, uniforms)
        * templeWeight * spokeHierarchy * (spokeCore * 0.54f + spokeGlow * 0.015f);

    // Crossing spiral families become woven circuitry in log-polar space.
    float weaveA = abs(sin(symmetry * angleA + depth * 4.75f + seed * 0.023f));
    float weaveB = abs(sin(symmetry * angleB - depth * 4.10f - seed * 0.019f));
    float weaveDistance = min(weaveA, weaveB);
    float weaveCore = 1.0f - smoothstep(0.045f, 0.075f + radialAA * 1.3f, weaveDistance);
    float weaveGate = smoothstep(0.085f, 0.17f, r) * (1.0f - smoothstep(1.30f, 1.85f, r));
    weaveGate *= 0.42f + 0.58f * smoothstep(0.10f, 0.52f, abs(sin(tunnelPhase * PI)));
    weaveGate *= mix(1.02f, 0.78f, smoothstep(0.78f, 1.65f, r));
    float crossing = (1.0f - smoothstep(0.10f, 0.28f, weaveA))
        * (1.0f - smoothstep(0.10f, 0.28f, weaveB));
    float3 weaveColor = getColor(
        colorPhase + 0.30f + depth * 0.082f + t * 0.007f,
        uniforms
    );
    color += weaveColor
        * weaveWeight * weaveGate * (weaveCore * 0.39f + crossing * 0.12f);

    // Mirrored ellipses inside each folded wedge create fleeting eyes and
    // masks. They are explicit in Oracle scenes and merely pareidolic hints
    // elsewhere.
    float localAngle = foldAngle(angleA + direction * 0.08f * sin(sceneTime * 0.16f), symmetry);
    float2 wedge = r * float2(cos(localAngle), sin(localAngle));
    float eyeRadius = 0.50f + 0.018f * breathWave;
    float2 eyeCenter = float2(eyeRadius, 0.060f + 0.008f * sin(t * 0.31f + seed));
    float2 eyeQ = (wedge - eyeCenter) / float2(0.112f, 0.038f);
    float eyeDistance = length(eyeQ) - 1.0f;
    float eyeOutline = lineMask(eyeDistance, 0.065f, pixelWidth * 32.0f);
    float eyeInterior = 1.0f - smoothstep(0.78f, 0.98f, length(eyeQ));
    float2 irisQ = (wedge - eyeCenter) / float2(0.031f, 0.031f);
    float irisDistance = length(irisQ) - 1.0f;
    float iris = lineMask(irisDistance, 0.12f, pixelWidth * 28.0f);
    float pupil = 1.0f - smoothstep(0.28f, 0.48f, length(irisQ));
    float3 eyeColor = getColor(colorPhase + 0.82f + breath * 0.08f, uniforms);
    color *= 1.0f - eyeInterior * min(eyeWeight, 1.0f) * 0.72f;
    color += eyeColor * eyeWeight
        * (eyeInterior * 0.13f + eyeOutline * 0.88f + iris * 0.72f);
    float irisFill = 1.0f - smoothstep(0.55f, 0.88f, length(irisQ));
    color += getColor(colorPhase + 0.48f, uniforms) * irisFill
        * min(eyeWeight, 1.0f) * 0.34f;
    color *= 1.0f - pupil * min(eyeWeight, 1.0f) * 0.52f;
    float glint = 1.0f - smoothstep(
        0.08f,
        0.22f,
        length(irisQ - float2(-0.22f, 0.24f))
    );
    color += float3(1.0f, 0.95f, 0.86f) * glint * min(eyeWeight, 1.0f) * 0.62f;

    // Architectural facets flash between tunnel rings, implying a recursive
    // temple without paying the cost of full raymarching.
    float panelA = sin(tunnelPhase * 2.0f + folded * symmetry * 1.5f);
    float panelB = sin(tunnelPhase * 2.0f - folded * symmetry * 1.5f);
    float panel = smoothstep(0.56f, 0.92f, abs(panelA * panelB));
    float panelPulse = 0.5f + 0.5f * sin(depth * 3.0f - t * 0.38f + seed);
    color += getColor(colorPhase + 0.68f - depth * 0.055f, uniforms)
        * templeWeight * panel * panelPulse * 0.042f;

    // Sparse, stationary dust makes the surrounding black feel like a void,
    // while radial gating prevents it from dirtying the mandala itself.
    float2 starCell = floor((p + seed * 0.001f) * 94.0f);
    float star = pow(hash21(starCell + seed), 42.0f);
    float starGate = smoothstep(0.75f, 1.30f, r);
    color += getColor(colorPhase + 0.90f, uniforms) * star * starGate * 0.40f;

    // The dark center and hot rim establish a readable portal at every phase.
    float portalRadius = 0.074f + 0.011f * breathWave;
    float portalDistance = r - portalRadius;
    float portalCore = lineMask(portalDistance, 0.0030f, pixelWidth * 1.7f);
    float portalGlow = broadGlow(portalDistance, 0.020f);
    float voidMask = 1.0f - smoothstep(portalRadius * 0.50f, portalRadius * 0.98f, r);
    color *= 1.0f - voidMask * 0.985f;
    color += getColor(colorPhase + 0.74f + breath * 0.05f, uniforms)
        * (portalCore * (1.12f + 0.28f * intensity) * pearlAccent
            + portalGlow * 0.050f);

    // A nested iris gives the portal a second depth plane while preserving a
    // genuinely dark central void.
    float irisPulse = sin(sceneTime * 0.29f + seed * 0.013f);
    float innerRadiusA = portalRadius * (0.66f + 0.020f * irisPulse);
    float innerRingA = lineMask(r - innerRadiusA, 0.0018f, pixelWidth * 1.55f);
    float innerGlowA = broadGlow(r - innerRadiusA, 0.006f);
    float3 irisColorA = getColor(colorPhase + 0.93f - t * 0.010f, uniforms);
    color += irisColorA * (innerRingA * 0.48f + innerGlowA * 0.010f);

    float outerFade = 1.0f - smoothstep(1.48f, 2.08f, r);
    float vignette = 1.0f - 0.20f * smoothstep(0.70f, 1.90f, r);
    color *= outerFade * vignette;

    // Ease the first and last few percent of a scene so structural motion
    // settles under the texture dissolve instead of appearing to jump.
    float sceneEase = smoothstep(0.0f, 0.055f, sceneProgress)
        * (1.0f - 0.10f * smoothstep(0.94f, 1.0f, sceneProgress));
    color *= mix(0.78f, 1.0f, sceneEase);
    color *= uniforms.quality.w * (0.78f + 0.32f * intensity);

    // Restore a little chroma lost when many translucent linear-light layers
    // overlap, while leaving Pearl Void almost neutral by design.
    float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    float saturation = mix(
        paletteIndex == 5 ? 1.02f : 1.085f,
        nextPaletteIndex == 5 ? 1.02f : 1.085f,
        uniforms.palette.y
    );
    color = max(mix(float3(luma), color, saturation), 0.0f);

    return tonemapSoftKnee(max(color, 0.0f), uniforms.palette.w);
}

kernel void mandalaKernel(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::read> heldFrame [[texture(1)]],
    constant MandalaUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float2 size = float2(float(width), float(height));
    float pixelWidth = 2.0f / max(float(height), 1.0f);
    int sampleCount = int(uniforms.quality.x);
    float3 color = float3(0.0f);

    if (sampleCount >= 4) {
        constexpr float2 offsets[4] = {
            float2(-0.30f, -0.10f), float2(0.10f, -0.30f),
            float2(0.30f, 0.10f), float2(-0.10f, 0.30f),
        };
        for (int i = 0; i < 4; ++i) {
            float2 samplePosition = float2(gid) + 0.5f + offsets[i];
            float2 p = (samplePosition * 2.0f - size) / max(float(height), 1.0f);
            color += renderMandala(p, uniforms, pixelWidth);
        }
        color *= 0.25f;
    } else {
        float2 samplePosition = float2(gid) + 0.5f;
        float2 p = (samplePosition * 2.0f - size) / max(float(height), 1.0f);
        color = renderMandala(p, uniforms, pixelWidth);
    }

    float heldWeight = uniforms.quality.y;
    if (heldWeight > 0.0001f) {
        color = mix(color, heldFrame.read(gid).rgb, heldWeight);
    }

    output.write(float4(color, 1.0f), gid);
}
