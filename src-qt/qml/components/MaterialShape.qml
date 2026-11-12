import QtQuick
import ymusic.ui

Canvas {
    id: root

    property string shape: "cookie9" // "softCookie", "cookie9", "flower", "clover4", "squircle", "circle"
    property color color: Appearance.colors.primary
    property real spinAngle: 0
    property real extent: 0.92
    property string morphTo: shape
    property real morph: 0

    implicitWidth: 44
    implicitHeight: 44
    // Rotate the finished contour, not its sampling coordinates: using the
    // same angle in both the radius function and coordinates cancels the spin.
    rotation: spinAngle

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorChanged: requestPaint()
    onShapeChanged: requestPaint()
    onExtentChanged: requestPaint()
    onMorphToChanged: requestPaint()
    onMorphChanged: requestPaint()

    function radiusFactor(kind, angle) {
        switch (kind) {
        case "softCookie": return 1 - 0.07 * Math.pow(0.5 + 0.5 * Math.cos(5 * angle), 1.15);
        case "cookie9": return 1 - 0.09 * (0.5 + 0.5 * Math.cos(9 * angle));
        case "flower": return 1 - 0.28 * Math.pow(0.5 + 0.5 * Math.cos(8 * angle), 0.5);
        case "clover4": return 1 - 0.35 * Math.pow(0.5 + 0.5 * Math.cos(4 * angle), 0.6);
        default: return 1;
        }
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var cx = width / 2;
        var cy = height / 2;
        var baseR = Math.min(cx, cy) * extent;

        ctx.fillStyle = color;
        ctx.beginPath();

        if (shape === "circle" && morph === 0) {
            ctx.arc(cx, cy, baseR, 0, 2 * Math.PI);
        } else {
            var steps = 180;
            for (var i = 0; i <= steps; ++i) {
                var rad = (i / steps) * 2 * Math.PI;
                var blend = Math.max(0, Math.min(1, morph));
                var r = baseR * (radiusFactor(shape, rad) * (1 - blend) + radiusFactor(morphTo, rad) * blend);
                var x = cx + r * Math.cos(rad);
                var y = cy + r * Math.sin(rad);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
        }
        ctx.closePath();
        ctx.fill();
    }
}
