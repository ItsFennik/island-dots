import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components
import qs.settings

// Displays pane: an arrangement preview, then each display's details. Brightness appears
// when the monitor answers DDC/CI (checked from Control Centre).
Column {
    id: root
    spacing: 20

    // One shape for every compositor: Hyprland reports make/model/refresh rate over IPC;
    // elsewhere Quickshell's screen list gives geometry and scale (no refresh rate).
    readonly property var mons: Compositor.hyprland
        ? Hyprland.monitors.values.map(m => ({ name: m.name, x: m.x, y: m.y, width: m.width, height: m.height, scale: m.scale, focused: m.focused,
                                               title: ((m.lastIpcObject?.make ?? "") + " " + (m.lastIpcObject?.model ?? "")).trim(),
                                               refresh: m.lastIpcObject?.refreshRate ?? 0 }))
        : Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: Math.round(s.width * s.devicePixelRatio), height: Math.round(s.height * s.devicePixelRatio),
                                         scale: s.devicePixelRatio, focused: s.name === Compositor.focusedScreen, title: s.model || "", refresh: 0 }))
    property int sel: 0
    readonly property var m: mons[Math.min(sel, mons.length - 1)] ?? null
    Component.onCompleted: if (Compositor.hyprland) Hyprland.refreshMonitors()

    // Arrangement
    Rectangle {
        width: parent.width; height: 170
        radius: 10
        color: Theme.dark ? Qt.alpha(Theme.text, 0.045) : Qt.alpha(Theme.text, 0.03)
        border { width: 1; color: Qt.alpha(Theme.text, 0.07) }
        readonly property real minX: Math.min(...root.mons.map(m => m.x), 0)
        readonly property real minY: Math.min(...root.mons.map(m => m.y), 0)
        readonly property real spanW: Math.max(...root.mons.map(m => m.x + m.width / m.scale), 1) - minX
        readonly property real spanH: Math.max(...root.mons.map(m => m.y + m.height / m.scale), 1) - minY
        readonly property real k: Math.min((width - 60) / spanW, (height - 50) / spanH)
        Repeater {
            model: root.mons
            MouseArea {
                required property var modelData
                required property int index
                readonly property var box: parent
                x: (box.width - box.spanW * box.k) / 2 + (modelData.x - box.minX) * box.k
                y: (box.height - box.spanH * box.k) / 2 + (modelData.y - box.minY) * box.k
                width: modelData.width / modelData.scale * box.k
                height: modelData.height / modelData.scale * box.k
                onClicked: root.sel = index
                Rectangle {
                    anchors.fill: parent; radius: 4
                    gradient: Gradient { GradientStop { position: 0; color: "#5ac8fa" } GradientStop { position: 1; color: "#0a84ff" } }
                    border { width: root.sel === index ? 3 : 0; color: Theme.text }
                }
                Rectangle { visible: modelData.focused; x: 0; y: 0; width: parent.width; height: 4; radius: 2; color: "white"; opacity: 0.8 }
                Text { anchors.centerIn: parent; text: modelData.name; color: "white"; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
            }
        }
    }

    Group {
        visible: !!root.m
        title: root.m ? root.m.title || root.m.name : ""
        SettingRow {
            visible: Popouts.ddc >= 0
            title: "Brightness"
            Slider { width: 230; from: 0; to: 100; value: Math.max(0, Popouts.ddc)
                onMoved: v => { Popouts.ddc = Math.round(v); setBright.restart(); } }
            Timer { id: setBright; interval: 350; onTriggered: Quickshell.execDetached(["ddcutil", "setvcp", "10", String(Popouts.ddc), "--noverify"]) }
        }
        Repeater {
            model: root.m ? [["Resolution", root.m.width + " × " + root.m.height],
                             ["Refresh rate", root.m.refresh ? Math.round(root.m.refresh) + " Hz" : ""],
                             ["Scale", Math.round(root.m.scale * 100) / 100 + "×"],
                             ["Connection", root.m.name]] : []
            delegate: SettingRow {
                required property var modelData
                visible: !!modelData[1]
                title: modelData[0]
                Text { text: modelData[1]; color: Theme.textDim; font { family: Theme.font; pixelSize: 13 } }
            }
        }
    }
    Text {
        width: parent.width
        text: "Resolution, refresh rate and arrangement are set in your compositor's config"
              + ({ hyprland: " (~/.config/hypr, monitor rules).", niri: " (~/.config/niri/config.kdl, output blocks).",
                   sway: " (~/.config/sway/config, output lines).", mango: " (~/.config/mango/config.conf, monitorrule)." })[Compositor.name] ?? "."
        color: Theme.textDim; wrapMode: Text.WordWrap
        font { family: Theme.font; pixelSize: 11 }
    }
}
