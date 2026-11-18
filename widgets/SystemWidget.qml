import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services

// System rings, like Apple's Batteries widget (Tahoe: white, red only when hot/low; Classic: a colour per ring): CPU, memory, temperature, and disk
// (or battery on a laptop). Click opens btop. Small: 2×2 rings. Medium: a row of rings.
// Large: the row plus a detail list.
Card {
    id: root
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBat: bat?.isLaptopBattery ?? false
    readonly property int batPct: Math.round((bat?.percentage ?? 0) <= 1 ? (bat?.percentage ?? 0) * 100 : bat.percentage)

    readonly property var rings: [
        { label: "CPU", frac: SysStats.cpu, text: Math.round(SysStats.cpu * 100) + "%", g: "", color: root.tahoe ? "" : "#0a84ff" },
        { label: "Memory", frac: SysStats.mem, text: (SysStats.memUsed / 1048576).toFixed(1) + "G", g: "\uf2db", color: root.tahoe ? "" : "#30d158" },
        SysStats.temp >= 0
            ? { label: "Temp", frac: Math.min(1, SysStats.temp / 100), text: SysStats.temp + "°", g: "", color: SysStats.temp >= 85 ? "#ff453a" : root.tahoe ? "" : "#ff9f0a" }
            : null,
        hasBat
            ? { label: "Battery", frac: batPct / 100, text: batPct + "%", g: "", color: batPct <= 15 ? "#ff453a" : root.tahoe ? "" : "#30d158" }
            : { label: "Disk", frac: SysStats.disk, text: Math.round(SysStats.disk * 100) + "%", g: "", color: root.tahoe ? "" : "#bf5af2" }
    ].filter(r => r !== null)

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached([Quickshell.env("TERMINAL") || "foot", "-e", "btop"])
    }

    readonly property bool small: size === "s"
    readonly property int ring: small ? 46 : 64

    Grid {
        columns: root.small ? 2 : root.rings.length
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.small ? 12 : (root.unit - height) / 2
        columnSpacing: root.small ? 26 : (root.width - 32 - root.rings.length * 64) / Math.max(1, root.rings.length - 1)
        rowSpacing: 4
        Repeater {
            model: root.rings
            Column {
                required property var modelData
                spacing: root.small ? 2 : 8
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.ring; height: root.ring
                    Canvas {
                        id: ring
                        anchors.fill: parent
                        property real frac: Math.max(0, Math.min(1, modelData.frac))
                        Behavior on frac { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                        onFracChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        Connections { target: Theme; function onPalChanged() { ring.requestPaint(); } }
                        Connections { target: root; function onFgChanged() { ring.requestPaint(); } function onTahoeChanged() { ring.requestPaint(); } }
                        onPaint: {
                            const lw = root.small ? 5 : 6, ctx = getContext("2d"), c = width / 2, r = c - lw / 2 - 1;
                            ctx.reset();
                            ctx.lineWidth = lw; ctx.lineCap = "round";
                            ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI);
                            ctx.strokeStyle = root.tahoe ? root.fgTrack : Theme.control; ctx.stroke();
                            if (frac > 0.005) {
                                ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + frac * 2 * Math.PI);
                                ctx.strokeStyle = modelData.color || root.fg; ctx.stroke();
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.g
                        color: root.fg
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: root.small ? 14 : 18 }
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.text; color: root.fg
                        font { family: root.font; pixelSize: root.small ? 11 : 13; weight: Font.Bold } }
                    Text { visible: !root.small; anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.fgDim
                        font { family: root.font; pixelSize: 10; weight: Font.Medium } }
                }
            }
        }
    }

    // ── Large: details under the rings ──
    Column {
        visible: root.large
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: root.unit + 2; leftMargin: 18; rightMargin: 18 }
        Rectangle { width: parent.width; height: 1; color: root.fgTrack }
        Repeater {
            model: root.large ? [
                ["Processor", Math.round(SysStats.cpu * 100) + "% used"],
                ["Memory", (SysStats.memUsed / 1048576).toFixed(1) + " of " + (SysStats.memTotal / 1048576).toFixed(1) + " GB"],
                ["Temperature", SysStats.temp >= 0 ? SysStats.temp + " °C" : "—"],
                root.hasBat ? ["Battery", root.batPct + "%"] : ["Disk", SysStats.diskFree ? SysStats.diskFree + " free" : Math.round(SysStats.disk * 100) + "% used"]
            ] : []
            Item {
                required property var modelData
                width: parent.width; height: 40
                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: root.fgDim
                    font { family: root.font; pixelSize: 13; weight: Font.Medium } }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: modelData[1]; color: root.fg
                    font { family: root.font; pixelSize: 13; weight: Font.DemiBold } }
            }
        }
    }
}
