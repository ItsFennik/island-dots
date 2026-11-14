import QtQuick
import Quickshell
import Quickshell.Networking
import qs.services
import qs.components
import qs.settings

// Network pane: every interface NetworkManager knows, with its status (like macOS's list).
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
                        color: Theme.textDim; font { family: Theme.font; pixelSize: 12 }
                    }
                }
            }
        }
    }
}
