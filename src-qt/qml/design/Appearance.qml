pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

// Design tokens matching Swiftify: rounding, typography, motion curves, zoom and sizes.
// Colours live in Theme (C++), which follows the active preset or desktop scheme.
QtObject {
    id: root

    final readonly property MaterialScheme colors: Theme.colors
    /// Nothing moves of its own accord over and over when reduced motion or performance mode is on.
    final readonly property bool reduceMotion: appSettings.reduceMotion || appSettings.performanceMode || !appSettings.motionEnabled
    /// Performance mode disables all animations and fades.
    final readonly property bool performanceMode: appSettings.performanceMode
    final readonly property real zoom: appSettings.zoom

    component Rounding: QtObject {
        final readonly property int unsharpen: 2
        final readonly property int unsharpenMore: 6
        final readonly property int verySmall: 8
        final readonly property int small: 12
        final readonly property int normal: 17
        final readonly property int large: 23
        final readonly property int veryLarge: 30
        final readonly property int full: 9999
        final readonly property int window: 18
    }
    final readonly property Rounding rounding: Rounding {}

    component FontSizes: QtObject {
        final readonly property int smallest: 10
        final readonly property int smaller: 12
        final readonly property int smallie: 13
        final readonly property int small: 15
        final readonly property int normal: 16
        final readonly property int large: 17
        final readonly property int larger: 19
        final readonly property int huge: 22
        final readonly property int hugeAss: 23
        final readonly property int title: 22
        final readonly property int headline: 30
        final readonly property int display: 36
    }
    final readonly property FontSizes fontSize: FontSizes {}

    final readonly property string fontFamily: Theme.fontFamily
    final readonly property string monoFontFamily: Theme.monoFontFamily
    final readonly property string iconFontFamily: "Material Symbols Rounded"

    // Material 3 Expressive bezier control points for Easing.BezierSpline.
    component Curves: QtObject {
        final readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
        final readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
        final readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
        final readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
        final readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        final readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        final readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        final readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        final readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        final readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
    }
    final readonly property Curves curves: Curves {}

    function duration(milliseconds: int): int {
        return performanceMode ? 0 : milliseconds
    }

    function motion(milliseconds: int): int {
        return performanceMode ? 0 : milliseconds
    }

    function fadeable(color: color, other: color): color {
        return color.a > 0 ? color : Qt.alpha(other, 0)
    }

    component Sizes: QtObject {
        final readonly property real elevationMargin: 10
        final readonly property real pageMargin: 32
        final readonly property real sectionGap: 32
        final readonly property real shelfGap: 16
        final readonly property real cardSize: 176
        final readonly property real headerArtwork: 232
        final readonly property real artworkRadius: 12
        final readonly property real smallArtworkRadius: 7
        final readonly property real sideSheetWidth: 320
        final readonly property real topBarHeight: 64
        final readonly property real playerBarClearance: 120
    }
    final readonly property Sizes sizes: Sizes {}
}
