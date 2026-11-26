pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
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

    property int activeTab: 0
    property string logFilter: "all"
    property string logQuery: ""
    property var replHistory: []
    property int replHistoryIndex: -1

    property int fps: 0
    property real frameMs: 0
    property int itemCount: 0
    property var frameHistory: []
    property int _frameCounter: 0
    property double _lastSampleMs: 0

    width: 860
    height: 580
    minimumWidth: 660
    minimumHeight: 440
    title: "Инструменты разработчика — Yandex Music"
    color: Appearance.colors.layer0
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
                devTools.appendConsoleEntry("error", "repl", res ? res.output : "Ошибка выполнения");
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
        anchors.margins: 12
        spacing: 12

        // Top M3 Expressive toolbar
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            SegmentedControl {
                currentIndex: win.activeTab
                onActivated: (index) => win.activeTab = index
                segments: [
                    Segment { text: "Консоль"; symbol: "terminal" },
                    Segment { text: "Инспектор"; symbol: "ads_click" },
                    Segment { text: "Состояние"; symbol: "tune" },
                    Segment { text: "Нагрузка"; symbol: "speed" }
                ]
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: win.fps + " fps · " + win.frameMs.toFixed(1) + " мс · "
                    + devTools.memoryPssMb.toFixed(0) + " МБ · " + devTools.graphicsApi
                font.family: Appearance.monoFontFamily
                font.pixelSize: Appearance.fontSize.smaller
                color: Appearance.colors.onSurfaceVariant
            }

            IconButton {
                symbol: "ads_click"
                size: 36
                iconSize: 19
                toggled: win.picking
                tooltip: "Выбрать элемент (Ctrl+Shift+C)"
                onClicked: win.picking = !win.picking
            }

            IconButton {
                symbol: "grid_view"
                size: 36
                iconSize: 19
                toggled: win.showModSlots
                tooltip: "Показать UI-слоты модов"
                onClicked: win.showModSlots = !win.showModSlots
            }

            IconButton {
                symbol: "refresh"
                size: 36
                iconSize: 19
                tooltip: "Перезагрузить моды (Ctrl+Shift+R)"
                onClicked: {
                    ModManager.reloadMods();
                    win.showToastRequested("Моды перезагружены");
                }
            }
        }

        // Main M3 surface sheet (matches SettingsDialog)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.layer1
            border.width: 1
            border.color: Appearance.colors.layer0Border
            clip: true

            // ================================================================
            // TAB 0: КОНСОЛЬ + JS REPL
            // ================================================================
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 0
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SegmentedControl {
                        segmentHeight: 32
                        horizontalPadding: 12
                        currentIndex: win.logFilter === "warn" ? 1
                            : win.logFilter === "error" ? 2
                            : win.logFilter === "mods" ? 3 : 0
                        onActivated: (index) => {
                            const keys = ["all", "warn", "error", "mods"];
                            win.logFilter = keys[index] || "all";
                        }
                        segments: [
                            Segment { text: "Все" },
                            Segment { text: "Предупр." },
                            Segment { text: "Ошибки" },
                            Segment { text: "Моды" }
                        ]
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: height / 2
                        color: Appearance.colors.surfaceContainer
                        border.width: 1
                        border.color: searchInput.activeFocus ? Appearance.colors.primary : Appearance.colors.outlineVariant

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6

                            MaterialSymbol {
                                text: "search"
                                iconSize: 16
                                color: Appearance.colors.onSurfaceVariant
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Appearance.fontFamily
                                font.pixelSize: Appearance.fontSize.small
                                color: Appearance.colors.onSurface
                                selectionColor: Appearance.colors.primaryContainer
                                selectedTextColor: Appearance.colors.onPrimaryContainer
                                onTextChanged: win.logQuery = text
                                clip: true

                                StyledText {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Фильтр логов..."
                                    font.pixelSize: Appearance.fontSize.small
                                    color: Appearance.colors.onSurfaceVariant
                                    visible: searchInput.text.length === 0
                                }
                            }
                        }
                    }

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "delete_sweep"
                        text: "Очистить"
                        onClicked: {
                            devTools.clearLogs();
                            ModManager.clearLogs();
                        }
                    }
                }

                // Log list surface
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant
                    clip: true

                    ListView {
                        id: logList
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        model: win.mergedLogs
                        onCountChanged: Qt.callLater(() => logList.positionViewAtEnd())
                        ScrollBar.vertical: StyledScrollBar {}

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: logList.width
                            height: Math.max(28, msgText.implicitHeight + 10)
                            radius: Appearance.rounding.verySmall
                            color: index % 2 === 0 ? "transparent" : Qt.alpha(Appearance.colors.onSurface, 0.03)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                StyledText {
                                    Layout.preferredWidth: 74
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 5
                                    text: modelData.time || ""
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: Appearance.colors.onSurfaceVariant
                                }

                                StyledText {
                                    Layout.preferredWidth: 44
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 5
                                    text: (modelData.level || "info").toUpperCase()
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: {
                                        const l = (modelData.level || "").toLowerCase();
                                        if (l === "error") return Appearance.colors.error;
                                        if (l === "warn") return Appearance.colors.tertiary;
                                        if (l === "result" || l === "js") return Appearance.colors.primary;
                                        return Appearance.colors.onSurfaceVariant;
                                    }
                                }

                                StyledText {
                                    Layout.preferredWidth: 72
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 5
                                    text: modelData.source || ""
                                    elide: Text.ElideRight
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: Appearance.colors.onSurfaceVariant
                                }

                                StyledText {
                                    id: msgText
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 5
                                    text: modelData.message || ""
                                    wrapMode: Text.WrapAnywhere
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 12
                                    color: Appearance.colors.onSurface
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
                }

                // JS REPL input bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainer
                    border.width: 1
                    border.color: replInput.activeFocus ? Appearance.colors.primary : Appearance.colors.outlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: 18
                            color: Appearance.colors.primary
                        }

                        TextInput {
                            id: replInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Appearance.monoFontFamily
                            font.pixelSize: 12
                            color: Appearance.colors.onSurface
                            selectionColor: Appearance.colors.primaryContainer
                            selectedTextColor: Appearance.colors.onPrimaryContainer
                            clip: true

                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "JS-консоль (window, backend, appSettings, UiState, Appearance, ModManager)..."
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 12
                                color: Appearance.colors.onSurfaceVariant
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
            // TAB 1: ИНСПЕКТОР UI
            // ================================================================
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 1
                spacing: 12

                // Clickable parent breadcrumb chain
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: win.inspectedInfo && win.inspectedInfo.chain && win.inspectedInfo.chain.length > 0

                    Repeater {
                        model: (win.inspectedInfo && win.inspectedInfo.chain) ? win.inspectedInfo.chain : []

                        delegate: RippleButton {
                            required property var modelData
                            implicitHeight: 28
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 0
                            bottomPadding: 0
                            buttonRadius: Appearance.rounding.full
                            toggled: modelData.stepsUp === 0
                            colBackground: Appearance.colors.surfaceContainer
                            colBackgroundHover: Appearance.colors.surfaceContainerHigh
                            colBackgroundToggled: Appearance.colors.primaryContainer
                            colBackgroundToggledHover: Appearance.colors.primaryContainer
                            onClicked: {
                                const anc = devTools.ancestorAt(win.inspectedItem, modelData.stepsUp);
                                if (anc) win.selectInspectedItem(anc);
                            }

                            contentItem: StyledText {
                                text: (modelData.type || "Item") + (modelData.objectName ? ("#" + modelData.objectName) : "")
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 11
                                color: modelData.stepsUp === 0 ? Appearance.colors.onPrimaryContainer : Appearance.colors.onSurfaceVariant
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
                        spacing: 12

                        TitleText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Элемент не выбран"
                            font.pixelSize: Appearance.fontSize.large
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Нажмите Ctrl+Shift+C или кнопку пипетки и кликните по любому элементу в окне"
                            color: Appearance.colors.onSurfaceVariant
                        }
                        TextButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            variant: TextButton.Filled
                            symbol: "ads_click"
                            text: "Выбрать элемент"
                            onClicked: win.picking = true
                        }
                    }
                }

                // Inspected item properties sheet
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.inspectedItem !== null
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 12
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: (win.inspectedInfo.type || "Item")
                                    + (win.inspectedInfo.objectName ? (" #" + win.inspectedInfo.objectName) : "")
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: Appearance.fontSize.normal
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            TextButton {
                                variant: TextButton.Tonal
                                symbol: win.inspectedInfo.visible ? "visibility_off" : "visibility"
                                text: win.inspectedInfo.visible ? "Скрыть" : "Показать"
                                onClicked: {
                                    if (win.inspectedItem) {
                                        win.inspectedItem.visible = !win.inspectedItem.visible;
                                        win.refreshAll();
                                    }
                                }
                            }

                            TextButton {
                                variant: TextButton.Outlined
                                symbol: "content_copy"
                                text: "JSON"
                                onClicked: {
                                    devTools.copyToClipboard(JSON.stringify(win.inspectedInfo, null, 2));
                                    win.showToastRequested("JSON скопирован");
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Appearance.colors.outlineVariant
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            ScrollBar.vertical: StyledScrollBar {}
                            model: {
                                const d = win.inspectedInfo || {};
                                const rows = [
                                    { k: "Класс", v: d.rawClass || "" },
                                    { k: "objectName", v: d.objectName || "—" },
                                    { k: "Геометрия", v: Math.round(d.x || 0) + ", " + Math.round(d.y || 0) + "  (" + Math.round(d.width || 0) + " × " + Math.round(d.height || 0) + ")" },
                                    { k: "В окне", v: Math.round(d.sceneX || 0) + ", " + Math.round(d.sceneY || 0) },
                                    { k: "Видимость / alpha", v: (d.visible ? "да" : "нет") + " · " + Number(d.opacity || 0).toFixed(2) },
                                    { k: "z / clip / дети", v: String(d.z || 0) + " · " + (d.clip ? "да" : "нет") + " · " + String(d.childCount || 0) }
                                ];
                                if (d.color) rows.push({ k: "Цвет", v: d.color, swatch: d.color });
                                if (d.text) rows.push({ k: "Текст", v: d.text });
                                if (d.slotName) rows.push({ k: "Слот мода", v: d.slotName });
                                return rows;
                            }

                            delegate: Item {
                                required property var modelData
                                width: ListView.view.width
                                height: 34

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    StyledText {
                                        Layout.preferredWidth: 144
                                        text: modelData.k
                                        font.pixelSize: Appearance.fontSize.smaller
                                        color: Appearance.colors.onSurfaceVariant
                                    }
                                    Rectangle {
                                        visible: Boolean(modelData.swatch)
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                        radius: 4
                                        color: modelData.swatch || "transparent"
                                        border.width: 1
                                        border.color: Appearance.colors.outlineVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.v
                                        elide: Text.ElideRight
                                        font.family: Appearance.monoFontFamily
                                        font.pixelSize: 12
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Qt.alpha(Appearance.colors.outlineVariant, 0.5)
                                }
                            }
                        }
                    }
                }
            }

            // ================================================================
            // TAB 2: СОСТОЯНИЕ И ПАЛИТРА
            // ================================================================
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 2
                spacing: 12

                // Left: Backend & Mods
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant
                    clip: true

                    ListView {
                        anchors.fill: parent
                        clip: true
                        ScrollBar.vertical: StyledScrollBar {}
                        model: [
                            { k: "Версия", v: "v" + updater.currentVersion },
                            { k: "Авторизация", v: backend.loggedIn ? "выполнена" : "нет" },
                            { k: "Страница", v: String(backend.page) + (UiState.activeModPageId ? (" (мод: " + UiState.activeModPageId + ")") : "") },
                            { k: "Плеер", v: (backend.playing ? "играет" : "пауза") + (backend.buffering ? " · буферизация" : "") },
                            { k: "ID трека", v: backend.nowTrackId || "—" },
                            { k: "Трек", v: backend.hasTrack ? (backend.nowTitle + " — " + backend.nowArtists) : "—" },
                            { k: "Позиция", v: Math.floor(backend.positionSecs) + "с / " + Math.floor(backend.durationSecs) + "с" },
                            { k: "Качество потока", v: backend.audioQuality || "—" },
                            { k: "Формат загрузки", v: backend.downloadQuality || "—" },
                            { k: "Громкость / масштаб", v: Math.round(backend.volume * 100) + "% · " + Math.round(appSettings.zoom * 100) + "%" },
                            { k: "Моды", v: ModManager.activeModCount + " акт. · " + ModManager.activeOverrideCount + " overrides · rev " + ModManager.reloadRevision },
                            { k: "Last.fm", v: backend.lastfmConnected ? ("подключён (" + backend.lastfmUsername + ")") : (backend.lastfmHasBuiltinKeys ? "ключи вшиты" : "нет ключей") }
                        ]

                        delegate: Item {
                            required property var modelData
                            width: ListView.view.width
                            height: 34

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                StyledText {
                                    Layout.preferredWidth: 140
                                    text: modelData.k
                                    font.pixelSize: Appearance.fontSize.smaller
                                    color: Appearance.colors.onSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    elide: Text.ElideRight
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 12
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Qt.alpha(Appearance.colors.outlineVariant, 0.5)
                            }
                        }
                    }
                }

                // Right: Live Appearance.colors palette tokens
                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant
                    clip: true

                    ListView {
                        anchors.fill: parent
                        clip: true
                        ScrollBar.vertical: StyledScrollBar {}
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

                        delegate: Item {
                            required property var modelData
                            width: ListView.view.width
                            height: 34

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    radius: 4
                                    color: modelData.col
                                    border.width: 1
                                    border.color: Appearance.colors.outlineVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    text: String(modelData.col)
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: Appearance.colors.onSurfaceVariant
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
                                color: Qt.alpha(Appearance.colors.outlineVariant, 0.5)
                            }
                        }
                    }
                }
            }

            // ================================================================
            // TAB 3: НАГРУЗКА И ИНСТРУМЕНТЫ
            // ================================================================
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                visible: win.activeTab === 3
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            { label: "Кадры", value: win.fps + " fps", sub: win.frameMs.toFixed(1) + " мс / кадр" },
                            { label: "Память PSS", value: devTools.memoryPssMb.toFixed(1) + " МБ", sub: "RSS " + devTools.memoryRssMb.toFixed(1) + " МБ" },
                            { label: "Узлы сцены", value: String(win.itemCount), sub: devTools.graphicsApi },
                            { label: "Среда", value: "Qt " + devTools.qtVersion, sub: "ymusic v" + updater.currentVersion }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 86
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.surfaceContainer
                            border.width: 1
                            border.color: Appearance.colors.outlineVariant

                            Column {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 4

                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Appearance.fontSize.smaller
                                    color: Appearance.colors.onSurfaceVariant
                                }
                                StyledText {
                                    text: modelData.value
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: Appearance.fontSize.large
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    text: modelData.sub
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: 11
                                    color: Appearance.colors.onSurfaceVariant
                                }
                            }
                        }
                    }
                }

                // Frame time bar chart
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant

                    StyledText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 14
                        text: "Время кадра (мс) · ориентир 16.6 мс"
                        font.family: Appearance.monoFontFamily
                        font.pixelSize: 11
                        color: Appearance.colors.onSurfaceVariant
                    }

                    Item {
                        id: chartArea
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 38
                        anchors.bottomMargin: 14

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            y: parent.height * (1.0 - 16.6 / 40.0)
                            height: 1
                            color: Appearance.colors.outlineVariant
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
                                        radius: 3
                                        color: modelData > 24.0 ? Appearance.colors.error : Appearance.colors.primary
                                        opacity: 0.85
                                    }
                                }
                            }
                        }
                    }
                }

                // Quick actions using native M3 TextButton
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "cleaning_services"
                        text: "Сборка мусора (GC)"
                        onClicked: {
                            devTools.collectGarbage();
                            win.refreshAll();
                            win.showToastRequested("GC выполнен");
                        }
                    }
                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "refresh"
                        text: "Перезагрузить моды"
                        onClicked: {
                            ModManager.reloadMods();
                            win.showToastRequested("Моды перезагружены");
                        }
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "description"
                        text: "Папка логов"
                        onClicked: appSettings.openLogsFolder()
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "folder_open"
                        text: "Папка модов"
                        onClicked: ModManager.openModsFolder()
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "new_releases"
                        text: "Проверить «Что нового»"
                        onClicked: win.previewWhatsNewRequested()
                    }
                }
            }
        }
    }
}
