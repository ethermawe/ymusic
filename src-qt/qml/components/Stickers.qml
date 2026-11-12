import QtQuick
import ymusic.ui

Item {
    id: root

    implicitWidth: 600
    implicitHeight: 400
    clip: true

    // Sticker 1: Top Right soft flower
    MaterialShape {
        x: root.width - 120
        y: -40
        width: 180
        height: 180
        shape: "flower"
        color: Appearance.colors.primary
        opacity: 0.07
        spinAngle: 15
    }

    // Sticker 2: Left Middle clover
    MaterialShape {
        x: -50
        y: 140
        width: 150
        height: 150
        shape: "clover4"
        color: Appearance.colors.secondary
        opacity: 0.06
        spinAngle: 45
    }

    // Sticker 3: Bottom Right cookie
    MaterialShape {
        x: root.width - 200
        y: root.height - 100
        width: 220
        height: 220
        shape: "cookie9"
        color: Appearance.colors.tertiary
        opacity: 0.05
        spinAngle: 30
    }

    // Sticker 4: Center subtle soft cookie
    MaterialShape {
        x: root.width * 0.45
        y: root.height * 0.35
        width: 130
        height: 130
        shape: "softCookie"
        color: Appearance.colors.primaryContainer
        opacity: 0.06
        spinAngle: 60
    }
}
