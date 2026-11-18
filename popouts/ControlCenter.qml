import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services
import qs.components

// Control Centre (the toggles icon in the menu bar), laid out like macOS Sequoia: one glass
// panel (drawn by the bar, menu material) holding lighter modules on a 4-column grid —
// connectivity and Focus up top, the thick white Display and Sound sliders, Now Playing,
// then small tiles (Keep Awake, Dark Mode, Clipboard, Screenshot).
Item {
    id: root

    readonly property bool closeOnLeave: true
    readonly property int pad: 10                    // panel padding (read by bar/Bar.qml)
    property string screenName

    readonly property int g: 8                       // gap
    readonly property int u: 70                      // one grid cell
    readonly property int w: u * 4 + g * 3

    // Module and control colours (on the menu material)
    readonly property color modBg: Theme.dark ? Qt.rgba(1, 1, 1, 0.085) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color modEdge: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color offBg: Qt.alpha(Theme.menuText, Theme.dark ? 0.14 : 0.09)
    readonly property color dim: Qt.alpha(Theme.menuText, 0.55)

    implicitWidth: w
    implicitHeight: col.implicitHeight
    focus: true

    function settings(page) { Popouts.close(); Popouts.openSettings(page); }

    component Module: Rectangle {
        radius: 16
        antialiasing: true
        color: root.modBg
        border { width: 1; color: root.modEdge }
    }
    // Round toggle: selection colour when on.
    component Toggle: Rectangle {
        property string glyph
        property bool on: false
        property color onColor: Theme.menuSel
        width: 28; height: 28; radius: 14
        antialiasing: true
        color: on ? onColor : root.offBg
        Behavior on color { ColorAnimation { duration: 140 } }
        Text { anchors.centerIn: parent; text: parent.glyph; color: parent.on ? "white" : Theme.menuText
            font { family: Theme.mono; pixelSize: 13 } }
    }
    // One line of the connectivity module: toggle, name, status.
    component ConnRow: MouseArea {
        id: cr
        property string glyph
        property bool on
        property string title
        property string status
        width: parent.width; height: 40
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle { anchors { fill: parent; margins: 3 } radius: 10; antialiasing: true
            color: cr.pressed ? Qt.alpha(Theme.menuText, 0.1) : cr.containsMouse ? Qt.alpha(Theme.menuText, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } } }
        Toggle { id: tg; x: 10; anchors.verticalCenter: parent.verticalCenter; glyph: cr.glyph; on: cr.on }
        Column {
            anchors { left: tg.right; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; text: cr.title; elide: Text.ElideRight; color: Theme.menuText
                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
            Text { width: parent.width; text: cr.status; elide: Text.ElideRight; color: root.dim
                font { family: Theme.font; pixelSize: 11 } }
        }
    }
    // Square tile: a glyph, highlighted when on (like macOS's small modules).
    component Small: MouseArea {
        id: sm
        property string glyph
        property bool on: false
        property string tip
        width: root.u; height: root.u
        opacity: enabled ? 1 : 0.4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Module { anchors.fill: parent }
        Toggle { anchors.centerIn: parent; anchors.verticalCenterOffset: sm.tip ? -7 : 0; width: 34; height: 34; radius: 17; glyph: sm.glyph; on: sm.on }
        Text { visible: sm.tip !== ""; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
            text: sm.tip; color: root.dim; font { family: Theme.font; pixelSize: 10 } }
        Rectangle { anchors.fill: parent; radius: 16; antialiasing: true
            color: sm.pressed ? Qt.rgba(0, 0, 0, 0.12) : sm.containsMouse ? Qt.alpha(Theme.menuText, 0.05) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } } }
    }
    // macOS Control Centre slider: a thick rounded track, white fill, icon inside on the left.
    component BigSlider: Item {
        id: bs
        property real value: 0                       // 0..1
        property string glyph
        signal moved(real v)
        height: 24
        readonly property real shown: drag.pressed ? drag.v : Math.max(0, Math.min(1, value))
        Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            color: Qt.alpha(Theme.menuText, Theme.dark ? 0.16 : 0.1)
            clip: true
            Rectangle {
                // the fill always covers the knob, so it never looks empty at 0
                width: Math.max(track.height, track.height + (track.width - track.height) * bs.shown)
                height: parent.height; radius: height / 2
                antialiasing: true
                color: "white"
            }
        }
        // knob
        Rectangle {
            x: (track.width - track.height) * bs.shown
            width: track.height; height: track.height; radius: height / 2
            antialiasing: true
            color: "white"
            border { width: 1; color: Qt.rgba(0, 0, 0, 0.12) }
        }
        Text { x: 7; anchors.verticalCenter: parent.verticalCenter; text: bs.glyph; color: "#5a5a5e"
            font { family: Theme.mono; pixelSize: 11 } }
        MouseArea {
            id: drag
            property real v: 0
            anchors.fill: parent
            function at(x) { return Math.max(0, Math.min(1, (x - track.height / 2) / (track.width - track.height))); }
            onPressed: e => { v = at(e.x); bs.moved(v); }
            onPositionChanged: e => { if (pressed) { v = at(e.x); bs.moved(v); } }
        }
        WheelHandler { onWheel: e => bs.moved(Math.max(0, Math.min(1, bs.value + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }

    Column {
        id: col
        width: root.w
        spacing: root.g

        // ── Connectivity | Focus + two small tiles ────────────────────
        Row {
            spacing: root.g
            Module {
                width: root.u * 2 + root.g; height: root.u * 2 + root.g
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 2
                    ConnRow {
                        glyph: Net.glyph
                        on: Net.online
                        title: Net.wired ? "Ethernet" : "Wi-Fi"
                        status: Net.online ? (Net.wired ? "Connected" : (Net.wifi?.name ?? "Connected")) : "Not Connected"
                        onClicked: Popouts.open("network", root.screenName)
                    }
                    ConnRow {
                        readonly property var adapter: Bluetooth.defaultAdapter
                        readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
                        enabled: !!adapter
                        opacity: enabled ? 1 : 0.4
                        glyph: ""
                        on: adapter?.enabled ?? false
                        title: "Bluetooth"
                        status: !adapter ? "Unavailable" : !adapter.enabled ? "Off" : connected.length ? connected[0].name : "On"
                        onClicked: adapter.enabled = !adapter.enabled
                        onPressAndHold: root.settings("bluetooth")
                    }
                    ConnRow {
                        glyph: ""
                        on: Popouts.caffeine
                        title: "Keep Awake"
                        status: Popouts.caffeine ? "On" : "Off"
                        onClicked: Popouts.caffeine = !Popouts.caffeine
                    }
                }
            }
            Column {
                spacing: root.g
                MouseArea {
                    width: root.u * 2 + root.g; height: root.u
                    onClicked: Notifs.setDnd(!Notifs.dnd)
                    Module { anchors.fill: parent }
                    Toggle { id: moon; x: 12; anchors.verticalCenter: parent.verticalCenter; glyph: ""; on: Notifs.dnd; onColor: "#5e5ce6" }
                    Column {
                        anchors { left: moon.right; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        Text { text: "Focus"; color: Theme.menuText; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
                        Text { text: Notifs.dnd ? "Do Not Disturb" : "Off"; color: root.dim; font { family: Theme.font; pixelSize: 11 } }
                    }
                }
                Row {
                    spacing: root.g
                    Small {
                        readonly property string other: Theme.counterpart(Theme.current)
                        glyph: ""; tip: "Dark Mode"
                        on: Theme.dark
                        enabled: other !== ""
                        onClicked: Theme.toggleDark()
                    }
                    Small { glyph: ""; tip: "Clipboard"; onClicked: Popouts.open("clipboard", root.screenName) }
                }
            }
        }

        // ── Display (external monitor brightness over DDC/CI) ─────────
        Module {
            id: display
            visible: bright >= 0
            width: root.w; height: 62
            property int bright: Popouts.ddc
            Text { x: 12; y: 9; text: "Display"; color: Theme.menuText; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
            BigSlider {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10; bottomMargin: 10 }
                glyph: ""
                value: display.bright / 100
                onMoved: v => { display.bright = Math.round(v * 100); setBright.restart(); }
            }
            // Probe once per session (ddcutil talks I2C over the GPU; on NVIDIA every call stalls
            // the display for a moment, which stuttered the cursor each time the menu opened).
            // After that the cached value is used; drags write it a moment after the last move.
            Process {
                running: Popouts.ddc === -2         // only probe until we know
                command: ["timeout", "4", "ddcutil", "getvcp", "10", "--brief"]
                stdout: StdioCollector { onStreamFinished: { const m = /C\s+(\d+)\s+(\d+)/.exec(text); Popouts.ddc = m ? Math.round(100 * Number(m[1]) / Math.max(1, Number(m[2]))) : -1; display.bright = Popouts.ddc; } }
            }
            Timer { id: setBright; interval: 350; onTriggered: { Popouts.ddc = display.bright; Quickshell.execDetached(["ddcutil", "setvcp", "10", String(display.bright), "--noverify"]); } }
        }

        // ── Sound ─────────────────────────────────────────────────────
        Module {
            width: root.w; height: 62
            Text { x: 12; y: 9; text: "Sound"; color: Theme.menuText; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
            MouseArea {
                // the output list lives in the Sound menu (speaker icon), like macOS
                anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 5 }
                width: 22; height: 22
                onClicked: Popouts.open("sound", root.screenName)
                Rectangle { anchors.fill: parent; radius: 11; color: parent.containsMouse ? root.offBg : "transparent" }
                hoverEnabled: true
                Text { anchors.centerIn: parent; text: ""; color: root.dim; font { family: Theme.mono; pixelSize: 9 } }
            }
            BigSlider {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10; bottomMargin: 10 }
                glyph: Audio.muted ? "" : ""
                value: Audio.muted ? 0 : Math.min(1, Audio.volume)
                onMoved: v => Audio.setVolume(v)
            }
        }

        // ── Now Playing ───────────────────────────────────────────────
        Module {
            visible: !!Media.player
            width: root.w; height: 62
            MouseArea { anchors.fill: parent; onClicked: Popouts.open("media", root.screenName) }
            Rectangle {
                id: art
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 42; height: 42; radius: 8
                color: root.offBg
                clip: true
                Text { anchors.centerIn: parent; text: ""; color: root.dim; font { family: Theme.mono; pixelSize: 16 } }
                Image { anchors.fill: parent; source: Media.player?.trackArtUrl ?? ""; sourceSize { width: 84; height: 84 }
                    fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
            }
            Column {
                anchors { left: art.right; leftMargin: 10; right: controls.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                Text { width: parent.width; text: Media.label || "Not Playing"; elide: Text.ElideRight
                    color: Theme.menuText; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
                Text { width: parent.width; visible: Media.artist !== ""; text: Media.artist; elide: Text.ElideRight
                    color: root.dim; font { family: Theme.font; pixelSize: 11 } }
            }
            Row {
                id: controls
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                Repeater {
                    model: [["", () => Media.previous()], [Media.playing ? "" : "", () => Media.playPause()], ["", () => Media.next()]]
                    MouseArea {
                        required property var modelData
                        width: 28; height: 28
                        onClicked: modelData[1]()
                        Text { anchors.centerIn: parent; text: parent.modelData[0]; color: Theme.menuText
                            font { family: Theme.mono; pixelSize: 14 } }
                    }
                }
            }
        }

        // ── Small tiles ───────────────────────────────────────────────
        Row {
            spacing: root.g
            Small { glyph: ""; tip: "Wallpaper"; onClicked: Popouts.open("wallpapers", root.screenName) }
            Small { glyph: ""; tip: "Screenshot"; onClicked: { Popouts.close(); Screenshot.openToolbar(); } }
            Small { glyph: ""; tip: "Search"; onClicked: { Popouts.close(); Popouts.openOverlay("spotlight"); } }
            Small { glyph: ""; tip: "Settings"; onClicked: root.settings("") }
        }
    }
}
