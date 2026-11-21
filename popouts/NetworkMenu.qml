import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.services
import qs.components

// The network menu extra (Wi-Fi / Ethernet icon in the menu bar), like macOS's Wi-Fi menu:
// Wi-Fi switch and networks (scans only while open), Ethernet, VPN switches, Network Settings….
Item {
    id: root
    implicitWidth: 300
    implicitHeight: col.implicitHeight
    focus: true

    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.filter(d => d.type === DeviceType.Wired)
    readonly property var nets: wifiDev && Networking.wifiEnabled
        ? wifiDev.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength)).slice(0, 10) : []
    Component.onCompleted: if (wifiDev && wifiDev.nmManaged) wifiDev.scannerEnabled = true
    Component.onDestruction: if (wifiDev) wifiDev.scannerEnabled = false

    function pct(n) { const s = n.signalStrength; return s <= 1 ? s * 100 : s; }
    function bars(n) { const p = pct(n); return p > 66 ? "\u{f0928}" : p > 33 ? "\u{f0925}" : "\u{f091f}"; }
    function join(n) {
        // Networks needing a password are joined from Settings (the menu has no text entry).
        if (n.known || n.security === WifiSecurityType.Open) n.connect();
        else { Popouts.close(); Popouts.openSettings("wifi"); }
    }

    // VPNs (NetworkManager), read once when the menu opens.
    property var vpns: []
    Process {
        id: vpnList
        running: true
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.vpns = text.split("\n").filter(l => l).map(l => {
                const out = []; let cur = "";
                for (let i = 0; i < l.length; i++) {
                    if (l[i] === "\\" && i + 1 < l.length) cur += l[++i];
                    else if (l[i] === ":") { out.push(cur); cur = ""; } else cur += l[i];
                }
                out.push(cur); return out;
            }).filter(f => f[2] === "vpn" || f[2] === "wireguard").map(f => ({ name: f[0], uuid: f[1], active: f[3] === "yes" }))
        }
    }
    Process { id: vpnAct; onExited: { vpnList.running = false; vpnList.running = true; } }

    Column {
        id: col
        width: parent.width

        // Wi-Fi
        MenuRow {
            visible: !!root.wifiDev
            kind: "header"; text: "Wi-Fi"
            Switch { checked: Networking.wifiEnabled; enabled: Networking.wifiHardwareEnabled; onToggled: c => Networking.wifiEnabled = c }
        }
        MenuRow { visible: !!root.wifiDev && root.nets.length > 0; kind: "section"; text: "Networks" }
        Repeater {
            model: root.nets
            MenuRow {
                required property var modelData
                text: modelData.name
                icon: root.bars(modelData)
                on: modelData.connected
                detail: modelData.stateChanging ? "Joining…" : modelData.security !== WifiSecurityType.Open ? "" : ""
                onClicked: modelData.connected ? modelData.disconnect() : root.join(modelData)
            }
        }
        MenuRow { visible: !!root.wifiDev; kind: "sep" }

        // Ethernet
        MenuRow { visible: root.wired.length > 0; kind: "header"; text: "Ethernet" }
        Repeater {
            model: root.wired
            MenuRow {
                required property var modelData
                text: modelData.name
                icon: "\u{f0200}"
                on: modelData.connected
                detail: modelData.connected ? (modelData.linkSpeed ? modelData.linkSpeed + " Mb/s" : "Connected") : "Not Connected"
                hoverEnabled: false
            }
        }
        MenuRow { visible: root.wired.length > 0; kind: "sep" }

        // VPN
        MenuRow { visible: root.vpns.length > 0; kind: "header"; text: "VPN" }
        Repeater {
            model: root.vpns
            MenuRow {
                required property var modelData
                text: modelData.name
                icon: ""
                on: modelData.active
                hoverEnabled: false
                Switch { checked: modelData.active; enabled: !vpnAct.running
                    onToggled: { vpnAct.command = ["nmcli", "connection", modelData.active ? "down" : "up", "uuid", modelData.uuid]; vpnAct.running = true; } }
            }
        }
        MenuRow { visible: root.vpns.length > 0; kind: "sep" }

        MenuRow { text: "Network Settings…"; onClicked: { Popouts.close(); Popouts.openSettings(root.wifiDev ? "wifi" : "network"); } }
    }
}
