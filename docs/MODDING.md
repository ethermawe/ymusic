# Моддинг `ymusic` (Руководство разработчика)

`ymusic` поддерживает кроссплатформенные QML/JS-моды (работают одинаково на Linux и Windows без компиляции C++).

## Где лежат моды

- **Linux:** `~/.local/share/ymusic/mods/<mod-id>/`
- **Windows:** `%LOCALAPPDATA%\ymusic\mods\<mod-id>\`

Открыть папку можно прямо из клиента: **Настройки → Моды → Открыть папку модов**.

## Безопасный режим и перезагрузка

- **Hot Reload:** `Ctrl+Shift+R` (или включите «Режим разработчика» в **Настройки → Моды**, чтобы клиент автоматически перезагружал моды при сохранении файлов).
- **Safe Mode:** запустите `ymusic-qml --safe-mode` (или удерживайте `Shift` при запуске), чтобы отключить все моды и UI-оверрайды. Если UI-оверрайд уронит старт интерфейса, клиент автоматически отправит его в карантин и запустится с чистым интерфейсом.

---

## Структура `manifest.json`

```json
{
  "id": "hello-ymusic",
  "name": "Hello YMusic",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "Пример мода: своя страница, пункт в меню трека и виджет в полном экране.",
  "apiVersion": 1,
  "entry": {
    "script": "main.qml",
    "settings": "ui/Settings.qml"
  },
  "sidebar": {
    "title": "Мой мод",
    "symbol": "auto_awesome"
  },
  "slots": {
    "sidebar.page": "ui/Page.qml",
    "immersive.overlay": "ui/ImmersiveBadge.qml"
  },
  "overrides": {
    "qml/player/FloatingPlayerBar.qml": "overrides/FloatingPlayerBar.qml"
  },
  "permissions": [
    "playback:read",
    "playback:control",
    "spectrum:read",
    "ui:slots",
    "storage",
    "clipboard"
  ]
}
```

### Доступные разрешения (`permissions`)

| Разрешение | Назначение |
|---|---|
| `playback:read` | Чтение `trackId`, `trackTitle`, `trackArtists`, `trackAlbum`, `trackCover`, `playing`, `positionSecs`, `durationSecs`, `volume`, `tempo` |
| `playback:control` | `toggle()`, `next()`, `prev()`, `seek(0..1)`, `setVolume(0..1)`, `toggleLike()`, `playNext(id)`, `addToQueue(id)` |
| `spectrum:read` | `spectrumLevels()` (48 FFT-полос), `spectrumEnergies()` (5 полос) и сигнал `spectrumUpdated` |
| `ui:slots` | Встраивание QML в слоты, `showToast(msg)`, `openExternalUrl(url)`, `registerTrackMenuAction(...)` |
| `ui:override` | Подмена встроенных `.qml` через `overrides` (требует перезапуска клиента после вкл/выкл) |
| `storage` | Изолированное JSON-хранилище: `storageGet`, `storageSet`, `storageRemove`, `storageAll` |
| `clipboard` | `copyText(text)` |
| `network:<host>` | Асинхронный `httpGet(url, requestId)` к конкретному HTTPS-домену (или `localhost`/`127.0.0.1`) |

---

## Официальные UI-слоты (`slots`)

Каждый QML-файл слота получает свойства `property var modApi` и `property var slotContext`:

- `window.backdrop` — слой под интерфейсом главного окна (`Main.qml`).
- `sidebar.page` — собственная страница приложения (появляется в секции «Моды» в сайдбаре).
- `immersive.backdrop` — фоновый слой в полноэкранном плеере (`ImmersivePlayer.qml`).
- `immersive.overlay` — верхний слой виджетов/визуализаторов в полноэкранном плеере (`ImmersivePlayer.qml`).
- `entry.script` — фоновый QML-хост, который работает всё время, пока мод включён (удобно для регистрации действий в `TrackMenu` и реакции на события `modApi.trackChanged`).
- `entry.settings` — собственный UI настроек мода (открывается кнопкой настроек в **Настройки → Моды**).

Готовый рабочий пример лежит в `examples/mods/hello-ymusic/`.
