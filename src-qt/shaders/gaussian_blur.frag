#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texelStep;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 sum = vec4(0.0);
    float weights = 0.0;
    // Adjacent, linearly filtered samples instead of a sparse UV grid.
    for (int i = -32; i <= 32; ++i) {
        float x = float(i);
        float weight = exp(-x * x / (2.0 * 14.0 * 14.0));
        sum += texture(source, clamp(qt_TexCoord0 + texelStep * x, vec2(0.0), vec2(1.0))) * weight;
        weights += weight;
    }
    fragColor = sum / weights * qt_Opacity;
}
