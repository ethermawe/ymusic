pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property string lineText: ""
    property var wordTimings: []
    property bool wordKaraokeActive: false
    property bool isCurrent: false
    property bool synced: false
    property bool isPast: false
    property bool isHovered: false
    property bool hasTime: false
    property int fontPixelSize: 20
    property int fontWeight: Font.Bold
    property color textColor: "white"
    property color accentColor: PlayerStyle.primary
    property real dimAlpha: 0.34
    property real glowAmount: 0.85
    property real activePositionSecs: UiState.smoothPositionSecs

    readonly property int contentLineCount: Math.max(1, plainText.lineCount)
    readonly property color sungLitColor: glowAmount > 0.01
        ? Qt.rgba(
            textColor.r + (accentColor.r - textColor.r) * 0.16 * Math.min(1, glowAmount),
            textColor.g + (accentColor.g - textColor.g) * 0.16 * Math.min(1, glowAmount),
            textColor.b + (accentColor.b - textColor.b) * 0.16 * Math.min(1, glowAmount),
            textColor.a
        )
        : textColor

    implicitWidth: plainText.implicitWidth
    implicitHeight: root.wordKaraokeActive
        ? Math.max(plainText.implicitHeight, wordFlow.implicitHeight)
        : plainText.implicitHeight

    StyledText {
        id: plainText
        width: root.width
        visible: !root.wordKaraokeActive
        text: root.lineText.length > 0 ? root.lineText : "♪"
        wrapMode: Text.Wrap
        font.pixelSize: root.fontPixelSize
        font.weight: root.fontWeight
        color: root.textColor
        opacity: {
            if (!root.synced) {
                return root.isHovered ? 1.0 : 0.90;
            }
            if (root.isCurrent) return 1.0;
            if (root.isHovered && root.hasTime) return 0.86;
            return root.isPast ? root.dimAlpha : 0.52;
        }

        Behavior on opacity {
            NumberAnimation { duration: Appearance.duration(260); easing.type: Easing.InOutQuad }
        }

        readonly property bool lineShaderActive: !root.wordKaraokeActive && root.isCurrent && root.synced && !Appearance.performanceMode
        layer.enabled: lineShaderActive
        layer.smooth: true
        layer.effect: ShaderEffect {
            property variant source
            property color accentColor: root.accentColor
            property color sungColor: root.textColor
            property size itemSize: Qt.size(plainText.width, plainText.height)
            property real progress: UiState.activeLyricProgress
            property real lineCount: Math.max(1, plainText.lineCount)
            property real textWidthFrac: plainText.width > 0
                ? Math.min(1.0, Math.max(0.06, plainText.contentWidth / plainText.width))
                : 1.0
            property real dimAlpha: Math.max(root.dimAlpha, 0.48)
            property real glowAmount: root.glowAmount
            property real zoomAmount: Appearance.reduceMotion ? 0.0 : 0.075
            property real padTop: plainText.topPadding
            property real padBottom: plainText.bottomPadding
            fragmentShader: "qrc:/shaders/lyric_karaoke.frag.qsb"
        }
    }

    Flow {
        id: wordFlow
        width: root.width
        visible: root.wordKaraokeActive
        spacing: 0

        Repeater {
            model: root.wordKaraokeActive ? root.wordTimings : []

            delegate: StyledText {
                id: wordItem
                required property var modelData
                readonly property real startS: Number(modelData.start)
                readonly property real endS: Math.max(startS + 0.05, Number(modelData.end))
                readonly property real wordProg: Math.max(0, Math.min(1, (root.activePositionSecs - startS) / (endS - startS)))
                readonly property bool isSinging: wordProg > 0.0 && wordProg < 1.0

                width: Math.min(implicitWidth, wordFlow.width)
                wrapMode: Text.Wrap
                text: String(modelData.text ?? "")
                font.pixelSize: root.fontPixelSize
                font.weight: root.fontWeight
                color: wordProg >= 1.0 ? root.sungLitColor : root.textColor
                opacity: isSinging ? 1.0 : (wordProg >= 1.0 ? 1.0 : root.dimAlpha)
                z: isSinging ? 1 : 0
                // Room inside the layer texture for glyphs lifted by the shader wave.
                topPadding: 4
                bottomPadding: 2

                layer.enabled: isSinging && !Appearance.performanceMode
                layer.smooth: true
                layer.effect: ShaderEffect {
                    property variant source
                    property color accentColor: root.accentColor
                    property color sungColor: root.textColor
                    property size itemSize: Qt.size(wordItem.width, wordItem.height)
                    property real progress: wordItem.wordProg
                    property real lineCount: Math.max(1, wordItem.lineCount)
                    property real textWidthFrac: wordItem.width > 0
                        ? Math.min(1.0, Math.max(0.06, wordItem.contentWidth / wordItem.width))
                        : 1.0
                    property real dimAlpha: root.dimAlpha
                    property real glowAmount: root.glowAmount
                    property real zoomAmount: Appearance.reduceMotion ? 0.0 : 0.075
                    property real padTop: wordItem.topPadding
                    property real padBottom: wordItem.bottomPadding
                    fragmentShader: "qrc:/shaders/lyric_karaoke.frag.qsb"
                }
            }
        }
    }
}
