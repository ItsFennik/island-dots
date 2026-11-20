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
    PwObjectTracker { objects: Audio.sinks.concat(root.sources, Audio.streams) }
    function label(n) { return n.nickname || n.description || n.name; }
    function devGlyph(n) {
        const s = (label(n) + " " + (n.name ?? "")).toLowerCase();
        return /head|ear|bluez|airpod|buds/.test(s) ? "" : /hdmi|displayport|monitor/.test(s) ? "" : "";
    }
    function appGlyph(name) {
        const s = String(name).toLowerCase();
        return /librewolf|firefox|chrome|chromium|browser/.test(s) ? ""
             : /vesktop|discord/.test(s) ? ""
             : /steam/.test(s) ? ""
             : "";
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
                from: 0; to: 1; stepSize: 0.01; displayScale: 100; suffix: "%"
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

        MenuRow { kind: "sep"; visible: Audio.apps.length > 0 }
        MenuRow { kind: "section"; text: "Applications"; visible: Audio.apps.length > 0 }
        Repeater {
            model: Audio.apps
            delegate: Item {
                id: appRow
                required property var modelData
                readonly property bool muted: Audio.appMuted(modelData)
                readonly property real vol: Audio.appVolume(modelData)
                width: col.width
                height: 46

                Rectangle {
                    x: 8; y: 4; width: 24; height: 24; radius: 12
                    color: appMute.containsMouse ? Qt.alpha(Theme.menuText, Theme.dark ? 0.22 : 0.14)
                                                : Qt.alpha(Theme.menuText, Theme.dark ? 0.16 : 0.1)
                    Text { anchors.centerIn: parent; text: appRow.muted ? "" : ""
                        color: Theme.menuText; opacity: appRow.muted ? 0.5 : 1
                        font { family: Theme.mono; pixelSize: 12 } }
                    MouseArea {
                        id: appMute
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleAppMute(appRow.modelData)
                    }
                }
                Text {
                    id: appTitle
                    anchors { left: parent.left; leftMargin: 40; right: appLevel.left; rightMargin: 8; top: parent.top; topMargin: 5 }
                    text: appRow.modelData.name
                    elide: Text.ElideRight
                    color: Theme.menuText
                    opacity: appRow.muted ? 0.5 : 1
                    font { family: Theme.font; pixelSize: 13 }
                }
                Text {
                    id: appLevel
                    anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 6 }
                    text: appRow.muted ? "Muted" : Math.round(Math.min(1, appRow.vol) * 100) + "%"
                    color: Qt.alpha(Theme.menuText, 0.45)
                    font { family: Theme.font; pixelSize: 11 }
                }
                Slider {
                    anchors { left: appTitle.left; right: parent.right; rightMargin: 12; top: parent.top; topMargin: 23 }
                    from: 0; to: 1; stepSize: 0.01; displayScale: 100; suffix: "%"
                    value: Math.min(1, appRow.vol)
                    onMoved: v => Audio.setAppVolume(appRow.modelData, v)
                }
            }
        }

        MenuRow { kind: "sep" }
        MenuRow { text: "Sound Settings…"; onClicked: { Popouts.close(); Popouts.openSettings("sound"); } }
    }
}
