import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.services

// Now playing, Apple style: rounded cover art, title, artist, progress, transport.
// Click the art to open the full player. Small: art, play/pause, title. Medium: art beside
// the title, progress and controls. Large: big art on top, everything under it.
Card {
    id: root
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
        width: root.size === "s" ? 76 : root.large ? 176 : root.height - 32
        height: width
        x: root.large ? (root.width - width) / 2 : root.size === "s" ? 14 : 16
        y: root.size === "s" ? 14 : 16
        onWidthChanged: requestPaint()
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
                ready = true;
            } else {
                ready = false;
                ctx.fillStyle = root.tahoe ? Qt.rgba(1, 1, 1, 0.12) : Theme.card; ctx.fillRect(0, 0, w, w);
            }
        }
        Connections { target: Theme; function onPalChanged() { art.requestPaint(); } }
        Connections { target: root; function onTahoeChanged() { art.requestPaint(); } }
        Text {
            anchors.centerIn: parent
            visible: !(art.ready && artSrc.status === Image.Ready)
            text: ""; color: root.fgFaint
            font { family: root.iconFont; pixelSize: root.size === "s" ? 26 : 34 }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Popouts.toggle("media", root.screenName) }
    }

    Item {
        visible: root.size !== "s"
        anchors {
            left: root.large ? parent.left : art.right; leftMargin: root.large ? 18 : 14
            right: parent.right; rightMargin: root.large ? 18 : 16
            top: root.large ? art.bottom : art.top; topMargin: root.large ? 12 : 0
            bottom: root.large ? parent.bottom : art.bottom; bottomMargin: root.large ? 12 : 0
        }

        Column {
            width: parent.width
            spacing: 1
            Text {
                width: parent.width
                text: root.p ? (root.p.identity || "Music").toUpperCase() : "MUSIC"
                elide: Text.ElideRight
                color: root.cPink || root.fgDim
                font { family: root.font; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.5 }
            }
            Item { width: 1; height: 4 }
            Text {
                width: parent.width
                text: root.p ? (Media.title || "Unknown title") : "Not Playing"
                elide: Text.ElideRight
                color: root.fg
                font { family: root.font; pixelSize: 15; weight: Font.Bold }
            }
            Text {
                width: parent.width
                visible: !!root.p
                text: Media.artist || root.p?.trackAlbum || ""
                elide: Text.ElideRight
                color: root.fgDim
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
                    color: root.fgTrack
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (root.p?.position ?? 0) / Math.max(1, root.p?.length ?? 1)))
                        height: parent.height; radius: 2
                        antialiasing: true
                        color: root.fg
                    }
                }
                Item {
                    width: parent.width; height: 12
                    Text { text: Media.fmt(root.p?.position ?? 0); color: root.fgDim
                        font { family: root.font; pixelSize: 9; weight: Font.DemiBold } }
                    Text { anchors.right: parent.right; text: "-" + Media.fmt(Math.max(0, (root.p?.length ?? 0) - (root.p?.position ?? 0))); color: root.fgDim
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
                        Rectangle { anchors.fill: parent; radius: 16; antialiasing: true; color: parent.containsMouse ? root.hover : "transparent" }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.g
                            color: parent.enabled ? root.fg : root.fgFaint
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
            color: root.fgFaint
            font { family: root.font; pixelSize: 11 }
        }
    }

    // ── Small: play/pause beside the art, title + artist along the bottom ──
    MouseArea {
        visible: root.size === "s" && !!root.p
        anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 14 }
        width: 36; height: 36
        enabled: root.p?.canTogglePlaying ?? false
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Media.playPause()
        Rectangle { anchors.fill: parent; radius: 18; antialiasing: true; color: parent.containsMouse ? root.hover : "transparent" }
        Text { anchors.centerIn: parent; text: root.p?.isPlaying ? "" : ""; color: root.fg
            font { family: root.iconFont; pixelSize: 22 } }
    }
    Column {
        visible: root.size === "s"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
        Text { width: parent.width; text: root.p ? (Media.title || "Unknown title") : "Not Playing"; elide: Text.ElideRight
            color: root.fg; font { family: root.font; pixelSize: 13; weight: Font.Bold } }
        Text { width: parent.width; visible: !!root.p; text: Media.artist || root.p?.trackAlbum || ""; elide: Text.ElideRight
            color: root.fgDim; font { family: root.font; pixelSize: 11; weight: Font.Medium } }
    }
}
