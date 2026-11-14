pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

StyledMenu {
    id: root

    StyledMenuItem {
        text: backend.playing ? qsTr("Пауза") : qsTr("Воспроизвести")
        symbol: backend.playing ? "pause" : "play_arrow"
        enabled: backend.hasTrack
        onTriggered: backend.toggle()
    }
    StyledMenuItem {
        text: qsTr("Следующий трек")
        symbol: "skip_next"
        enabled: backend.hasTrack
        onTriggered: backend.next()
    }
    StyledMenuItem {
        text: qsTr("Предыдущий трек")
        symbol: "skip_previous"
        enabled: backend.hasTrack
        onTriggered: backend.prev()
    }
    StyledMenuSeparator {}
    StyledMenuItem {
        text: qsTr("Вперёд на 10 сек")
        symbol: "forward_10"
        enabled: backend.hasTrack && backend.durationSecs > 0
        onTriggered: backend.seek(Math.min(1, (backend.positionSecs + 10) / backend.durationSecs))
    }
    StyledMenuItem {
        text: qsTr("Назад на 10 сек")
        symbol: "replay_10"
        enabled: backend.hasTrack && backend.durationSecs > 0
        onTriggered: backend.seek(Math.max(0, (backend.positionSecs - 10) / backend.durationSecs))
    }
    StyledMenuSeparator {}
    StyledMenuItem {
        text: qsTr("Громче")
        symbol: "volume_up"
        onTriggered: backend.setVolume(Math.min(1, backend.volume + 0.05))
    }
    StyledMenuItem {
        text: qsTr("Тише")
        symbol: "volume_down"
        onTriggered: backend.setVolume(Math.max(0, backend.volume - 0.05))
    }
    StyledMenuItem {
        text: backend.volume <= 0.01 ? qsTr("Включить звук") : qsTr("Без звука")
        symbol: backend.volume <= 0.01 ? "volume_up" : "volume_off"
        onTriggered: backend.toggleMute()
    }
    StyledMenuSeparator {}
    StyledMenuItem {
        text: backend.shuffle ? qsTr("Выключить перемешивание") : qsTr("Перемешивать")
        symbol: "shuffle"
        onTriggered: backend.toggleShuffle()
    }
    StyledMenuItem {
        text: backend.repeatMode === 2 ? qsTr("Повтор: один трек") : (backend.repeatMode === 1 ? qsTr("Повтор: всё") : qsTr("Повтор выкл."))
        symbol: backend.repeatMode === 2 ? "repeat_one" : "repeat"
        onTriggered: backend.toggleRepeat()
    }
    StyledMenuSeparator {}
    StyledMenuItem {
        text: qsTr("Настройки…")
        symbol: "settings"
        onTriggered: UiState.settingsRequested()
    }
}
