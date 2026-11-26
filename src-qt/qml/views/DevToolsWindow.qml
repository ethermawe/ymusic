pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ymusic.ui

Window {
    id: win

    required property Item sceneRoot
    property var evalJs: null
    property bool picking: false
    property bool showModSlots: false
    property var inspectedItem: null
    property var inspectedInfo: ({})

    signal previewWhatsNewRequested()
    signal showToastRequested(string message)

    // Unslop neutral graphite engineer ramp
    readonly property color colBg: "#111214"
    readonly property color colSurface: "#17181c"
    readonly property color colRaised: "#1e2026"
    readonly property color colHairline: Qt.rgba(1, 1, 1, 0.08)
    readonly property color colHairlineStrong: Qt.rgba(1, 1, 1, 0.14)
    readonly property color colText: "#eceef2"
    readonly property color colSecondary: "#9aa0ab"
    readonly property color colMuted: "#676d78"
    readonly property color colAccent: Appearance.colors.primary
    readonly property color colWarn: "#e0a458"
    readonly property color colErr: "#e06c75"
    readonly property color colOk: "#6cc070"

    property int activeTab: 0
    property string logFilter: "all"
    property string logQuery: ""
    property var replHistory: []
    property int replHistoryIndex: -1

    // Live frame timing metrics (only active while window is visible)
    property int fps: 0
    property real frameMs: 0
    property int itemCount: 0
    property var frameHistory: []
    property int _frameCounter: 0
    property double _lastSampleMs: 0

    width: 840
    height: 560
    minimumWidth: 640
    minimumHeight: 420
    title: "ymusic — DevTools"
    color: colBg
    visible: false

    function openWindow() {
        visible = true;
        raise();
        requestActivate();
        refreshAll();
    }

    function toggleWindow() {
        if (visible) {
            visible = false;
            picking = false;
        } else {
            openWindow();
        }
    }

    function selectInspectedItem(item) {
        inspectedItem = item;
        inspectedInfo = item ? devTools.inspectItem(item, sceneRoot) : ({});
        if (item) {
            activeTab = 1;
            if (!visible) openWindow();
            else {
                raise();
                requestActivate();
            }
        }
    }

    function refreshAll() {
        devTools.refreshMetrics();
        itemCount = sceneRoot ? devTools.countItems(sceneRoot) : 0;
        if (inspectedItem) {
            inspectedInfo = devTools.inspectItem(inspectedItem, sceneRoot);
        }
    }

    function runRepl(rawCode) {
        const code = rawCode.trim();
        if (code.length === 0) return;
        const nextHist = replHistory.slice();
        if (nextHist.length === 0 || nextHist[nextHist.length - 1] !== code) {
            nextHist.push(code);
            if (nextHist.length > 50) nextHist.shift();
        }
        replHistory = nextHist;
        replHistoryIndex = nextHist.length;
        devTools.appendConsoleEntry("js", "repl", "> " + code);
        if (typeof evalJs === "function") {
            const res = evalJs(code);
            if (res && res.ok) {
                devTools.appendConsoleEntry("result", "repl", res.output);
            } else {
                devTools.appendConsoleEntry("error", "repl", res ? res.output : "Eval failed");
            }
        }
    }

    readonly property var mergedLogs: {
        const out = [];
        const qtLogs = devTools.logs || [];
        for (let i = 0; i < qtLogs.length; ++i) {
            out.push(qtLogs[i]);
        }
        const modLogs = ModManager.logs || [];
        for (let j = 0; j < modLogs.length; ++j) {
            const m = modLogs[j];
            out.push({
                time: m.time || "",
                level: m.level || "info",
                source: "mod:" + (m.modId || "core"),
                message: m.message || ""
            });
        }
        const q = logQuery.trim().toLowerCase();
        return out.filter((entry) => {
            const lvl = (entry.level || "info").toLowerCase();
            const src = (entry.source || "").toLowerCase();
            if (logFilter === "warn" && lvl !== "warn") return false;
            if (logFilter === "error" && lvl !== "error") return false;
            if (logFilter === "mods" && !src.startsWith("mod:")) return false;
            if (q.length > 0) {
                const hay = (entry.message + " " + entry.source + " " + entry.level).toLowerCase();
                if (hay.indexOf(q) < 0) return false;
            }
            return true;
        });
    }

    onVisibleChanged: {
        if (visible) {
            _lastSampleMs = Date.now();
            _frameCounter = 0;
            refreshAll();
        } else {
            picking = false;
        }
    }

    FrameAnimation {
        running: win.visible
        onTriggered: {
            win._frameCounter += 1;
            const now = Date.now();
            const dt = now - win._lastSampleMs;
            if (dt >= 500) {
                const curFps = Math.round((win._frameCounter * 1000) / dt);
                const curMs = win._frameCounter > 0 ? (dt / win._frameCounter) : 0;
                win.fps = curFps;
                win.frameMs = Number(curMs.toFixed(1));
                const next = win.frameHistory.slice();
                next.push(win.frameMs);
                if (next.length > 48) next.shift();
                win.frameHistory = next;
                win._frameCounter = 0;
                win._lastSampleMs = now;
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: win.visible
        onTriggered: win.refreshAll()
    }

    Shortcut { sequence: "F12"; onActivated: win.toggleWindow() }
    Shortcut { sequence: "Ctrl+Shift+I"; onActivated: win.toggleWindow() }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: win.picking = !win.picking }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top toolbar (40px, 1px hairline bottom)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: win.colSurface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 12
                spacing: 4

                // Tab strip
                Repeater {
                    model: ["Console", "Inspector", "State", "Perf"]

                    delegate: Item {
                        required property int index
                        required property string modelData
                        readonly property bool active: win.activeTab === index

                        Layout.preferredWidth: tabLabel.implicitWidth + 20
                        Layout.fillHeight: true

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.family: Appearance.fontFamily
                            font.pixelSize: 13
                            font.weight: active ? Font.Medium : Font.Normal
                            color: active ? win.colText : win.colSecondary
                        }

                        Rectangle {
                            visible: active
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            color: win.colAccent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.activeTab = index
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Live mono telemetry readout
                Text {
                    text: win.fps + " fps · " + win.frameMs.toFixed(1) + " ms · "
                        + devTools.memoryPssMb.toFixed(0) + " MB · " + devTools.graphicsApi
                    font.family: Appearance.monoFontFamily
                    font.pixelSize: 11
                    color: win.colMuted
                    Layout.rightMargin: 8
                }

                // Element picker button
                Rectangle {
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: pickBtnText.implicitWidth + 16
                    radius: 6
                    color: win.picking ? win.colAccent : win.colRaised
                    border.width: 1
                    border.color: win.picking ? win.colAccent : win.colHairline

                    Text {
                        id: pickBtnText
                        anchors.centerIn: parent
                        text: "Pick"
                        font.family: Appearance.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: win.picking ? Appearance.colors.onPrimary : win.colText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.picking = !win.picking
                    }
                }

                // Mod slots overlay toggle
                Rectangle {
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: slotsBtnText.implicitWidth + 16
                    radius: 6
                    color: win.showModSlots ? "#3a2d18" : win.colRaised
                    border.width: 1
                    border.color: win.showModSlots ? win.colWarn : win.colHairline

                    Text {
                        id: slotsBtnText
                        anchors.centerIn: parent
                        text: "Slots"
                        font.family: Appearance.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: win.showModSlots ? "#f4c97a" : win.colText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.showModSlots = !win.showModSlots
                    }
                }

                // Hot Reload Mods
                Rectangle {
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: reloadBtnText.implicitWidth + 16
                    radius: 6
                    color: win.colRaised
                    border.width: 1
                    border.color: win.colHairline

                    Text {
                        id: reloadBtnText
                        anchors.centerIn: parent
                        text: "Reload"
                        font.family: Appearance.fontFamily
                        font.pixelSize: 12
                        color: win.colText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ModManager.reloadMods();
                            win.showToastRequested("Моды перезагружены");
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: win.colHairline
            }
        }

        // Main tab viewport
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ================================================================
            // TAB 0: CONSOLE + JS REPL
            // ================================================================
            ColumnLayout {
                anchors.fill: parent
                visible: win.activeTab === 0
                spacing: 0

                // Filter strip (36px)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: win.colBg

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "all", label: "All" },
                                { id: "warn", label: "Warn" },
                                { id: "error", label: "Error" },
                                { id: "mods", label: "Mods" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: win.logFilter === modelData.id
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: fText.implicitWidth + 14
                                radius: 5
                                color: selected ? win.colRaised : "transparent"
                                border.width: 1
                                border.color: selected ? win.colHairlineStrong : "transparent"

                                Text {
                                    id: fText
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: Appearance.fontFamily
                                    font.pixelSize: 12
                                    color: selected ? win.colText : win.colSecondary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.logFilter = modelData.id
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: 5
                            color: win.colSurface
                            border.width: 1
                            border.color: searchInput.activeFocus ? win.colAccent : win.colHairline

                            TextInput {
                                id: searchInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 12
                                color: win.colText
                                selectionColor: win.colAccent
                                onTextChanged: win.logQuery = text
                                clip: true

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Filter logs..."
                                    font: searchInput.font
                                    color: win.colMuted
                                    visible: searchInput.text.length === 0
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: clearTxt.implicitWidth + 14
                            radius: 5
                            color: win.colRaised
                            border.width: 1
                            border.color: win.colHairline

                            Text {
                                id: clearTxt
                                anchors.centerIn: parent
                                text: "Clear"
                                font.family: Appearance.fontFamily
                                font.pixelSize: 12
                                color: win.colSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    devTools.clearLogs();
                                    ModManager.clearLogs();
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: win.colHairline
                    }
                }

                // Log list
                ListView {
                    id: logList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: win.mergedLogs
                    onCountChanged: Qt.callLater(() => logList.positionViewAtEnd())

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: logList.width
                        height: Math.max(24, msgText.implicitHeight + 8)
                        color: index % 2 === 0 ? win.colBg : "#141519"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                Layout.preferredWidth: 74
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                text: modelData.time || ""
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 11
                                color: win.colMuted
                            }

                            Text {
                                Layout.preferredWidth: 42
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                text: (modelData.level || "info").toUpperCase()
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: {
                                    const l = (modelData.level || "").toLowerCase();
                                    if (l === "error") return win.colErr;
                                    if (l === "warn") return win.colWarn;
                                    if (l === "result") return win.colOk;
                                    if (l === "js") return win.colAccent;
                                    return win.colSecondary;
                                }
                            }

                            Text {
                                Layout.preferredWidth: 72
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                text: modelData.source || ""
                                elide: Text.ElideRight
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 11
                                color: win.colMuted
                            }

                            Text {
                                id: msgText
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                text: modelData.message || ""
                                wrapMode: Text.WrapAnywhere
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 12
                                color: win.colText
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onDoubleClicked: {
                                devTools.copyToClipboard(modelData.message || "");
                                win.showToastRequested("Строка скопирована");
                            }
                        }
                    }
                }

                // Interactive JS REPL bar (36px)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: win.colSurface

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: win.colHairline
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: ">"
                            font.family: Appearance.monoFontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: win.colAccent
                        }

                        TextInput {
                            id: replInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Appearance.monoFontFamily
                            font.pixelSize: 12
                            color: win.colText
                            selectionColor: win.colAccent
                            clip: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "JS eval (window, backend, appSettings, UiState, Appearance, ModManager)..."
                                font: replInput.font
                                color: win.colMuted
                                visible: replInput.text.length === 0
                            }

                            Keys.onReturnPressed: {
                                win.runRepl(text);
                                text = "";
                            }
                            Keys.onEnterPressed: {
                                win.runRepl(text);
                                text = "";
                            }
                            Keys.onUpPressed: {
                                if (win.replHistory.length === 0) return;
                                win.replHistoryIndex = Math.max(0, win.replHistoryIndex - 1);
                                text = win.replHistory[win.replHistoryIndex] || "";
                            }
                            Keys.onDownPressed: {
                                if (win.replHistory.length === 0) return;
                                win.replHistoryIndex = Math.min(win.replHistory.length, win.replHistoryIndex + 1);
                                text = win.replHistoryIndex < win.replHistory.length
                                    ? win.replHistory[win.replHistoryIndex]
                                    : "";
                            }
                        }
                    }
                }
            }

            // ================================================================
            // TAB 1: UI INSPECTOR
            // ================================================================
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 1
                spacing: 12

                // Breadcrumb chain
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: win.inspectedInfo && win.inspectedInfo.chain && win.inspectedInfo.chain.length > 0

                    Repeater {
                        model: (win.inspectedInfo && win.inspectedInfo.chain) ? win.inspectedInfo.chain : []

                        delegate: Rectangle {
                            required property var modelData
                            height: 24
                            width: crumbText.implicitWidth + 14
                            radius: 5
                            color: modelData.stepsUp === 0 ? win.colRaised : win.colSurface
                            border.width: 1
                            border.color: modelData.stepsUp === 0 ? win.colAccent : win.colHairline

                            Text {
                                id: crumbText
                                anchors.centerIn: parent
                                text: (modelData.type || "Item") + (modelData.objectName ? ("#" + modelData.objectName) : "")
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 11
                                color: modelData.stepsUp === 0 ? win.colText : win.colSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const anc = devTools.ancestorAt(win.inspectedItem, modelData.stepsUp);
                                    if (anc) win.selectInspectedItem(anc);
                                }
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !win.inspectedItem

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Элемент не выбран"
                            font.family: Appearance.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: win.colText
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Нажмите Pick или Ctrl+Shift+C и кликните по любому элементу в окне плеера"
                            font.family: Appearance.fontFamily
                            font.pixelSize: 13
                            color: win.colSecondary
                        }
                    }
                }

                // Properties table
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.inspectedItem !== null
                    radius: 8
                    color: win.colSurface
                    border.width: 1
                    border.color: win.colHairline

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Action bar
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 12
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: (win.inspectedInfo.type || "Item")
                                    + (win.inspectedInfo.objectName ? (" #" + win.inspectedInfo.objectName) : "")
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: win.colText
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: visBtn.implicitWidth + 14
                                radius: 5
                                color: win.colRaised
                                border.width: 1
                                border.color: win.colHairline

                                Text {
                                    id: visBtn
                                    anchors.centerIn: parent
                                    text: win.inspectedInfo.visible ? "Hide" : "Show"
                                    font.family: Appearance.fontFamily
                                    font.pixelSize: 12
                                    color: win.colText
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (win.inspectedItem) {
                                            win.inspectedItem.visible = !win.inspectedItem.visible;
                                            win.refreshAll();
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: copyJsonBtn.implicitWidth + 14
                                radius: 5
                                color: win.colRaised
                                border.width: 1
                                border.color: win.colHairline

                                Text {
                                    id: copyJsonBtn
                                    anchors.centerIn: parent
                                    text: "Copy JSON"
                                    font.family: Appearance.fontFamily
                                    font.pixelSize: 12
                                    color: win.colText
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        devTools.copyToClipboard(JSON.stringify(win.inspectedInfo, null, 2));
                                        win.showToastRequested("JSON скопирован");
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.colHairline }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: {
                                const d = win.inspectedInfo || {};
                                const rows = [
                                    { k: "class", v: d.rawClass || "" },
                                    { k: "objectName", v: d.objectName || "—" },
                                    { k: "geometry", v: Math.round(d.x || 0) + ", " + Math.round(d.y || 0) + "  (" + Math.round(d.width || 0) + " × " + Math.round(d.height || 0) + ")" },
                                    { k: "scene", v: Math.round(d.sceneX || 0) + ", " + Math.round(d.sceneY || 0) },
                                    { k: "visible / opacity", v: String(Boolean(d.visible)) + " · " + Number(d.opacity || 0).toFixed(2) },
                                    { k: "z / clip / children", v: String(d.z || 0) + " · " + String(Boolean(d.clip)) + " · " + String(d.childCount || 0) }
                                ];
                                if (d.color) rows.push({ k: "color", v: d.color, swatch: d.color });
                                if (d.text) rows.push({ k: "text", v: d.text });
                                if (d.slotName) rows.push({ k: "slotName", v: d.slotName });
                                return rows;
                            }

                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width
                                height: 30
                                color: "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    Text {
                                        Layout.preferredWidth: 140
                                        text: modelData.k
                                        font.family: Appearance.monoFontFamily
                                        font.pixelSize: 12
                                        color: win.colSecondary
                                    }
                                    Rectangle {
                                        visible: Boolean(modelData.swatch)
                                        Layout.preferredWidth: 12
                                        Layout.preferredHeight: 12
                                        radius: 3
                                        color: modelData.swatch || "transparent"
                                        border.width: 1
                                        border.color: win.colHairlineStrong
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.v
                                        elide: Text.ElideRight
                                        font.family: Appearance.monoFontFamily
                                        font.pixelSize: 12
                                        color: win.colText
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: win.colHairline
                                }
                            }
                        }
                    }
                }
            }

            // ================================================================
            // TAB 2: STATE & PALETTE TOKENS
            // ================================================================
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 2
                spacing: 12

                // Left: Backend & Mods state
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: win.colSurface
                    border.width: 1
                    border.color: win.colHairline

                    ListView {
                        anchors.fill: parent
                        clip: true
                        model: [
                            { k: "version", v: updater.currentVersion },
                            { k: "loggedIn", v: String(backend.loggedIn) },
                            { k: "page", v: String(backend.page) + (UiState.activeModPageId ? (" (mod:" + UiState.activeModPageId + ")") : "") },
                            { k: "playing / buffering", v: String(backend.playing) + " / " + String(backend.buffering) },
                            { k: "trackId", v: backend.nowTrackId || "—" },
                            { k: "track", v: backend.hasTrack ? (backend.nowTitle + " — " + backend.nowArtists) : "—" },
                            { k: "position", v: Math.floor(backend.positionSecs) + "s / " + Math.floor(backend.durationSecs) + "s" },
                            { k: "audioQuality", v: backend.audioQuality || "—" },
                            { k: "downloadQuality", v: backend.downloadQuality || "—" },
                            { k: "volume / zoom", v: Math.round(backend.volume * 100) + "% · " + Math.round(appSettings.zoom * 100) + "%" },
                            { k: "mods", v: ModManager.activeModCount + " active · " + ModManager.activeOverrideCount + " overrides · rev " + ModManager.reloadRevision },
                            { k: "lastfm", v: backend.lastfmConnected ? ("connected (" + backend.lastfmUsername + ")") : (backend.lastfmHasBuiltinKeys ? "ready (builtin keys)" : "no keys") }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 30
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    Layout.preferredWidth: 132
                                    text: modelData.k
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: win.colSecondary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    elide: Text.ElideRight
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 12
                                    color: win.colText
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: win.colHairline
                            }
                        }
                    }
                }

                // Right: Live Appearance.colors palette tokens
                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    radius: 8
                    color: win.colSurface
                    border.width: 1
                    border.color: win.colHairline

                    ListView {
                        anchors.fill: parent
                        clip: true
                        model: [
                            { name: "primary", col: Appearance.colors.primary },
                            { name: "onPrimary", col: Appearance.colors.onPrimary },
                            { name: "primaryContainer", col: Appearance.colors.primaryContainer },
                            { name: "secondary", col: Appearance.colors.secondary },
                            { name: "secondaryContainer", col: Appearance.colors.secondaryContainer },
                            { name: "surface", col: Appearance.colors.surface },
                            { name: "surfaceContainer", col: Appearance.colors.surfaceContainer },
                            { name: "surfaceContainerHigh", col: Appearance.colors.surfaceContainerHigh },
                            { name: "onSurface", col: Appearance.colors.onSurface },
                            { name: "onSurfaceVariant", col: Appearance.colors.onSurfaceVariant },
                            { name: "layer0", col: Appearance.colors.layer0 },
                            { name: "layer1", col: Appearance.colors.layer1 },
                            { name: "outlineVariant", col: Appearance.colors.outlineVariant },
                            { name: "error", col: Appearance.colors.error }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 30
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    radius: 3
                                    color: modelData.col
                                    border.width: 1
                                    border.color: win.colHairlineStrong
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: win.colText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: String(modelData.col)
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: win.colMuted
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    devTools.copyToClipboard(String(modelData.col));
                                    win.showToastRequested("Скопировано " + String(modelData.col));
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: win.colHairline
                            }
                        }
                    }
                }
            }

            // ================================================================
            // TAB 3: PERFORMANCE & TOOLS
            // ================================================================
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 3
                spacing: 12

                // 4 clean numeric stat cards (no icons, no fluff)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "FPS", value: String(win.fps), sub: win.frameMs.toFixed(1) + " ms / frame" },
                            { label: "Memory PSS", value: devTools.memoryPssMb.toFixed(1) + " MB", sub: "RSS " + devTools.memoryRssMb.toFixed(1) + " MB" },
                            { label: "Scene Items", value: String(win.itemCount), sub: devTools.graphicsApi },
                            { label: "Runtime", value: "Qt " + devTools.qtVersion, sub: "v" + updater.currentVersion }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            radius: 8
                            color: win.colSurface
                            border.width: 1
                            border.color: win.colHairline

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4

                                Text {
                                    text: modelData.label
                                    font.family: Appearance.fontFamily
                                    font.pixelSize: 11
                                    color: win.colSecondary
                                }
                                Text {
                                    text: modelData.value
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 20
                                    font.weight: Font.Medium
                                    color: win.colText
                                }
                                Text {
                                    text: modelData.sub
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: win.colMuted
                                }
                            }
                        }
                    }
                }

                // Frame time bar chart (single accent, muted 16.6ms target line)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: win.colSurface
                    border.width: 1
                    border.color: win.colHairline

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 12
                        text: "Frame time (ms) · target 16.6 ms"
                        font.family: Appearance.monoFontFamily
                        font.pixelSize: 11
                        color: win.colSecondary
                    }

                    Item {
                        id: chartArea
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 36
                        anchors.bottomMargin: 12

                        // 16.6ms reference hairline (scale 0..40ms)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            y: parent.height * (1.0 - 16.6 / 40.0)
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.12)
                        }

                        Row {
                            anchors.fill: parent
                            spacing: 3

                            Repeater {
                                model: win.frameHistory

                                delegate: Item {
                                    required property real modelData
                                    width: Math.max(4, (chartArea.width - 47 * 3) / 48)
                                    height: chartArea.height

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: Math.max(2, Math.min(parent.height, parent.height * (modelData / 40.0)))
                                        radius: 2
                                        color: modelData > 24.0 ? win.colErr : win.colAccent
                                        opacity: 0.85
                                    }
                                }
                            }
                        }
                    }
                }

                // Quick developer actions
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "gc", label: "Run GC" },
                            { id: "reload", label: "Hot Reload Mods (Ctrl+Shift+R)" },
                            { id: "logs", label: "Open Logs Folder" },
                            { id: "mods", label: "Open Mods Folder" },
                            { id: "whatsnew", label: "Preview What's New" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            height: 30
                            width: actText.implicitWidth + 20
                            radius: 6
                            color: win.colRaised
                            border.width: 1
                            border.color: win.colHairline

                            Text {
                                id: actText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Appearance.fontFamily
                                font.pixelSize: 12
                                color: win.colText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.id === "gc") {
                                        devTools.collectGarbage();
                                        win.refreshAll();
                                        win.showToastRequested("GC выполнен");
                                    } else if (modelData.id === "reload") {
                                        ModManager.reloadMods();
                                        win.showToastRequested("Моды перезагружены");
                                    } else if (modelData.id === "logs") {
                                        appSettings.openLogsFolder();
                                    } else if (modelData.id === "mods") {
                                        ModManager.openModsFolder();
                                    } else if (modelData.id === "whatsnew") {
                                        win.previewWhatsNewRequested();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
