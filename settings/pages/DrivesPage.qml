import QtQuick
import Quickshell
import qs.services
import qs.components
import qs.settings

// Drives pane: automount options, then every mountable drive with Mount / Unmount / Eject and
// a "mount at login" switch. All through udisks (services/Drives.qml).
Column {
    id: root
    spacing: 20

    Component.onCompleted: { Drives.pageOpen = true; Drives.refresh(); }
    Component.onDestruction: Drives.pageOpen = false

    Group {
        title: "Automount"
        footer: "Drives you plug in (USB sticks, SD cards, external disks) are mounted under /run/media/" + (Quickshell.env("USER") ?? "you") + "."
        Setting { spec: ({ key: "automount", type: "switch", label: "Mount drives when plugged in" }) }
        Setting { spec: ({ key: "automountOpen", type: "switch", label: "Open in the file manager", when: "automount" }) }
        Setting { spec: ({ key: "automountNotify", type: "switch", label: "Show a notification", when: "automount" }) }
    }

    Group {
        title: "Drives"
        footer: Drives.error !== "" ? Drives.error
              : "Mount at login works for drives with a filesystem ID. Mounting an internal drive may ask for your password."

        SettingRow {
            visible: Drives.list.length === 0
            title: Drives.scanned ? "No other drives" : "Looking for drives…"
            subtitle: Drives.scanned ? "Your system drive isn't listed here." : ""
        }
        Repeater {
            model: Drives.list
            delegate: SettingRow {
                id: row
                required property var modelData
                readonly property var d: modelData
                readonly property bool busy: !!Drives.busy[d.dev]
                glyph: d.removable ? "󱊞" : "󰋊"
                glyphTint: d.removable ? "#ff9f0a" : "#8e8e93"
                title: d.name
                subtitle: [Drives.sizeText(d.size), d.fstype, d.mount ? d.mount : "Not mounted"].filter(x => x).join("  ·  ")

                Row {
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.d.uuid !== ""
                        text: "At login"
                        color: Theme.textDim
                        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
                    }
                    Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.d.uuid !== ""
                        checked: (Config.values.mountAtLogin ?? []).includes(row.d.uuid)
                        onToggled: c => Drives.setAtLogin(row.d, c)
                    }
                    PushButton {
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: !row.busy
                        text: row.busy ? "…" : row.d.mount ? "Unmount" : "Mount"
                        onClicked: row.d.mount ? Drives.unmount(row.d) : Drives.mount(row.d, false)
                    }
                    PushButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.d.removable
                        enabled: !row.busy
                        text: "Eject"
                        onClicked: Drives.eject(row.d)
                    }
                }
            }
        }
    }
}
