import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.services

// Now playing, Apple style: rounded cover art, title, artist, progress, transport.
// Click the art to open the full player.
Card {
    id: root
    wide: true
    property string screenName: ""
    readonly property MprisPlayer p: Media.player
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    // MPRIS doesn't push position; poll while playing.
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.p?.isPlaying ?? false
        onTriggered: root.p.positionChanged()
    }

    // Cover art, rounded with a Canvas clip (the software renderer can't mask).
    Image {
        id: artSrc
        visible: false
        source: root.p?.trackArtUrl ?? ""
        asynchronous: true
        // Canvas can't reliably draw an Image item (hidden + software renderer), so it loads
        // the URL itself; this Image only supplies status and dimensions for the crop.
        onSourceChanged: {
            if (art.loaded !== "") art.unloadImage(art.loaded);
            art.ready = false;
            art.loaded = source.toString();
            if (art.loaded !== "") art.loadImage(art.loaded);
            art.requestPaint();
        }
        onStatusChanged: art.requestPaint()
    }
    Canvas {
        id: art
        x: 16; y: 16
        width: root.height - 32; height: width
        property string loaded: ""
        property bool ready: false
        onImageLoaded: { ready = loaded !== "" && isImageLoaded(loaded); requestPaint(); }
        Component.onCompleted: if (artSrc.source != "") { loaded = artSrc.source.toString(); loadImage(loaded); }
        onPaint: {
            const ctx = getContext("2d"), r = 14, w = width;
            ctx.reset();
            ctx.beginPath();
            ctx.roundedRect(0, 0, w, w, r, r);
            ctx.closePath();
            ctx.clip();
            if (artSrc.status === Image.Ready && loaded !== "" && isImageLoaded(loaded)) {
                // Center-crop non-square art.
                const iw = artSrc.implicitWidth, ih = artSrc.implicitHeight, side = Math.min(iw, ih);
                ctx.drawImage(loaded, (iw - side) / 2, (ih - side) / 2, side, side, 0, 0, w, w);
            } else {
                ctx.fillStyle = Theme.card; ctx.fillRect(0, 0, w, w);
            }
        }
        Connections { target: Theme; function onPalChanged() { art.requestPaint(); } }
        Text {
            anchors.centerIn: parent
            visible: !(art.ready && artSrc.status === Image.Ready)
            text: ""; color: Theme.textFaint
            font { family: root.iconFont; pixelSize: 34 }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Popouts.toggle("media", root.screenName) }
    }

    Item {
        anchors { left: art.right; leftMargin: 14; right: parent.right; rightMargin: 16; top: art.top; bottom: art.bottom }

        Column {
            width: parent.width
            spacing: 1
            Text {
                width: parent.width
                text: root.p ? (root.p.identity || "Music").toUpperCase() : "MUSIC"
                elide: Text.ElideRight
                color: "#ff375f"
                font { family: root.font; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.5 }
            }
            Item { width: 1; height: 4 }
            Text {
                width: parent.width
                text: root.p ? (Media.title || "Unknown title") : "Not Playing"
                elide: Text.ElideRight
                color: Theme.text
                font { family: root.font; pixelSize: 15; weight: Font.Bold }
            }
            Text {
                width: parent.width
                visible: !!root.p
                text: Media.artist || root.p?.trackAlbum || ""
                elide: Text.ElideRight
                color: Theme.textDim
                font { family: root.font; pixelSize: 12; weight: Font.Medium }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 2
            visible: !!root.p

            // Progress, with elapsed / remaining like macOS
            Column {
                visible: (root.p?.positionSupported ?? false) && (root.p?.length ?? 0) > 0
                width: parent.width
                spacing: 3
                Rectangle {
                    width: parent.width; height: 4; radius: 2
                    antialiasing: true
                    color: Qt.alpha(Theme.text, 0.18)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (root.p?.position ?? 0) / Math.max(1, root.p?.length ?? 1)))
                        height: parent.height; radius: 2
                        antialiasing: true
                        color: Qt.alpha(Theme.text, 0.85)
                    }
                }
                Item {
                    width: parent.width; height: 12
                    Text { text: Media.fmt(root.p?.position ?? 0); color: Theme.textDim
                        font { family: root.font; pixelSize: 9; weight: Font.DemiBold } }
                    Text { anchors.right: parent.right; text: "-" + Media.fmt(Math.max(0, (root.p?.length ?? 0) - (root.p?.position ?? 0))); color: Theme.textDim
                        font { family: root.font; pixelSize: 9; weight: Font.DemiBold } }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Repeater {
                    model: [
                        { g: "", f: () => Media.previous(), on: root.p?.canGoPrevious ?? false, big: false },
                        { g: root.p?.isPlaying ? "" : "", f: () => Media.playPause(), on: root.p?.canTogglePlaying ?? false, big: true },
                        { g: "", f: () => Media.next(), on: root.p?.canGoNext ?? false, big: false }
                    ]
                    MouseArea {
                        required property var modelData
                        width: 32; height: 32
                        enabled: modelData.on
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.f()
                        Rectangle { anchors.fill: parent; radius: 16; antialiasing: true; color: parent.containsMouse ? Qt.alpha(Theme.text, 0.1) : "transparent" }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.g
                            color: parent.enabled ? Theme.text : Qt.alpha(Theme.text, 0.3)
                            font { family: root.iconFont; pixelSize: modelData.big ? 22 : 16 }
                        }
                    }
                }
            }
        }

        Text {
            visible: !root.p
            anchors { left: parent.left; bottom: parent.bottom }
            text: "Play something to see it here"
            color: Theme.textFaint
            font { family: root.font; pixelSize: 11 }
        }
    }
}
