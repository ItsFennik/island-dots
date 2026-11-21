import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.services
import qs.components
import qs.settings

// Network pane: every interface NetworkManager knows, with its status (like macOS's list),
// then VPNs (NetworkManager WireGuard / OpenVPN / … profiles via nmcli).
Column {
    id: root
    spacing: 20

    readonly property var devs: Networking.devices.values.filter(d => d.type !== DeviceType.None)

    Group {
        footer: Networking.connectivity === NetworkConnectivity.Full ? "Connected to the internet."
              : Networking.connectivity === NetworkConnectivity.Portal ? "A sign-in page is blocking the internet."
              : Networking.connectivity === NetworkConnectivity.Limited ? "Connected, with limited internet access." : ""
        Repeater {
            model: root.devs
            delegate: SettingRow {
                required property var modelData
                readonly property bool wired: modelData.type === DeviceType.Wired
                title: wired ? "Ethernet" : "Wi-Fi"
                subtitle: modelData.name + (modelData.connected ? "" : modelData.nmManaged ? "" : " · unmanaged")
                glyph: wired ? "" : ""
                glyphTint: modelData.connected ? "#34c759" : Theme.switchOff
                Row {
                    spacing: 8
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4
                        color: modelData.connected ? "#34c759" : Theme.textFaint }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.connected ? (wired && modelData.linkSpeed ? "Connected · " + modelData.linkSpeed + " Mb/s" : "Connected") : "Not Connected"
                        color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 }
                    }
                }
            }
        }
    }

    // VPN
    property var vpns: []             // { name, uuid, type, active }
    property string vpnError: ""
    property string busy: ""          // uuid being switched
    property string armed: ""         // uuid whose Remove was clicked once

    // nmcli -t escapes ':' inside fields as '\:'
    function splitT(l) {
        const out = []; let cur = "";
        for (let i = 0; i < l.length; i++) {
            if (l[i] === "\\" && i + 1 < l.length) cur += l[++i];
            else if (l[i] === ":") { out.push(cur); cur = ""; }
            else cur += l[i];
        }
        out.push(cur);
        return out;
    }
    Process {
        id: vpnList
        running: true
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.vpns = text.split("\n").filter(l => l).map(root.splitT)
                .filter(f => f[2] === "vpn" || f[2] === "wireguard")
                .map(f => ({ name: f[0], uuid: f[1], type: f[2], active: f[3] === "yes" }))
        }
    }
    Timer { interval: 3000; running: true; repeat: true; onTriggered: if (!vpnList.running) vpnList.running = true }
    function refresh() { vpnList.running = false; vpnList.running = true; }

    Process {
        id: vpnAct
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            root.busy = "";
            root.vpnError = code === 0 ? "" : (actErr.text.trim().split("\n").pop() || "nmcli failed").replace(/^Error: /, "");
            root.refresh();
        }
    }
    function run(cmd, uuid) { vpnError = ""; busy = uuid ?? ""; vpnAct.command = cmd; vpnAct.running = true; }

    // Import: pick a .conf (WireGuard) or .ovpn (OpenVPN) file with zenity, hand it to nmcli.
    function importVpn() {
        run(["sh", "-c", `f=$(zenity --file-selection --title="Import VPN configuration" \\
                --file-filter="VPN configurations | *.conf *.ovpn" --file-filter="All files | *" 2>/dev/null) || exit 0
            case "$f" in *.ovpn) t=openvpn ;; *) t=wireguard ;; esac
            nmcli connection import type "$t" file "$f" >/dev/null`]);
    }

    Group {
        title: "VPN"
        footer: root.vpnError !== "" ? root.vpnError
              : root.vpns.length === 0 ? "Import a WireGuard .conf or an OpenVPN .ovpn file from your VPN provider. OpenVPN needs the NetworkManager-openvpn package."
              : "VPNs are NetworkManager connections, so they also work from nmcli and stay after a restart."
        Repeater {
            model: root.vpns
            delegate: SettingRow {
                id: vrow
                required property var modelData
                title: modelData.name
                subtitle: (modelData.type === "wireguard" ? "WireGuard" : "VPN")
                        + (root.busy === modelData.uuid ? " · " + (modelData.active ? "Disconnecting…" : "Connecting…")
                           : modelData.active ? " · Connected" : "")
                glyph: "\uf023"
                glyphTint: modelData.active ? "#34c759" : Theme.switchOff
                Row {
                    spacing: 10
                    PushButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !vrow.modelData.active
                        text: root.armed === vrow.modelData.uuid ? "Remove" : "Remove…"
                        destructive: root.armed === vrow.modelData.uuid
                        onClicked: {
                            if (root.armed !== vrow.modelData.uuid) { root.armed = vrow.modelData.uuid; return; }
                            root.armed = "";
                            root.run(["nmcli", "connection", "delete", "uuid", vrow.modelData.uuid]);
                        }
                    }
                    Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: root.busy === ""
                        checked: vrow.modelData.active
                        onToggled: root.run(["nmcli", "connection", vrow.modelData.active ? "down" : "up", "uuid", vrow.modelData.uuid], vrow.modelData.uuid)
                    }
                }
            }
        }
        SettingRow {
            title: root.vpns.length ? "Add another VPN" : "Add a VPN"
            subtitle: "From a WireGuard or OpenVPN configuration file"
            PushButton { text: "Import…"; enabled: root.busy === "" && !vpnAct.running; onClicked: root.importVpn() }
        }
    }
}
