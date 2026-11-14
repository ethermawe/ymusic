pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

SpectrumView {
    kind: SpectrumView.Compact
    sensitivity: appSettings.visualizerSensitivity
}
