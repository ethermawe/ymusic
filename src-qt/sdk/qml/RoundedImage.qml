import QtQuick
import ymusic.sdk

Item {
    id: root

    property url source: ""
    property real radius: 12
    property string fallbackSymbol: "music_note"
    property int fallbackIconSize: 24
    property color backgroundColor: Theme.colors.surfaceContainerHigh
    property color maskColor: Theme.colors.surfaceContainerLowest
    property color borderColor: Theme.withAlpha(Theme.colors.onSurface, 0.12)
    property int fillMode: Image.PreserveAspectCrop

    readonly property bool ready: img.status === Image.Ready

    onRadiusChanged: cornerMask.requestPaint()
    onMaskColorChanged: cornerMask.requestPaint()
    onWidthChanged: cornerMask.requestPaint()
    onHeightChanged: cornerMask.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.backgroundColor
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: root.fillMode
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
    }

    Canvas {
        id: cornerMask
        anchors.fill: parent
        visible: img.visible && root.radius > 0

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width;
            const h = height;
            if (w <= 0 || h <= 0) return;
            const r = Math.max(0, Math.min(root.radius, Math.min(w, h) / 2));
            if (r <= 0) return;

            ctx.fillStyle = root.maskColor;

            // Top-left
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(r, 0);
            ctx.arc(r, r, r, -Math.PI / 2, -Math.PI, true);
            ctx.closePath();
            ctx.fill();

            // Top-right
            ctx.beginPath();
            ctx.moveTo(w, 0);
            ctx.lineTo(w - r, 0);
            ctx.arc(w - r, r, r, -Math.PI / 2, 0, false);
            ctx.closePath();
            ctx.fill();

            // Bottom-right
            ctx.beginPath();
            ctx.moveTo(w, h);
            ctx.lineTo(w, h - r);
            ctx.arc(w - r, h - r, r, 0, Math.PI / 2, false);
            ctx.closePath();
            ctx.fill();

            // Bottom-left
            ctx.beginPath();
            ctx.moveTo(0, h);
            ctx.lineTo(0, h - r);
            ctx.arc(r, h - r, r, Math.PI, Math.PI / 2, true);
            ctx.closePath();
            ctx.fill();
        }

        Connections {
            target: Theme.colors
            function onChanged() { cornerMask.requestPaint(); }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.borderColor.a > 0 ? 1 : 0
        border.color: root.borderColor
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !img.visible && root.fallbackSymbol.length > 0
        symbol: root.fallbackSymbol
        iconSize: root.fallbackIconSize
        color: Theme.colors.onSurfaceVariant
    }
}
