#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
    vec2 uvScale;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 halfSize = itemSize * 0.5;
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    vec2 p = abs((qt_TexCoord0 - 0.5) * itemSize) - halfSize + r;
    float distanceToEdge = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - r;
    float aa = max(fwidth(distanceToEdge), 0.001);
    float mask = 1.0 - smoothstep(-aa, aa, distanceToEdge);
    vec2 uv = (qt_TexCoord0 - 0.5) * uvScale + 0.5;
    fragColor = texture(source, uv) * (mask * qt_Opacity);
}
