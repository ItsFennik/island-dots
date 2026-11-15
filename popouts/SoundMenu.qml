import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.components

// The Sound menu extra (speaker icon in the menu bar), laid out like macOS: volume slider,
// output devices, input devices, Sound Settings…
Item {
    id: root
    implicitWidth: 300
    implicitHeight: col.implicitHeight
    focus: true

    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: Audio.sinks.concat(root.sources) }
    function label(n) { return n.nickname || n.description || n.name; }
    function devGlyph(n) {
        const s = (label(n) + " " + (n.name ?? "")).toLowerCase();
        return /head|ear|bluez|airpod|buds/.test(s) ? "" : /hdmi|displayport|monitor/.test(s) ? "" : "";
    }

    Column {
        id: col
        width: parent.width

        MenuRow { kind: "header"; text: "Sound" }
        Item {
            width: parent.width; height: 30
            Text { id: lo; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                text: ""; color: Qt.alpha(Theme.menuText, 0.6); font { family: Theme.mono; pixelSize: 12 } }
            Slider {
                anchors { left: lo.right; leftMargin: 8; right: hi.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                from: 0; to: 1; stepSize: 0.01; suffix: ""
                value: Audio.muted ? 0 : Math.min(1, Audio.volume)
                onMoved: v => Audio.setVolume(v)
            }
            Text { id: hi; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: ""; color: Qt.alpha(Theme.menuText, 0.6); font { family: Theme.mono; pixelSize: 12 } }
        }

        MenuRow { kind: "sep" }
        MenuRow { kind: "section"; text: "Output" }
        Repeater {
            model: Audio.sinks
            MenuRow {
                required property var modelData
                text: root.label(modelData)
                icon: root.devGlyph(modelData)
                on: modelData === Audio.sink
                onClicked: Audio.setDefault(modelData)
            }
        }

        MenuRow { kind: "sep"; visible: root.sources.length > 0 }
        MenuRow { kind: "section"; text: "Input"; visible: root.sources.length > 0 }
        Repeater {
            model: root.sources
            MenuRow {
                required property var modelData
                text: root.label(modelData)
                icon: ""
                on: modelData === Audio.source
                onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
        }

        MenuRow { kind: "sep" }
        MenuRow { text: "Sound Settings…"; onClicked: { Popouts.close(); Popouts.openSettings("sound"); } }
    }
}
