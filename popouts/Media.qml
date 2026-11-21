import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.services
import qs.components

// Music player (the ♪ button in the bar, Super+M): cover art, seek bar, transport,
// shuffle / repeat, the player's own volume, and a switcher when several players are open.
//   Space play/pause · ←/→ seek 5 s · Shift+←/→ previous/next
Item {
    id: root

    readonly property bool closeOnLeave: true
    readonly property MprisPlayer p: Media.player

    implicitWidth: 420
    implicitHeight: (p ? body.implicitHeight : empty.implicitHeight) + 8
    focus: true

    Keys.onSpacePressed: Media.playPause()
    Keys.onLeftPressed: e => e.modifiers & Qt.ShiftModifier ? Media.previous() : seekBy(-5)
    Keys.onRightPressed: e => e.modifiers & Qt.ShiftModifier ? Media.next() : seekBy(5)

    component Btn: MouseArea {
        id: btn
        property string glyph
        property bool on: false
        property int size: 36
        width: size; height: size
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        anchors.verticalCenter: parent.verticalCenter
        Rectangle { anchors.fill: parent; radius: width / 2; color: btn.containsMouse && btn.enabled ? Theme.hover : "transparent" }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: !btn.enabled ? Qt.alpha(Theme.textFaint, 0.5) : btn.on ? Theme.accent : btn.containsMouse ? Theme.text : Theme.textDim
            font { family: Theme.mono; pixelSize: 18 }
        }
    }

    function seekBy(d) { if (p?.canSeek && p.positionSupported) p.position = Math.max(0, Math.min(p.length, p.position + d)); }

    // MPRIS doesn't push position updates; poll it only while this is open and playing.
    Timer {
        interval: 500; repeat: true; triggeredOnStart: true
        running: root.p?.isPlaying ?? false
        onTriggered: root.p.positionChanged()
    }
    Connections { target: root; function onPChanged() { if (root.p) root.p.positionChanged(); } }

    // ── Nothing playing ───────────────────────────────────────────────
    Column {
        id: empty
        visible: !root.p
        width: parent.width
        topPadding: 22; bottomPadding: 24
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\u{f075a}"
            color: Theme.textFaint
            font { family: Theme.mono; pixelSize: 30 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nothing playing"
            color: Theme.textFaint
            font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 }
        }
    }

    // ── Player ────────────────────────────────────────────────────────
    Column {
        id: body
        visible: !!root.p
        x: 4; y: 6
        width: parent.width - 8
        spacing: 14

        // Art + track
        Item {
            width: parent.width
            height: 112

            Rectangle {
                id: art
                width: 112; height: 112; radius: 14
                color: Theme.card
                clip: true
                Text { anchors.centerIn: parent; text: "\u{f075a}"; color: Theme.textFaint; font { family: Theme.mono; pixelSize: 34 } }
                Image {
                    anchors.fill: parent
                    source: root.p?.trackArtUrl ?? ""
                    sourceSize { width: 224; height: 224 }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.p?.canRaise ?? false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { root.p.raise(); Popouts.close(); }
                }
            }

            Column {
                anchors { left: art.right; leftMargin: 16; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    width: parent.width
                    text: (root.p?.identity ?? "").toUpperCase()
                    elide: Text.ElideRight
                    color: Theme.textFaint
                    font { family: Theme.font; pixelSize: 9; weight: Theme.w(Font.Bold); letterSpacing: 1 }
                }
                Text {
                    width: parent.width
                    text: Media.label
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 15; weight: Theme.w(Font.Bold) }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: Media.artist
                    elide: Text.ElideRight
                    color: Theme.textDim
                    font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.p?.trackAlbum ?? ""
                    elide: Text.ElideRight
                    color: Theme.textFaint
                    font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
                }
            }
        }

        // Seek bar
        Item {
            id: seek
            readonly property bool usable: (root.p?.positionSupported ?? false) && (root.p?.lengthSupported ?? false) && (root.p?.length ?? 0) > 0
            readonly property real frac: drag.pressed ? drag.f : usable ? Math.max(0, Math.min(1, root.p.position / root.p.length)) : 0
            visible: usable
            width: parent.width
            height: 30

            Rectangle {
                id: track
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 6 }
                height: drag.containsMouse || drag.pressed ? 6 : 4
                radius: height / 2
                color: Theme.control
                Behavior on height { NumberAnimation { duration: 120 } }
                Rectangle { width: parent.width * seek.frac; height: parent.height; radius: parent.radius; color: Theme.text }
            }
            Rectangle {
                visible: drag.containsMouse || drag.pressed
                x: track.width * seek.frac - width / 2
                anchors.verticalCenter: track.verticalCenter
                width: 12; height: 12; radius: 6
                color: Theme.text
            }
            MouseArea {
                id: drag
                property real f: 0
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 18
                enabled: root.p?.canSeek ?? false
                hoverEnabled: true
                preventStealing: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: e => f = Math.max(0, Math.min(1, e.x / width))
                onPositionChanged: e => { if (pressed) f = Math.max(0, Math.min(1, e.x / width)); }
                onReleased: root.p.position = f * root.p.length
            }
            Text {
                anchors { left: parent.left; bottom: parent.bottom }
                text: Media.fmt(drag.pressed ? drag.f * (root.p?.length ?? 0) : root.p?.position ?? 0)
                color: Theme.textFaint
                font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 10 }
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom }
                text: Media.fmt(root.p?.length ?? 0)
                color: Theme.textFaint
                font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 10 }
            }
        }

        // Transport
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Btn {
                visible: root.p?.shuffleSupported ?? false
                glyph: root.p?.shuffle ? "\u{f049d}" : "\u{f049e}"
                on: root.p?.shuffle ?? false
                enabled: root.p?.canControl ?? false
                onClicked: root.p.shuffle = !root.p.shuffle
            }
            Btn {
                glyph: "\u{f04ae}"
                size: 42
                enabled: (root.p?.canGoPrevious ?? false) || (root.p?.canSeek ?? false)
                onClicked: Media.previous()
            }
            MouseArea {
                id: play
                width: 52; height: 52
                anchors.verticalCenter: parent.verticalCenter
                enabled: root.p?.canTogglePlaying ?? false
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Media.playPause()
                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    color: Theme.text
                    opacity: play.enabled ? 1 : 0.4
                    scale: play.pressed ? 0.92 : play.containsMouse ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.centerIn: parent
                        text: Media.playing ? "\u{f03e4}" : "\u{f040a}"
                        color: Theme.bg
                        font { family: Theme.mono; pixelSize: 24 }
                    }
                }
            }
            Btn {
                glyph: "\u{f04ad}"
                size: 42
                enabled: root.p?.canGoNext ?? false
                onClicked: Media.next()
            }
            Btn {
                visible: root.p?.loopSupported ?? false
                readonly property int ls: root.p?.loopState ?? MprisLoopState.None
                glyph: ls === MprisLoopState.Track ? "\u{f0458}" : ls === MprisLoopState.Playlist ? "\u{f0456}" : "\u{f0457}"
                on: ls !== MprisLoopState.None
                enabled: root.p?.canControl ?? false
                // off → playlist → track → off
                onClicked: root.p.loopState = ls === MprisLoopState.None ? MprisLoopState.Playlist
                                             : ls === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
            }
        }

        // Player volume (the app's own, separate from the system output)
        Row {
            visible: root.p?.volumeSupported ?? false
            width: parent.width
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                text: (root.p?.volume ?? 0) <= 0 ? "\u{f0581}" : "\u{f057e}"
                color: Theme.textFaint
                font { family: Theme.mono; pixelSize: 15 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.p.volume = root.p.volume > 0 ? 0 : 1 }
            }
            Slider {
                width: parent.width - 28
                from: 0; to: 100; stepSize: 1; suffix: "%"
                value: Math.round((root.p?.volume ?? 0) * 100)
                onMoved: v => root.p.volume = v / 100
            }
        }

        // Switcher
        Flow {
            visible: Media.players.length > 1
            width: parent.width
            spacing: 6
            Repeater {
                model: Media.players
                MouseArea {
                    id: chip
                    required property MprisPlayer modelData
                    readonly property bool current: modelData === root.p
                    width: chipRow.implicitWidth + 20; height: 26
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Media.pick(modelData)
                    Rectangle {
                        anchors.fill: parent; radius: 13
                        color: chip.current ? Theme.control : chip.containsMouse ? Theme.hover : "transparent"
                        border { width: 1; color: Theme.hairline }
                    }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6; height: 6; radius: 3
                            color: chip.modelData.isPlaying ? Theme.accent : Theme.textFaint
                        }
                        Text {
                            text: chip.modelData.identity || chip.modelData.dbusName
                            color: chip.current ? Theme.text : Theme.textDim
                            font { family: Theme.font; pixelSize: 11; weight: Theme.w(chip.current ? Font.DemiBold : Font.Normal) }
                        }
                    }
                }
            }
        }
    }
}
