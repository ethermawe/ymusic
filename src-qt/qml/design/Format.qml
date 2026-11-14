pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    readonly property var locale: Qt.locale()

    /// "3:07", as playbackTime() writes a song's time
    function playbackTime(milliseconds: real): string {
        const seconds = Math.max(Math.floor(milliseconds / 1000), 0)
        const remainder = seconds % 60
        return Math.floor(seconds / 60) + ":" + (remainder < 10 ? "0" : "") + remainder
    }

    /// "3 ч 24 мин" / "24 мин", a collection's running time; empty when nothing reports one
    function totalDuration(milliseconds: real): string {
        if (milliseconds <= 0) {
            return ""
        }
        const totalMinutes = Math.floor(milliseconds / 60000)
        const hours = Math.floor(totalMinutes / 60)
        const minutes = totalMinutes % 60
        if (hours > 0) {
            return minutes > 0 ? hours + qsTr(" ч ") + minutes + qsTr(" мин") : hours + qsTr(" ч")
        }
        return minutes + qsTr(" мин")
    }

    function songCount(count: int): string {
        const mod10 = count % 10
        const mod100 = count % 100
        if (mod10 === 1 && mod100 !== 11) {
            return count + qsTr(" трек")
        }
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
            return count + qsTr(" трека")
        }
        return count + qsTr(" треков")
    }

    function joined(parts: list<string>, separator: string): string {
        let result = ""
        for (let index = 0; index < parts.length; ++index) {
            const part = parts[index]
            if (part.length === 0) {
                continue
            }
            result += (result.length > 0 ? separator : "") + part
        }
        return result
    }

    function fileSize(bytes: real): string {
        if (bytes <= 0) {
            return qsTr("0 КБ")
        }
        if (bytes < 1000) {
            return Math.round(bytes) + qsTr(" Б")
        }
        const units = [qsTr("КБ"), qsTr("МБ"), qsTr("ГБ"), qsTr("ТБ")]
        let value = bytes / 1000
        let unit = 0
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000
            unit += 1
        }
        return (value >= 100 ? String(Math.round(value)) : value.toFixed(1)) + " " + units[unit]
    }
}
