#version 440
// Luminous 3D Silk-Plasma Wave Orb + Flowing Acoustic Energy Waves:
// - Curated HSV aurora color booster (prevents muddy olive/brown on dark covers).
// - Smooth round 3D sphere with refracted internal aurora ribbons and Fresnel rim.
// - Asymmetric acoustic wave crests + directional aurora arcs radiating outward.

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
};

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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

// Boosts palette saturation/value and avoids muddy olive/brown hues (0.12..0.28)
vec3 vividColor(vec3 rgb, float fallbackHue, float hueShift, float minSat, float minVal)
{
    vec3 hsv = rgb2hsv(clamp(rgb, 0.0, 1.0));
    if (hsv.y < 0.16 || hsv.z < 0.18) {
        hsv.x = fract(fallbackHue + hueShift);
    } else {
        hsv.x = fract(hsv.x + hueShift);
    }
    // Push away from muddy yellow-olive zone into warm coral/gold or vibrant cyan/violet
    if (hsv.x > 0.11 && hsv.x < 0.27) {
        hsv.x = (hsv.x < 0.19) ? 0.07 : 0.56;
    }
    hsv.y = clamp(max(hsv.y * 1.4, minSat), minSat, 0.95);
    hsv.z = clamp(max(hsv.z * 1.35, minVal), minVal, 1.0);
    return hsv2rgb(hsv);
}

// A soft volumetric 3D silk wave ribbon inside the sphere
float silkWave(vec2 uv, float freq, float speed, float amp, float yOffset, float phase, float width)
{
    float waveY = yOffset
                + amp * sin(uv.x * freq + time * speed + phase)
                + amp * 0.42 * cos(uv.x * (freq * 1.65) - time * (speed * 0.78) + phase * 1.3);
    float d = abs(uv.y - waveY);
    float body = exp(-pow(d / max(width, 0.01), 1.65));
    float crest = exp(-pow(d / max(width * 0.26, 0.005), 2.0));
    return body * 0.65 + crest * 0.60;
}

void main()
{
    vec2 pos = qt_TexCoord0 * itemSize;
    float bgLum = dot(bgColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    bool isDark = bgLum < 0.45;
    float tone = isDark ? 1.0 : 0.72;

    float subBass = energy.x;
    float bass = energy.y;
    float upperBass = energy.z;
    float vocal = energy.w;
    float beat = clamp(subBass * 0.45 + bass * 0.55, 0.0, 1.6);
    float shimmer = clamp(vocal * 0.55 + lead * 0.65, 0.0, 1.6);

    // Rich 3-tone aurora palette (always luminous, never muddy brown)
    vec3 colA = vividColor(c0.rgb, 0.92,  0.00, 0.78, 0.96);
    vec3 colB = vividColor(c1.rgb, 0.76, -0.15, 0.82, 0.96);
    vec3 colC = vividColor(c2.rgb, 0.56, -0.28, 0.76, 0.95);

    vec2 rel = pos - orbCenter;
    float dp = length(rel);
    float safeOrb = max(orbSize, 1.0);
    float rNorm = dp / safeOrb;
    float angle = atan(rel.y, rel.x);

    // Gentle, round liquid breathing (no polygon corners)
    float liquidDeform = 0.008 * sin(angle * 2.0 + time * 1.15)
                       + 0.005 * cos(angle * 3.0 - time * 0.90)
                       + 0.008 * beat * sin(angle * 2.0 - time * 1.8);
    float breath = 1.0 + 0.024 * sin(time * 0.95) + 0.068 * waveActive * beat;
    float sphereR = breath + liquidDeform;
    float rScaled = rNorm / max(sphereR, 0.001);

    // ========================================================================
    // 1. Acoustic Energy Waves & Corona Radiating Outside the Sphere
    // ========================================================================
    float distFromEdge = max(rScaled - 1.0, 0.0);

    // Tight bright corona hugging the sphere rim
    float corona = exp(-distFromEdge * 4.4) * (0.52 + 0.28 * beat);
    // Soft stage aura around the right pane
    float wideAura = exp(-rScaled * 0.68) * (0.20 + 0.10 * waveActive);

    // 4 propagating acoustic wave fronts with flowing angular aurora arcs
    float waveFronts = 0.0;
    vec3 waveAccumCol = vec3(0.0);
    float speed = 0.16 + 0.05 * waveActive;

    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float phase = fract(time * speed + fi * 0.25);

        // Slight angular wave modulation so each wave flows organically
        float angularShift = 0.035 * sin(angle * 2.0 + time * 0.9 + fi * 1.57)
                           + 0.020 * cos(angle * 3.0 - time * 1.1 + fi * 2.1);
        float waveRadius = 1.02 + phase * 1.75 + angularShift * phase;

        // Asymmetric wave profile: crisp leading crest + soft trailing wake
        float d = rScaled - waveRadius;
        float width = (d > 0.0) ? (0.065 + 0.045 * phase) : (0.18 + 0.10 * phase);
        float profile = exp(- (d * d) / max(width * width, 0.0001));
        float crestHighlight = exp(- (d * d) / max((width * 0.36) * (width * 0.36), 0.00005));

        // Directional aurora intensity along the wave arc
        float arcLobe = 0.62 + 0.38 * sin(angle * 2.0 - time * (0.8 + 0.15 * fi) + fi * 1.8);
        float life = smoothstep(0.0, 0.10, phase) * pow(1.0 - phase, 1.35);

        float w = (profile * 0.65 + crestHighlight * 0.55) * arcLobe * life;
        waveFronts += w;

        vec3 wCol = (i % 2 == 0)
            ? mix(colA, colB, 0.5 + 0.5 * sin(angle + fi + time * 0.5))
            : mix(colB, colC, 0.5 + 0.5 * cos(angle - fi - time * 0.4));
        wCol = mix(wCol, vec3(1.0), crestHighlight * 0.28);
        waveAccumCol += wCol * w;
    }

    float waveIntensity = waveFronts * (0.18 + 0.28 * waveActive + 0.22 * beat);

    vec3 baseOuterCol = mix(colA, colB, 0.5 + 0.5 * sin(angle + time * 0.4));
    baseOuterCol = mix(baseOuterCol, colC, clamp(distFromEdge * 0.42, 0.0, 1.0));
    vec3 outerColor = (waveFronts > 0.001)
        ? mix(baseOuterCol, waveAccumCol / max(waveFronts, 0.001), clamp(waveIntensity * 1.5, 0.0, 0.85))
        : baseOuterCol;

    // Fade near viewport edges & attenuate over the left track queue so tracks stay crisp
    vec2 uv = qt_TexCoord0;
    float stageFade = smoothstep(0.0, 0.06, uv.x) * smoothstep(1.0, 0.94, uv.x)
                    * smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);
    float queueRespect = mix(0.28, 1.0, smoothstep(0.28, 0.48, uv.x));

    float outerAlpha = clamp((corona + wideAura + waveIntensity) * tone * tintStrength, 0.0, 0.90)
                     * stageFade * queueRespect;

    vec3 finalCol = outerColor;
    float finalAlpha = outerAlpha;

    // ========================================================================
    // 2. Inside the Sphere: 3D Volumetric Silk-Plasma Orb
    // ========================================================================
    float aa = max(fwidth(rScaled), 1.5 / safeOrb);
    float sphereMask = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, rScaled);

    if (sphereMask > 0.0001) {
        vec2 sp = rel / (safeOrb * max(sphereR, 0.001));
        float r2 = clamp(dot(sp, sp), 0.0, 1.0);
        float z = sqrt(max(0.0, 1.0 - r2));
        vec3 N = vec3(sp, z);

        // 3D spherical lens distortion so inner silk ribbons wrap around the globe
        vec2 lensUv = sp / (0.54 + 0.46 * z);

        // Deep cosmic interior base for crisp white text & button legibility
        vec3 innerBase = mix(vec3(0.05, 0.03, 0.10), colA * 0.30, 0.50);
        innerBase = mix(innerBase, colB * 0.34, 0.5 + 0.5 * sp.y);
        innerBase = mix(innerBase, colC * 0.26, 0.5 - 0.5 * sp.x);

        // Flowing 3D silk light ribbons inside the sphere
        float amp = 0.22 + 0.10 * waveActive + 0.18 * beat;
        float w1 = silkWave(lensUv, 2.5,  0.95, amp,        -0.10, 0.0, 0.27 + 0.08 * beat);
        float w2 = silkWave(lensUv, 3.3, -0.80, amp * 0.85,  0.08, 1.8, 0.23 + 0.07 * shimmer);
        float w3 = silkWave(vec2(lensUv.y, -lensUv.x), 2.8, 0.65, amp * 0.72, 0.0, 3.2, 0.25 + 0.06 * upperBass);
        float w4 = silkWave(lensUv, 4.2,  1.15, amp * 0.58,  0.01, 4.7, 0.17 + 0.05 * shimmer);

        vec3 orbCol = innerBase;
        orbCol += colA * w1 * 0.78;
        orbCol += colB * w2 * 0.74;
        orbCol += colC * w3 * 0.64;
        orbCol += mix(colB, vec3(1.0), 0.65) * w4 * (0.45 + 0.35 * shimmer);

        // Warm reactive center core
        float coreGlow = exp(-r2 * 2.5) * (0.28 + 0.24 * beat);
        orbCol += mix(colA, colB, 0.5) * coreGlow;

        // Luminous 3D Fresnel glass rim
        float fresnel = pow(1.0 - z, 2.35);
        vec3 rimColor = mix(colA, colB, 0.5 + 0.5 * sin(angle * 2.0 - time * 0.9));
        rimColor = mix(rimColor, colC, 0.5 + 0.5 * cos(angle - time * 0.6));
        rimColor = mix(rimColor, vec3(1.0), 0.50);
        orbCol = mix(orbCol, rimColor, clamp(fresnel * 0.88, 0.0, 0.96));

        // Subtle top-left glass specular highlight
        vec3 lightDir = normalize(vec3(-0.36, -0.54, 0.76));
        float spec = pow(max(dot(N, lightDir), 0.0), 10.0);
        orbCol += vec3(1.0) * spec * 0.26;

        orbCol = clamp(orbCol, 0.0, 1.0);

        finalCol = mix(outerColor, orbCol, sphereMask);
        finalAlpha = mix(outerAlpha, 0.98, sphereMask);
    }

    float dither = (hash12(pos + fract(time) * 13.7) - 0.5) / 255.0;
    finalCol = clamp(finalCol + dither, 0.0, 1.0);

    fragColor = vec4(finalCol * finalAlpha, finalAlpha) * qt_Opacity;
}
