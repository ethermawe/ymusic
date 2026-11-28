#version 440
// Karaoke highlight shader for lyrics text.
// The sweep front and the "lift" wave are measured in pixels and tied to the row
// height (~ one glyph wide), so the effect looks identical on short and long words.
// Only the letters under the front rise (vertical displacement only, no X warp).

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
    float zoomAmount;
    float padTop;     // px of empty space above glyphs inside the layer texture
    float padBottom;  // px below
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec2 sizePx = max(itemSize, vec2(1.0));
    vec2 p = qt_TexCoord0 * sizePx;

    // Rows are laid out inside the padded content box.
    float rows = max(1.0, lineCount);
    float contentH = max(sizePx.y - padTop - padBottom, 1.0);
    float rowHeightPx = max(contentH / rows, 12.0);
    float row = clamp(floor((p.y - padTop) / rowHeightPx), 0.0, rows - 1.0);
    float rowProgress = clamp(progress * rows - row, 0.0, 1.0);
    float rowTopPx = padTop + row * rowHeightPx;
    float rowBottomPx = rowTopPx + rowHeightPx;

    // Single line: sweep across the real glyph width, not the box.
    float activeSpan = rows <= 1.5 ? clamp(textWidthFrac, 0.06, 1.0) : 1.0;
    float spanPx = max(sizePx.x * activeSpan, 1.0);

    // Wave width ~ one letter; colour feather a bit narrower so the edge stays crisp.
    float sigma = rowHeightPx * 0.55;
    float feather = sigma * 0.7;
    float frontPx = mix(-sigma, spanPx + sigma, rowProgress);
    float d = (p.x - frontPx) / sigma;

    // Fade in/out at word edges -> no jump when the layer toggles on/off.
    float edgeFade = smoothstep(0.0, 0.12, rowProgress) * smoothstep(1.0, 0.88, rowProgress);
    float wave = exp(-0.5 * d * d) * edgeFade;

    float motion = clamp(zoomAmount, 0.0, 0.14) / 0.075;  // 0 when reduceMotion
    float liftPx = 3.0 * wave * motion;
    // Tiny vertical-only swell around the row baseline area (feels "bolder", never spreads in X).
    float swell = 1.0 + 0.025 * wave * motion;
    float anchorY = rowBottomPx - rowHeightPx * 0.22;

    vec2 sp = p;
    sp.y = anchorY + (p.y - anchorY) / swell + liftPx;

    // Allow sampling into the top padding (lifted glyph tops), but never into the neighbouring row.
    float minY = row < 0.5 ? 0.0 : rowTopPx;
    float maxY = row > rows - 1.5 ? sizePx.y : rowBottomPx;
    float inBounds = step(minY, sp.y) * step(sp.y, maxY);

    vec4 tex = texture(source, clamp(sp / sizePx, vec2(0.0), vec2(1.0)));
    float glyphAlpha = tex.a * inBounds;
    if (glyphAlpha <= 0.0005) {
        fragColor = vec4(0.0);
        return;
    }

    float sung = 1.0 - smoothstep(frontPx - feather, frontPx + feather, p.x);

    float g = clamp(glowAmount, 0.0, 1.0);
    vec3 sungTint = mix(sungColor.rgb, accentColor.rgb, 0.16 * g);
    vec3 frontTint = mix(sungColor.rgb, accentColor.rgb, 0.55);
    vec3 litRgb = mix(sungTint, frontTint, clamp(wave * 0.75 * glowAmount, 0.0, 0.85));
    vec3 finalRgb = mix(sungColor.rgb, litRgb, sung);

    // Letters under the front get full alpha slightly before the colour fully lands.
    float alphaScale = mix(dimAlpha, 1.0, max(sung, wave * 0.6));
    float outAlpha = glyphAlpha * alphaScale;
    fragColor = vec4(finalRgb * outAlpha, outAlpha) * qt_Opacity;
}
