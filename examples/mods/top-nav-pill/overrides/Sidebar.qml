pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

// Collapsed sidebar override: hands full width to the main sheet while TopNavPill handles navigation.
Item {
    id: root

    readonly property int activePage: UiState.activeModPageId.length > 0 ? -1 : Backend.page
    property bool compact: true
    property real expandedWidth: 0
    property bool resizing: false
    property bool toggleVisible: false
    readonly property bool isCompact: true
    signal settingsRequested()
    signal toggleCompactRequested()

    implicitWidth: 0
    width: 0
    visible: false
}
