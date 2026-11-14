import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services

// System rings, like Apple's Batteries widget: CPU, memory, temperature, and disk
// (or battery on a laptop). Click opens btop.
Card {
    id: root
    wide: true
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBat: bat?.isLaptopBattery ?? false
    readonly property int batPct: Math.round((bat?.percentage ?? 0) <= 1 ? (bat?.percentage ?? 0) * 100 : bat.percentage)

    readonly property var rings: [
        { label: "CPU", frac: SysStats.cpu, text: Math.round(SysStats.cpu * 100) + "%", g: "", color: "#0a84ff" },
        { label: "Memory", frac: SysStats.mem, text: (SysStats.memUsed / 1048576).toFixed(1) + "G", g: "\uf2db", color: "#30d158" },
        SysStats.temp >= 0
            ? { label: "Temp", frac: Math.min(1, SysStats.temp / 100), text: SysStats.temp + "°", g: "", color: SysStats.temp >= 85 ? "#ff453a" : "#ff9f0a" }
            : null,
        hasBat
            ? { label: "Battery", frac: batPct / 100, text: batPct + "%", g: "", color: batPct <= 15 ? "#ff453a" : "#30d158" }
            : { label: "Disk", frac: SysStats.disk, text: Math.round(SysStats.disk * 100) + "%", g: "", color: "#bf5af2" }
    ].filter(r => r !== null)

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached([Quickshell.env("TERMINAL") || "foot", "-e", "btop"])
    }

    Row {
        anchors.centerIn: parent
        spacing: (root.width - 32 - root.rings.length * 64) / Math.max(1, root.rings.length - 1)
        Repeater {
            model: root.rings
            Column {
                required property var modelData
                spacing: 8
                Item {
                    width: 64; height: 64
                    Canvas {
                        id: ring
                        anchors.fill: parent
                        property real frac: Math.max(0, Math.min(1, modelData.frac))
                        Behavior on frac { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                        onFracChanged: requestPaint()
                        Connections { target: Theme; function onPalChanged() { ring.requestPaint(); } }
                        onPaint: {
                            const ctx = getContext("2d"), c = width / 2, r = c - 4;
                            ctx.reset();
                            ctx.lineWidth = 6; ctx.lineCap = "round";
                            ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI);
                            ctx.strokeStyle = Theme.control; ctx.stroke();
                            if (frac > 0.005) {
                                ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + frac * 2 * Math.PI);
                                ctx.strokeStyle = modelData.color; ctx.stroke();
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.g
                        color: Theme.text
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.text; color: Theme.text
                        font { family: root.font; pixelSize: 13; weight: Font.Bold } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Theme.textDim
                        font { family: root.font; pixelSize: 10; weight: Font.Medium } }
                }
            }
        }
    }
}
