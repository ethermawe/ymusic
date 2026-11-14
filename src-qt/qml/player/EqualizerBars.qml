pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

// Compatibility wrapper routing EqualizerBars callers to Swiftify's live FFT CompactMeter.
SpectrumView {
    kind: SpectrumView.Compact
    sensitivity: appSettings.visualizerSensitivity
    implicitWidth: 26
    implicitHeight: 22
}
