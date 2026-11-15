#version 440
// Smooth per-line karaoke highlight shader for lyrics text.
// Sweeps left-to-right across wrapped lines (lineCount) using actual text width
// on single lines, illuminating sung letters with a vivid accent front and soft halo.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 accentColor;
    vec4 sungColor;
    vec2 itemSize;
    float progress;
    float lineCount;
    float textWidthFrac;
    float dimAlpha;
    float glowAmount;
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec4 tex = texture(source, qt_TexCoord0);
    float glyphAlpha = tex.a;
    if (glyphAlpha <= 0.0005) {
        fragColor = vec4(0.0);
        return;
    }

    float rows = max(1.0, lineCount);
    float row = clamp(floor(qt_TexCoord0.y * rows), 0.0, rows - 1.0);
    float rowProgress = clamp(progress * rows - row, 0.0, 1.0);

    // On single-line lyrics, sweep strictly across actual glyph width rather than full box width.
    float activeSpan = rows <= 1.5 ? clamp(textWidthFrac, 0.06, 1.0) : 1.0;
    float u = clamp(qt_TexCoord0.x / activeSpan, 0.0, 1.0);

    // Smooth feather front across the syllable currently being sung.
    float feather = clamp(28.0 / max(itemSize.x * activeSpan, 48.0), 0.05, 0.16);
    float edge = mix(-feather, 1.0 + feather, rowProgress);
    float sung = 1.0 - smoothstep(edge - feather, edge + feather, u);

    // Subtle accent highlight right at the singing cursor (strictly inside glyph coverage, no shifted ghost taps).
    float dist = (u - edge) / max(feather * 1.45, 0.045);
    float frontier = exp(-dist * dist * 1.5) * smoothstep(0.0, 0.03, rowProgress) * smoothstep(1.0, 0.97, rowProgress);

    vec3 sungTint = mix(sungColor.rgb, accentColor.rgb, 0.16 * clamp(glowAmount, 0.0, 1.0));
    vec3 frontTint = mix(sungColor.rgb, accentColor.rgb, 0.55);

    vec3 dimRgb = sungColor.rgb;
    vec3 litRgb = mix(sungTint, frontTint, clamp(frontier * 0.75 * glowAmount, 0.0, 0.85));
    vec3 finalRgb = mix(dimRgb, litRgb, sung);

    float alphaScale = mix(dimAlpha, 1.0, sung);
    float outAlpha = glyphAlpha * alphaScale;
    fragColor = vec4(finalRgb * outAlpha, outAlpha) * qt_Opacity;
}
