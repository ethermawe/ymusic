pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property var colors: ({
        background: "#0a0c10",
        surface: "#12151c",
        surfaceDim: "#0e1015",
        surfaceBright: "#232733",
        surfaceContainerLowest: "#08090d",
        surfaceContainerLow: "#141720",
        surfaceContainer: "#191d28",
        surfaceContainerHigh: "#212635",
        surfaceContainerHighest: "#2b3144",
        onSurface: "#f0f2f8",
        onSurfaceVariant: "#9ea3b5",
        outline: "#4b5166",
        outlineVariant: "#262b3a",
        primary: "#fc3f1d",
        primaryHover: "#ff583b",
        onPrimary: "#ffffff",
        primaryContainer: "#45140b",
        onPrimaryContainer: "#ffdad4",
        secondary: "#e59b24",
        secondaryContainer: "#362712",
        tertiary: "#36c39f",
        error: "#ff5449"
    })

    component Rounding: QtObject {
        readonly property int verySmall: 6
        readonly property int small: 10
        readonly property int normal: 16
        readonly property int large: 22
        readonly property int veryLarge: 30
        readonly property int full: 9999
    }
    readonly property Rounding rounding: Rounding {}

    component FontSizes: QtObject {
        readonly property int smallest: 11
        readonly property int smaller: 12
        readonly property int small: 14
        readonly property int normal: 15
        readonly property int large: 18
        readonly property int title: 22
        readonly property int display: 32
    }
    readonly property FontSizes fontSize: FontSizes {}

    function duration(ms) {
        return ms;
    }
}
