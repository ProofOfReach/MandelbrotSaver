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

// Fire palette - warm and intense
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

// Ocean palette - cool and deep
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

// Electric palette - neon cyberpunk
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

// Sunset palette - warm gradients
constant float3 palette_sunset[16] = {
    float3(0.05, 0.00, 0.10),
    float3(0.10, 0.00, 0.20),
    float3(0.20, 0.00, 0.35),
    float3(0.35, 0.00, 0.45),
    float3(0.50, 0.05, 0.50),
    float3(0.65, 0.10, 0.45),
    float3(0.80, 0.20, 0.35),
    float3(0.90, 0.35, 0.25),
    float3(1.00, 0.50, 0.15),
    float3(1.00, 0.65, 0.10),
    float3(1.00, 0.80, 0.20),
    float3(1.00, 0.90, 0.40),
    float3(1.00, 0.95, 0.60),
    float3(0.95, 0.85, 0.70),
    float3(0.80, 0.60, 0.60),
    float3(0.50, 0.30, 0.40)
};

// Glacial palette - icy blues and whites
constant float3 palette_glacial[16] = {
    float3(0.00, 0.00, 0.05),
    float3(0.00, 0.05, 0.15),
    float3(0.05, 0.15, 0.30),
    float3(0.10, 0.25, 0.45),
    float3(0.15, 0.40, 0.60),
    float3(0.25, 0.55, 0.75),
    float3(0.40, 0.70, 0.85),
    float3(0.55, 0.80, 0.92),
    float3(0.70, 0.88, 0.96),
    float3(0.85, 0.94, 0.98),
    float3(0.95, 0.98, 1.00),
    float3(1.00, 1.00, 1.00),
    float3(0.90, 0.95, 1.00),
    float3(0.75, 0.85, 0.95),
    float3(0.55, 0.70, 0.85),
    float3(0.30, 0.50, 0.70)
};

// ============================================================================
// ADDITIONAL PALETTES (18 more to reach 24 total)
// Indices 6-23 in Swift's paletteNames array
// ============================================================================

// Rainbow palette - full spectrum ROYGBIV (index 6)
constant float3 palette_rainbow[16] = {
    float3(1.00, 0.00, 0.00),
    float3(1.00, 0.25, 0.00),
    float3(1.00, 0.50, 0.00),
    float3(1.00, 0.75, 0.00),
    float3(1.00, 1.00, 0.00),
    float3(0.50, 1.00, 0.00),
    float3(0.00, 1.00, 0.00),
    float3(0.00, 1.00, 0.50),
    float3(0.00, 1.00, 1.00),
    float3(0.00, 0.50, 1.00),
    float3(0.00, 0.00, 1.00),
    float3(0.25, 0.00, 1.00),
    float3(0.50, 0.00, 1.00),
    float3(0.75, 0.00, 1.00),
    float3(1.00, 0.00, 0.75),
    float3(1.00, 0.00, 0.50)
};

// Plasma palette - hot energy waves (index 7)
constant float3 palette_plasma[16] = {
    float3(0.05, 0.00, 0.20),
    float3(0.15, 0.00, 0.40),
    float3(0.30, 0.00, 0.60),
    float3(0.50, 0.00, 0.70),
    float3(0.70, 0.00, 0.75),
    float3(0.85, 0.00, 0.70),
    float3(0.95, 0.20, 0.55),
    float3(1.00, 0.40, 0.40),
    float3(1.00, 0.55, 0.25),
    float3(1.00, 0.70, 0.15),
    float3(1.00, 0.85, 0.10),
    float3(1.00, 0.95, 0.20),
    float3(0.95, 0.95, 0.40),
    float3(0.80, 0.80, 0.60),
    float3(0.50, 0.50, 0.50),
    float3(0.20, 0.20, 0.30)
};

// Lava palette - molten rock (index 8)
constant float3 palette_lava[16] = {
    float3(0.00, 0.00, 0.00),
    float3(0.10, 0.00, 0.00),
    float3(0.20, 0.00, 0.00),
    float3(0.35, 0.00, 0.00),
    float3(0.50, 0.05, 0.00),
    float3(0.65, 0.10, 0.00),
    float3(0.80, 0.20, 0.00),
    float3(0.90, 0.30, 0.00),
    float3(1.00, 0.45, 0.00),
    float3(1.00, 0.60, 0.00),
    float3(1.00, 0.75, 0.10),
    float3(1.00, 0.85, 0.30),
    float3(1.00, 0.50, 0.20),
    float3(0.80, 0.30, 0.10),
    float3(0.50, 0.15, 0.05),
    float3(0.25, 0.05, 0.00)
};

// Forest palette - deep greens and earth tones (index 9)
constant float3 palette_forest[16] = {
    float3(0.00, 0.05, 0.00),
    float3(0.02, 0.10, 0.02),
    float3(0.05, 0.20, 0.05),
    float3(0.10, 0.30, 0.08),
    float3(0.15, 0.40, 0.10),
    float3(0.20, 0.50, 0.15),
    float3(0.30, 0.60, 0.20),
    float3(0.40, 0.70, 0.25),
    float3(0.50, 0.75, 0.30),
    float3(0.60, 0.80, 0.40),
    float3(0.70, 0.85, 0.50),
    float3(0.55, 0.45, 0.25),
    float3(0.45, 0.35, 0.20),
    float3(0.35, 0.25, 0.15),
    float3(0.25, 0.15, 0.10),
    float3(0.10, 0.08, 0.05)
};

// Midnight palette - deep blues and purples (index 10)
constant float3 palette_midnight[16] = {
    float3(0.00, 0.00, 0.02),
    float3(0.02, 0.00, 0.05),
    float3(0.05, 0.00, 0.10),
    float3(0.08, 0.02, 0.18),
    float3(0.10, 0.05, 0.25),
    float3(0.12, 0.08, 0.35),
    float3(0.15, 0.10, 0.45),
    float3(0.18, 0.15, 0.55),
    float3(0.20, 0.20, 0.65),
    float3(0.25, 0.25, 0.75),
    float3(0.30, 0.30, 0.85),
    float3(0.40, 0.40, 0.90),
    float3(0.50, 0.50, 0.95),
    float3(0.35, 0.30, 0.70),
    float3(0.20, 0.15, 0.45),
    float3(0.10, 0.05, 0.20)
};

// Aurora palette - northern lights (index 11)
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

// Copper palette - metallic warm tones (index 12)
constant float3 palette_copper[16] = {
    float3(0.10, 0.05, 0.02),
    float3(0.20, 0.10, 0.05),
    float3(0.35, 0.18, 0.08),
    float3(0.50, 0.28, 0.12),
    float3(0.65, 0.38, 0.18),
    float3(0.75, 0.48, 0.25),
    float3(0.85, 0.58, 0.35),
    float3(0.92, 0.68, 0.45),
    float3(0.95, 0.78, 0.55),
    float3(0.98, 0.85, 0.65),
    float3(1.00, 0.90, 0.75),
    float3(0.90, 0.75, 0.55),
    float3(0.75, 0.55, 0.35),
    float3(0.55, 0.35, 0.20),
    float3(0.35, 0.20, 0.10),
    float3(0.18, 0.10, 0.05)
};

// Emerald palette - rich greens (index 13)
constant float3 palette_emerald[16] = {
    float3(0.00, 0.08, 0.05),
    float3(0.00, 0.15, 0.10),
    float3(0.00, 0.25, 0.15),
    float3(0.00, 0.35, 0.22),
    float3(0.00, 0.45, 0.30),
    float3(0.05, 0.55, 0.38),
    float3(0.15, 0.65, 0.45),
    float3(0.25, 0.75, 0.55),
    float3(0.35, 0.85, 0.65),
    float3(0.50, 0.92, 0.75),
    float3(0.70, 0.95, 0.85),
    float3(0.85, 0.98, 0.92),
    float3(0.60, 0.90, 0.75),
    float3(0.35, 0.75, 0.55),
    float3(0.15, 0.55, 0.35),
    float3(0.05, 0.30, 0.18)
};

// Amethyst palette - purple crystal tones (index 14)
constant float3 palette_amethyst[16] = {
    float3(0.08, 0.00, 0.10),
    float3(0.15, 0.00, 0.20),
    float3(0.25, 0.05, 0.35),
    float3(0.35, 0.10, 0.50),
    float3(0.45, 0.15, 0.65),
    float3(0.55, 0.25, 0.75),
    float3(0.65, 0.35, 0.82),
    float3(0.75, 0.50, 0.88),
    float3(0.85, 0.65, 0.92),
    float3(0.92, 0.80, 0.95),
    float3(0.98, 0.92, 0.98),
    float3(0.88, 0.75, 0.92),
    float3(0.72, 0.55, 0.82),
    float3(0.55, 0.35, 0.68),
    float3(0.38, 0.18, 0.50),
    float3(0.20, 0.05, 0.30)
};

// Gold palette - precious metal warmth (index 15)
constant float3 palette_gold[16] = {
    float3(0.15, 0.10, 0.00),
    float3(0.30, 0.20, 0.00),
    float3(0.45, 0.32, 0.00),
    float3(0.60, 0.45, 0.00),
    float3(0.75, 0.58, 0.05),
    float3(0.85, 0.70, 0.15),
    float3(0.92, 0.80, 0.30),
    float3(0.97, 0.88, 0.45),
    float3(1.00, 0.93, 0.60),
    float3(1.00, 0.97, 0.75),
    float3(1.00, 1.00, 0.88),
    float3(0.98, 0.92, 0.65),
    float3(0.90, 0.78, 0.40),
    float3(0.75, 0.60, 0.20),
    float3(0.55, 0.40, 0.08),
    float3(0.35, 0.22, 0.00)
};

// Silver palette - cool metallic (index 16)
constant float3 palette_silver[16] = {
    float3(0.10, 0.10, 0.12),
    float3(0.20, 0.20, 0.22),
    float3(0.32, 0.32, 0.35),
    float3(0.45, 0.45, 0.48),
    float3(0.55, 0.55, 0.60),
    float3(0.65, 0.65, 0.70),
    float3(0.75, 0.75, 0.80),
    float3(0.82, 0.82, 0.87),
    float3(0.88, 0.88, 0.92),
    float3(0.93, 0.93, 0.96),
    float3(0.97, 0.97, 1.00),
    float3(0.92, 0.92, 0.95),
    float3(0.80, 0.80, 0.85),
    float3(0.65, 0.65, 0.72),
    float3(0.48, 0.48, 0.55),
    float3(0.30, 0.30, 0.35)
};

// Bronze palette - warm antique metal (index 17)
constant float3 palette_bronze[16] = {
    float3(0.12, 0.08, 0.05),
    float3(0.22, 0.15, 0.08),
    float3(0.35, 0.25, 0.12),
    float3(0.48, 0.35, 0.18),
    float3(0.58, 0.45, 0.25),
    float3(0.68, 0.52, 0.32),
    float3(0.76, 0.60, 0.40),
    float3(0.82, 0.68, 0.48),
    float3(0.88, 0.75, 0.55),
    float3(0.92, 0.82, 0.65),
    float3(0.95, 0.88, 0.75),
    float3(0.88, 0.78, 0.60),
    float3(0.75, 0.62, 0.45),
    float3(0.60, 0.45, 0.30),
    float3(0.42, 0.30, 0.18),
    float3(0.25, 0.18, 0.10)
};

// Neon palette - bright electric colors (index 18)
constant float3 palette_neon[16] = {
    float3(0.00, 0.00, 0.00),
    float3(1.00, 0.00, 0.40),
    float3(1.00, 0.00, 0.80),
    float3(0.80, 0.00, 1.00),
    float3(0.40, 0.00, 1.00),
    float3(0.00, 0.00, 1.00),
    float3(0.00, 0.40, 1.00),
    float3(0.00, 0.80, 1.00),
    float3(0.00, 1.00, 0.80),
    float3(0.00, 1.00, 0.40),
    float3(0.00, 1.00, 0.00),
    float3(0.40, 1.00, 0.00),
    float3(0.80, 1.00, 0.00),
    float3(1.00, 1.00, 0.00),
    float3(1.00, 0.60, 0.00),
    float3(1.00, 0.20, 0.00)
};

// Vapor palette - vaporwave aesthetic (index 19)
constant float3 palette_vapor[16] = {
    float3(0.05, 0.00, 0.10),
    float3(0.15, 0.00, 0.25),
    float3(0.30, 0.05, 0.45),
    float3(0.50, 0.10, 0.65),
    float3(0.70, 0.20, 0.80),
    float3(0.85, 0.35, 0.90),
    float3(0.95, 0.55, 0.95),
    float3(1.00, 0.75, 0.95),
    float3(0.95, 0.85, 0.98),
    float3(0.80, 0.90, 1.00),
    float3(0.55, 0.85, 1.00),
    float3(0.30, 0.75, 0.95),
    float3(0.15, 0.60, 0.85),
    float3(0.10, 0.45, 0.70),
    float3(0.08, 0.30, 0.50),
    float3(0.05, 0.15, 0.30)
};

// Thermal palette - heat map style (index 20)
constant float3 palette_thermal[16] = {
    float3(0.00, 0.00, 0.00),
    float3(0.05, 0.00, 0.20),
    float3(0.10, 0.00, 0.40),
    float3(0.15, 0.00, 0.60),
    float3(0.20, 0.00, 0.80),
    float3(0.30, 0.00, 0.70),
    float3(0.50, 0.00, 0.50),
    float3(0.70, 0.00, 0.30),
    float3(0.90, 0.10, 0.10),
    float3(1.00, 0.30, 0.00),
    float3(1.00, 0.50, 0.00),
    float3(1.00, 0.70, 0.00),
    float3(1.00, 0.85, 0.20),
    float3(1.00, 0.95, 0.50),
    float3(1.00, 1.00, 0.80),
    float3(1.00, 1.00, 1.00)
};

// Spectrum palette - scientific color mapping (index 21)
constant float3 palette_spectrum[16] = {
    float3(0.20, 0.00, 0.30),
    float3(0.30, 0.00, 0.50),
    float3(0.35, 0.00, 0.70),
    float3(0.30, 0.00, 0.90),
    float3(0.15, 0.20, 1.00),
    float3(0.00, 0.45, 0.95),
    float3(0.00, 0.65, 0.80),
    float3(0.00, 0.80, 0.55),
    float3(0.20, 0.90, 0.30),
    float3(0.50, 0.95, 0.15),
    float3(0.75, 0.95, 0.00),
    float3(0.95, 0.90, 0.00),
    float3(1.00, 0.70, 0.00),
    float3(1.00, 0.45, 0.00),
    float3(1.00, 0.20, 0.00),
    float3(0.85, 0.00, 0.00)
};

// Monochrome palette - grayscale with subtle blue (index 22)
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

// Candy palette - sweet pastel colors (index 23)
constant float3 palette_candy[16] = {
    float3(1.00, 0.85, 0.90),
    float3(1.00, 0.75, 0.80),
    float3(1.00, 0.65, 0.75),
    float3(1.00, 0.55, 0.70),
    float3(0.95, 0.55, 0.80),
    float3(0.85, 0.60, 0.90),
    float3(0.75, 0.70, 0.95),
    float3(0.70, 0.80, 1.00),
    float3(0.70, 0.90, 1.00),
    float3(0.75, 0.95, 0.95),
    float3(0.80, 1.00, 0.85),
    float3(0.85, 1.00, 0.75),
    float3(0.95, 1.00, 0.70),
    float3(1.00, 0.98, 0.70),
    float3(1.00, 0.92, 0.75),
    float3(1.00, 0.88, 0.82)
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

// Sample palette by index (24 palettes total)
float3 samplePaletteByIndex(int paletteIndex, float t) {
    switch(paletteIndex) {
        case 0:  return samplePalette(palette_ultra, t);
        case 1:  return samplePalette(palette_fire, t);
        case 2:  return samplePalette(palette_ocean, t);
        case 3:  return samplePalette(palette_electric, t);
        case 4:  return samplePalette(palette_sunset, t);
        case 5:  return samplePalette(palette_glacial, t);
        case 6:  return samplePalette(palette_rainbow, t);
        case 7:  return samplePalette(palette_plasma, t);
        case 8:  return samplePalette(palette_lava, t);
        case 9:  return samplePalette(palette_forest, t);
        case 10: return samplePalette(palette_midnight, t);
        case 11: return samplePalette(palette_aurora, t);
        case 12: return samplePalette(palette_copper, t);
        case 13: return samplePalette(palette_emerald, t);
        case 14: return samplePalette(palette_amethyst, t);
        case 15: return samplePalette(palette_gold, t);
        case 16: return samplePalette(palette_silver, t);
        case 17: return samplePalette(palette_bronze, t);
        case 18: return samplePalette(palette_neon, t);
        case 19: return samplePalette(palette_vapor, t);
        case 20: return samplePalette(palette_thermal, t);
        case 21: return samplePalette(palette_spectrum, t);
        case 22: return samplePalette(palette_monochrome, t);
        case 23: return samplePalette(palette_candy, t);
        default: return samplePalette(palette_ultra, t);
    }
}

float3 getPaletteColor(float t, int paletteIndex, float paletteMix) {
    // Total of 24 palettes
    int totalPalettes = 24;
    int nextPalette = (paletteIndex + 1) % totalPalettes;

    // Sample current and next palettes
    float3 c1 = samplePaletteByIndex(paletteIndex, t);
    float3 c2 = samplePaletteByIndex(nextPalette, t);

    return mix(c1, c2, paletteMix);
}

// Apply subtle P3 saturation boost for wide gamut displays
// This enhances colors slightly beyond sRGB when rendering to P3 colorspace
float3 applyP3Boost(float3 color) {
    // Compute luminance
    float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    // Boost saturation by 8% - subtle but visible on P3 displays
    float3 saturated = mix(float3(luma), color, 1.08f);
    return saturated;
}

// ============================================================================
// EXTENDED PRECISION FOR DEEP ZOOM (10^13+ capability)
// Uses Dekker/Knuth algorithms for error-free transformations with floats
// Represents a number as sum of two floats: hi + lo where |lo| <= ulp(hi)/2
// This achieves ~14 decimal digits of precision (vs ~7 for single float)
// ============================================================================

struct dd_real {
    float hi;
    float lo;
};

// Two-sum: error-free addition of two floats
// Returns sum in s, error in e such that a + b = s + e exactly
inline void two_sum(float a, float b, thread float &s, thread float &e) {
    s = a + b;
    float v = s - a;
    e = (a - (s - v)) + (b - v);
}

// Quick-two-sum: when |a| >= |b|, faster version
inline void quick_two_sum(float a, float b, thread float &s, thread float &e) {
    s = a + b;
    e = b - (s - a);
}

// Two-product using FMA: error-free multiplication
// Returns product in p, error in e such that a * b = p + e exactly
inline void two_product(float a, float b, thread float &p, thread float &e) {
    p = a * b;
    e = fma(a, b, -p);
}

// Double-float addition (full precision)
dd_real dd_add(dd_real a, dd_real b) {
    float s1, s2, t1, t2;
    two_sum(a.hi, b.hi, s1, s2);
    two_sum(a.lo, b.lo, t1, t2);
    s2 += t1;
    quick_two_sum(s1, s2, s1, s2);
    s2 += t2;
    quick_two_sum(s1, s2, s1, s2);
    dd_real r;
    r.hi = s1;
    r.lo = s2;
    return r;
}

// Double-float subtraction
dd_real dd_sub(dd_real a, dd_real b) {
    dd_real neg_b;
    neg_b.hi = -b.hi;
    neg_b.lo = -b.lo;
    return dd_add(a, neg_b);
}

// Double-float multiplication (Dekker's algorithm)
dd_real dd_mul(dd_real a, dd_real b) {
    float p1, p2;
    two_product(a.hi, b.hi, p1, p2);
    p2 += a.hi * b.lo + a.lo * b.hi;
    quick_two_sum(p1, p2, p1, p2);
    dd_real r;
    r.hi = p1;
    r.lo = p2;
    return r;
}

// Create dd_real from a single float
dd_real dd_set(float a) {
    dd_real r;
    r.hi = a;
    r.lo = 0.0f;
    return r;
}

// Create dd_real from two floats (hi, lo pair transmitted from Swift)
// The Swift side splits a double d into:
//   hi = Float(d)
//   lo = Float(d - Double(hi))
// We reconstruct with proper error tracking
dd_real floats_to_dd(float hi, float lo) {
    dd_real r;
    // Use two_sum to maintain precision when combining
    two_sum(hi, lo, r.hi, r.lo);
    return r;
}

// ============================================================================
// MAIN KERNEL
// ============================================================================

kernel void mandelbrotKernel(
    texture2d<float, access::write> output [[texture(0)]],
    constant float4 &params [[buffer(0)]],      // centerX_hi, centerY_hi, scale, maxIterations
    constant float4 &params2 [[buffer(1)]],     // colorOffset, aspectRatio, paletteIndex, paletteMix
    constant float4 &params3 [[buffer(2)]],     // centerX_lo, centerY_lo, shadingMode, time
    constant float4 &params4 [[buffer(3)]],     // opacity, juliaMode, juliaCx, juliaCy
    constant float &highPrecisionFlag [[buffer(4)]], // Optimization flag
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();

    if (gid.x >= width || gid.y >= height) return;

    // Unpack parameters
    float centerX_hi = params.x;
    float centerY_hi = params.y;
    float scale = params.z;
    float maxIterations = params.w;

    float colorOffset = params2.x;
    float aspectRatio = params2.y;
    int paletteIndex = int(params2.z);
    float paletteMix = params2.w;

    float centerX_lo = params3.x;
    float centerY_lo = params3.y;
    int shadingMode = int(params3.z);
    float time = params3.w;

    // Unpack params4: opacity, juliaMode, juliaCx, juliaCy
    float opacity = params4.x;
    bool juliaMode = params4.y > 0.5f;
    float juliaCx = params4.z;
    float juliaCy = params4.w;

    bool useHighPrecision = highPrecisionFlag > 0.5f;

    // Output variables
    float iteration = 0.0f;
    float dzx = 0.0f;
    float dzy = 0.0f;
    float final_zx = 0.0f;
    float final_zy = 0.0f;

    // Common map pixel to complex plane offset
    float px = (float(gid.x) / float(width) - 0.5f) * scale * aspectRatio;
    float py = (float(gid.y) / float(height) - 0.5f) * scale;

    if (useHighPrecision) {
        // ==========================================================
        // DOUBLE-DOUBLE PRECISION PATH (Deep Zoom)
        // ==========================================================
        
        // Reconstruct center coordinates using double-float precision
        dd_real x0 = floats_to_dd(centerX_hi, centerX_lo);
        dd_real y0 = floats_to_dd(centerY_hi, centerY_lo);

        x0 = dd_add(x0, dd_set(px));
        y0 = dd_add(y0, dd_set(py));

        dd_real cx_dd, cy_dd;
        dd_real zx, zy;

        if (juliaMode) {
            zx = x0;
            zy = y0;
            cx_dd = dd_set(juliaCx);
            cy_dd = dd_set(juliaCy);
        } else {
            zx = dd_set(0.0f);
            zy = dd_set(0.0f);
            cx_dd = x0;
            cy_dd = y0;
        }

        // Quick cardioid/bulb check (only for Mandelbrot mode)
        float cx = cx_dd.hi;
        float cy = cy_dd.hi;
        float q = (cx - 0.25f) * (cx - 0.25f) + cy * cy;
        bool inCardioid = !juliaMode && (q * (q + (cx - 0.25f)) <= 0.25f * cy * cy);
        bool inBulb = !juliaMode && ((cx + 1.0f) * (cx + 1.0f) + cy * cy <= 0.0625f);

        if (inCardioid || inBulb) {
            iteration = maxIterations;
        } else {
            while (iteration < maxIterations) {
                float zx_hi = zx.hi;
                float zy_hi = zy.hi;
                float mag_sq = zx_hi * zx_hi + zy_hi * zy_hi;

                if (mag_sq > 256.0f) {
                    final_zx = zx_hi;
                    final_zy = zy_hi;
                    break;
                }

                // Distance estimation derivative: dz = 2*z*dz + 1
                float new_dzx = 2.0f * (zx_hi * dzx - zy_hi * dzy) + 1.0f;
                float new_dzy = 2.0f * (zx_hi * dzy + zy_hi * dzx);
                dzx = new_dzx;
                dzy = new_dzy;

                // z = z^2 + c using double-float precision
                dd_real zx_sq = dd_mul(zx, zx);
                dd_real zy_sq = dd_mul(zy, zy);
                dd_real zx_zy = dd_mul(zx, zy);

                dd_real new_zx = dd_add(dd_sub(zx_sq, zy_sq), cx_dd);
                dd_real new_zy = dd_add(dd_add(zx_zy, zx_zy), cy_dd);

                zx = new_zx;
                zy = new_zy;
                iteration += 1.0f;
            }
        }
    } else {
        // ==========================================================
        // FLOAT PRECISION PATH (Fast for shallow zoom)
        // ==========================================================
        
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
        
        // Cardioid/Bulb check
        float q = (cx - 0.25f) * (cx - 0.25f) + cy * cy;
        bool inCardioid = !juliaMode && (q * (q + (cx - 0.25f)) <= 0.25f * cy * cy);
        bool inBulb = !juliaMode && ((cx + 1.0f) * (cx + 1.0f) + cy * cy <= 0.0625f);
        
        if (inCardioid || inBulb) {
            iteration = maxIterations;
        } else {
            while (iteration < maxIterations) {
                float zx_sq = zx * zx;
                float zy_sq = zy * zy;
                
                if (zx_sq + zy_sq > 256.0f) {
                    final_zx = zx;
                    final_zy = zy;
                    break;
                }
                
                // dz derivative
                float new_dzx = 2.0f * (zx * dzx - zy * dzy) + 1.0f;
                float new_dzy = 2.0f * (zx * dzy + zy * dzx);
                dzx = new_dzx;
                dzy = new_dzy;
                
                float new_zy = 2.0f * zx * zy + cy;
                float new_zx = zx_sq - zy_sq + cx;
                
                zx = new_zx;
                zy = new_zy;
                iteration += 1.0f;
            }
        }
    }

    // Coloring
    float3 color;

    if (iteration >= maxIterations) {
        // Inside the set - deep black with subtle variation
        color = float3(0.0f, 0.0f, 0.0f);
    } else {
        // Smooth iteration count
        float mag_sq = final_zx * final_zx + final_zy * final_zy;
        float log_zn = log(mag_sq) / 2.0f;
        float nu = log(log_zn / log(2.0f)) / log(2.0f);
        float smoothIter = iteration + 1.0f - nu;

        // Color from palette
        float t = (smoothIter + colorOffset) * 0.02f;
        color = getPaletteColor(t, paletteIndex, paletteMix);

        // Apply shading based on mode
        if (shadingMode == 1) {
            // Enhanced Blinn-Phong 3D lighting with multiple light sources
            float dz_mag = sqrt(dzx * dzx + dzy * dzy);
            float fz_mag = float(sqrt(mag_sq));
            float dist = 0.5f * float(log(mag_sq)) * fz_mag / dz_mag;

            // Compute surface normal from distance estimation
            float3 N = normalize(float3(dzx, dzy, dist * 100.0f));

            // View direction (assuming camera at z = infinity looking at -z)
            float3 V = float3(0.0f, 0.0f, 1.0f);

            // Primary light: warm white, rotating around the surface
            float lightAngle = time * 0.5f;
            float3 primaryLightDir = normalize(float3(
                cos(lightAngle) * 1.5f,
                sin(lightAngle) * 0.8f - 1.0f,
                2.0f
            ));
            float3 primaryLightColor = float3(1.0f, 0.95f, 0.85f); // Warm white

            // Secondary light: cool blue fill from opposite side
            float3 secondaryLightDir = normalize(float3(
                -cos(lightAngle) * 1.2f,
                -sin(lightAngle) * 0.6f + 0.5f,
                1.5f
            ));
            float3 secondaryLightColor = float3(0.4f, 0.5f, 0.7f); // Cool blue

            // Blinn-Phong for primary light
            float3 H1 = normalize(primaryLightDir + V);
            float diffuse1 = max(dot(N, primaryLightDir), 0.0f);
            float shininess = 32.0f;
            float specular1 = pow(max(dot(N, H1), 0.0f), shininess);

            // Blinn-Phong for secondary light
            float3 H2 = normalize(secondaryLightDir + V);
            float diffuse2 = max(dot(N, secondaryLightDir), 0.0f);
            float specular2 = pow(max(dot(N, H2), 0.0f), shininess * 0.5f);

            // Rim lighting: edge glow effect using Fresnel approximation
            float rim = pow(1.0f - max(dot(N, V), 0.0f), 3.0f);
            float3 rimColor = float3(0.6f, 0.7f, 1.0f); // Soft blue rim

            // Ambient occlusion approximation from iteration depth
            float ao = 1.0f - smoothstep(50.0f, maxIterations * 0.5f, smoothIter) * 0.4f;

            // Combine all lighting components
            float ambient = 0.15f;
            float3 lighting = float3(ambient) * ao;
            lighting += primaryLightColor * (diffuse1 * 0.6f + specular1 * 0.3f);
            lighting += secondaryLightColor * (diffuse2 * 0.3f + specular2 * 0.15f);
            lighting += rimColor * rim * 0.4f;

            color = color * lighting;
        } else if (shadingMode == 2) {
            // Angle-based shading
            float angle = float(atan2(final_zy, final_zx));
            float shade = 0.5f + 0.5f * sin(angle * 8.0f + time);
            color = color * (0.6f + 0.4f * shade);
        } else if (shadingMode == 3) {
            // Stripe shading
            float stripe = 0.5f + 0.5f * sin(smoothIter * 0.5f + time * 2.0f);
            color = mix(color, color * 0.3f, stripe * 0.3f);
        }

        // Subtle vignette
        float2 uv = float2(float(gid.x) / float(width), float(gid.y) / float(height));
        float vignette = 1.0f - 0.3f * length(uv - 0.5f);
        color *= vignette;
    }

    // Gamma correction for better display
    color = pow(color, float3(0.9f));

    // Apply opacity for smooth fade transitions
    color *= opacity;

    output.write(float4(color, 1.0f), gid);
}

// ============================================================================
// BLIT SHADERS FOR P3 WIDE GAMUT RENDERING
// These render the compute texture to the MTKView drawable in P3 colorspace
// ============================================================================

struct BlitVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fullscreen triangle vertex shader (no vertex buffer needed)
// Uses vertex ID to generate a fullscreen quad from 6 vertices (2 triangles)
vertex BlitVertexOut blitVertex(uint vertexID [[vertex_id]]) {
    BlitVertexOut out;

    // Generate fullscreen quad vertices from vertex ID
    // Triangle 1: 0,1,2 (top-left, top-right, bottom-left)
    // Triangle 2: 3,4,5 (top-right, bottom-right, bottom-left)
    float2 positions[6] = {
        float2(-1.0, -1.0),  // bottom-left
        float2( 1.0, -1.0),  // bottom-right
        float2(-1.0,  1.0),  // top-left
        float2( 1.0, -1.0),  // bottom-right
        float2( 1.0,  1.0),  // top-right
        float2(-1.0,  1.0)   // top-left
    };

    float2 texCoords[6] = {
        float2(0.0, 1.0),  // bottom-left (flipped Y for Metal)
        float2(1.0, 1.0),  // bottom-right
        float2(0.0, 0.0),  // top-left
        float2(1.0, 1.0),  // bottom-right
        float2(1.0, 0.0),  // top-right
        float2(0.0, 0.0)   // top-left
    };

    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];

    return out;
}

// Fragment shader that samples the compute texture
// Outputs to rgba16Float drawable with P3 colorspace
fragment float4 blitFragment(BlitVertexOut in [[stage_in]],
                              texture2d<float> computeTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 color = computeTexture.sample(textureSampler, in.texCoord);
    return color;
}
