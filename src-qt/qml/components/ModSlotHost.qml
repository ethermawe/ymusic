pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property string slotName: ""
    property string filterModId: ""
    property var slotContext: ({})

    readonly property var entries: {
        const _rev = ModManager.reloadRevision;
        if (!root.slotName || root.slotName.length === 0) return [];
        const list = ModManager.slotEntries(root.slotName);
        if (!root.filterModId || root.filterModId.length === 0) return list;
        return list.filter(item => item.modId === root.filterModId);
    }

    Repeater {
        model: root.entries

        delegate: Loader {
            id: modLoader
            required property var modelData
            property string loadedKey: ""
            anchors.fill: parent

            function loadEntry() {
                if (!modelData || !modelData.sourceUrl) return;
                const key = modelData.modId + "|" + String(modelData.sourceUrl) + "|" + ModManager.reloadRevision;
                if (key === loadedKey) return;
                loadedKey = key;
                setSource(modelData.sourceUrl, {
                    modApi: modelData.api,
                    slotContext: root.slotContext
                });
            }

            Component.onCompleted: loadEntry()
            onModelDataChanged: loadEntry()

            onStatusChanged: {
                if (status === Loader.Error && modelData) {
                    ModManager.reportModError(
                        modelData.modId,
                        "Ошибка загрузки слота '" + root.slotName + "': " + String(modelData.sourceUrl)
                    );
                }
            }
        }
    }
}
