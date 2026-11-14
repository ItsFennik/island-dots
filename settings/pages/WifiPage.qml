import QtQuick
import Quickshell
import Quickshell.Networking
import qs.services
import qs.components
import qs.settings

// Wi-Fi pane: on/off, the current network, then known and other networks (NetworkManager).
// Scans only while this pane is open.
Column {
    id: root
    spacing: 20

    readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var nets: dev ? dev.networks.values.slice().sort((a, b) => b.signalStrength - a.signalStrength) : []
    readonly property var known: nets.filter(n => n.known && !n.connected)
    readonly property var others: nets.filter(n => !n.known && !n.connected)
    readonly property var connectedNet: nets.find(n => n.connected) ?? null
    property var asking: null                 // network waiting for a password

    Component.onCompleted: if (dev && dev.nmManaged) dev.scannerEnabled = true
    Component.onDestruction: if (dev) dev.scannerEnabled = false

    function pct(n) { const s = n.signalStrength; return s <= 1 ? s * 100 : s; }
    function bars(n) { const p = pct(n); return p > 66 ? "" : p > 33 ? "\u{f0928}" : "\u{f091f}"; }
    function secured(n) { return n.security !== WifiSecurityType.Open; }
    function join(n) { if (n.known || !secured(n)) n.connect(); else asking = n; }

    Group {
        SettingRow {
            title: "Wi-Fi"
            glyph: ""; glyphTint: "#0a84ff"
            subtitle: !root.dev ? "No Wi-Fi hardware found" : !root.dev.nmManaged ? "Not managed by NetworkManager" : root.connectedNet ? "Connected" : ""
            Switch {
                enabled: !!root.dev && root.dev.nmManaged && Networking.wifiHardwareEnabled
                checked: Networking.wifiEnabled
                onToggled: c => Networking.wifiEnabled = c
            }
        }
        SettingRow {
            visible: !!root.connectedNet
            title: root.connectedNet?.name ?? ""
            subtitle: "Connected"
            glyph: root.connectedNet ? root.bars(root.connectedNet) : ""; glyphTint: "#0a84ff"
            PushButton { text: "Disconnect"; onClicked: root.connectedNet.disconnect() }
        }
    }

    Group {
        visible: !!root.dev && !root.dev.nmManaged
        footer: "This Wi-Fi card is set to unmanaged, so NetworkManager (and this pane) leave it alone. Let NetworkManager manage it to see and join networks here."
        SettingRow {
            title: root.dev?.name ?? ""
            subtitle: "Unmanaged"
            PushButton { text: "Manage"; onClicked: { try { root.dev.nmManaged = true; } catch (e) { console.warn("island: can't manage", e); } } }
        }
    }

    Group {
        visible: root.known.length > 0 && Networking.wifiEnabled
        title: "Known Networks"
        Repeater {
            model: root.known
            delegate: SettingRow {
                required property var modelData
                title: modelData.name
                glyph: root.bars(modelData); glyphTint: Theme.switchOff
                Row {
                    spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: root.secured(modelData); text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 11 } }
                    PushButton { text: modelData.stateChanging ? "Joining…" : "Join"; enabled: !modelData.stateChanging; onClicked: root.join(modelData) }
                    PushButton { text: "Forget"; onClicked: modelData.forget() }
                }
            }
        }
    }

    Group {
        visible: root.others.length > 0 && Networking.wifiEnabled
        title: "Other Networks"
        Repeater {
            model: root.others
            delegate: SettingRow {
                id: row
                required property var modelData
                title: modelData.name
                glyph: root.bars(modelData); glyphTint: Theme.switchOff
                Row {
                    spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: root.secured(row.modelData); text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 11 } }
                    PushButton { text: row.modelData.stateChanging ? "Joining…" : "Join"; enabled: !row.modelData.stateChanging; onClicked: root.join(row.modelData) }
                }
                below: Row {
                    visible: root.asking === row.modelData
                    height: visible ? 40 : 0
                    leftPadding: 44; spacing: 8
                    TextField { id: psk; width: 220; placeholder: "Password"; input.echoMode: TextInput.Password
                        onVisibleChanged: if (visible) input.forceActiveFocus()
                        Connections { target: psk.input; function onAccepted() { if (psk.text) row.modelData.connectWithPsk(psk.text); root.asking = null; } } }
                    PushButton { text: "Join"; prominent: true; onClicked: { if (psk.text) row.modelData.connectWithPsk(psk.text); root.asking = null; } }
                    PushButton { text: "Cancel"; onClicked: root.asking = null }
                }
            }
        }
    }
}
