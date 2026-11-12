pragma Singleton
import QtQuick

QtObject {
    id: root

    // Reactive shell colors from ThemeManager
    readonly property var colors: themeManager

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
