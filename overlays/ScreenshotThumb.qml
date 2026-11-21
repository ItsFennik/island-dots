import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The floating thumbnail after a screenshot (bottom right, like macOS). Stays ~6 s, longer
// while hovered. Click: open · swipe right / ✕: dismiss · hover: Copy, Show in Folder, Delete.
PanelWindow {
    id: win

    anchors { bottom: true; right: true }
    margins { bottom: 24; right: 24 }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 260
    implicitHeight: card.height + 8
    color: "transparent"
    WlrLayershell.namespace: "island-screenshot-thumb"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property string family: Theme.font
    readonly property string path: Screenshot.shot

    Timer { id: life; interval: 6000; running: !hover.containsMouse; onTriggered: Screenshot.dismiss() }

    Rectangle {
        id: card
        x: 4 + drag.dx
        y: 4
        width: win.implicitWidth - 8
        height: Math.max(80, Math.min(220, img.implicitHeight > 0 ? width * img.implicitHeight / img.implicitWidth : 140)) + 0
        radius: 10
        color: Qt.alpha(Theme.bg, 0.9)
        border { width: 1; color: Qt.alpha(Theme.text, 0.2) }
        clip: true
        opacity: 1 - Math.min(1, Math.max(0, drag.dx) / 200)

        Image {
            id: img
            anchors { fill: parent; margins: 3 }
            source: win.path ? "file://" + win.path : ""
            // Decode only at thumbnail size, never cache: a 4K PNG would otherwise sit in RAM.
            sourceSize.width: 512
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property real startX: 0
            property bool moved: false
            onPressed: e => { startX = e.x; moved = false; }
            onPositionChanged: e => { if (pressed) { drag.dx = Math.max(-20, e.x - startX); if (Math.abs(drag.dx) > 6) moved = true; } }
            onReleased: { if (drag.dx > 80) Screenshot.dismiss(); else drag.dx = 0; }
            onClicked: if (!moved) Screenshot.clipboardOnly ? Screenshot.dismiss() : Screenshot.open()
        }

        // Hover actions
        Row {
            visible: hover.containsMouse && !hover.pressed
            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
            spacing: 6
            Action { text: "Copy"; onClicked: { Screenshot.copy(); flash.restart(); } }
            Action { text: "Show in Folder"; visible: !Screenshot.clipboardOnly; onClicked: Screenshot.showInFolder() }
            Action { text: "Delete"; visible: !Screenshot.clipboardOnly; onClicked: Screenshot.trash() }
        }
        Action {
            visible: hover.containsMouse && !hover.pressed
            anchors { right: parent.right; top: parent.top; margins: 8 }
            text: "✕"
            onClicked: Screenshot.dismiss()
        }
        Rectangle {
            id: copied
            anchors.centerIn: parent
            visible: flash.running
            width: 90; height: 28; radius: 8
            color: Qt.alpha(Theme.bg, 0.85)
            Text { anchors.centerIn: parent; text: "Copied"; color: Theme.text; font { family: win.family; weight: Theme.fontWeight; pixelSize: 13 } }
        }
        Timer { id: flash; interval: 900 }
        Text {
            visible: Screenshot.clipboardOnly && !hover.containsMouse
            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
            text: "Copied to clipboard"
            color: "white"; style: Text.Outline; styleColor: "#80000000"
            font { family: win.family; weight: Theme.fontWeight; pixelSize: 12 }
        }
    }
    QtObject { id: drag; property real dx: 0 }

    component Action: MouseArea {
        property string text
        width: t.implicitWidth + 16; height: 24
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle { anchors.fill: parent; radius: 6; color: Qt.alpha(Theme.bg, parent.containsMouse ? 0.95 : 0.78) }
        Text { id: t; anchors.centerIn: parent; text: parent.text; color: Theme.text; font { family: win.family; weight: Theme.fontWeight; pixelSize: 12 } }
    }
}
