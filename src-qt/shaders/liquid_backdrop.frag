/*
 * Swiftify, a spotify player for desktop
 * Copyright (C) 2026  shred0s
 * Modified for ymusic (2026).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#version 440
// Smooth ambient fluid field for the immersive player: low-frequency
// quintic value noise with gentle domain warping, coloured from the
// cover's palette so it flows cleanly without high-frequency shimmer.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float time;
    // smoothed sub-bass, bass, upper bass, vocal
    vec4 energy;
    float lead;
    vec4 c0;
    vec4 c1;
    vec4 c2;
    vec4 c3;
    vec4 c4;
};

float liquidHash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float liquidNoise(vec2 p)
{
    vec2 cell = floor(p);
    vec2 f = fract(p);
    // C2-continuous quintic interpolation eliminates grid creases and shimmer.
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float a = liquidHash(cell);
    float b = liquidHash(cell + vec2(1.0, 0.0));
    float c = liquidHash(cell + vec2(0.0, 1.0));
    float d = liquidHash(cell + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 liquidRotate(vec2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// 3 smooth octaves keep all features well above the downsampled texel Nyquist limit.
float liquidFbm(vec2 p)
{
    float total = 0.0;
    float amplitude = 0.56;
    for (int octave = 0; octave < 3; octave++) {
        total += amplitude * liquidNoise(p);
        p *= 1.92;
        amplitude *= 0.48;
    }
    return total;
}

void main()
{
    float bassEnergy = clamp((energy.x + energy.y) * 0.5, 0.0, 1.0);
    float midEnergy = clamp((energy.z + energy.w) * 0.5, 0.0, 1.0);
    float leadEnergy = clamp(lead, 0.0, 1.0);

    vec2 position = qt_TexCoord0 * itemSize;
    vec2 uv = position / max(itemSize.y, 1.0);
    vec2 centred = uv - vec2(itemSize.x / max(itemSize.y, 1.0), 1.0) * 0.5;

    // Broad, velvety scale so color pools breathe rather than crinkle.
    vec2 domainA = liquidRotate(centred, time * 0.008) * 0.95;
    vec2 domainB = liquidRotate(centred, time * -0.006) * 0.95;

    float warpQ = 1.45 * (1.0 + 0.18 * sin(time * 0.031)) + bassEnergy * 0.10;
    float warpR = 1.45 * (1.0 + 0.18 * cos(time * 0.025)) + midEnergy * 0.08;

    vec2 flowA = vec2(sin(time * 0.041), cos(time * 0.033)) * 0.24;
    vec2 flowB = vec2(cos(time * 0.029), sin(time * 0.047)) * 0.24;
    vec2 flowC = vec2(sin(time * 0.023), sin(time * 0.037)) * 0.20;
    vec2 flowD = vec2(cos(time * 0.035), cos(time * 0.027)) * 0.20;
    vec2 flowE = vec2(sin(time * 0.049), cos(time * 0.019)) * 0.18;

    vec2 q = vec2(liquidFbm(domainA + flowA),
                  liquidFbm(domainA + vec2(5.2, 1.3) + flowB));

    vec2 r = vec2(liquidFbm(domainB + warpQ * q + vec2(1.7, 9.2) + flowC),
                  liquidFbm(domainB + warpQ * q + vec2(8.3, 2.8) + flowD));

    float pattern = liquidFbm(domainA + warpR * r + flowE);

    vec4 base = mix(c0, c1, smoothstep(0.24, 0.62, pattern));
    base = mix(base, c2, smoothstep(0.50, 0.86, pattern));
    base = mix(base, c3, smoothstep(0.42, 0.88, r.x));
    base = mix(base, c4, smoothstep(0.46, 0.90, q.y));

    // Gentle tonal lift on vocal/lead energy instead of harsh white seam spikes.
    float breath = 1.0 + bassEnergy * 0.08 + leadEnergy * 0.06;
    base.rgb *= breath;

    float falloff = 1.0 - smoothstep(0.32, 0.96, length(qt_TexCoord0 - 0.5));

    vec4 ground = vec4(0.012, 0.012, 0.016, 1.0);
    fragColor = mix(ground, base, 0.48 + 0.40 * falloff) * qt_Opacity;
}
