#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float progress;
    float amplitude;
    float wavelength;
    float phase;
    float thickness;
    float handleWidth;
    float handleHeight;
    float gap;
    vec4 activeColor;
    vec4 trackColor;
    vec4 handleColor;
};

float coverage(float distanceToLine, float width) {
    float edge = max(fwidth(distanceToLine), 0.001);
    return 1.0 - smoothstep(width * 0.5 - edge, width * 0.5 + edge, distanceToLine);
}

void main() {
    vec2 point = vec2(qt_TexCoord0.x * itemSize.x,
                      (qt_TexCoord0.y - 0.5) * itemSize.y);
    float handleX = progress * itemSize.x;

    float halfThickness = thickness * 0.5;
    float handleSpace = handleWidth > 0.0 ? gap + handleWidth * 0.5 : 0.0;
    float activeEnd = handleX - handleSpace;
    float playedCoverage = 0.0;
    if (activeEnd > halfThickness) {
        float x = clamp(point.x, halfThickness, activeEnd);
        float angle = 6.28318530718 * x / max(wavelength, 1.0) + phase;
        float y = amplitude * sin(angle);
        float slope = amplitude * 6.28318530718 / max(wavelength, 1.0) * cos(angle);
        vec2 delta = vec2(point.x - x, (point.y - y) / sqrt(1.0 + slope * slope));
        playedCoverage = coverage(length(delta), thickness);
    }

    float trackStart = handleX + (handleWidth > 0.0 ? handleSpace : gap);
    float track = 0.0;
    if (trackStart < itemSize.x - halfThickness) {
        float x = clamp(point.x, trackStart, itemSize.x - halfThickness);
        track = coverage(length(vec2(point.x - x, point.y)), thickness);
    }

    float handle = 0.0;
    if (handleWidth > 0.0) {
        // Capsule rather than a hard-edged rectangle.
        float radius = handleWidth * 0.5;
        vec2 q = abs(point - vec2(handleX, 0.0))
               - vec2(0.0, max(0.0, handleHeight * 0.5 - radius));
        float distanceToHandle = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
        float edge = max(fwidth(distanceToHandle), 0.001);
        handle = 1.0 - smoothstep(-edge, edge, distanceToHandle);
    }

    vec4 color = mix(trackColor * track, activeColor, playedCoverage);
    color = mix(color, handleColor, handle);
    fragColor = color * qt_Opacity;
}
