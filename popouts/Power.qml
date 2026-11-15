import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services
import qs.components

// Power menu (the ⏻ at the right end of the menu bar, Super+Escape): who/uptime, sound and
// microphone sliders with output picker, display brightness, quick toggles, and
// Lock / Sleep / Log Out / Restart / Shut Down. Log Out / Restart / Shut Down need a second
// click (or Enter) to confirm. ←/→ pick a power action, Enter runs it, ↑/↓ change the volume.
Item {
    id: root

    readonly property bool closeOnLeave: true
    readonly property int w: 336
    implicitWidth: w
    implicitHeight: col.implicitHeight
    focus: true

    property int index: -1
    property string armed: ""
    readonly property string user: Quickshell.env("USER") || "user"

    readonly property var actions: [
        { id: "lock", text: "Lock", glyph: "", confirm: false, f: () => Compositor.lock() },
        { id: "sleep", text: "Sleep", glyph: "", confirm: false, cmd: ["systemctl", "suspend"] },
        { id: "logout", text: "Log Out", glyph: "", confirm: true, f: () => Compositor.logout() },
        { id: "reboot", text: "Restart", glyph: "", confirm: true, cmd: ["systemctl", "reboot"] },
        { id: "off", text: "Shut Down", glyph: "", confirm: true, cmd: ["systemctl", "poweroff"] }
    ]

    function run(a) {
        if (a.confirm && armed !== a.id) { armed = a.id; return; }
        Popouts.close();
        if (a.f) a.f(); else Quickshell.execDetached(a.cmd);
    }
    function settings(page) { Popouts.close(); Popouts.openSettings(page); }

    Keys.onPressed: e => {
        const n = actions.length;
        if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_L) { index = (index + 1) % n; armed = ""; }
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_H) { index = (Math.max(0, index) + n - 1) % n; armed = ""; }
        else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) Audio.nudge(0.05);
        else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) Audio.nudge(-0.05);
        else if (e.key === Qt.Key_M) Audio.toggleMute();
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) && index >= 0) run(actions[index]);
        else return;
        e.accepted = true;
    }

    // Uptime, read once when the menu opens.
    FileView { id: up; path: "/proc/uptime" }
    readonly property string uptime: {
        const s = Math.floor(Number((up.text() ?? "0").split(" ")[0]) || 0);
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
    }

    component Section: Text {
        color: Theme.textDim
        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
    }
    // Glyph button (round), accent when on.
    component Round: MouseArea {
        id: r
        property string glyph
        property bool on: false
        property int size: 30
        width: size; height: size
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        opacity: enabled ? 1 : 0.4
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: r.on ? Theme.accent : r.containsMouse ? Theme.control : Theme.hover
        }
        Text { anchors.centerIn: parent; text: r.glyph; color: r.on ? Theme.onAccent : Theme.text
            font { family: Theme.mono; pixelSize: Math.round(r.size * 0.42) } }
    }
    // One slider row: mute button, slider, percentage.
    component Level: Row {
        id: lv
        property string glyph
        property bool muted: false
        property real value: 0
        signal toggled()
        signal changed(real v)
        width: root.w
        spacing: 10
        Round { anchors.verticalCenter: parent.verticalCenter; glyph: lv.glyph; on: !lv.muted; onClicked: lv.toggled() }
        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: lv.width - 30 - 40 - 20
            from: 0; to: 1; stepSize: 0.01
            value: lv.muted ? 0 : Math.min(1, lv.value)
            onMoved: v => lv.changed(v)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 40; horizontalAlignment: Text.AlignRight
            text: lv.muted ? "Muted" : Math.round(lv.value * 100) + "%"
            color: Theme.textDim
            font { family: Theme.font; pixelSize: 12; features: { "tnum": 1 } }
        }
    }
    component Rule: Rectangle { width: root.w; height: 1; color: Theme.hairline }

    Column {
        id: col
        width: root.w
        spacing: 12

        // ── Who + uptime | settings ───────────────────────────────────
        Item {
            width: root.w; height: 40
            Rectangle {
                id: avatar
                width: 40; height: 40; radius: 20
                color: Theme.accent
                Text { anchors.centerIn: parent; text: root.user.charAt(0).toUpperCase(); color: Theme.onAccent
                    font { family: Theme.font; pixelSize: 18; weight: Font.Bold } }
            }
            Column {
                anchors { left: avatar.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                Text { text: root.user; color: Theme.text; font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
                Text { text: root.uptime; color: Theme.textDim; font { family: Theme.font; pixelSize: 11 } }
            }
            Round { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                glyph: ""; onClicked: root.settings("") }
        }

        Rule {}

        // ── Sound ─────────────────────────────────────────────────────
        Item {
            width: root.w; height: 16
            Section { text: "Sound" }
            MouseArea {
                id: outBtn
                property bool open: false
                anchors.right: parent.right
                width: outName.implicitWidth + 16; height: 16
                cursorShape: Qt.PointingHandCursor
                onClicked: open = !open
                Text {
                    id: outName
                    anchors.right: parent.right
                    width: Math.min(implicitWidth, 220); elide: Text.ElideRight
                    text: Audio.name + (outBtn.open ? "  " : "  ")
                    color: Theme.textDim
                    font { family: Theme.font; pixelSize: 11 }
                }
            }
        }
        Level {
            glyph: Audio.muted ? "" : ""
            muted: Audio.muted; value: Audio.volume
            onToggled: Audio.toggleMute()
            onChanged: v => Audio.setVolume(v)
        }
        Column {
            visible: outBtn.open
            width: root.w
            Repeater {
                model: outBtn.open ? Audio.sinks : []
                MouseArea {
                    id: o
                    required property var modelData
                    width: root.w; height: 26
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.setDefault(modelData)
                    Rectangle { anchors.fill: parent; radius: 6; color: o.containsMouse ? Theme.hover : "transparent" }
                    Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: o.modelData === Audio.sink ? "✓" : ""
                        color: Theme.text; font { family: Theme.font; pixelSize: 11 } }
                    Text { anchors { left: parent.left; leftMargin: 24; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: o.modelData.nickname || o.modelData.description || o.modelData.name; elide: Text.ElideRight
                        color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
                }
            }
        }

        // ── Microphone ────────────────────────────────────────────────
        Section { visible: !!Audio.source; text: "Microphone" }
        Level {
            visible: !!Audio.source
            glyph: Audio.micMuted ? "" : ""
            muted: Audio.micMuted; value: Audio.micVolume
            onToggled: Audio.toggleMic()
            onChanged: v => Audio.setMic(v)
        }

        // ── Display brightness (DDC/CI, shared cache with Control Center) ──
        Section { visible: display.bright >= 0; text: "Display" }
        Row {
            id: display
            visible: bright >= 0
            property int bright: Popouts.ddc
            width: root.w
            spacing: 10
            Round { anchors.verticalCenter: parent.verticalCenter; glyph: ""; on: true; enabled: false; opacity: 1 }
            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: root.w - 30 - 40 - 20
                from: 0; to: 100; value: display.bright
                onMoved: v => { display.bright = Math.round(v); setBright.restart(); }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; width: 40; horizontalAlignment: Text.AlignRight
                text: display.bright + "%"; color: Theme.textDim; font { family: Theme.font; pixelSize: 12 } }
            Process {
                running: Popouts.ddc === -2                // only probe until we know
                command: ["timeout", "4", "ddcutil", "getvcp", "10", "--brief"]
                stdout: StdioCollector { onStreamFinished: { const m = /C\s+(\d+)\s+(\d+)/.exec(text); Popouts.ddc = m ? Math.round(100 * Number(m[1]) / Math.max(1, Number(m[2]))) : -1; } }
            }
            Timer { id: setBright; interval: 350; onTriggered: { Popouts.ddc = display.bright; Quickshell.execDetached(["ddcutil", "setvcp", "10", String(display.bright), "--noverify"]); } }
        }

        Rule {}

        // ── Quick toggles ─────────────────────────────────────────────
        Row {
            id: toggles
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var items: [
                { glyph: Net.glyph, label: Net.online ? (Net.wired ? "Wired" : (Net.wifi?.name ?? "Wi-Fi")) : "Offline", on: Net.online, ok: true,
                  f: () => root.settings(Net.wired ? "network" : "wifi") },
                { glyph: "", label: "Bluetooth", on: toggles.adapter?.enabled ?? false, ok: !!toggles.adapter,
                  f: () => toggles.adapter.enabled = !toggles.adapter.enabled },
                { glyph: "", label: "Focus", on: Notifs.dnd, ok: true, f: () => Notifs.setDnd(!Notifs.dnd) },
                { glyph: "", label: "Awake", on: Popouts.caffeine, ok: true, f: () => Popouts.caffeine = !Popouts.caffeine },
                { glyph: "", label: Theme.dark ? "Dark" : "Light", on: Theme.dark, ok: Theme.counterpart(Theme.current) !== "", f: () => Theme.toggleDark() }
            ]
            width: root.w
            spacing: (root.w - 5 * 56) / 4
            Repeater {
                model: toggles.items
                Column {
                    required property var modelData
                    width: 56
                    spacing: 5
                    Round {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 40
                        glyph: parent.modelData.glyph
                        on: parent.modelData.on
                        enabled: parent.modelData.ok
                        onClicked: parent.modelData.f()
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: parent.modelData.label; color: Theme.textDim
                        font { family: Theme.font; pixelSize: 10 }
                    }
                }
            }
        }

        Rule {}

        // ── Power actions ─────────────────────────────────────────────
        Row {
            width: root.w
            spacing: (root.w - 5 * 62) / 4
            Repeater {
                model: root.actions
                MouseArea {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool current: index === root.index
                    readonly property bool isArmed: root.armed === modelData.id
                    width: 62; height: 62
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: { if (root.index !== index) root.armed = ""; root.index = index; }
                    onClicked: root.run(modelData)

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: tile.isArmed ? Qt.alpha(Theme.pal.red ?? "#ff453a", 0.22) : tile.current ? Theme.control : Theme.hover
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.glyph
                            color: tile.isArmed ? (Theme.pal.red ?? "#ff453a") : Theme.text
                            font { family: Theme.mono; pixelSize: 17 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.isArmed ? "Sure?" : tile.modelData.text
                            color: tile.isArmed ? (Theme.pal.red ?? "#ff453a") : tile.current ? Theme.text : Theme.textDim
                            font { family: Theme.font; pixelSize: 10; weight: Font.DemiBold }
                        }
                    }
                }
            }
        }
    }
}
