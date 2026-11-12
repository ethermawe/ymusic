#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
    float wavelength;
    float amplitude;
    float thickness;
    float phase;
    vec2 itemSize;
};
void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float angle = 6.28318530718 * p.x / max(wavelength, 1.0) + phase;
    float slope = amplitude * 6.28318530718 / max(wavelength, 1.0) * cos(angle);
    float distanceToLine = abs(p.y - itemSize.y * 0.5 - amplitude * sin(angle)) / sqrt(1.0 + slope * slope);
    float aa = max(fwidth(distanceToLine), 0.001);
    float coverage = 1.0 - smoothstep(thickness * 0.5 - aa, thickness * 0.5 + aa, distanceToLine);
    fragColor = color * coverage * qt_Opacity;
}
