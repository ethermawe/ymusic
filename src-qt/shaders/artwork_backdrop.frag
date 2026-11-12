#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    // Vertical pass over the low-resolution, horizontally blurred texture.
    vec3 blurred = vec3(0.0);
    float weightSum = 0.0;
    for (int y = -32; y <= 32; ++y) {
            float offset = float(y);
            float weight = exp(-offset * offset / (2.0 * 14.0 * 14.0));
            vec2 uv = clamp(qt_TexCoord0 + vec2(0.0, offset / 64.0), vec2(0.0), vec2(1.0));
            blurred += texture(source, uv).rgb * weight;
            weightSum += weight;
    }
    blurred /= weightSum;
    float luminance = dot(blurred, vec3(0.2126, 0.7152, 0.0722));
    blurred = mix(vec3(luminance), blurred, 1.35);

    vec2 halfSize = itemSize * 0.5;
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    vec2 p = abs((qt_TexCoord0 - 0.5) * itemSize) - halfSize + r;
    float distanceToEdge = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - r;
    float aa = max(fwidth(distanceToEdge), 0.001);
    float mask = 1.0 - smoothstep(-aa, aa, distanceToEdge);
    fragColor = vec4(blurred, 1.0) * (mask * qt_Opacity);
}
