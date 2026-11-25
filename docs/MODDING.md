# Моддинг ymusic

Моды пишутся на QML и JavaScript (плюс опциональные `.qsb`-шейдеры Qt 6 RHI) и работают на Linux и Windows без пересборки клиента.

## Установка и структура

Папка с модами:
- **Linux:** `~/.local/share/ymusic/mods/`
- **Windows:** `%LOCALAPPDATA%\ymusic\mods\`

Открыть её можно из **Настройки → Моды → Папка модов**. Там же можно установить готовый архив `.ymmod` или `.zip` (это обычный ZIP с `manifest.json` в корне или внутри одной папки).

Каждый мод — отдельная директория с `manifest.json` внутри, например:

```text
mods/
└── my-mod/
    ├── manifest.json
    ├── main.qml
    └── ui/
        └── Widget.qml
```

Порядок загрузки и приоритет при конфликте `overrides` задаётся в списке модов стрелками ↑/↓ (выше в списке — выше приоритет).

### Отладка и безопасный режим

- **Режим разработчика** (**Настройки → Моды**) включает `QFileSystemWatcher` и перезагружает включённые моды при сохранении файлов.
- **`Ctrl+Shift+R`** — ручная перезагрузка всех модов (сбрасывает кэш QML-компонентов и пересоздаёт `ModApi`).
- Логи и ошибки QML выводятся в **Настройки → Моды → Консоль модов** и в `ymusic.log`.
- **`ymusic-qml --safe-mode`** или удержание **`Shift`** при запуске отключает все моды и `overrides`.
- Если `ui:override` ломает загрузку `Main.qml`, клиент автоматически отключает проблемный мод (карантин) и запускает стандартный интерфейс.

Примеры в репозитории:
- [`examples/mods/hello-ymusic/`](../examples/mods/hello-ymusic/) — скрипт, пункт в `TrackMenu`, страница в сайдбаре, оверлей в `ImmersivePlayer`, окно настроек.
- [`examples/mods/top-nav-pill/`](../examples/mods/top-nav-pill/) — скрытие сайдбара через `overrides` и верхняя панель навигации в `topbar.center`.

---

## Жизненный цикл

При включении мода `ModManager` создаёт отдельный экземпляр C++-объекта `ModApi` (`modApi`). Все подписки, пункты `TrackMenu`, хоткеи и HTTP-запросы привязаны к этому объекту. При выключении или перезагрузке `ModApi` уничтожается: незавершённые `QNetworkReply` отменяются, пункты меню и хоткеи удаляются, кэш QML сбрасывается.

---

## Формат `manifest.json`

```json
{
  "id": "my-mod",
  "name": "My Mod",
  "version": "1.0.0",
  "author": "handle",
  "description": "Короткое описание для списка модов.",
  "minAppVersion": "0.3.0",
  "apiVersion": 1,

  "entry": {
    "script": "main.qml",
    "settings": "ui/Settings.qml"
  },

  "ui": {
    "sidebar.page": [
      { "id": "main", "file": "ui/Page.qml", "title": "Мой экран", "symbol": "auto_awesome", "shape": "gem" },
      { "id": "stats", "file": "ui/Stats.qml", "title": "Статистика", "symbol": "bar_chart" }
    ],
    "topbar.center": "ui/TopWidget.qml",
    "playerBar.controls": "ui/PlayerButton.qml",
    "immersive.panel": {
      "file": "ui/ImmersivePanel.qml",
      "title": "Анализатор",
      "symbol": "graphic_eq"
    },
    "settings.tab": {
      "file": "ui/SettingsTab.qml",
      "title": "Мой мод",
      "symbol": "tune",
      "shape": "flower"
    },
    "settings.section.player": "ui/PlayerSettingsSection.qml"
  },

  "shortcuts": [
    { "id": "toggle-panel", "sequence": "Ctrl+Alt+T", "description": "Переключить панель" }
  ],

  "overrides": {
    "qml/sidebar/Sidebar.qml": "overrides/Sidebar.qml"
  },

  "permissions": [
    "playback:read",
    "playback:control",
    "library:read",
    "lyrics:read",
    "lyrics:transform",
    "spectrum:read",
    "ui:slots",
    "ui:override",
    "storage",
    "clipboard",
    "network:api.example.com"
  ]
}
```

### Поля и валидация

- `id` — соответствует `^[a-z0-9][a-z0-9_-]{1,47}$`.
- `apiVersion` — сейчас `1`.
- `minAppVersion` — минимальная версия клиента (`QVersionNumber`). Если клиент старее, мод не загружается и показывает ошибку в списке.
- `ui` (старое имя `slots` тоже принимается) — для каждого слота можно указать:
  - строку с путём к QML (`"topbar.center": "ui/TopWidget.qml"`);
  - объект с `file` и метаданными (`id`, `title`, `symbol`, `shape`);
  - массив строк и/или объектов, если нужно добавить несколько элементов в один слот.
- Все пути в `entry`, `ui` и `overrides` должны быть относительными и оставаться внутри папки мода (`..` и симлинки наружу отклоняются).
- `overrides` без разрешения `"ui:override"` не принимается.

---

## Разрешения (`permissions`)

Моды выполняются в общем QML-движке приложения без песочницы ОС. Разрешения ограничивают методы `ModApi` и показываются пользователю в карточке мода вместе со списком `overrides`.

| Разрешение | Доступ | Ограничения |
|---|---|---|
| `playback:read` | Свойства текущего трека, состояния плеера, прогресса, громкости, темпа | Без доступа к OAuth-токену |
| `playback:control` | `toggle()`, `next()`, `prev()`, `seek()`, `setVolume()`, `toggleLike()`, `playNext()`, `addToQueue()` | Нет доступа к аккаунту и выходу |
| `library:read` | `queueTracks()`, `currentTracks()`, `historyTracks()`, сигнал `libraryChanged` | Только чтение |
| `lyrics:read` | `lyricsTrackId`, `lyricsSynced`, `lyricsLines`, сигнал `lyricsChanged` | Только чтение |
| `lyrics:transform` | `setLyricSubtitles(trackId, lines)`, `clearLyricSubtitles()` | Добавляет подстрочник под строками текста |
| `spectrum:read` | `spectrumLevels()` (48 полос), `spectrumEnergies()` (5 полос), сигнал `spectrumUpdated` | 60 Hz, без сырого PCM |
| `ui:slots` | UI-слоты, навигация (`openHome`, `openPlaylist` и т.д.), `showToast()`, `openImmersive()`, `openSettings()`, `openCreatePlaylist()`, `openExternalUrl()`, `registerTrackMenuAction()`, `registerShortcut()` | `openExternalUrl` принимает только `http://` и `https://` |
| `ui:override` | Подмена QML-файлов `ymusic.ui` через `ModUrlInterceptor` | Применяется после перезапуска |
| `storage` | `storageGet`, `storageSet`, `storageRemove`, `storageAll` | Отдельный файл `mod-data/<mod-id>.json` |
| `clipboard` | `copyText(text)` | Только запись |
| `network:<host>` | `httpGet(url, requestId)`, `httpRequest(method, url, headers, body, requestId)`, сигнал `httpFinished(...)` | Только HTTPS (или `http://localhost` / `127.0.0.1`), методы `GET/POST/PUT/PATCH/DELETE`, заголовки `Host`/`Cookie`/`Content-Length` вырезаются, лимит ответа 4 МБ, таймаут 15 с |

---

## UI-слоты (`ui`)

В каждый компонент слота передаются два свойства:
- `property var modApi: null`
- `property var slotContext: ({})`

| Слот | Хост | Раскладка | `slotContext` | Назначение |
|---|---|---|---|---|
| `window.backdrop` | `Main.qml` (`z: -1`) | `fill` | `{}` | Фон окна, шейдеры |
| `topbar.center` | `TopBar.qml` | `fill` | `{ topBarWidth, compact }` | Центральная часть верхней панели |
| `topbar.right` | `TopBar.qml` | `row` (`height: buttonSize`) | `{ buttonSize, compact }` | Кнопки справа в верхней панели |
| `sidebar.page` | `Main.qml` + `Sidebar.qml` | `fill` | `{}` | Отдельная страница в навигации |
| `home.top` | `HomeView.qml` | `column` | `{ narrow }` | Блок вверху Главной |
| `home.sections` | `HomeView.qml` | `column` | `{ narrow }` | Секции на Главной |
| `search.top` | `SearchView.qml` | `column` | `{ query, filter, loading }` | Блок вверху экрана поиска |
| `collection.actions` | `CollectionHero.qml` | `row` (`height: 40`) | `{ title, isArtist, kind, playlistKey }` | Кнопки в шапке плейлиста / альбома / артиста |
| `card.overlay` | `CardItem.qml` (`z: 2`) | `fill` | `{ card, index, title, subtitle, isArtist, isPlaylist, hovered }` | Оверлей на карточках (ленивый) |
| `trackRow.badges` | `TrackRow.qml` | `row` (`height: 28`) | `{ track, index, isCurrent, hovered }` | Бейджи и кнопки в строке трека (ленивый) |
| `playerBar.left` | `FloatingPlayerBar.qml` | `row` (`height: buttonSize`) | `{ scheme, buttonSize, compact, tiny }` | Кнопки слева в плеере |
| `playerBar.controls` | `FloatingPlayerBar.qml` | `row` (`height: buttonSize`) | `{ scheme, buttonSize, compact }` | Кнопки справа в плеере |
| `playerBar.overlay` | `FloatingPlayerBar.qml` | `fill` (`z: 0`) | `{ scheme, compact, twoRow }` | Фоновый слой бара плеера |
| `lyrics.header` | `LyricsPanel.qml` | `row` (`height: 28`) | `{ scheme, trackId, synced, wordSynced }` | Кнопки в шапке панели текста |
| `queue.header` | `QueuePanel.qml` | `row` (`height: 32`) | `{ scheme, count }` | Кнопки в шапке панели очереди |
| `wave.overlay` | `WaveHero.qml` | `fill` (`z: 15`) | `{ inWave, applying }` | Оверлей экрана «Моя волна» |
| `immersive.backdrop` | `ImmersivePlayer.qml` | `fill` | `{ scheme }` | Фон полноэкранного плеера |
| `immersive.overlay` | `ImmersivePlayer.qml` | `fill` (`z: 50`) | `{ scheme, controlsOpacity }` | Оверлей в полноэкранном плеере |
| `immersive.panel` | `ImmersivePlayer.qml` | `fill` | `{ scheme }` | Дополнительная боковая панель |
| `immersive.lyrics.header` | `ImmersiveLyrics.qml` | `row` (`height: 30`) | `{ scheme, trackId, synced }` | Шапка текста в полноэкранном плеере |
| `immersive.queue.header` | `ImmersiveQueue.qml` | `row` (`height: 32`) | `{ scheme, count }` | Шапка очереди в полноэкранном плеере |
| `settings.tab` | `SettingsDialog.qml` + `SettingsPages.qml` | `column` | `{}` | Отдельная вкладка в Настройках |
| `settings.section.appearance` | `SettingsPages.qml` | `column` | `{}` | Секция в «Оформление» |
| `settings.section.player` | `SettingsPages.qml` | `column` | `{}` | Секция в «Плеер и фон» |
| `settings.section.audio` | `SettingsPages.qml` | `column` | `{}` | Секция в «Звук» |
| `settings.section.animations` | `SettingsPages.qml` | `column` | `{}` | Секция в «Анимации» |
| `settings.section.integrations` | `SettingsPages.qml` | `column` | `{}` | Секция в «Интеграции» |
| `settings.section.system` | `SettingsPages.qml` | `column` | `{}` | Секция в «Система» |

Для `column`-слотов корневой элемент должен задавать `implicitHeight`, для `row`-слотов — `implicitWidth` (или `width`).

---

## Справочник `modApi`

### Свойства (read-only)

- **Мод:** `modId`, `modName`, `permissions`, `hasPermission(perm)`
- **Трек (`playback:read`):** `hasTrack`, `trackId`, `trackTitle`, `trackArtists`, `trackAlbum`, `trackCover`, `trackLiked`, `trackIsAi`
- **Плеер (`playback:read`):** `playing`, `buffering`, `volume` (`0..1`), `shuffle`, `repeatMode` (`0` = выкл, `1` = все, `2` = один), `tempo`, `positionSecs`, `durationSecs`, `progress` (`0..1`)
- **Навигация и профиль:** `currentPage`, `canGoBack`, `loggedIn`, `userName`, `userAvatar`, `pinnedPlaylists`
- **Текст (`lyrics:read`):** `lyricsTrackId`, `lyricsSynced`, `lyricsLines` (массив `{ text, time, words }`)

### Сигналы

- `trackChanged()`
- `playbackChanged()`
- `positionChanged()`
- `navigationChanged()`
- `libraryChanged()` *(требует `library:read`)*
- `lyricsChanged()` *(требует `lyrics:read`)*
- `spectrumUpdated()` *(60 Hz, требует `spectrum:read`)*
- `trackMenuActionTriggered(actionId, trackId, trackTitle)`
- `shortcutTriggered(actionId)`
- `httpFinished(requestId, statusCode, body, error)`

### Методы

- **Управление (`playback:control`):** `toggle()`, `next()`, `prev()`, `seek(0..1)`, `setVolume(0..1)`, `toggleLike()`, `playNext(trackId)`, `addToQueue(trackId)`
- **Навигация (`ui:slots`):** `openHome()`, `openWave()`, `openLikes()`, `openDownloads()`, `openPlaylists()`, `openAlbums()`, `openArtists()`, `openSearch(query)`, `openPlaylist(uid, kind, title)`, `goBack()`, `openCreatePlaylist()`
- **Списки треков (`library:read`):** `queueTracks()`, `currentTracks()`, `historyTracks()` — возвращают массивы `{ id, title, artists, album, durationSecs, coverUrl, liked, available, isAi }`
- **Субтитры (`lyrics:transform`):** `setLyricSubtitles(trackId, subtitles)`, `clearLyricSubtitles()`
- **Спектр (`spectrum:read`):** `spectrumLevels()` (`number[48]`), `spectrumEnergies()` (`number[5]`, от низов к верхам)
- **Хранилище (`storage`):** `storageGet(key, fallback)`, `storageSet(key, value)`, `storageRemove(key)`, `storageAll()`
- **UI (`ui:slots`):**
  - `showToast(message)`
  - `openImmersive()`, `closeImmersive()`
  - `openSettings()`
  - `openExternalUrl(url)`
  - `registerTrackMenuAction(actionId, label, symbol, destructive)`, `unregisterTrackMenuAction(actionId)`
  - `registerShortcut(actionId, sequence, description)`, `unregisterShortcut(actionId)`
- **Буфер (`clipboard`):** `copyText(text)`
- **Сеть (`network:<host>`):**
  - `httpGet(url, requestId)`
  - `httpRequest(method, url, headers, body, requestId)`
- **Логи:** `log(message)`, `warn(message)`

---

## Компоненты `import ymusic.ui`

Из модуля `ymusic.ui` доступны токены и контролы клиента:

- **Токены (`Appearance`):**
  - `Appearance.colors` (`primary`, `onPrimary`, `primaryContainer`, `onPrimaryContainer`, `surface`, `surfaceContainer`, `surfaceContainerHigh`, `onSurface`, `onSurfaceVariant`, `outlineVariant`, `error`, `layer0`, `layer1`, `layer2Hover`, `dark`)
  - `Appearance.rounding` (`verySmall`, `small`, `normal`, `large`, `veryLarge`, `full`)
  - `Appearance.fontSize` (`smallest`, `smaller`, `small`, `normal`, `large`, `title`, `headline`)
  - `Appearance.fontFamily`, `Appearance.monoFontFamily`
  - `Appearance.curves.expressiveFastSpatial`, `Appearance.duration(ms)`, `Appearance.motion(ms)`, `Appearance.performanceMode`
- **Контролы:** `StyledText`, `TitleText`, `TextButton` (`Filled` / `Tonal` / `Outlined` / `Text`), `IconButton`, `RippleButton`, `StyledSwitch`, `StyledSlider`, `StyledComboBox`, `OutlinedTextField`, `StyledMenu`, `StyledMenuItem`, `StyledMenuSeparator`, `StyledDialog`, `ArtworkImage`, `MaterialSymbol`, `ShapeIcon`, `SoftShadow`, `SpectrumView`.
- **Настройки:** `ContentSection`, `ConfigSwitch`, `ConfigSlider`, `ConfigSelection`, `NoteText`.

---

## Подмена файлов интерфейса (`overrides`)

Любой QML-файл модуля `ymusic.ui` можно заменить своим:

```json
"overrides": {
  "qml/sidebar/Sidebar.qml": "overrides/Sidebar.qml",
  "qml/player/FloatingPlayerBar.qml": "overrides/FloatingPlayerBar.qml"
}
```

Интерфейсы ключевых компонентов, на которые опирается `Main.qml`:

- **`qml/sidebar/Sidebar.qml`** — свойства `compact`, `expandedWidth`, `resizing`, `toggleVisible`, `isCompact`; сигналы `settingsRequested()`, `toggleCompactRequested()`. Чтобы полностью скрыть сайдбар, достаточно вернуть `Item { implicitWidth: 0; width: 0; visible: false }` с этими свойствами и сигналами.
- **`qml/shell/TopBar.qml`** — `required property Window window`, `property Item backdropSource`, `property bool windowControlsOnRight`, `property bool inspectorShown`, `readonly property bool searchEditing`; методы `focusSearch()`, `dismissSearch()`, `isSearchInteractiveAt(sourceItem, x, y)`.
- **`qml/player/FloatingPlayerBar.qml`** — сигнал `immersiveRequested()`.
- **`qml/library/TrackRow.qml`** — `required property int index`, `required property var model`, `property bool queueView`.

---

## Примеры

### Вкладка настроек (`settings.tab`)

```qml
import QtQuick
import ymusic.ui

Column {
    id: root
    property var modApi: null
    width: parent ? parent.width : 0
    spacing: 16

    ContentSection {
        title: "Мой мод"
        symbol: "auto_awesome"

        ConfigSwitch {
            text: "Включить функцию"
            checked: root.modApi ? Boolean(root.modApi.storageGet("enabled", true)) : true
            onToggledTo: (v) => {
                if (root.modApi) root.modApi.storageSet("enabled", v)
            }
        }
    }
}
```

### Кнопка в панели плеера (`playerBar.controls`)

```qml
import QtQuick
import ymusic.ui

IconButton {
    property var modApi: null
    property var slotContext: ({})
    scheme: slotContext.scheme || Appearance.colors
    size: slotContext.buttonSize || 34
    iconSize: 19
    symbol: "auto_awesome"
    tooltip: "Действие"
    onClicked: if (modApi) modApi.showToast("Нажато")
}
```

### Реакция на спектр (`immersive.overlay`)

```qml
import QtQuick
import ymusic.ui

Item {
    id: root
    property var modApi: null
    property var slotContext: ({})
    property real bassEnergy: 0

    Connections {
        target: root.modApi
        enabled: root.visible && root.modApi !== null
        function onSpectrumUpdated() {
            const e = root.modApi.spectrumEnergies()
            if (e.length > 0) root.bassEnergy = e[0]
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        width: 14 + root.bassEnergy * 24
        height: width
        radius: width / 2
        color: Appearance.colors.primary
        opacity: 0.75
    }
}
```

### Шейдеры `.qsb`

Qt 6 загружает предкомпилированные `.qsb`-файлы (сырой GLSL в рантайме не компилируется):

```bash
qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/effect.frag.qsb shaders/effect.frag
```

```qml
ShaderEffect {
    anchors.fill: parent
    fragmentShader: Qt.resolvedUrl("../shaders/effect.frag.qsb")
}
```

### HTTP-запрос (`POST`)

```qml
// permissions: ["network:api.listenbrainz.org", "playback:read", "ui:slots"]
function submitListen(artist, track) {
    const payload = JSON.stringify({
        listen_type: "playing_now",
        payload: [{ track_metadata: { artist_name: artist, track_name: track } }]
    })
    modApi.httpRequest(
        "POST",
        "https://api.listenbrainz.org/1/submit-listens",
        { "Content-Type": "application/json", "Authorization": "Token " + myToken },
        payload,
        "lb-now"
    )
}

Connections {
    target: root.modApi
    function onHttpFinished(requestId, statusCode, body, error) {
        if (requestId === "lb-now" && statusCode !== 200) {
            modApi.warn("ListenBrainz HTTP " + statusCode + ": " + error)
        }
    }
}
```

### Подстрочник для текста песни (`lyrics:read` + `lyrics:transform`)

```qml
Connections {
    target: root.modApi
    function onLyricsChanged() {
        const lines = root.modApi.lyricsLines
        if (!lines || lines.length === 0) return
        const subs = lines.map(l => myTransliterate(l.text || ""))
        root.modApi.setLyricSubtitles(root.modApi.lyricsTrackId, subs)
    }
}
```

Подстрочник отображается в `LyricsPanel` и `ImmersiveLyrics` и автоматически очищается при выключении или перезагрузке мода.

---

## Частые ошибки и производительность

- **`contentItem` в `RippleButton` / `AbstractButton`:** не задавайте `anchors.centerIn: parent` напрямую на `contentItem` — `AbstractButton` сам управляет его геометрией. Используйте обёртку `contentItem: Item { Row { anchors.centerIn: parent } }`.
- **Обработка `onSpectrumUpdated()`:** вызывается на 60 Hz в UI-потоке. Отключайте `Connections` через `enabled: root.visible` и не делайте там тяжёлых вычислений или логирования.
- **`trackRow.badges` и `card.overlay`:** инстанцируются для каждого видимого элемента списка или сетки. Держите компоненты минимальными (без `ShaderEffect` и тяжёлого `Canvas`). Если моды не используют эти слоты, они не создаются.
