import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.components
import qs.settings

// Sound pane: output volume and mute, the output and input devices, and per-app levels (Pipewire).
Column {
    id: root
    spacing: 20

    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: [root.source] }

    function label(n) { return n.nickname || n.description || n.name; }

    Group {
        SettingRow {
            title: "Output volume"
            Row {
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 12 } }
                Slider { width: 200; from: 0; to: 1; stepSize: 0.01; displayScale: 100; suffix: "%"; value: Math.min(1, Audio.volume); onMoved: v => Audio.setVolume(v) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 13 } }
            }
        }
        SettingRow {
            title: "Mute"
            Switch { checked: Audio.muted; onToggled: Audio.toggleMute() }
        }
    }

    Group {
        title: "Output"
        Repeater {
            model: Audio.sinks
            delegate: SettingRow {
                required property var modelData
                title: root.label(modelData)
                glyph: ""; glyphTint: modelData === Audio.sink ? "#ff2d55" : Theme.switchOff
                Text { text: modelData === Audio.sink ? "✓" : ""; color: Theme.accent; font { family: Theme.font; pixelSize: 14; weight: Theme.w(Font.Bold) } }
                clickable: true
                onClicked: Audio.setDefault(modelData)
            }
        }
    }

    Group {
        title: "Input"
        visible: root.sources.length > 0
        Repeater {
            model: root.sources
            delegate: SettingRow {
                required property var modelData
                title: root.label(modelData)
                glyph: ""; glyphTint: modelData === root.source ? "#ff2d55" : Theme.switchOff
                Text { text: modelData === root.source ? "✓" : ""; color: Theme.accent; font { family: Theme.font; pixelSize: 14; weight: Theme.w(Font.Bold) } }
                clickable: true
                onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
        SettingRow {
            visible: !!root.source?.audio
            title: "Input volume"
            Slider { width: 230; from: 0; to: 1; stepSize: 0.01; displayScale: 100; suffix: "%"; value: Math.min(1, root.source?.audio?.volume ?? 0)
                onMoved: v => { if (root.source?.audio) root.source.audio.volume = v; } }
        }
    }

    Group {
        title: "Applications"
        SettingRow {
            visible: Audio.apps.length === 0
            title: "No apps playing audio"
            enabled: false
        }
        Repeater {
            model: Audio.apps
            delegate: SettingRow {
                required property var modelData
                title: modelData.name
                glyph: ""; glyphTint: Theme.switchOff
                Row {
                    spacing: 10
                    Slider { width: 200; from: 0; to: 1; stepSize: 0.01; displayScale: 100; suffix: "%"
                        value: Math.min(1, Audio.appVolume(modelData))
                        onMoved: v => Audio.setAppVolume(modelData, v) }
                    Switch { checked: Audio.appMuted(modelData); onToggled: Audio.toggleAppMute(modelData) }
                }
            }
        }
    }
}
