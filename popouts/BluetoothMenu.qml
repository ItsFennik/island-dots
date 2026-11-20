import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.components

// The Bluetooth menu (the Bluetooth icon in the bottom bar), like macOS's: adapter switch,
// paired devices (connect / disconnect), nearby devices (scanned only while open), and a
// link to the full settings pane.
Item {
    id: root
    implicitWidth: 300
    implicitHeight: col.implicitHeight
    focus: true

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var mine: devices.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || (a.name ?? "").localeCompare(b.name ?? ""))
    readonly property var nearby: devices.filter(d => !d.paired && !d.bonded && (d.name ?? "") !== "")

    Component.onCompleted: if (adapter?.enabled) adapter.discovering = true
    Component.onDestruction: if (adapter) adapter.discovering = false

    function label(d) { return d.name || d.deviceName || d.address; }
    function glyphFor(d) {
        const s = (label(d) + " " + (d.icon ?? "")).toLowerCase();
        return /head|ear|bud|airpod|audio|speaker/.test(s) ? ""
             : /keyb/.test(s) ? ""
             : /mouse|trackpad|touchpad/.test(s) ? ""
             : /game|joy|controller/.test(s) ? ""
             : /phone|iphone|android|pixel/.test(s) ? ""
             : "";
    }
    function state(d) {
        if (d.pairing) return "Pairing…";
        if (d.connected) return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "Connected";
        return "";
    }
    function activate(d) {
        if (d.connected) d.disconnect();
        else if (d.pairing) d.cancelPair();
        else if (d.paired || d.bonded) d.connect();
        else d.pair();
    }

    Column {
        id: col
        width: parent.width

        MenuRow {
            kind: "header"; text: "Bluetooth"
            Switch {
                checked: root.adapter?.enabled ?? false
                enabled: !!root.adapter
                onToggled: c => {
                    if (!root.adapter) return;
                    root.adapter.enabled = c;
                    if (c) root.adapter.discovering = true;
                }
            }
        }
        MenuRow { visible: !root.adapter; text: "No Bluetooth adapter"; hoverEnabled: false; enabled: false }

        MenuRow { visible: root.mine.length > 0; kind: "section"; text: "My Devices" }
        Repeater {
            model: root.mine
            MenuRow {
                required property var modelData
                text: root.label(modelData)
                icon: root.glyphFor(modelData)
                on: modelData.connected
                detail: root.state(modelData)
                onClicked: root.activate(modelData)
            }
        }

        MenuRow { visible: root.mine.length > 0; kind: "sep" }
        MenuRow { visible: !!root.adapter?.enabled; kind: "section"; text: "Nearby Devices" }
        Repeater {
            model: root.adapter?.enabled ? root.nearby : []
            MenuRow {
                required property var modelData
                text: root.label(modelData)
                icon: root.glyphFor(modelData)
                on: modelData.connected
                detail: root.state(modelData)
                onClicked: root.activate(modelData)
            }
        }
        MenuRow {
            visible: !!root.adapter?.enabled && root.nearby.length === 0
            text: root.mine.length ? "Searching…" : "No devices found"
            hoverEnabled: false; enabled: false
        }

        MenuRow { kind: "sep" }
        MenuRow { text: "Bluetooth Settings…"; onClicked: { Popouts.close(); Popouts.openSettings("bluetooth"); } }
    }
}
