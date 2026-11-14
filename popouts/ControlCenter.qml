import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import qs.services
import qs.components

// Control Center (the toggles icon in the menu bar), laid out like macOS: separate tiles on
// a 4-column grid — network and Now Playing up top, Bluetooth / Keep Awake, Focus,
// Display and Sound sliders, then Dark Mode, Calculator, Wallpaper and Screenshot.
// Flat tiles (no glass), drawn without a panel behind them.
Item {
    id: root

    readonly property bool closeOnLeave: true
    readonly property bool bare: true                // menu bar: don't draw a panel behind us
    property string screenName

    readonly property int u: 62                      // one grid cell
    readonly property int g: 12                      // gap
    readonly property int w: u * 4 + g * 3
    readonly property color tileBg: Theme.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.94) : Qt.rgba(0.96, 0.96, 0.97, 0.95)
    readonly property color offBg: Qt.alpha(Theme.text, Theme.dark ? 0.14 : 0.1)

    implicitWidth: w
    implicitHeight: col.implicitHeight
    focus: true

    function settings(page) { Popouts.close(); Popouts.openSettings(page); }
    function sh(c) { Quickshell.execDetached(["sh", "-c", c]); }

    component Tile: Rectangle {
        radius: height / 2
        color: root.tileBg
        border { width: 1; color: Qt.alpha(Theme.text, 0.08) }
    }
    // Round toggle with a glyph; accent when on.
    component Circle: MouseArea {
        id: c
        property string glyph
        property bool on: false
        property bool tile: true              // sits on its own tile background
        property string label: ""
        width: root.u; height: root.u
        opacity: enabled ? 1 : 0.4
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: c.on ? Theme.accent : c.tile ? root.tileBg : root.offBg
            border { width: c.tile && !c.on ? 1 : 0; color: Qt.alpha(Theme.text, 0.08) }
            Rectangle { anchors.fill: parent; radius: parent.radius; color: Qt.rgba(0, 0, 0, c.pressed ? 0.15 : 0) }
        }
        Text { anchors.centerIn: parent; text: c.glyph; color: c.on ? Theme.onAccent : Theme.text
            font { family: Theme.mono; pixelSize: 20 } }
    }

    Column {
        id: col
        width: root.w
        spacing: root.g

        // ── Network + Bluetooth/Awake | Now Playing ───────────────────
        Row {
            spacing: root.g
            Column {
                spacing: root.g
                // Network pill
                Tile {
                    width: root.u * 2 + root.g; height: root.u
                    MouseArea { anchors.fill: parent; onClicked: root.settings(Net.wired ? "network" : "wifi") }
                    Rectangle {
                        id: netIc
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 46; radius: 23
                        color: Net.online ? Theme.accent : root.offBg
                        Text { anchors.centerIn: parent; text: Net.glyph; color: Net.online ? Theme.onAccent : Theme.text
                            font { family: Theme.mono; pixelSize: 18 } }
                    }
                    Column {
                        anchors { left: netIc.right; leftMargin: 9; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        Text { width: parent.width; text: Net.wired ? "Ethernet" : "Wi-Fi"; color: Theme.text; elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                        Text { width: parent.width; text: Net.online ? (Net.wired ? "Connected" : (Net.wifi?.name ?? "Connected")) : "Off"
                            color: Theme.textDim; elide: Text.ElideRight; font { family: Theme.font; pixelSize: 11 } }
                    }
                }
                Row {
                    spacing: root.g
                    Circle {
                        readonly property var adapter: Bluetooth.defaultAdapter
                        glyph: ""
                        enabled: !!adapter
                        on: adapter?.enabled ?? false
                        onClicked: adapter.enabled = !adapter.enabled
                        onPressAndHold: root.settings("bluetooth")
                    }
                    Circle {
                        glyph: ""                      // keep awake (idle inhibitor)
                        on: Popouts.caffeine
                        onClicked: Popouts.caffeine = !Popouts.caffeine
                    }
                }
            }

            // Now Playing (2×2)
            Rectangle {
                width: root.u * 2 + root.g; height: root.u * 2 + root.g
                radius: 22
                color: root.tileBg
                border { width: 1; color: Qt.alpha(Theme.text, 0.08) }
                readonly property var p: Media.player
                MouseArea { anchors.fill: parent; onClicked: Popouts.open("media", root.screenName) }
                Rectangle {
                    id: art
                    x: 14; y: 14; width: 44; height: 44; radius: 8
                    color: root.offBg
                    clip: true
                    Image { anchors.fill: parent; source: parent.parent.p?.trackArtUrl ?? ""; sourceSize { width: 88; height: 88 }
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
                }
                Column {
                    anchors { left: parent.left; right: parent.right; top: art.bottom; topMargin: 10; leftMargin: 14; rightMargin: 14 }
                    Text { width: parent.width; text: parent.parent.p ? (Media.title || "Unknown") : "Not Playing"; elide: Text.ElideRight
                        color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                    Text { width: parent.width; visible: !!parent.parent.p; text: Media.artist; elide: Text.ElideRight
                        color: Theme.textDim; font { family: Theme.font; pixelSize: 11 } }
                }
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                    spacing: 14
                    Repeater {
                        model: [["", () => Media.previous()], [Media.playing ? "" : "", () => Media.playPause()], ["", () => Media.next()]]
                        MouseArea {
                            required property var modelData
                            width: 28; height: 28
                            enabled: !!Media.player
                            onClicked: modelData[1]()
                            Text { anchors.centerIn: parent; text: parent.modelData[0]; color: parent.enabled ? Theme.text : Theme.textFaint
                                font { family: Theme.mono; pixelSize: parent.modelData[0] === "" || parent.modelData[0] === "" ? 18 : 14 } }
                        }
                    }
                }
            }
        }

        // ── Focus | Clipboard | Settings ──────────────────────────────
        Row {
            spacing: root.g
            Tile {
                width: root.u * 2 + root.g; height: root.u
                MouseArea { anchors.fill: parent; onClicked: Notifs.setDnd(!Notifs.dnd) }
                Rectangle {
                    id: moon
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 46; height: 46; radius: 23
                    color: Notifs.dnd ? "#5e5ce6" : root.offBg
                    Text { anchors.centerIn: parent; text: ""; color: Notifs.dnd ? "white" : Theme.text; font { family: Theme.mono; pixelSize: 18 } }
                }
                Column {
                    anchors { left: moon.right; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    Text { text: "Focus"; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                    Text { visible: Notifs.dnd; text: "Do Not Disturb"; color: Theme.textDim; font { family: Theme.font; pixelSize: 11 } }
                }
            }
            Circle { glyph: ""; onClicked: Popouts.open("clipboard", root.screenName) }
            Circle { glyph: ""; onClicked: root.settings("general") }
        }

        // ── Display (external monitor brightness over DDC/CI) ─────────
        Tile {
            id: display
            visible: bright >= 0
            width: root.w; height: root.u
            radius: 20
            property int bright: Popouts.ddc
            Text { x: 14; y: 9; text: "Display"; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12; bottomMargin: 8 }
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 11 } }
                Slider {
                    width: parent.width - 48; from: 0; to: 100; value: display.bright
                    onMoved: v => { display.bright = Math.round(v); setBright.restart(); }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Theme.text; font { family: Theme.mono; pixelSize: 15 } }
            }
            // Read once when Control Center opens; write a moment after the last drag.
            Process {
                running: Popouts.ddc !== -1          // skip once we know the monitor doesn't do DDC/CI
                command: ["timeout", "4", "ddcutil", "getvcp", "10", "--brief"]
                stdout: StdioCollector { onStreamFinished: { const m = /C\s+(\d+)\s+(\d+)/.exec(text); Popouts.ddc = m ? Math.round(100 * Number(m[1]) / Math.max(1, Number(m[2]))) : -1; display.bright = Popouts.ddc; } }
            }
            Timer { id: setBright; interval: 350; onTriggered: { Popouts.ddc = display.bright; Quickshell.execDetached(["ddcutil", "setvcp", "10", String(display.bright), "--noverify"]); } }
        }

        // ── Sound ─────────────────────────────────────────────────────
        Tile {
            id: sound
            width: root.w; height: root.u + (outputs ? outList.height + 6 : 0)
            radius: 20
            property bool outputs: false
            Text { x: 14; y: 9; text: "Sound"; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
            Row {
                x: 12; y: root.u - height - 8
                width: parent.width - 24
                spacing: 8
                MouseArea { width: 14; height: 22; onClicked: Audio.toggleMute()
                    Text { anchors.centerIn: parent; text: Audio.muted ? "" : ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 12 } } }
                Slider {
                    width: parent.width - 14 - 22 - 34 - 24; from: 0; to: 1; stepSize: 0.01; decimals: 0
                    value: Audio.muted ? 0 : Math.min(1, Audio.volume)
                    onMoved: v => Audio.setVolume(v)
                }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 22; text: ""; color: Theme.text; font { family: Theme.mono; pixelSize: 14 } }
                MouseArea {
                    width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
                    onClicked: sound.outputs = !sound.outputs
                    Rectangle { anchors.fill: parent; radius: 15; color: sound.outputs ? Theme.accent : root.offBg }
                    Text { anchors.centerIn: parent; text: ""; color: sound.outputs ? Theme.onAccent : Theme.text; font { family: Theme.mono; pixelSize: 12 } }
                }
            }
            // Output picker
            Column {
                id: outList
                visible: sound.outputs
                x: 8; y: root.u
                width: parent.width - 16
                Repeater {
                    model: sound.outputs ? Audio.sinks : []
                    MouseArea {
                        id: o
                        required property var modelData
                        width: outList.width; height: 26
                        hoverEnabled: true
                        onClicked: Audio.setDefault(modelData)
                        Rectangle { anchors.fill: parent; radius: 6; color: o.containsMouse ? Theme.hover : "transparent" }
                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: o.modelData === Audio.sink ? "✓" : ""; color: Theme.text
                            font { family: Theme.font; pixelSize: 11 } }
                        Text { anchors { left: parent.left; leftMargin: 24; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: o.modelData.nickname || o.modelData.description || o.modelData.name; elide: Text.ElideRight
                            color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
                    }
                }
            }
        }

        // ── Dark Mode | Calculator | Wallpaper | Screenshot ───────────
        Row {
            spacing: root.g
            Circle {
                readonly property string other: Theme.counterpart(Theme.current)
                glyph: ""
                on: !Theme.dark
                enabled: other !== ""
                onClicked: Theme.toggleDark()
            }
            Circle { glyph: ""; onClicked: { Popouts.close(); Popouts.openOverlay("spotlight"); } }
            Circle { glyph: ""; onClicked: Popouts.open("wallpapers", root.screenName) }
            Circle {
                glyph: ""
                onClicked: {
                    Popouts.close();
                    // Region capture → clipboard and ~/Pictures/Screenshots (like ⇧⌘4).
                    root.sh('sleep 0.3; d="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$d"; f="$d/Screenshot $(date "+%Y-%m-%d at %H.%M.%S").png"; '
                          + 'g=$(slurp) && grim -g "$g" "$f" && wl-copy < "$f" && notify-send -i "$f" "Screenshot" "Saved to Screenshots and copied"');
                }
            }
        }
    }
}
