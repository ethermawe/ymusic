/*
 * Swiftify, a spotify player for desktop
 * Copyright (C) 2026  shred0s
 * Modified for ymusic (2026).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import ymusic.ui
import "../settings"

Item {
    id: root

    property int page: 0
    property string activeModTabId: ""
    property string cacheSizeLabel: "—"
    property int themeListRev: 0
    property var fontOptions: ["По умолчанию (Google Sans Flex / система)"]

    readonly property list<string> fades: ["none", "finalSeconds", "entire"]
    readonly property list<string> qualities: ["nq", "hq", "lossless"]
    readonly property list<string> downloadFormats: ["mp3", "flac", "match"]
    readonly property list<string> aiBehaviors: ["skip_if_not_liked", "dislike_if_not_liked", "skip", "dislike", "nothing"]
    readonly property list<string> themeModes: ["auto", "light", "dark"]
    readonly property list<string> schemeVariantIds: ["tonal_spot", "expressive", "vibrant", "fidelity", "monochrome", "neutral"]
    readonly property list<string> schemeVariantLabels: ["Tonal Spot", "Expressive", "Vibrant", "Fidelity", "Monochrome", "Neutral"]
    readonly property list<string> accentQuickSwatches: ["#fc3f1d", "#ff3d8a", "#8b5cf6", "#3b82f6", "#06b6d4", "#10b981", "#f59e0b", "#ef4444"]
    readonly property list<string> backends: ["auto", "vulkan", "opengl"]
    readonly property list<string> discordDisplayModes: ["track", "artist", "app"]
    readonly property list<string> discordActivityTypes: ["listening", "playing"]
    readonly property list<string> lyricsSourceModes: ["yandex_first", "lrclib_first", "lrclib_only", "yandex_only"]
    readonly property list<string> immersivePanels: ["artwork", "lyrics", "queue"]
    readonly property list<real> volumeSteps: [0.02, 0.05, 0.10]
    readonly property string normalizedPreset: (AppSettings.themePreset === "" || AppSettings.themePreset === "system")
        ? "auto" : AppSettings.themePreset

    function fontComboIndex(): int {
        if (!AppSettings.customFontFamily || AppSettings.customFontFamily.length === 0) return 0;
        const idx = fontOptions.indexOf(AppSettings.customFontFamily);
        return idx >= 0 ? idx : 0;
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            root.fontOptions = ["По умолчанию (Google Sans Flex / система)"].concat(Theme.availableFonts());
        });
    }

    Connections {
        target: Theme
        function onSchemeChanged() { root.themeListRev += 1; }
        function onUserThemesChanged() { root.themeListRev += 1; }
    }

    function nearestVolumeStepIndex(): int {
        let best = 1;
        let minDiff = 999;
        for (let i = 0; i < volumeSteps.length; ++i) {
            const diff = Math.abs(volumeSteps[i] - AppSettings.volumeStep);
            if (diff < minDiff) {
                minDiff = diff;
                best = i;
            }
        }
        return best;
    }

    onPageChanged: {
        if (page === 6) Qt.callLater(() => root.cacheSizeLabel = AppSettings.cacheSizeText());
    }

    component Page: Column {
        width: parent ? parent.width : 0
        spacing: 24
    }

    component StatusRow: Item {
        id: status
        property string label
        property string value
        property bool good: false

        width: parent ? parent.width : 0
        height: 40

        StyledText {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: status.label
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: status.good ? Appearance.colors.primary : Appearance.colors.error
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: status.value
                color: Appearance.colors.onSurfaceVariant
            }
        }
    }

    component KeyRow: Item {
        id: krow
        property string label
        property string shortcut

        width: parent ? parent.width : 0
        height: 36

        StyledText {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: krow.label
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: keyText.implicitWidth + 16
            radius: 6
            color: Appearance.colors.surfaceContainerHighest
            border.width: 1
            border.color: Appearance.colors.outlineVariant

            StyledText {
                id: keyText
                anchors.centerIn: parent
                text: krow.shortcut
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.onSurface
            }
        }
    }

    implicitHeight: pages.implicitHeight

    Column {
        id: pages
        width: parent.width

        // 0: Оформление
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 0

            ContentSection {
                title: "Цвета и тема"
                symbol: "palette"

                ConfigSelection {
                    text: "Режим темы"
                    currentIndex: Math.max(0, root.themeModes.indexOf(AppSettings.themeMode === "system" ? "auto" : AppSettings.themeMode))
                    segments: [
                        Segment { text: "Система"; symbol: "brightness_auto" },
                        Segment { text: "Светлая"; symbol: "light_mode" },
                        Segment { text: "Тёмная"; symbol: "dark_mode" }
                    ]
                    onActivated: (index) => AppSettings.themeMode = root.themeModes[index]
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 10
                    topPadding: 6
                    bottomPadding: 10

                    Repeater {
                        model: root.themeListRev >= 0 ? Theme.themeOptions(Theme.dark) : []

                        delegate: ThemeSwatch {
                            required property var modelData
                            option: modelData
                            selected: modelData.id === root.normalizedPreset
                            onClicked: Theme.selectPreset(modelData.id)
                            onDeleteRequested: {
                                const removedName = modelData.name;
                                if (Theme.deleteUserTheme(modelData.id)) {
                                    UiState.showToast("Тема «" + removedName + "» удалена");
                                }
                            }
                        }
                    }
                }

                Column {
                    x: 8
                    width: parent.width - 16
                    spacing: 10
                    topPadding: 4
                    bottomPadding: 8
                    visible: root.normalizedPreset === "custom"

                    StyledText {
                        text: "Акцентный цвет и стиль Material 3"
                        font.pixelSize: Appearance.fontSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.onSurfaceVariant
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.accentQuickSwatches
                            delegate: RippleButton {
                                id: swatchBtn
                                required property string modelData
                                readonly property bool isCurrent: AppSettings.customAccentColor.toLowerCase() === modelData.toLowerCase()
                                width: 36
                                height: 36
                                padding: 0
                                buttonRadius: Appearance.rounding.small
                                buttonRadiusPressed: Appearance.rounding.verySmall
                                colBackground: modelData
                                colBackgroundHover: modelData
                                backgroundItem.border.width: isCurrent ? 2 : 1
                                backgroundItem.border.color: isCurrent
                                    ? Appearance.colors.onSurface
                                    : Appearance.colors.outlineVariant
                                tooltip: modelData
                                onClicked: AppSettings.customAccentColor = modelData

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: swatchBtn.isCurrent
                                    text: "check"
                                    iconSize: 16
                                    color: Appearance.colors.onPrimary
                                }
                            }
                        }

                        OutlinedTextField {
                            id: customHexField
                            width: 126
                            placeholder: "#FC3F1D"
                            text: AppSettings.customAccentColor
                            onAccepted: AppSettings.customAccentColor = text
                        }
                        Connections {
                            target: customHexField.inputItem
                            function onActiveFocusChanged() {
                                if (!customHexField.inputItem.activeFocus) {
                                    AppSettings.customAccentColor = customHexField.text;
                                }
                            }
                        }

                        TextButton {
                            variant: TextButton.Tonal
                            symbol: "colorize"
                            text: "Выбрать цвет…"
                            onClicked: {
                                accentColorDialog.selectedColor = AppSettings.customAccentColor;
                                accentColorDialog.open();
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.schemeVariantIds.length
                            delegate: TextButton {
                                required property int index
                                readonly property string variantId: root.schemeVariantIds[index]
                                text: root.schemeVariantLabels[index]
                                variant: AppSettings.customSchemeVariant === variantId ? TextButton.Filled : TextButton.Outlined
                                onClicked: AppSettings.customSchemeVariant = variantId
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: path.implicitHeight + automatic.implicitHeight + 24
                    visible: root.normalizedPreset === "auto"

                    OutlinedTextField {
                        id: path
                        x: 8
                        y: 8
                        width: parent.width - 16
                        placeholder: "Автоопределение (опционально путь к JSON Matugen)"
                        text: AppSettings.matugenColorsPath
                        onAccepted: AppSettings.matugenColorsPath = text
                    }
                    TextButton {
                        id: automatic
                        x: 8
                        y: path.y + path.height + 8
                        variant: TextButton.Tonal
                        symbol: "refresh"
                        text: "Автопоиск"
                        onClicked: {
                            path.text = "";
                            AppSettings.matugenColorsPath = "";
                            Theme.refreshSystemScheme();
                        }
                    }
                    Connections {
                        target: path.inputItem
                        function onActiveFocusChanged() {
                            if (!path.inputItem.activeFocus) {
                                AppSettings.matugenColorsPath = path.text;
                            }
                        }
                    }
                }

                NoteText {
                    text: root.normalizedPreset === "custom"
                        ? ("Своя палитра Material 3 (" + AppSettings.customAccentColor + ", " + AppSettings.customSchemeVariant + ").")
                        : (root.normalizedPreset.startsWith("user:")
                            ? "Используется сохранённая пользовательская тема."
                            : (root.normalizedPreset !== "auto"
                                ? "Используется встроенный пресет цветов."
                                : (Theme.usingSystemScheme
                                    ? ("Системная схема: " + Theme.systemSchemePath + " (обновляется автоматически)")
                                    : (AppSettings.matugenColorsPath.length > 0
                                        ? ("Файл схемы не найден по пути: " + AppSettings.matugenColorsPath)
                                        : "Автоматически подбирает цвета по обоям или системному акценту."))))
                }
            }

            ContentSection {
                title: "Типографика и скругления"
                symbol: "text_fields"

                RowLayout {
                    x: 8
                    width: parent.width - 16
                    spacing: 12

                    StyledText {
                        Layout.fillWidth: true
                        text: "Шрифт интерфейса"
                        elide: Text.ElideRight
                    }

                    StyledComboBox {
                        id: fontCombo
                        Layout.preferredWidth: 280
                        model: root.fontOptions
                        currentIndex: root.fontComboIndex()
                        onActivated: (index) => {
                            AppSettings.customFontFamily = index <= 0 ? "" : root.fontOptions[index];
                        }
                    }

                    IconButton {
                        visible: AppSettings.customFontFamily.length > 0
                        symbol: "restart_alt"
                        tooltip: "Вернуть стандартный шрифт"
                        onClicked: AppSettings.customFontFamily = ""
                    }
                }

                ConfigSlider {
                    text: "Скругление углов"
                    from: 0.0
                    to: 1.6
                    stepSize: 0.05
                    value: AppSettings.roundingScale
                    valueText: Math.round(AppSettings.roundingScale * 100) + "%"
                    onMoved: (value) => AppSettings.roundingScale = Number(value.toFixed(2))
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8

                    TextButton {
                        variant: Math.abs(AppSettings.roundingScale - 0.25) < 0.03 ? TextButton.Filled : TextButton.Outlined
                        text: "Острые (25%)"
                        onClicked: AppSettings.roundingScale = 0.25
                    }
                    TextButton {
                        variant: Math.abs(AppSettings.roundingScale - 1.0) < 0.03 ? TextButton.Filled : TextButton.Outlined
                        text: "Стандарт (100%)"
                        onClicked: AppSettings.roundingScale = 1.0
                    }
                    TextButton {
                        variant: Math.abs(AppSettings.roundingScale - 1.4) < 0.03 ? TextButton.Filled : TextButton.Outlined
                        text: "Мягкие (140%)"
                        onClicked: AppSettings.roundingScale = 1.4
                    }
                }
            }

            ContentSection {
                title: "Пользовательские темы"
                symbol: "save"

                RowLayout {
                    x: 8
                    width: parent.width - 16
                    spacing: 8

                    OutlinedTextField {
                        id: saveThemeNameField
                        Layout.fillWidth: true
                        placeholder: "Название темы (например, Неоновый вечер)"
                    }

                    TextButton {
                        variant: TextButton.Filled
                        symbol: "add"
                        text: "Сохранить в коллекцию"
                        onClicked: {
                            const res = Theme.saveUserTheme(saveThemeNameField.text);
                            if (res.ok) {
                                saveThemeNameField.text = "";
                                UiState.showToast("Тема «" + res.name + "» сохранена");
                            } else {
                                UiState.showToast(res.error || "Не удалось сохранить тему");
                            }
                        }
                    }
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "upload_file"
                        text: "Экспорт (.ymtheme)…"
                        onClicked: exportThemeDialog.open()
                    }
                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "download"
                        text: "Импорт (.ymtheme / .json)…"
                        onClicked: importThemeDialog.open()
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "restart_alt"
                        text: "Сбросить тему"
                        onClicked: {
                            Theme.resetThemeDefaults();
                            UiState.showToast("Оформление сброшено к стандартному");
                        }
                    }
                }

                NoteText {
                    text: "Экспортированный файл .ymtheme хранит палитру, стиль M3, шрифт и скругление углов."
                }
            }

            ContentSection {
                title: "Интерфейс и обложки"
                symbol: "image"

                ConfigSwitch {
                    text: "Загружать обложки треков и коллекций"
                    checked: AppSettings.coversEnabled
                    onToggledTo: (checked) => AppSettings.coversEnabled = checked
                }
                ConfigSwitch {
                    text: "Минимализм (без декоративных фигур и стикеров)"
                    checked: AppSettings.noShapes
                    onToggledTo: (checked) => AppSettings.noShapes = checked
                }
                ConfigSwitch {
                    text: "Сглаживание иконок"
                    checked: AppSettings.iconAntialiasing
                    onToggledTo: (checked) => AppSettings.iconAntialiasing = checked
                }
                ConfigSlider {
                    text: "Масштаб интерфейса"
                    from: 0.8
                    to: 1.3
                    stepSize: 0.05
                    value: AppSettings.zoom
                    valueText: Math.round(AppSettings.zoom * 100) + "%"
                    onMoved: (value) => AppSettings.zoom = Number(value.toFixed(2))
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    visible: Math.abs(AppSettings.zoom - 1.0) > 0.01

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "restart_alt"
                        text: "Сбросить масштаб (100%)"
                        onClicked: AppSettings.zoom = 1.0
                    }
                }
            }

            ContentSection {
                visible: Qt.platform.os !== "osx" || WindowController.trayAvailable
                title: "Окно и трей"
                symbol: "web_asset"

                ConfigSelection {
                    visible: Qt.platform.os !== "osx"
                    text: "Рамка окна"
                    currentIndex: AppSettings.nativeTitleBar ? 0 : 1
                    segments: [
                        Segment { text: "Системная панель" },
                        Segment { text: "Встроенные кнопки" }
                    ]
                    onActivated: (index) => AppSettings.nativeTitleBar = index === 0
                }
                ConfigSwitch {
                    visible: Qt.platform.os !== "osx" && Qt.platform.os !== "windows" && !AppSettings.nativeTitleBar
                    text: "Кнопки свернуть / развернуть / закрыть"
                    checked: AppSettings.showWindowControls
                    onToggledTo: (checked) => AppSettings.showWindowControls = checked
                }
                ConfigSwitch {
                    visible: Qt.platform.os !== "osx"
                    text: "Кнопки управления справа"
                    enabled: !AppSettings.nativeTitleBar && (Qt.platform.os === "windows" || AppSettings.showWindowControls)
                    checked: AppSettings.windowControlsOnRight
                    onToggledTo: (checked) => AppSettings.windowControlsOnRight = checked
                }
                ConfigSwitch {
                    visible: WindowController.trayAvailable
                    text: "Сворачивать в трей при закрытии окна"
                    checked: AppSettings.minimizeToTray
                    onToggledTo: (checked) => AppSettings.minimizeToTray = checked
                }
            }
            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                visible: implicitHeight > 0
                slotName: "settings.section.appearance"
            }
        }

        // 1: Плеер и фон
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 1

            ContentSection {
                title: "Иммерсивный плеер"
                symbol: "open_in_full"

                ConfigSelection {
                    text: "Боковая панель по умолчанию"
                    currentIndex: Math.max(0, root.immersivePanels.indexOf(AppSettings.immersivePlayerPanel))
                    segments: [
                        Segment { text: "Обложка" },
                        Segment { text: "Текст" },
                        Segment { text: "Очередь" }
                    ]
                    onActivated: (index) => AppSettings.immersivePlayerPanel = root.immersivePanels[index]
                }
                ConfigSwitch {
                    text: "Круглая обложка в полном экране"
                    enabled: !AppSettings.visualizersEnabled || !AppSettings.immersiveVisualizer
                    checked: AppSettings.roundArtwork || (AppSettings.visualizersEnabled && AppSettings.immersiveVisualizer && AppSettings.circularVisualizer)
                    onToggledTo: (checked) => AppSettings.roundArtwork = checked
                }
                ConfigSwitch {
                    text: "Живой фон по обложке"
                    checked: AppSettings.livingBackdrop
                    onToggledTo: (checked) => AppSettings.livingBackdrop = checked
                }
                ConfigSlider {
                    text: "Размытие фона"
                    enabled: AppSettings.livingBackdrop
                    from: 0
                    to: 60
                    stepSize: 1
                    value: AppSettings.backdropBlur
                    onMoved: (value) => AppSettings.backdropBlur = Math.round(value)
                }
                ConfigSlider {
                    text: "Реакция фона на бас"
                    enabled: AppSettings.livingBackdrop
                    from: 0
                    to: 3
                    stepSize: 0.1
                    value: AppSettings.backdropReactivity
                    valueText: Math.round(AppSettings.backdropReactivity * 100) + "%"
                    onMoved: (value) => AppSettings.backdropReactivity = Number(value.toFixed(1))
                }
            }

            ContentSection {
                title: "Аудиовизуализация"
                symbol: "graphic_eq"

                ConfigSwitch {
                    text: "Включить аудиовизуализацию"
                    checked: AppSettings.visualizersEnabled
                    onToggledTo: (checked) => AppSettings.visualizersEnabled = checked
                }
                ConfigSwitch {
                    text: "Индикатор ритма в нижнем плеере и списке"
                    enabled: AppSettings.visualizersEnabled
                    checked: AppSettings.playerBarVisualizer
                    onToggledTo: (checked) => AppSettings.playerBarVisualizer = checked
                }
                ConfigSwitch {
                    text: "Визуализатор на весь экран"
                    enabled: AppSettings.visualizersEnabled
                    checked: AppSettings.immersiveVisualizer
                    onToggledTo: (checked) => AppSettings.immersiveVisualizer = checked
                }
                ConfigSelection {
                    text: "Стиль"
                    enabled: AppSettings.visualizersEnabled && AppSettings.immersiveVisualizer
                    currentIndex: AppSettings.circularVisualizer ? 1 : 0
                    segments: [
                        Segment { text: "Полоса" },
                        Segment { text: "Кольцо" }
                    ]
                    onActivated: (index) => AppSettings.circularVisualizer = index === 1
                }
                ConfigSelection {
                    text: "Симметрия полосы"
                    enabled: AppSettings.visualizersEnabled && AppSettings.immersiveVisualizer && !AppSettings.circularVisualizer
                    currentIndex: AppSettings.continuousVisualizer ? 1 : 0
                    segments: [
                        Segment { text: "Зеркало" },
                        Segment { text: "Сплошной" }
                    ]
                    onActivated: (index) => AppSettings.continuousVisualizer = index === 1
                }
                ConfigSelection {
                    text: "Форма"
                    enabled: AppSettings.visualizersEnabled && AppSettings.immersiveVisualizer
                    currentIndex: AppSettings.visualizerShape === "wave" ? 1 : 0
                    segments: [
                        Segment { text: "Столбцы" },
                        Segment { text: "Волна" }
                    ]
                    onActivated: (index) => AppSettings.visualizerShape = index === 1 ? "wave" : "bars"
                }
                ConfigSlider {
                    text: "Чувствительность"
                    enabled: AppSettings.visualizersEnabled && (AppSettings.playerBarVisualizer || AppSettings.immersiveVisualizer)
                    from: 0.6
                    to: 1.8
                    stepSize: 0.05
                    value: AppSettings.visualizerSensitivity
                    valueText: Math.round(AppSettings.visualizerSensitivity * 100) + "%"
                    onMoved: (value) => AppSettings.visualizerSensitivity = Number(value.toFixed(2))
                }
                NoteText {
                    text: "Реагирует на спектр аудиопотока в реальном времени. Отключение снижает нагрузку на GPU."
                }
            }

            ContentSection {
                title: "Экран «Моя волна»"
                symbol: "my_wave"

                ConfigSwitch {
                    text: "Кольцевой визуализатор"
                    enabled: AppSettings.visualizersEnabled
                    checked: AppSettings.waveVisualizer
                    onToggledTo: (checked) => AppSettings.waveVisualizer = checked
                }
                ConfigSelection {
                    text: "Форма визуализатора"
                    enabled: AppSettings.visualizersEnabled && AppSettings.waveVisualizer
                    currentIndex: AppSettings.waveVisualizerShape === "wave" ? 1 : 0
                    segments: [
                        Segment { text: "Столбцы" },
                        Segment { text: "Волна" }
                    ]
                    onActivated: (index) => AppSettings.waveVisualizerShape = index === 1 ? "wave" : "bars"
                }
                ConfigSlider {
                    text: "Чувствительность"
                    enabled: AppSettings.visualizersEnabled && AppSettings.waveVisualizer
                    from: 0.6
                    to: 1.8
                    stepSize: 0.05
                    value: AppSettings.waveVisualizerSensitivity
                    valueText: Math.round(AppSettings.waveVisualizerSensitivity * 100) + "%"
                    onMoved: (value) => AppSettings.waveVisualizerSensitivity = Number(value.toFixed(2))
                }
                ConfigSwitch {
                    text: "Живая плазма (Аврора)"
                    enabled: !AppSettings.performanceMode
                    checked: AppSettings.waveAurora
                    onToggledTo: (checked) => AppSettings.waveAurora = checked
                }
                ConfigSwitch {
                    text: "Обложка трека внутри сферы"
                    checked: AppSettings.waveOrbArtwork
                    onToggledTo: (checked) => AppSettings.waveOrbArtwork = checked
                }
                ConfigSwitch {
                    text: "Волнистый контур сферы"
                    enabled: !AppSettings.noShapes
                    checked: AppSettings.waveOrbSquiggle
                    onToggledTo: (checked) => AppSettings.waveOrbSquiggle = checked
                }
                ConfigSlider {
                    text: "Пульсация сферы от баса"
                    enabled: AppSettings.motionEnabled && !AppSettings.performanceMode
                    from: 0
                    to: 3
                    stepSize: 0.1
                    value: AppSettings.waveReactivity
                    valueText: Math.round(AppSettings.waveReactivity * 100) + "%"
                    onMoved: (value) => AppSettings.waveReactivity = Number(value.toFixed(1))
                }
            }
            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                visible: implicitHeight > 0
                slotName: "settings.section.player"
            }
        }

        // 2: Звук и Анти-ИИ
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 2

            ContentSection {
                title: "Аудиопоток и воспроизведение"
                symbol: "play_circle"

                ConfigSelection {
                    text: "Качество звука"
                    currentIndex: Math.max(0, root.qualities.indexOf(Backend.audioQuality))
                    segments: [
                        Segment { text: "Обычное" },
                        Segment { text: "Высокое (HQ)" },
                        Segment { text: "Lossless (FLAC)" }
                    ]
                    onActivated: (index) => Backend.feature({action: "set_audio_quality", quality: root.qualities[index]})
                }
                ConfigSelection {
                    text: "Формат скачивания на ПК"
                    currentIndex: Math.max(0, root.downloadFormats.indexOf(Backend.downloadQuality))
                    segments: [
                        Segment { text: "MP3 (320 kbps)" },
                        Segment { text: "FLAC (Lossless)" },
                        Segment { text: "Как в плеере" }
                    ]
                    onActivated: (index) => Backend.feature({action: "set_download_quality", quality: root.downloadFormats[index]})
                }
                ConfigSwitch {
                    text: "Выравнивание громкости (EBU R128)"
                    checked: Backend.normalizeVolume
                    onToggledTo: (checked) => Backend.feature({action: "set_normalize_volume", enabled: checked})
                }
                ConfigSlider {
                    text: "Скорость воспроизведения"
                    from: 0.5
                    to: 2.0
                    stepSize: 0.05
                    value: Backend.tempo
                    valueText: Backend.tempo.toFixed(2) + "×"
                    onMoved: (value) => {
                        const rounded = Number(value.toFixed(2));
                        Backend.setTempo(rounded);
                        AppSettings.playbackSpeed = rounded;
                    }
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    visible: Math.abs(Backend.tempo - 1.0) > 0.01

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "restart_alt"
                        text: "Обычная скорость (1.00×)"
                        onClicked: {
                            Backend.setTempo(1.0);
                            AppSettings.playbackSpeed = 1.0;
                        }
                    }
                }

                ConfigSelection {
                    text: "Затухание таймера сна"
                    currentIndex: Math.max(0, root.fades.indexOf(AppSettings.sleepTimerFade))
                    segments: [
                        Segment { text: "Нет" },
                        Segment { text: "10 сек" },
                        Segment { text: "Весь таймер" }
                    ]
                    onActivated: (index) => AppSettings.sleepTimerFade = root.fades[index]
                }
            }

            ContentSection {
                title: "AI треки"
                symbol: "smart_toy"

                ConfigSelection {
                    text: "Действие при ИИ-треке"
                    currentIndex: Math.max(0, root.aiBehaviors.indexOf(Backend.aiMusicBehavior))
                    segments: [
                        Segment { text: "Пропуск (кроме ♥)" },
                        Segment { text: "Дизлайк (кроме ♥)" },
                        Segment { text: "Всегда пропуск" },
                        Segment { text: "Всегда дизлайк" },
                        Segment { text: "Только метка" }
                    ]
                    onActivated: (index) => Backend.feature({action: "set_ai_music_behavior", behavior: root.aiBehaviors[index]})
                }
                ConfigSwitch {
                    text: "Показывать метку AI рядом с треком"
                    checked: Backend.showAiLabels
                    onToggledTo: (checked) => Backend.feature({action: "set_show_ai_labels", enabled: checked})
                }
                ConfigSwitch {
                    text: "Строго по трекам (не блокировать живые треки артиста)"
                    checked: Backend.aiStrictTracks
                    onToggledTo: (checked) => Backend.feature({action: "set_ai_strict_tracks", enabled: checked})
                }
                NoteText {
                    text: "Использует встроенную базу Slopless и онлайн проверку slopless.art."
                }
            }
            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                visible: implicitHeight > 0
                slotName: "settings.section.audio"
            }
        }

        // 3: Анимации и ввод
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 3

            ContentSection {
                title: "Анимации и отклик"
                symbol: "animation"

                ConfigSwitch {
                    text: "Анимации интерфейса"
                    checked: AppSettings.motionEnabled
                    onToggledTo: (checked) => AppSettings.motionEnabled = checked
                }
                ConfigSwitch {
                    text: "Ускоренный переход в иммерсивный плеер"
                    enabled: AppSettings.motionEnabled && !AppSettings.performanceMode
                    checked: AppSettings.fastImmersiveTransition
                    onToggledTo: (checked) => AppSettings.fastImmersiveTransition = checked
                }
                ConfigSwitch {
                    text: "Эффекты частиц при лайках и запуске"
                    enabled: !AppSettings.performanceMode
                    checked: AppSettings.burstsEnabled
                    onToggledTo: (checked) => AppSettings.burstsEnabled = checked
                }
                ConfigSwitch {
                    text: "Уменьшить фоновое движение"
                    checked: AppSettings.reduceMotion || AppSettings.performanceMode
                    enabled: !AppSettings.performanceMode
                    onToggledTo: (checked) => AppSettings.reduceMotion = checked
                }
                ConfigSwitch {
                    text: "Режим производительности"
                    checked: AppSettings.performanceMode
                    onToggledTo: (checked) => AppSettings.performanceMode = checked
                }
                NoteText {
                    text: "Уменьшение фонового движения сохраняет плавные отклики при нажатиях. Режим производительности отключает все анимации."
                }
            }

            ContentSection {
                title: "Прокрутка и управление"
                symbol: "mouse"

                ConfigSlider {
                    text: "Скорость прокрутки колесом"
                    from: 0.5
                    to: 6.0
                    stepSize: 0.25
                    value: AppSettings.scrollSpeed
                    valueText: AppSettings.scrollSpeed.toFixed(2) + "×"
                    onMoved: (value) => AppSettings.scrollSpeed = Number(value.toFixed(2))
                }
                ConfigSelection {
                    text: "Шаг громкости колесом и клавишами"
                    currentIndex: root.nearestVolumeStepIndex()
                    segments: [
                        Segment { text: "2%" },
                        Segment { text: "5%" },
                        Segment { text: "10%" }
                    ]
                    onActivated: (index) => AppSettings.volumeStep = root.volumeSteps[index]
                }
                ConfigSelection {
                    text: "Раскрытие громкости в плеере"
                    currentIndex: AppSettings.volumeExpandOnHover ? 0 : 1
                    segments: [
                        Segment { text: "При наведении" },
                        Segment { text: "По клику" }
                    ]
                    onActivated: (index) => AppSettings.volumeExpandOnHover = (index === 0)
                }
            }

            ContentSection {
                title: "Графический движок"
                symbol: "memory"

                ConfigSelection {
                    text: "Рендерер (после перезапуска)"
                    currentIndex: Math.max(0, root.backends.indexOf(AppSettings.graphicsBackend))
                    segments: [
                        Segment { text: "Авто" },
                        Segment { text: "Vulkan" },
                        Segment { text: "OpenGL" }
                    ]
                    onActivated: (index) => AppSettings.graphicsBackend = root.backends[index]
                }
            }
            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                visible: implicitHeight > 0
                slotName: "settings.section.animations"
            }
        }

        // 4: Интеграции и горячие клавиши
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 4

            ContentSection {
                title: "Discord Rich Presence"
                symbol: "extension"

                StatusRow {
                    label: "Статус Discord RPC"
                    value: AppSettings.discordRpcEnabled
                        ? (Backend.discordStatus.length > 0 ? Backend.discordStatus : "Ожидание трека")
                        : "Отключено"
                    good: !AppSettings.discordRpcEnabled || Backend.discordConnected
                }
                ConfigSwitch {
                    text: "Включить Discord Rich Presence"
                    checked: AppSettings.discordRpcEnabled
                    onToggledTo: (checked) => AppSettings.discordRpcEnabled = checked
                }
                ConfigSelection {
                    text: "Режим активности"
                    enabled: AppSettings.discordRpcEnabled
                    currentIndex: Math.max(0, root.discordActivityTypes.indexOf(AppSettings.discordRpcType))
                    segments: [
                        Segment { text: "Слушает" },
                        Segment { text: "Играет в" }
                    ]
                    onActivated: (index) => AppSettings.discordRpcType = root.discordActivityTypes[index]
                }
                ConfigSelection {
                    text: "В строке статуса"
                    enabled: AppSettings.discordRpcEnabled && AppSettings.discordRpcType === "listening"
                    currentIndex: Math.max(0, root.discordDisplayModes.indexOf(AppSettings.discordRpcDisplay))
                    segments: [
                        Segment { text: "Трек" },
                        Segment { text: "Исполнитель" },
                        Segment { text: "Приложение" }
                    ]
                    onActivated: (index) => AppSettings.discordRpcDisplay = root.discordDisplayModes[index]
                }
                ConfigSwitch {
                    text: "Показывать трек на паузе"
                    enabled: AppSettings.discordRpcEnabled
                    checked: AppSettings.discordRpcShowPaused
                    onToggledTo: (checked) => AppSettings.discordRpcShowPaused = checked
                }
                ConfigSwitch {
                    text: "Показывать обложку трека"
                    enabled: AppSettings.discordRpcEnabled
                    checked: AppSettings.discordRpcShowCover
                    onToggledTo: (checked) => AppSettings.discordRpcShowCover = checked
                }
                ConfigSwitch {
                    text: "Название альбома на обложке"
                    enabled: AppSettings.discordRpcEnabled && AppSettings.discordRpcShowCover
                    checked: AppSettings.discordRpcShowAlbum
                    onToggledTo: (checked) => AppSettings.discordRpcShowAlbum = checked
                }
                ConfigSwitch {
                    text: "Показывать прогресс трека"
                    enabled: AppSettings.discordRpcEnabled
                    checked: AppSettings.discordRpcShowTimestamps
                    onToggledTo: (checked) => AppSettings.discordRpcShowTimestamps = checked
                }
                ConfigSwitch {
                    text: "Кнопка «Открыть трек»"
                    enabled: AppSettings.discordRpcEnabled
                    checked: AppSettings.discordRpcShowButton
                    onToggledTo: (checked) => AppSettings.discordRpcShowButton = checked
                }
                NoteText {
                    text: "Пункт «В строке статуса» управляет текстом рядом с ником в списке друзей: название трека, исполнитель или «Яндекс Музыка»."
                }
            }

            ContentSection {
                title: "Тексты песен и LRCLIB"
                symbol: "lyrics"

                StatusRow {
                    label: "Текущий текст"
                    value: {
                        if (UiState.lyricsLoading) return "Загрузка…";
                        if (!UiState.lyricsLines || UiState.lyricsLines.length === 0) return "Не загружен";
                        const src = UiState.lyricsSource === "lrclib" ? "LRCLIB" : "Яндекс Музыка";
                        if (!UiState.lyricsSynced) return src + " (без синхронизации)";
                        return src + (UiState.lyricsWordSynced ? " (пословно)" : " (построчно)");
                    }
                    good: UiState.lyricsLines && UiState.lyricsLines.length > 0
                }
                ConfigSelection {
                    text: "Приоритет источников"
                    currentIndex: Math.max(0, root.lyricsSourceModes.indexOf(AppSettings.lyricsSourceMode))
                    segments: [
                        Segment { text: "Яндекс → LRCLIB" },
                        Segment { text: "LRCLIB → Яндекс" },
                        Segment { text: "Только LRCLIB" },
                        Segment { text: "Только Яндекс" }
                    ]
                    onActivated: (index) => AppSettings.lyricsSourceMode = root.lyricsSourceModes[index]
                }
                ConfigSwitch {
                    text: "Предпочитать пословную синхронизацию LRCLIB"
                    enabled: AppSettings.lyricsSourceMode === "yandex_first"
                    checked: AppSettings.lrclibPreferWordSync
                    onToggledTo: (checked) => AppSettings.lrclibPreferWordSync = checked
                }
                ConfigSwitch {
                    text: "Караоке по словам при наличии таймингов"
                    checked: AppSettings.lyricsWordKaraoke
                    onToggledTo: (checked) => AppSettings.lyricsWordKaraoke = checked
                }

                Item {
                    width: parent.width
                    height: lrclibUrlField.implicitHeight + (lrclibResetBtn.visible ? lrclibResetBtn.implicitHeight + 8 : 0) + 16
                    visible: AppSettings.lyricsSourceMode !== "yandex_only"

                    OutlinedTextField {
                        id: lrclibUrlField
                        x: 8
                        y: 6
                        width: parent.width - 16
                        placeholder: "Сервер LRCLIB (по умолчанию https://lrclib.net)"
                        text: AppSettings.lrclibBaseUrl
                        onAccepted: AppSettings.lrclibBaseUrl = text
                    }
                    TextButton {
                        id: lrclibResetBtn
                        x: 8
                        y: lrclibUrlField.y + lrclibUrlField.height + 8
                        visible: AppSettings.lrclibBaseUrl !== "https://lrclib.net"
                        variant: TextButton.Tonal
                        symbol: "restart_alt"
                        text: "Сбросить на https://lrclib.net"
                        onClicked: {
                            AppSettings.lrclibBaseUrl = "https://lrclib.net";
                            lrclibUrlField.text = AppSettings.lrclibBaseUrl;
                        }
                    }
                    Connections {
                        target: lrclibUrlField.inputItem
                        function onActiveFocusChanged() {
                            if (!lrclibUrlField.inputItem.activeFocus) {
                                AppSettings.lrclibBaseUrl = lrclibUrlField.text;
                            }
                        }
                    }
                }

                NoteText {
                    text: "Режим «LRCLIB → Яндекс» сначала берёт текст из открытой базы LRCLIB (помогает обходить цензуру в текстах Яндекс Музыки). Пословное караоке работает только для треков с реальными таймингами слов; для обычных LRC активная строка выделяется целиком."
                }
            }

            ContentSection {
                id: lastfmSection
                title: "Last.fm"
                symbol: "radio"
                property bool showCustomKeys: false

                StatusRow {
                    label: Backend.lastfmConnected && Backend.lastfmUsername.length > 0
                        ? ("Аккаунт: " + Backend.lastfmUsername)
                        : "Статус Last.fm"
                    value: Backend.lastfmStatus
                    good: Backend.lastfmConnected && !Backend.lastfmIsError
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4
                    bottomPadding: 4

                    TextButton {
                        visible: !Backend.lastfmConnected && !Backend.lastfmAuthorizing
                        variant: TextButton.Filled
                        symbol: "login"
                        text: "Войти через браузер"
                        enabled: Backend.lastfmConfigured
                        onClicked: Backend.feature({action: "lastfm_auth_start"})
                    }
                    TextButton {
                        visible: Backend.lastfmAuthorizing
                        variant: TextButton.Outlined
                        symbol: "close"
                        text: "Отменить вход"
                        onClicked: Backend.feature({action: "lastfm_auth_cancel"})
                    }
                    TextButton {
                        visible: Backend.lastfmConnected
                        variant: TextButton.Outlined
                        symbol: "logout"
                        text: "Отключить Last.fm"
                        onClicked: Backend.feature({action: "lastfm_disconnect"})
                    }
                    TextButton {
                        variant: TextButton.Text
                        symbol: "key"
                        text: lastfmSection.showCustomKeys ? "Скрыть свои ключи" : "Свои API-ключи"
                        visible: Backend.lastfmHasBuiltinKeys
                        onClicked: lastfmSection.showCustomKeys = !lastfmSection.showCustomKeys
                    }
                }

                Column {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4
                    bottomPadding: 4
                    visible: !Backend.lastfmHasBuiltinKeys || lastfmSection.showCustomKeys || Backend.lastfmCustomApiKey.length > 0

                    OutlinedTextField {
                        id: lastfmApiKeyField
                        width: parent.width
                        placeholder: "Last.fm API Key"
                        text: Backend.lastfmCustomApiKey
                    }
                    OutlinedTextField {
                        id: lastfmApiSecretField
                        width: parent.width
                        placeholder: Backend.lastfmHasCustomSecret
                            ? "Last.fm Shared Secret (сохранён; введите новый для замены)"
                            : "Last.fm Shared Secret"
                        text: ""
                    }
                    Flow {
                        width: parent.width
                        spacing: 8

                        TextButton {
                            variant: TextButton.Tonal
                            symbol: "check"
                            text: "Сохранить ключи"
                            enabled: lastfmApiKeyField.text.trim().length > 0
                                && (lastfmApiSecretField.text.trim().length > 0 || Backend.lastfmHasCustomSecret)
                            onClicked: {
                                Backend.feature({
                                    action: "set_lastfm_config",
                                    customApiKey: lastfmApiKeyField.text.trim(),
                                    customApiSecret: lastfmApiSecretField.text.trim()
                                });
                                lastfmApiSecretField.text = "";
                                UiState.showToast("Ключи Last.fm сохранены");
                            }
                        }
                        TextButton {
                            visible: Backend.lastfmCustomApiKey.length > 0 || Backend.lastfmHasCustomSecret
                            variant: TextButton.Outlined
                            symbol: "restart_alt"
                            text: "Сбросить ключи"
                            onClicked: {
                                lastfmApiKeyField.text = "";
                                lastfmApiSecretField.text = "";
                                Backend.feature({action: "lastfm_clear_custom_keys"});
                            }
                        }
                    }
                }

                ConfigSwitch {
                    text: "Включить скробблинг Last.fm"
                    enabled: Backend.lastfmConnected
                    checked: Backend.lastfmEnabled
                    onToggledTo: (checked) => Backend.feature({action: "set_lastfm_config", enabled: checked})
                }
                ConfigSwitch {
                    text: "Отправлять статус «Сейчас играет»"
                    enabled: Backend.lastfmConnected && Backend.lastfmEnabled
                    checked: Backend.lastfmNowPlaying
                    onToggledTo: (checked) => Backend.feature({action: "set_lastfm_config", nowPlaying: checked})
                }
                ConfigSwitch {
                    text: "Отправлять лайк (♥ Love) в Last.fm"
                    enabled: Backend.lastfmConnected && Backend.lastfmEnabled
                    checked: Backend.lastfmLoveOnLike
                    onToggledTo: (checked) => Backend.feature({action: "set_lastfm_config", loveOnLike: checked})
                }
                ConfigSwitch {
                    text: "Не скробблить AI-треки (Slopless)"
                    enabled: Backend.lastfmConnected && Backend.lastfmEnabled
                    checked: Backend.lastfmSkipAi
                    onToggledTo: (checked) => Backend.feature({action: "set_lastfm_config", skipAi: checked})
                }
                NoteText {
                    text: Backend.lastfmHasBuiltinKeys
                        ? "Скробблинг срабатывает после прослушивания ≥ 50% трека (или 4 мин для длинных треков, от 30 сек). При потере сети скробблы сохраняются в локальную очередь."
                        : "В этой локальной сборке не заданы встроенные LASTFM_API_KEY/LASTFM_API_SECRET. Введите свои ключи с last.fm/api/account/create или используйте релизную сборку GitHub Actions."
                }
            }

            ContentSection {
                title: "Горячие клавиши"
                symbol: "keyboard"

                KeyRow { label: "Пауза / Воспроизведение"; shortcut: "Пробел" }
                KeyRow { label: "Следующий / Предыдущий трек"; shortcut: "Ctrl + → / ←" }
                KeyRow { label: "Перемотка ±10 секунд"; shortcut: "Ctrl + Alt + → / ←" }
                KeyRow { label: "Громкость"; shortcut: "Ctrl + ↑ / ↓" }
                KeyRow { label: "Без звука"; shortcut: "Ctrl + Alt + M" }
                KeyRow { label: "Перемешать / Повтор"; shortcut: "Ctrl + Alt + S / R" }
                KeyRow { label: "Поиск музыки"; shortcut: "Ctrl + K" }
                KeyRow { label: "Масштаб интерфейса"; shortcut: "Ctrl + + / - / 0" }
                KeyRow { label: "Перезагрузить моды"; shortcut: "Ctrl + Shift + R" }
                KeyRow { label: "Настройки"; shortcut: "Ctrl + ," }
            }
            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                visible: implicitHeight > 0
                slotName: "settings.section.integrations"
            }
        }

        // 5: Моды и расширения
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 5

            ContentSection {
                title: "Система модов"
                symbol: "widgets"

                Rectangle {
                    visible: ModManager.safeMode
                    x: 8
                    width: parent.width - 16
                    implicitHeight: safeText.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: Appearance.colors.errorContainer

                    StyledText {
                        id: safeText
                        anchors.fill: parent
                        anchors.margins: 10
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.onErrorContainer
                        font.pixelSize: Appearance.fontSize.smaller
                        text: "Клиент запущен в безопасном режиме (--safe-mode / Shift). Все моды и UI-оверрайды временно отключены."
                    }
                }

                Rectangle {
                    visible: ModManager.overridesNeedRestart
                    x: 8
                    width: parent.width - 16
                    implicitHeight: restartText.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: Appearance.colors.tertiaryContainer

                    StyledText {
                        id: restartText
                        anchors.fill: parent
                        anchors.margins: 10
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.onTertiaryContainer
                        font.pixelSize: Appearance.fontSize.smaller
                        text: "Вы изменили моды с подменой экранов (ui:override). Перезапустите клиент, чтобы новые оверрайды вёрстки применились полностью."
                    }
                }

                ConfigSwitch {
                    text: "Включить систему модов"
                    enabled: !ModManager.safeMode
                    checked: AppSettings.modsEnabled
                    onToggledTo: (checked) => AppSettings.modsEnabled = checked
                }

                ConfigSwitch {
                    text: "Режим разработчика (автоперезагрузка при изменении файлов)"
                    enabled: ModManager.modsEnabled
                    checked: AppSettings.modDevMode
                    onToggledTo: (checked) => AppSettings.modDevMode = checked
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "folder_open"
                        text: "Папка модов"
                        onClicked: {
                            if (!ModManager.openModsFolder()) {
                                UiState.showToast("Не удалось открыть папку модов");
                            }
                        }
                    }
                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "archive"
                        text: "Установить .ymmod…"
                        onClicked: installModArchiveDialog.open()
                    }
                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "add"
                        text: "Установить папку мода…"
                        onClicked: installModFolderDialog.open()
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "refresh"
                        text: "Перезагрузить моды"
                        enabled: ModManager.modsEnabled
                        onClicked: {
                            ModManager.reloadMods();
                            UiState.showToast("Моды перезагружены");
                        }
                    }
                }

                NoteText {
                    text: "Активных модов: " + ModManager.activeModCount
                        + (ModManager.activeOverrideCount > 0 ? (" • UI-оверрайдов: " + ModManager.activeOverrideCount) : "")
                        + ". Безопасный запуск без модов: ymusic-qml --safe-mode или удержание Shift при старте."
                }
                NoteText {
                    text: "Моды выполняются на движке QML внутри интерфейса клиента. Устанавливайте моды только из надёжных источников."
                }
            }

            ContentSection {
                title: "Установленные моды"
                symbol: "layers"

                NoteText {
                    visible: ModManager.mods.length === 0
                    text: "Установленных модов пока нет. Скопируйте папку мода с manifest.json в каталог модов (или нажмите «Установить папку мода…»)."
                }

                Repeater {
                    model: ModManager.mods

                    delegate: Rectangle {
                        id: modCard
                        required property int index
                        required property var modelData
                        x: 8
                        width: parent ? parent.width - 16 : 0
                        implicitHeight: modCardCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.surfaceContainer
                        border.width: 1
                        border.color: !modelData.valid
                            ? Appearance.colors.error
                            : (modelData.enabled ? Appearance.colors.primary : Appearance.colors.outlineVariant)

                        Column {
                            id: modCardCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                width: parent.width
                                spacing: 8

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Row {
                                        spacing: 8
                                        StyledText {
                                            text: modCard.modelData.name || modCard.modelData.id
                                            font.weight: Font.DemiBold
                                        }
                                        StyledText {
                                            text: "v" + (modCard.modelData.version || "1.0.0")
                                            font.pixelSize: Appearance.fontSize.smaller
                                            color: Appearance.colors.onSurfaceVariant
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            visible: (modCard.modelData.author || "").length > 0
                                            text: "• " + (modCard.modelData.author || "")
                                            font.pixelSize: Appearance.fontSize.smaller
                                            color: Appearance.colors.onSurfaceVariant
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        visible: (modCard.modelData.description || "").length > 0
                                        text: modCard.modelData.description || ""
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: Appearance.fontSize.smaller
                                        color: Appearance.colors.onSurfaceVariant
                                    }
                                }

                                IconButton {
                                    visible: ModManager.mods.length > 1
                                    enabled: modCard.index > 0
                                    symbol: "arrow_upward"
                                    size: 30
                                    iconSize: 17
                                    tooltip: "Выше приоритет загрузки"
                                    onClicked: ModManager.moveMod(modCard.modelData.id, -1)
                                }

                                IconButton {
                                    visible: ModManager.mods.length > 1
                                    enabled: modCard.index < ModManager.mods.length - 1
                                    symbol: "arrow_downward"
                                    size: 30
                                    iconSize: 17
                                    tooltip: "Ниже приоритет загрузки"
                                    onClicked: ModManager.moveMod(modCard.modelData.id, 1)
                                }

                                IconButton {
                                    visible: Boolean(modCard.modelData.enabled && modCard.modelData.hasSettings)
                                    symbol: "settings"
                                    tooltip: "Настройки мода"
                                    onClicked: {
                                        modSettingsDialog.modTitle = modCard.modelData.name || modCard.modelData.id;
                                        modSettingsDialog.modId = modCard.modelData.id;
                                        modSettingsDialog.settingsUrl = modCard.modelData.settingsUrl;
                                        modSettingsDialog.open();
                                    }
                                }

                                IconButton {
                                    symbol: "delete"
                                    tooltip: "Удалить мод"
                                    onClicked: {
                                        const name = modCard.modelData.name || modCard.modelData.id;
                                        if (ModManager.uninstallMod(modCard.modelData.id)) {
                                            UiState.showToast("Мод «" + name + "» удалён");
                                        } else {
                                            UiState.showToast("Не удалось удалить мод");
                                        }
                                    }
                                }

                                StyledSwitch {
                                    enabled: Boolean(modCard.modelData.valid) && ModManager.modsEnabled
                                    checked: Boolean(modCard.modelData.enabled)
                                    onToggled: ModManager.setModEnabled(modCard.modelData.id, checked)
                                }
                            }

                            StyledText {
                                width: parent.width
                                visible: !modCard.modelData.valid
                                text: "Ошибка манифеста: " + (modCard.modelData.error || "")
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.fontSize.smaller
                                color: Appearance.colors.error
                            }

                            StyledText {
                                width: parent.width
                                visible: (modCard.modelData.warnings || []).length > 0
                                text: "Предупреждение: " + (modCard.modelData.warnings || []).join(" • ")
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.fontSize.smaller
                                color: Appearance.colors.tertiary
                            }

                            StyledText {
                                width: parent.width
                                visible: (modCard.modelData.overrideTargets || []).length > 0
                                text: "Подмена UI (полный доступ): " + (modCard.modelData.overrideTargets || []).join(", ")
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.fontSize.smaller
                                color: Appearance.colors.tertiary
                            }

                            StyledText {
                                width: parent.width
                                visible: (modCard.modelData.conflicts || []).length > 0
                                text: "Конфликты оверрайдов: " + (modCard.modelData.conflicts || []).join(", ")
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.fontSize.smaller
                                color: Appearance.colors.error
                            }

                            Flow {
                                width: parent.width
                                spacing: 6
                                visible: (modCard.modelData.permissions || []).length > 0

                                Repeater {
                                    model: modCard.modelData.permissions || []
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool elevated: modelData === "ui:override" || modelData.startsWith("network:")
                                        width: permLabel.implicitWidth + 14
                                        height: 22
                                        radius: Appearance.rounding.verySmall
                                        color: elevated ? Appearance.colors.tertiaryContainer : Appearance.colors.surfaceContainerHigh

                                        StyledText {
                                            id: permLabel
                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            font.pixelSize: Appearance.fontSize.smallest
                                            color: parent.elevated ? Appearance.colors.onTertiaryContainer : Appearance.colors.onSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ContentSection {
                title: "Консоль модов"
                symbol: "terminal"

                NoteText {
                    visible: ModManager.logs.length === 0
                    text: "Сообщений и ошибок от модов пока нет."
                }

                Rectangle {
                    visible: ModManager.logs.length > 0
                    x: 8
                    width: parent.width - 16
                    implicitHeight: Math.min(220, logsCol.implicitHeight + 20)
                    radius: Appearance.rounding.small
                    color: Appearance.colors.surfaceContainerLowest
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant
                    clip: true

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 10
                        contentHeight: logsCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        Column {
                            id: logsCol
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: ModManager.logs
                                delegate: StyledText {
                                    required property var modelData
                                    width: parent ? parent.width : 0
                                    wrapMode: Text.WrapAnywhere
                                    font.family: Appearance.monoFontFamily
                                    font.pixelSize: Appearance.fontSize.smaller
                                    color: modelData.level === "error"
                                        ? Appearance.colors.error
                                        : (modelData.level === "warn" ? Appearance.colors.tertiary : Appearance.colors.onSurfaceVariant)
                                    text: "[" + modelData.time + "] [" + modelData.modId + "] " + modelData.message
                                }
                            }
                        }
                    }
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    visible: ModManager.logs.length > 0

                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "delete"
                        text: "Очистить консоль"
                        onClicked: ModManager.clearLogs()
                    }
                }
            }
        }

        // 6: Система и аккаунт
        Page {
            visible: root.activeModTabId.length === 0 && root.page === 6

            ContentSection {
                title: "Аккаунт Яндекс"
                symbol: "account_circle"

                StatusRow {
                    label: Backend.loggedIn ? (Backend.userName || "Пользователь") : "Не выполнен вход"
                    value: Backend.loggedIn ? "Подключён" : "Нет авторизации"
                    good: Backend.loggedIn
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4
                    visible: Backend.loggedIn

                    TextButton {
                        symbol: "logout"
                        text: "Выйти из аккаунта"
                        colBackground: Appearance.colors.error
                        colBackgroundHover: Appearance.colors.errorHover
                        labelColor: Appearance.colors.onError
                        onClicked: logoutDialog.open()
                    }
                }

                StyledDialog {
                    id: logoutDialog
                    headline: "Выйти из аккаунта?"
                    symbol: "logout"
                    iconShape: "ghostish"
                    body: "Токен авторизации будет удалён с этого устройства. Загруженные треки останутся на диске."
                    buttons: [
                        TextButton {
                            text: "Отмена"
                            variant: TextButton.Text
                            onClicked: logoutDialog.close()
                        },
                        TextButton {
                            text: "Выйти"
                            colBackground: Appearance.colors.error
                            colBackgroundHover: Appearance.colors.errorHover
                            labelColor: Appearance.colors.onError
                            onClicked: {
                                Backend.logout();
                                logoutDialog.accept();
                            }
                        }
                    ]
                }
            }

            ContentSection {
                title: "Файлы и кэш"
                symbol: "folder_open"

                StatusRow {
                    label: "Кэш обложек и изображений"
                    value: root.cacheSizeLabel
                    good: true
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "folder_open"
                        text: "Папка загрузок"
                        onClicked: {
                            if (!AppSettings.openOfflineFolder()) {
                                UiState.showToast("Не удалось открыть папку загрузок.");
                            }
                        }
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "cleaning_services"
                        text: "Очистить кэш"
                        onClicked: {
                            if (AppSettings.clearCoverCache()) {
                                root.cacheSizeLabel = AppSettings.cacheSizeText();
                                UiState.showToast("Кэш обложек очищен");
                            } else {
                                UiState.showToast("Не все файлы кэша удалось удалить");
                            }
                        }
                    }
                }
            }

            ContentSection {
                title: "Обновления и версия"
                symbol: "system_update"

                StatusRow {
                    label: "Версия v" + Updater.currentVersion
                    value: Updater.supported ? Updater.statusText : "Автообновление активно только на Windows"
                    good: !Updater.supported || !Updater.hasError
                }

                ConfigSwitch {
                    visible: Updater.supported
                    text: "Автоматически проверять и скачивать обновления"
                    checked: AppSettings.autoUpdateEnabled
                    onToggledTo: (checked) => AppSettings.autoUpdateEnabled = checked
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4

                    TextButton {
                        visible: Updater.supported && Updater.readyToInstall
                        variant: TextButton.Filled
                        symbol: "restart_alt"
                        text: "Перезапустить и обновить" + (Updater.latestVersion.length > 0 ? (" (v" + Updater.latestVersion + ")") : "")
                        onClicked: Updater.installAndRestart()
                    }
                    TextButton {
                        visible: Updater.supported && Updater.portableUpdateAvailable
                        variant: TextButton.Filled
                        symbol: "open_in_new"
                        text: "Открыть релиз v" + Updater.latestVersion
                        onClicked: Updater.openReleasePage()
                    }
                    TextButton {
                        visible: Updater.supported && !Updater.readyToInstall
                        variant: TextButton.Tonal
                        symbol: "refresh"
                        text: Updater.busy ? "Обновление…" : "Проверить обновления"
                        enabled: !Updater.busy
                        onClicked: Updater.checkForUpdates(true)
                    }
                    TextButton {
                        variant: TextButton.Text
                        symbol: "open_in_new"
                        text: "Релизы на GitHub"
                        onClicked: Updater.openReleasePage()
                    }
                }
            }

            ContentSection {
                title: "Обслуживание и отладка"
                symbol: "bug_report"

                ConfigSwitch {
                    text: "Отладочный циферблат (секунды в таймере сна)"
                    checked: AppSettings.debuggingEnabled
                    onToggledTo: (checked) => AppSettings.debuggingEnabled = checked
                }

                Flow {
                    x: 8
                    width: parent.width - 16
                    spacing: 8
                    topPadding: 4

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "description"
                        text: "Папка логов"
                        onClicked: {
                            if (!AppSettings.openLogsFolder()) {
                                UiState.showToast("Не удалось открыть папку логов.");
                            }
                        }
                    }
                    TextButton {
                        variant: TextButton.Outlined
                        symbol: "restart_alt"
                        text: "Сбросить настройки интерфейса"
                        onClicked: resetUiDialog.open()
                    }
                }

                StyledDialog {
                    id: resetUiDialog
                    headline: "Сбросить настройки интерфейса?"
                    symbol: "restart_alt"
                    iconShape: "clover4"
                    body: "Все настройки оформления, визуализаторов, анимаций и окна вернутся к значениям по умолчанию. Аккаунт и загрузки не пострадают."
                    buttons: [
                        TextButton {
                            text: "Отмена"
                            variant: TextButton.Text
                            onClicked: resetUiDialog.close()
                        },
                        TextButton {
                            text: "Сбросить"
                            variant: TextButton.Filled
                            onClicked: {
                                AppSettings.resetUiSettings();
                                resetUiDialog.accept();
                                UiState.showToast("Настройки интерфейса сброшены");
                            }
                        }
                    ]
                }
            }

            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                visible: implicitHeight > 0
                slotName: "settings.section.system"
            }
        }

        // Динамическая глава настроек, добавленная модом (slot: "settings.tab")
        Page {
            visible: root.activeModTabId.length > 0

            ModSlotHost {
                layoutMode: "column"
                width: parent.width
                slotName: "settings.tab"
                filterEntryId: root.activeModTabId
            }
        }
    }

    ColorDialog {
        id: accentColorDialog
        title: "Выбор акцентного цвета"
        onAccepted: AppSettings.customAccentColor = String(selectedColor)
    }

    FileDialog {
        id: exportThemeDialog
        title: "Экспортировать тему (.ymtheme)"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "ymtheme"
        nameFilters: ["Тема Yandex Music (*.ymtheme)", "JSON (*.json)"]
        onAccepted: {
            const res = Theme.exportThemeFile(selectedFile);
            UiState.showToast(res.ok ? "Тема экспортирована" : (res.error || "Ошибка экспорта"));
        }
    }

    FileDialog {
        id: importThemeDialog
        title: "Импортировать тему (.ymtheme / .json)"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Темы (*.ymtheme *.json)"]
        onAccepted: {
            const res = Theme.importThemeFile(selectedFile, true);
            UiState.showToast(res.ok ? ("Тема «" + res.name + "» применена") : (res.error || "Ошибка импорта"));
        }
    }

    FileDialog {
        id: installModArchiveDialog
        title: "Выберите архив мода (.ymmod / .zip)"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Архивы модов (*.ymmod *.zip)"]
        onAccepted: {
            const res = ModManager.installModFromArchive(selectedFile);
            UiState.showToast(res.ok ? ("Мод «" + res.name + "» установлен. Включите его в списке.") : (res.error || "Ошибка установки архива"));
            if (res.ok && res.hasOverrides) {
                overrideInstallWarningDialog.modName = res.name || res.id || "";
                overrideInstallWarningDialog.overrideTargets = res.overrideTargets || [];
                overrideInstallWarningDialog.open();
            }
        }
    }

    FolderDialog {
        id: installModFolderDialog
        title: "Выберите папку мода (содержащую manifest.json)"
        onAccepted: {
            const res = ModManager.installModFromFolder(selectedFolder);
            UiState.showToast(res.ok ? ("Мод «" + res.name + "» установлен. Включите его в списке.") : (res.error || "Ошибка установки мода"));
            if (res.ok && res.hasOverrides) {
                overrideInstallWarningDialog.modName = res.name || res.id || "";
                overrideInstallWarningDialog.overrideTargets = res.overrideTargets || [];
                overrideInstallWarningDialog.open();
            }
        }
    }

    StyledDialog {
        id: overrideInstallWarningDialog
        property string modName: ""
        property var overrideTargets: []
        headline: "Мод получает полный доступ"
        symbol: "warning"
        iconShape: "cookie9"
        preferredWidth: 460

        StyledText {
            width: parent ? parent.width : 400
            wrapMode: Text.WordWrap
            color: Appearance.colors.onSurfaceVariant
            text: "Мод «" + overrideInstallWarningDialog.modName
                + "» использует механизм overrides и подменяет файлы интерфейса приложения целиком ("
                + (overrideInstallWarningDialog.overrideTargets || []).join(", ")
                + "). Такой мод получает полный доступ к приложению вне песочницы. Включайте его только если доверяете автору."
        }

        buttons: [
            TextButton {
                text: "Понятно"
                variant: TextButton.Filled
                onClicked: overrideInstallWarningDialog.close()
            }
        ]
    }

    StyledDialog {
        id: modSettingsDialog
        property string modTitle: ""
        property string modId: ""
        property url settingsUrl: ""
        headline: modTitle.length > 0 ? ("Настройки: " + modTitle) : "Настройки мода"
        symbol: "settings"
        iconShape: "cookie9"
        preferredWidth: 480

        ModSlotItem {
            id: modSettingsHost
            width: parent ? parent.width : 420
            height: implicitHeight
            modId: modSettingsDialog.modId
            slotName: "settings"
            sourceUrl: modSettingsDialog.settingsUrl
            reloadRevision: ModManager.reloadRevision
            fillContent: false
            fitWidth: true
            active: modSettingsDialog.opened && String(modSettingsDialog.settingsUrl).length > 0
        }

        buttons: [
            TextButton {
                text: "Готово"
                variant: TextButton.Filled
                onClicked: modSettingsDialog.close()
            }
        ]
    }
}
