import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.components
import qs.settings

// Bluetooth pane: on/off, My Devices (paired), Nearby Devices (while this pane is open).
Column {
    id: root
    spacing: 20

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var mine: devices.filter(d => d.paired || d.bonded)
    readonly property var nearby: devices.filter(d => !d.paired && !d.bonded && d.name)

    Component.onCompleted: if (adapter?.enabled) adapter.discovering = true
    Component.onDestruction: if (adapter) adapter.discovering = false

    Group {
        footer: root.adapter ? "This computer is discoverable as “" + root.adapter.name + "” while Bluetooth settings are open." : ""
        SettingRow {
            title: "Bluetooth"
            glyph: ""; glyphTint: "#0a84ff"
            subtitle: root.adapter ? "" : "No Bluetooth adapter found"
            Switch {
                enabled: !!root.adapter
                checked: root.adapter?.enabled ?? false
                onToggled: c => { root.adapter.enabled = c; if (c) root.adapter.discovering = true; }
            }
        }
    }

    component DeviceRow: SettingRow {
        id: d
        required property var modelData
        title: modelData.name || modelData.address
        subtitle: modelData.connected ? "Connected" + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "")
                : modelData.pairing ? "Pairing…" : modelData.paired ? "Not Connected" : ""
        glyph: ""; glyphTint: modelData.connected ? "#0a84ff" : Theme.switchOff
    }

    Group {
        visible: root.mine.length > 0
        title: "My Devices"
        Repeater {
            model: root.mine
            delegate: DeviceRow {
                Row {
                    spacing: 8
                    PushButton { text: modelData.connected ? "Disconnect" : "Connect"; onClicked: modelData.connected ? modelData.disconnect() : modelData.connect() }
                    PushButton { text: "Forget"; onClicked: modelData.forget() }
                }
            }
        }
    }

    Group {
        visible: (root.adapter?.enabled ?? false)
        title: "Nearby Devices"
        footer: root.nearby.length === 0 ? "Searching…" : ""
        Repeater {
            model: root.nearby
            delegate: DeviceRow {
                PushButton { text: modelData.pairing ? "Cancel" : "Connect"; onClicked: modelData.pairing ? modelData.cancelPair() : modelData.pair() }
            }
        }
    }
}
