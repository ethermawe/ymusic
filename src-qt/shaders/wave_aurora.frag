/*
 * Yandex Music Qt - Moja Volna 3D Liquid-Plasma Sphere & Soft Stage Aura
 *
 * Designed for WaveHero.qml:
 *  - Soft, velvety studio aura outside the orb (attenuated over the left queue)
 *  - 3D rotating domain-warped FBM liquid-aurora globe inside the orb when no cover is shown
 *  - Crisp glass Fresnel rim & directional studio highlight matching circular cover art when hasCover > 0.5
 */

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 orbCenter;
    float radius;
    float time;
    vec4 energy;
    float lead;
    float waveActive;
    vec4 bgColor;
    vec4 c0;
    vec4 c1;
    vec4 c2;
    float orbSize;
    float tintStrength;
    float hasCover;
};

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p)
{
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p)
{
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);

    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

float fbm3(vec3 p)
{
    float v = 0.0;
    float a = 0.52;
    for (int i = 0; i < 3; ++i) {
        v += a * vnoise3(p);
        p = p * 2.07 + vec3(1.7, 3.1, 2.3);
        a *= 0.5;
    }
    return v;
}

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Lift muted cover accents into clean, luminous aurora hues without muddy browns
vec3 vividColor(vec3 rgb, float fallbackHue, float hueShift, float minSat, float minVal)
{
    vec3 hsv = rgb2hsv(clamp(rgb, 0.0, 1.0));
    if (hsv.y < 0.14 || hsv.z < 0.18) {
        hsv.x = fract(fallbackHue + hueShift);
    } else {
        hsv.x = fract(hsv.x + hueShift);
    }
    if (hsv.x > 0.11 && hsv.x < 0.27) {
        hsv.x = (hsv.x < 0.19) ? 0.06 : 0.56;
    }
    hsv.y = clamp(max(hsv.y * 1.28, minSat), minSat, 0.90);
    hsv.z = clamp(max(hsv.z * 1.15, minVal), minVal, 1.0);
    return hsv2rgb(hsv);
}

vec3 rotateYX(vec3 p, float ay, float ax)
{
    float cy = cos(ay), sy = sin(ay);
    p.xz = vec2(cy * p.x + sy * p.z, -sy * p.x + cy * p.z);
    float cx = cos(ax), sx = sin(ax);
    p.yz = vec2(cx * p.y - sx * p.z, sx * p.y + cx * p.z);
    return p;
}

void main()
{
    vec2 pos = qt_TexCoord0 * itemSize;
    float bgLum = dot(bgColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    bool isDark = bgLum < 0.45;
    float tone = isDark ? 1.0 : 0.36;

    float subBass = energy.x;
    float bass = energy.y;
    float upperBass = energy.z;
    float vocal = energy.w;
    float beat = clamp(subBass * 0.45 + bass * 0.55, 0.0, 1.5);
    float shimmer = clamp(vocal * 0.55 + lead * 0.65, 0.0, 1.5);

    vec3 colA = vividColor(c0.rgb, 0.93,  0.00, isDark ? 0.72 : 0.58, isDark ? 0.94 : 0.98);
    vec3 colB = vividColor(c1.rgb, 0.74, isDark ? -0.14 : -0.06, isDark ? 0.76 : 0.55, isDark ? 0.94 : 0.98);
    vec3 colC = vividColor(c2.rgb, 0.56, isDark ? -0.26 :  0.07, isDark ? 0.70 : 0.52, isDark ? 0.92 : 0.98);

    vec2 rel = pos - orbCenter;
    float dp = length(rel);
    float safeOrb = max(orbSize, 1.0);
    float rNorm = dp / safeOrb;
    float angle = atan(rel.y, rel.x);

    // Subtle organic liquid silhouette breathing (kept circular when cover art is active)
    float liquidStrength = (1.0 - clamp(hasCover, 0.0, 1.0)) * (0.005 + 0.009 * waveActive + 0.008 * beat);
    float liquidDeform = liquidStrength * (
        0.65 * sin(angle * 2.0 + time * 1.15)
      + 0.35 * cos(angle * 3.0 - time * 0.85)
    );
    float breath = 1.0 + 0.012 * sin(time * 0.9) * (1.0 - 0.65 * hasCover) + 0.052 * waveActive * beat;
    float sphereR = breath + liquidDeform;
    float rScaled = rNorm / max(sphereR, 0.001);

    // ========================================================================
    // 1. Soft Asymmetric Studio Atmosphere Outside the Sphere (No Radar Rings)
    // ========================================================================
    float distFromEdge = max(rScaled - 1.0, 0.0);

    float flowLobe = 0.82
        + 0.11 * sin(angle * 2.0 + time * 0.48)
        + 0.07 * cos(angle * 3.0 - time * 0.36);

    float rimBloom = exp(-distFromEdge * 5.6) * (0.42 + 0.24 * beat + 0.10 * waveActive);
    float softAura = exp(-distFromEdge * 1.35) * (0.16 + 0.09 * waveActive + 0.07 * beat) * flowLobe;

    float colorSpin = 0.5 + 0.5 * sin(angle + time * 0.32 + distFromEdge * 0.45);
    float colorSpin2 = 0.5 + 0.5 * cos(angle * 2.0 - time * 0.24);
    vec3 outerCol = mix(colA, colB, colorSpin);
    outerCol = mix(outerCol, colC, colorSpin2 * clamp(distFromEdge * 0.45 + 0.22, 0.0, isDark ? 0.85 : 0.55));
    outerCol = mix(outerCol, mix(colA, vec3(1.0), 0.35), exp(-distFromEdge * 12.0) * 0.45);
    if (!isDark) {
        // Keep light-theme studio aura airy and pastel instead of dark/muddy
        outerCol = mix(outerCol, vec3(1.0), 0.34);
    }

    vec2 uv = qt_TexCoord0;
    float stageFade = smoothstep(0.0, 0.06, uv.x) * smoothstep(1.0, 0.94, uv.x)
                    * smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);
    float queueRespect = mix(0.24, 1.0, smoothstep(0.28, 0.48, uv.x));

    float outerAlpha = clamp((rimBloom + softAura) * tone * tintStrength, 0.0, 0.88)
                     * stageFade * queueRespect;

    vec3 finalCol = outerCol;
    float finalAlpha = outerAlpha;

    // ========================================================================
    // 2. Sculpted 3D Volumetric Liquid-Plasma Glass Sphere
    // ========================================================================
    float aa = max(fwidth(rScaled), 1.4 / safeOrb);
    float sphereMask = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, rScaled);

    if (sphereMask > 0.0001) {
        vec2 sp = rel / (safeOrb * max(sphereR, 0.001));
        float r2 = clamp(dot(sp, sp), 0.0, 1.0);
        float z = sqrt(max(0.0, 1.0 - r2));
        vec3 N = vec3(sp, z);

        // Rotate surface normals slowly in 3D so fluid currents wrap around a true globe
        float flowClock = time * (0.24 + 0.14 * waveActive);
        vec3 Nrot = rotateYX(N, flowClock * 0.85, sin(flowClock * 0.55) * 0.38);

        // 2-stage domain-warped 3D FBM for silky iridescent plasma currents
        vec3 p = Nrot * 2.05 + vec3(0.0, -flowClock * 0.55, flowClock * 0.35);
        vec3 q = vec3(
            fbm3(p),
            fbm3(p + vec3(5.2, 1.3, 2.8)),
            fbm3(p + vec3(1.7, 6.4, 4.1))
        );
        vec3 r = vec3(
            fbm3(p + 1.55 * q + vec3(1.4, 4.8, 0.6) + 0.16 * flowClock),
            fbm3(p + 1.55 * q + vec3(7.1, 2.3, 3.2) - 0.13 * flowClock),
            fbm3(p + 1.55 * q + vec3(3.3, 5.7, 6.8))
        );
        float f = fbm3(p + 1.45 * r + 0.12 * beat);

        // Smooth caustic filaments along folded fluid ridges
        float fold1 = smoothstep(0.30, 0.82, f);
        float fold2 = smoothstep(0.28, 0.80, r.x);
        float caustic = pow(clamp(1.0 - abs(f - 0.50) * 4.4, 0.0, 1.0), 2.4);
        float caustic2 = pow(clamp(1.0 - abs(r.y - 0.52) * 4.8, 0.0, 1.0), 2.8);

        // Deep obsidian glass core -> keeps white title & Play icon crystal clear
        vec3 obsidian = mix(vec3(0.035, 0.028, 0.068), colA * 0.14 + colB * 0.10, 0.42);
        vec3 plasmaCol = mix(colA, colB, fold1);
        plasmaCol = mix(plasmaCol, colC, fold2 * 0.72);

        // Modulate intensity slightly darker in center, brighter toward spherical curvature
        float radialDepth = mix(0.56, 1.0, smoothstep(0.08, 0.85, r2));
        vec3 orbCol = mix(obsidian, plasmaCol * (0.72 + 0.24 * beat), (0.36 + 0.46 * fold1) * radialDepth);

        // Add subtle glowing filament ridges inside the fluid
        vec3 ridgeTint = mix(mix(colA, colC, r.z), vec3(1.0), 0.34);
        orbCol += ridgeTint * caustic * (0.34 + 0.28 * beat + 0.18 * shimmer) * radialDepth;
        orbCol += mix(colB, vec3(1.0), 0.42) * caustic2 * (0.20 + 0.22 * shimmer);

        // Subtle inner core pulse on bass hits
        float centerPulse = exp(-r2 * 2.8) * (0.14 + 0.20 * beat) * waveActive;
        orbCol += mix(colA, colB, 0.5) * centerPulse;

        // Crisp 3D Fresnel glass shell wrapping the edges
        float fresnel = pow(1.0 - z, 2.85);
        vec3 rimCol = mix(colA, colB, 0.5 + 0.5 * sin(angle * 2.0 - time * 0.75));
        rimCol = mix(rimCol, colC, 0.45 * (0.5 + 0.5 * cos(angle + time * 0.5)));
        rimCol = mix(rimCol, vec3(1.0), 0.42);
        orbCol = mix(orbCol, rimCol, clamp(fresnel * (0.82 + 0.14 * waveActive), 0.0, 0.94));

        // Top-left studio softbox highlight & bottom bounce light for physical 3D glass read
        vec3 lightDir = normalize(vec3(-0.36, -0.54, 0.76));
        float spec = pow(max(dot(N, lightDir), 0.0), 14.0);
        float softArc = smoothstep(0.62, 0.94, dot(N, vec3(-0.34, -0.58, 0.74))) * pow(1.0 - z, 1.35);
        float bounce = pow(max(dot(N, vec3(0.28, 0.74, 0.61)), 0.0), 5.0) * pow(1.0 - z, 1.4);

        orbCol += vec3(1.0) * (spec * 0.30 + softArc * 0.18);
        orbCol += mix(colB, colC, 0.5) * bounce * 0.26;
        orbCol = clamp(orbCol, 0.0, 1.0);

        // When album cover artwork is active inside coreButton, keep only the crisp outer glass rim glow
        float cov = clamp(hasCover, 0.0, 1.0);
        float orbVisibility = max(1.0 - cov, fresnel * 0.85);
        finalCol = mix(outerCol, orbCol, sphereMask * orbVisibility);
        finalAlpha = mix(outerAlpha, mix(max(outerAlpha, fresnel * 0.85), 0.98, 1.0 - cov), sphereMask);
    }

    float dither = (hash12(pos + fract(time) * 13.7) - 0.5) / 255.0;
    finalCol = clamp(finalCol + dither, 0.0, 1.0);

    fragColor = vec4(finalCol * finalAlpha, finalAlpha) * qt_Opacity;
}
