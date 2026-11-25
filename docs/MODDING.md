# Руководство по разработке модов для `ymusic`

> Документация от разработчиков клиента — для разработчиков модов.
> Стек клиента: **Rust (`ymusic_core`) + Qt 6 (C++20) + QML (`ymusic.ui`)**.
> Моды пишутся на **QML + JavaScript** (плюс опциональные предкомпилированные `.qsb`-шейдеры Qt 6 RHI) и работают одинаково на **Linux и Windows без компиляции**.

---

## 1. Быстрый старт (за 3 минуты)

1. Откройте папку модов:
   - Через UI: **Настройки → Моды → Папка модов**.
   - Напрямую:
     - **Linux:** `~/.local/share/ymusic/mods/`
     - **Windows:** `%LOCALAPPDATA%\ymusic\mods\`
2. Создайте папку с валидным ID мода (например, `my-first-mod/`), положите туда `manifest.json` и `main.qml`.
3. Включите **Настройки → Моды → Режим разработчика** — клиент начнёт следить за файлами включённых модов (`QFileSystemWatcher`) и автоматически перезагружать их при сохранении.
4. Горячие клавиши и аварийный запуск:
   - **`Ctrl+Shift+R`** — мгновенный Hot Reload всех модов (`clearComponentCache()` + `collectGarbage()` + пересоздание `ModApi`).
   - **`ymusic-qml --safe-mode`** или **удержание `Shift` при старте** — запуск без модов и без UI-оверрайдов.
   - Если мод с `ui:override` сломает загрузку `Main.qml`, клиент автоматически отправит его в карантин и переподнимет чистый интерфейс.

Готовые эталонные примеры лежат в репозитории:
- `examples/mods/hello-ymusic/` — фоновый скрипт, пункт в `TrackMenu`, своя страница в сайдбаре, оверлей в `ImmersivePlayer`, окно настроек мода.
- `examples/mods/top-nav-pill/` — фундаментальная переделка вёрстки: скрытие левого сайдбара через `ui:override` + парящая верхняя пилюля навигации в слоте `topbar.center`.

---

## 2. Как устроен жизненный цикл мода (и почему он не течёт)

1. При включении мода `ModManager` создаёт для него изолированный C++-объект **`ModApi`** (`modApi`).
2. `ModApi` — единственный владелец всех подписок, таймеров, пунктов `TrackMenu` и асинхронных HTTP-запросов этого мода.
3. При выключении или `Ctrl+Shift+R` старый `ModApi` уничтожается (`disconnect()` + `deleteLater()`), все его незавершённые `QNetworkReply` обрываются, зарегистрированные пункты меню очищаются, а QML-движок сбрасывает кэш компонентов.
4. Все ошибки загрузки QML и предупреждения `modApi.warn()` / `modApi.log()` попадают в **Настройки → Моды → Консоль модов** и в `ymusic.log`.

---

## 3. Полная спецификация `manifest.json`

```json
{
  "id": "my-mod",
  "name": "My Awesome Mod",
  "version": "1.0.0",
  "author": "your-handle",
  "description": "Краткое описание, отображается в карточке мода.",
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
    { "id": "toggle-panel", "sequence": "Ctrl+Alt+T", "description": "Переключить панель мода" }
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

### Как работает блок `"ui"` (и обратная совместимость)
Для любого слота в `"ui"` (старый ключ `"slots"` также поддерживается) можно указать:
- **строку** — просто путь к QML: `"topbar.center": "ui/TopWidget.qml"`;
- **объект** — путь + метаданные (`id`, `file`, `title`, `symbol`, `shape`), особенно удобно для `sidebar.page`, `settings.tab`, `immersive.panel`;
- **массив** строк и/или объектов — один мод может добавить сразу несколько страниц, глав настроек, кнопок в плеере или иммерсивных панелей.

### Ограничения валидации
- `id`: только `^[a-z0-9][a-z0-9_-]{1,47}$`.
- `apiVersion`: сейчас строго `1`.
- `minAppVersion`: если указана (например, `"0.3.0"`), сравнивается с текущей версией клиента через `QVersionNumber`; при несовместимости мод не загружается и показывает понятную ошибку в списке.
- Все пути в `entry`, `ui`/`slots` и `overrides` обязаны быть относительными и строго внутри папки мода (`..` и симлинки наружу блокируются).
- Использование `overrides` без разрешения `"ui:override"` отклоняется на этапе парсинга манифеста.

---

## 4. Таблица разрешений (`permissions`)

> **Модель безопасности:** моды выполняются на движке QML внутри интерфейса клиента. Разрешения определяют контракт `ModApi` и прозрачно отображаются пользователю в карточке мода (вместе со списком подменяемых файлов `overrideTargets`), но не являются жёсткой изоляцией уровня ОС.

| Разрешение | Что открывает | Ограничения безопасности |
|---|---|---|
| `playback:read` | Чтение свойств текущего трека, состояния плеера, прогресса, громкости, темпа | Без OAuth-токена |
| `playback:control` | `toggle()`, `next()`, `prev()`, `seek()`, `setVolume()`, `toggleLike()`, `playNext()`, `addToQueue()` | Нет доступа к выходу/настройкам аккаунта |
| `library:read` | `queueTracks()`, `currentTracks()`, `historyTracks()`, сигнал `libraryChanged` | Только чтение снимков списков треков |
| `lyrics:read` | `lyricsTrackId`, `lyricsSynced`, `lyricsLines`, сигнал `lyricsChanged` | Только чтение загруженного текста |
| `lyrics:transform` | `setLyricSubtitles(trackId, lines)`, `clearLyricSubtitles()` | Добавляет подстрочник (перевод/транслит) под строками текста |
| `spectrum:read` | `spectrumLevels()` (48 FFT-полос), `spectrumEnergies()` (5 полос), сигнал `spectrumUpdated` | 60 Hz, без доступа к сырому PCM |
| `ui:slots` | Встраивание в UI-слоты, навигация (`openHome`, `openPlaylist` и др.), `showToast()`, `openImmersive()`, `openSettings()`, `openCreatePlaylist()`, `openExternalUrl()`, `registerTrackMenuAction()`, `registerShortcut()` | `openExternalUrl` разрешает только `http://` и `https://` |
| `ui:override` | Подмена любых `.qml` модуля `ymusic.ui` через `ModUrlInterceptor` | Требует перезапуска клиента; автокарантин при падении старта |
| `storage` | `storageGet`, `storageSet`, `storageRemove`, `storageAll` | Изолированный файл `mod-data/<mod-id>.json` |
| `clipboard` | `copyText(text)` | Только запись в буфер |
| `network:<host>` | `httpGet(url, requestId)` и `httpRequest(method, url, headers, body, requestId)` + сигнал `httpFinished(...)` | Только HTTPS (или `http://localhost` / `127.0.0.1`), методы `GET/POST/PUT/PATCH/DELETE`, заголовки `Host`/`Cookie`/`Content-Length` фильтруются, лимит 4 МБ, таймаут 15 сек |

---

## 5. Полный справочник UI-слотов (`slots`)

Каждый загружаемый QML-файл слота автоматически получает:
- `property var modApi: null` — ваш изолированный `ModApi`
- `property var slotContext: ({})` — контекст конкретного слота

| Слот | Файл-хост | Режим раскладки | Поля `slotContext` | Типичное применение |
|---|---|---|---|---|
| `window.backdrop` | `Main.qml` (`z: -1`) | `fill` | `{}` | Кастомные обои окна, градиенты, шейдерный фон |
| `topbar.center` | `TopBar.qml` | `fill` | `{ topBarWidth, compact }` | Верхняя пилюля навигации, мини-статус |
| `sidebar.page` | `Main.qml` + `Sidebar.qml` | `fill` | `{}` | Полноценная страница мода (статистика, утилиты, экспорт) |
| `home.top` | `HomeView.qml` | `column` | `{ narrow }` | Баннер/виджет над Spotlight на Главной |
| `home.sections` | `HomeView.qml` | `column` | `{ narrow }` | Свои полки и подборки на Главной |
| `collection.actions` | `CollectionHero.qml` | `row` (`height: 40`) | `{ title, isArtist, kind, playlistKey }` | Кнопки для плейлиста/альбома/артиста (экспорт M3U и т.д.) |
| `trackRow.badges` | `TrackRow.qml` | `row` (`height: 28`) | `{ track, index, isCurrent, hovered }` | Бейджи и мини-кнопки в каждой строке трека *(ленивый: 0 накладных расходов, если не используется)* |
| `playerBar.controls` | `FloatingPlayerBar.qml` | `row` (`height: buttonSize`) | `{ scheme, buttonSize, compact }` | Кнопки в правом блоке нижнего бара |
| `playerBar.overlay` | `FloatingPlayerBar.qml` | `fill` (`z: 0`) | `{ scheme, compact, twoRow }` | Фоновый эффект / полоса / свечение поверх нижнего бара |
| `lyrics.header` | `LyricsPanel.qml` | `row` (`height: 28`) | `{ scheme, trackId, synced, wordSynced }` | Кнопки в шапке текста (перевод, копирование, смещение) |
| `queue.header` | `QueuePanel.qml` | `row` (`height: 32`) | `{ scheme, count }` | Действия над очередью (убрать дубликаты, сохранить плейлист) |
| `wave.overlay` | `WaveHero.qml` | `fill` (`z: 15`) | `{ inWave, applying }` | Оверлей и доп. контролы на экране «Моя волна» |
| `immersive.backdrop` | `ImmersivePlayer.qml` | `fill` | `{ scheme }` | Кастомный фон / 3D / шейдер в полном экране |
| `immersive.overlay` | `ImmersivePlayer.qml` | `fill` (`z: 50`) | `{ scheme, controlsOpacity }` | Бейджи, мини-визуализаторы, часы, инфо-оверлеи |
| `immersive.panel` | `ImmersivePlayer.qml` | `fill` | `{ scheme }` | Собственная боковая панель (кнопка рядом со свичером панелей) |
| `settings.tab` | `SettingsDialog.qml` + `SettingsPages.qml` | `column` | `{}` | Своя полноценная «глава» в левом меню Настроек |
| `settings.section.appearance` | `SettingsPages.qml` | `column` | `{}` | Новые секции/пункты в главе «Оформление» |
| `settings.section.player` | `SettingsPages.qml` | `column` | `{}` | Новые секции/пункты в главе «Плеер и фон» |
| `settings.section.audio` | `SettingsPages.qml` | `column` | `{}` | Новые секции/пункты в главе «Звук» |
| `settings.section.animations` | `SettingsPages.qml` | `column` | `{}` | Новые секции/пункты в главе «Анимации» |
| `settings.section.integrations` | `SettingsPages.qml` | `column` | `{}` | Новые секции/пункты в главе «Интеграции» |
| `settings.section.system` | `SettingsPages.qml` | `column` | `{}` | Новые секции/пункты в главе «Система» |

> **Важно для `column` и `row` слотов:** корневой элемент вашего QML должен задавать `implicitHeight` (для `column`, например `ContentSection {}` или `Column {}`) или `implicitWidth` / `width` (для `row`, например `IconButton {}` или `Row {}`).

---

## 6. Справочник `modApi`

### Свойства (read-only)
- Идентификация: `modId`, `modName`, `permissions`, `hasPermission(perm)`
- Трек (`playback:read`): `hasTrack`, `trackId`, `trackTitle`, `trackArtists`, `trackAlbum`, `trackCover`, `trackLiked`, `trackIsAi`
- Плеер (`playback:read`): `playing`, `buffering`, `volume` (`0..1`), `shuffle`, `repeatMode` (`0`=выкл, `1`=все, `2`=один), `tempo`, `positionSecs`, `durationSecs`, `progress` (`0..1`)
- Навигация и профиль: `currentPage`, `canGoBack`, `loggedIn`, `userName`, `userAvatar`, `pinnedPlaylists`
- Текст песни (`lyrics:read`): `lyricsTrackId`, `lyricsSynced`, `lyricsLines` (массив `{ text, time, words }`)

### Сигналы
- `trackChanged()` — сменился текущий трек или его метаданные/лайк
- `playbackChanged()` — play/pause, buffering, volume, shuffle, repeat, tempo
- `positionChanged()` — обновление позиции трека
- `navigationChanged()` — смена страницы, статуса входа или закреплённых плейлистов
- `libraryChanged()` — обновление очереди, текущего списка треков или истории (`library:read`)
- `lyricsChanged()` — загружен или очищен текст текущей песни (`lyrics:read`)
- `spectrumUpdated()` — 60 Hz обновление FFT-буфера (только при `spectrum:read`)
- `trackMenuActionTriggered(actionId, trackId, trackTitle)` — клик по вашему пункту в `TrackMenu`
- `shortcutTriggered(actionId)` — сработала горячая клавиша мода (из `manifest.json` или `registerShortcut`)
- `httpFinished(requestId, statusCode, body, error)` — завершение `httpGet(...)` / `httpRequest(...)`

### Методы
- **Управление (`playback:control`):** `toggle()`, `next()`, `prev()`, `seek(0..1)`, `setVolume(0..1)`, `toggleLike()`, `playNext(trackId)`, `addToQueue(trackId)`
- **Навигация (`ui:slots`):** `openHome()`, `openWave()`, `openLikes()`, `openDownloads()`, `openPlaylists()`, `openAlbums()`, `openArtists()`, `openSearch(query)`, `openPlaylist(uid, kind, title)`, `goBack()`, `openCreatePlaylist()`
- **Библиотека (`library:read`):** `queueTracks()`, `currentTracks()`, `historyTracks()` → массивы `{ id, title, artists, album, durationSecs, coverUrl, liked, available, isAi }`
- **Субтитры текста (`lyrics:transform`):** `setLyricSubtitles(trackId, subtitles)` (массив строк по индексу), `clearLyricSubtitles()`
- **Спектр (`spectrum:read`):** `spectrumLevels()` → `number[48]`, `spectrumEnergies()` → `number[5]` (от саб-баса к верхам)
- **Хранилище (`storage`):** `storageGet(key, fallback)`, `storageSet(key, value)`, `storageRemove(key)`, `storageAll()`
- **Интерфейс (`ui:slots`):**
  - `showToast(message)`
  - `openImmersive()` / `closeImmersive()`
  - `openSettings()`
  - `openExternalUrl(url)`
  - `registerTrackMenuAction(actionId, label, symbol, destructive)` / `unregisterTrackMenuAction(actionId)`
  - `registerShortcut(actionId, sequence, description)` / `unregisterShortcut(actionId)`
- **Буфер (`clipboard`):** `copyText(text)`
- **Сеть (`network:<host>`):**
  - `httpGet(url, requestId)`
  - `httpRequest(method, url, headers, body, requestId)` — поддержка `GET`, `POST`, `PUT`, `PATCH`, `DELETE` и JSON/текстовых заголовков и тела
- **Логи:** `log(message)`, `warn(message)`

---

## 7. Встроенные компоненты `import ymusic.ui`

Вам не нужно рисовать UI с нуля — все родные компоненты Material 3 Expressive доступны через `import ymusic.ui`:

- **Дизайн-токены (`Appearance`):**
  - `Appearance.colors` (`primary`, `onPrimary`, `primaryContainer`, `onPrimaryContainer`, `surface`, `surfaceContainer`, `surfaceContainerHigh`, `onSurface`, `onSurfaceVariant`, `outlineVariant`, `error`, `layer0`, `layer1`, `layer2Hover`, `dark`)
  - `Appearance.rounding` (`verySmall`, `small`, `normal`, `large`, `veryLarge`, `full`)
  - `Appearance.fontSize` (`smallest`, `smaller`, `small`, `normal`, `large`, `title`, `headline`)
  - `Appearance.fontFamily`, `Appearance.monoFontFamily`
  - `Appearance.curves.expressiveFastSpatial`, `Appearance.duration(ms)`, `Appearance.motion(ms)`, `Appearance.performanceMode`
- **Контролы:** `StyledText`, `TitleText`, `TextButton` (`Filled` / `Tonal` / `Outlined` / `Text`), `IconButton`, `RippleButton`, `StyledSwitch`, `StyledSlider`, `StyledComboBox`, `OutlinedTextField`, `StyledMenu`, `StyledMenuItem`, `StyledMenuSeparator`, `StyledDialog`, `ArtworkImage`, `MaterialSymbol`, `ShapeIcon`, `SoftShadow`, `SpectrumView`.
- **Компоненты для Настроек (`import ymusic.ui`):** `ContentSection`, `ConfigSwitch`, `ConfigSlider`, `ConfigSelection`, `NoteText`.

---

## 8. Фундаментальная подмена вёрстки (`ui:override`)

Любой файл из `ymusic.ui` можно подменить в `manifest.json`:

```json
"overrides": {
  "qml/sidebar/Sidebar.qml": "overrides/Sidebar.qml",
  "qml/player/FloatingPlayerBar.qml": "overrides/FloatingPlayerBar.qml"
}
```

Ключевые файлы и их минимальные контракты (что ожидает `Main.qml`):
- **`qml/sidebar/Sidebar.qml`** — свойства `compact`, `expandedWidth`, `resizing`, `toggleVisible`, `isCompact`, сигналы `settingsRequested()`, `toggleCompactRequested()`. Чтобы полностью убрать сайдбар, достаточно `implicitWidth: 0; width: 0; visible: false`.
- **`qml/shell/TopBar.qml`** — `required property Window window`, `property Item backdropSource`, `property bool windowControlsOnRight`, `property bool inspectorShown`, `readonly property bool searchEditing`, методы `focusSearch()`, `dismissSearch()`, `isSearchInteractiveAt(sourceItem, x, y)`.
- **`qml/player/FloatingPlayerBar.qml`** — сигнал `immersiveRequested()`.
- **`qml/library/TrackRow.qml`** — `required property int index`, `required property var model`, `property bool queueView`.
- **`qml/views/HomeView.qml`** / **`qml/immersive/ImmersivePlayer.qml`** / **`qml/Main.qml`** — полная свобода перекомпоновки.

---

## 9. Практические рецепты (Cookbook)

### Рецепт 1: Новая «глава» настроек + секция во встроенной главе

```qml
// ui/MySettingsTab.qml  (slot: "settings.tab")
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
            text: "Включить авто-действие"
            checked: root.modApi ? Boolean(root.modApi.storageGet("auto", true)) : true
            onToggledTo: (v) => {
                if (root.modApi) root.modApi.storageSet("auto", v)
            }
        }
    }
}
```

### Рецепт 2: Кнопка в нижнем плавающем баре (`playerBar.controls`)

```qml
// ui/BarButton.qml
import QtQuick
import ymusic.ui

IconButton {
    property var modApi: null
    property var slotContext: ({})
    scheme: slotContext.scheme || Appearance.colors
    size: slotContext.buttonSize || 34
    iconSize: 19
    symbol: "auto_awesome"
    tooltip: "Моё действие"
    onClicked: if (modApi) modApi.showToast("Нажато из FloatingPlayerBar!")
}
```

### Рецепт 3: 60 fps визуализатор в `immersive.overlay` (без лишней нагрузки)

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
        // Подписка активна только когда виджет реально виден
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

### Рецепт 4: Предкомпилированные шейдеры `.qsb` для Qt 6 RHI

Qt 6 не компилирует сырой `.frag` с диска в рантайме, но отлично грузит `.qsb` рядом с модом:

```bash
# Собрать .qsb утилитой из Qt 6 SDK (работает на Vulkan, OpenGL и D3D11):
qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/my_effect.frag.qsb shaders/my_effect.frag
```

```qml
ShaderEffect {
    anchors.fill: parent
    fragmentShader: Qt.resolvedUrl("../shaders/my_effect.frag.qsb")
}
```

### Рецепт 5: Асинхронный HTTP-запрос (`GET` / `POST`) и скробблинг

```qml
// В manifest.json: "permissions": ["network:api.listenbrainz.org", "playback:read", "ui:slots"]
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

### Рецепт 6: Перевод / транслитерация текста песни (`lyrics:read` + `lyrics:transform`)

```qml
// В manifest.json: "permissions": ["lyrics:read", "lyrics:transform", "ui:slots"]
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
Подстрочник автоматически отобразится и в боковой панели `LyricsPanel`, и в полноэкранном `ImmersiveLyrics`, а при выключении или перезагрузке мода очистится сам.

---

## 10. Советы по производительности и подводные камни

1. **`contentItem` в `RippleButton` / `AbstractButton`:** не вешайте `anchors.centerIn: parent` напрямую на сам `contentItem` — `AbstractButton` управляет его геометрией сам. Оборачивайте внутренний `Row`/`Column` в `contentItem: Item { Row { anchors.centerIn: parent } }`.
2. **Берегите UI-поток на 60 Hz:** в `onSpectrumUpdated()` избегайте тяжёлых вычислений, рекурсий и `console.log`. Всегда проверяйте `enabled: root.visible` на `Connections`.
3. **Слот `trackRow.badges`:** в длинных плейлистах одновременно рендерятся десятки строк — делайте компонент для `trackRow.badges` максимально лёгким (1–2 `Rectangle`/`StyledText`/`IconButton`, без `ShaderEffect` и тяжёлых `Canvas`).
4. **Отладка:** включите **Режим разработчика**, смотрите ошибки в **Настройки → Моды → Консоль модов** и используйте `Ctrl+Shift+R` после каждого сохранения.
