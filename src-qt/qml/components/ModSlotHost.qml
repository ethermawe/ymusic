pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property string slotName: ""
    property string filterModId: ""
    property string filterEntryId: ""
    property var slotContext: ({})
    /// "fill" (overlay/full-area), "column" (vertical flow, e.g. settings), or "row" (horizontal flow, e.g. playerBar)
    property string layoutMode: "fill"
    property real spacing: 12

    readonly property var entries: {
        const _rev = ModManager.reloadRevision;
        if (!root.slotName || root.slotName.length === 0) return [];
        const list = ModManager.slotEntries(root.slotName);
        if (root.filterEntryId && root.filterEntryId.length > 0) {
            return list.filter(item => (item.entryId || item.modId) === root.filterEntryId);
        }
        if (root.filterModId && root.filterModId.length > 0) {
            return list.filter(item => item.modId === root.filterModId);
        }
        return list;
    }

    implicitWidth: layoutMode === "row" ? rowHost.implicitWidth : 0
    implicitHeight: layoutMode === "column" ? colHost.implicitHeight : (layoutMode === "row" ? rowHost.implicitHeight : 0)

    Repeater {
        model: root.layoutMode === "fill" ? root.entries : []
        delegate: ModSlotItem {
            required property var modelData
            modId: modelData.modId || ""
            slotName: root.slotName
            sourceUrl: modelData.sourceUrl || ""
            slotContext: root.slotContext || ({})
            reloadRevision: ModManager.reloadRevision
            fillContent: true
            fitWidth: false
            anchors.fill: parent
        }
    }

    Column {
        id: colHost
        visible: root.layoutMode === "column"
        width: parent.width
        spacing: root.spacing

        Repeater {
            model: root.layoutMode === "column" ? root.entries : []
            delegate: ModSlotItem {
                required property var modelData
                modId: modelData.modId || ""
                slotName: root.slotName
                sourceUrl: modelData.sourceUrl || ""
                slotContext: root.slotContext || ({})
                reloadRevision: ModManager.reloadRevision
                fillContent: false
                fitWidth: true
                width: colHost.width
                height: implicitHeight
            }
        }
    }

    Row {
        id: rowHost
        visible: root.layoutMode === "row"
        height: parent.height
        spacing: root.spacing

        Repeater {
            model: root.layoutMode === "row" ? root.entries : []
            delegate: ModSlotItem {
                required property var modelData
                modId: modelData.modId || ""
                slotName: root.slotName
                sourceUrl: modelData.sourceUrl || ""
                slotContext: root.slotContext || ({})
                reloadRevision: ModManager.reloadRevision
                fillContent: false
                fitWidth: false
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                width: implicitWidth
                height: implicitHeight > 0 ? implicitHeight : rowHost.height
            }
        }
    }
}
