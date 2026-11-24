pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property string slotName: ""
    property string filterModId: ""
    property var slotContext: ({})
    /// "fill" (overlay/full-area), "column" (vertical flow, e.g. settings), or "row" (horizontal flow, e.g. playerBar)
    property string layoutMode: "fill"
    property real spacing: 12

    readonly property var entries: {
        const _rev = ModManager.reloadRevision;
        if (!root.slotName || root.slotName.length === 0) return [];
        const list = ModManager.slotEntries(root.slotName);
        if (!root.filterModId || root.filterModId.length === 0) return list;
        return list.filter(item => item.modId === root.filterModId);
    }

    implicitWidth: layoutMode === "row" ? rowHost.implicitWidth : 0
    implicitHeight: layoutMode === "column" ? colHost.implicitHeight : (layoutMode === "row" ? rowHost.implicitHeight : 0)

    component ModEntryLoader: Loader {
        id: modLoader
        required property var entryData
        property string loadedKey: ""

        function loadEntry() {
            if (!entryData || !entryData.sourceUrl) return;
            const key = entryData.modId + "|" + String(entryData.sourceUrl) + "|" + ModManager.reloadRevision;
            if (key === loadedKey) return;
            loadedKey = key;
            setSource(entryData.sourceUrl, {
                modApi: entryData.api,
                slotContext: root.slotContext
            });
        }

        Component.onCompleted: loadEntry()
        onEntryDataChanged: loadEntry()

        onStatusChanged: {
            if (status === Loader.Error && entryData) {
                ModManager.reportModError(
                    entryData.modId,
                    "Ошибка загрузки слота '" + root.slotName + "': " + String(entryData.sourceUrl)
                );
            }
        }
    }

    Repeater {
        model: root.layoutMode === "fill" ? root.entries : []
        delegate: ModEntryLoader {
            required property var modelData
            entryData: modelData
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
            delegate: ModEntryLoader {
                required property var modelData
                readonly property Item loadedItem: item as Item
                entryData: modelData
                width: colHost.width
                height: loadedItem ? Math.max(loadedItem.implicitHeight, loadedItem.height) : 0
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
            delegate: ModEntryLoader {
                required property var modelData
                readonly property Item loadedItem: item as Item
                entryData: modelData
                anchors.verticalCenter: parent.verticalCenter
                width: loadedItem ? Math.max(loadedItem.implicitWidth, loadedItem.width) : 0
                height: loadedItem ? Math.max(loadedItem.implicitHeight, loadedItem.height) : rowHost.height
            }
        }
    }
}
