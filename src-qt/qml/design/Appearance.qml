pragma Singleton
import QtQuick

QtObject {
    id: root

    // Reactive shell colors from ThemeManager
    readonly property var colors: themeManager

    readonly property string fontFamily: "Rubik"
    readonly property string monoFontFamily: "monospace"
    readonly property bool reduceMotion: !appSettings.motionEnabled

    component Rounding: QtObject {
        readonly property int unsharpen: 2
        readonly property int unsharpenMore: 6
        readonly property int verySmall: 8
        readonly property int small: 12
        readonly property int normal: 17
        readonly property int large: 23
        readonly property int veryLarge: 30
        readonly property int full: 9999
        readonly property int window: 18
    }
    readonly property Rounding rounding: Rounding {}

    component FontSizes: QtObject {
        readonly property int smallest: 10
        readonly property int smaller: 12
        readonly property int small: 14
        readonly property int normal: 15
        readonly property int large: 17
        readonly property int larger: 19
        readonly property int huge: 22
        readonly property int title: 22
        readonly property int headline: 28
        readonly property int display: 34
    }
    readonly property FontSizes fontSize: FontSizes {}

    component Sizes: QtObject {
        readonly property real elevationMargin: 10
        readonly property real pageMargin: 28
        readonly property real sectionGap: 24
        readonly property real shelfGap: 16
        readonly property real cardSize: 176
        readonly property real headerArtwork: 200
        readonly property real artworkRadius: 14
        readonly property real smallArtworkRadius: 8
        readonly property real topBarHeight: 60
        readonly property real playerBarClearance: 110
    }
    readonly property Sizes sizes: Sizes {}

    component Curves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
        readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
    }
    readonly property Curves curves: Curves {}

    function duration(ms) {
        return ms;
    }

    function motion(ms) {
        return ms;
    }
}
