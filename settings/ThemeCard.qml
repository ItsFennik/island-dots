import QtQuick
import qs.components
import qs.services

// Clickable theme preview drawn in the theme's own colours.
MouseArea {
    id: root
    required property var theme
    readonly property bool applied: theme.id === Theme.current

    height: width * 0.72
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        // A hand-picked theme replaces wallpaper colours.
        // Only this key is saved; other unsaved edits stay staged.
        const wasMatugen = theme.id !== "matugen" && (Config.saved.matugen || Config.values.matugen);
        if (wasMatugen) Config.commit("matugen", false);
        Theme.apply(theme.id);
        // …and one of the theme's paired wallpapers at random (services/ThemeWalls.qml).
        ThemeWalls.applyRandom(theme.id, wasMatugen);
    }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: root.theme.bg
        border { width: root.applied ? 2 : 1; color: root.applied ? Theme.accent : root.containsMouse ? Theme.textFaint : Theme.hairline }

        Rectangle {
            id: win
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            height: parent.height * 0.5
            radius: 4
            color: root.theme.bg_alt
            border { width: 1; color: root.theme.overlay }
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: 10; color: root.theme.surface
                Row { anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter } spacing: 3
                    Repeater { model: [root.theme.red, root.theme.yellow, root.theme.green]
                        Rectangle { required property var modelData; width: 4; height: 4; radius: 2; color: modelData } } }
            }
            Column {
                anchors { left: parent.left; top: parent.top; leftMargin: 7; topMargin: 17 }
                spacing: 4
                Rectangle { width: win.width * 0.55; height: 3; radius: 1.5; color: root.theme.fg }
                Rectangle { width: win.width * 0.35; height: 3; radius: 1.5; color: root.theme.fg_faint }
            }
            Rectangle { anchors { right: parent.right; bottom: parent.bottom; margins: 6 } width: 22; height: 8; radius: 2; color: root.theme.accent }
        }

        Text {
            anchors { left: parent.left; right: check.left; top: win.bottom; leftMargin: 10; topMargin: 8 }
            text: root.theme.name
            elide: Text.ElideRight
            color: root.theme.fg
            font { family: Theme.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) }
        }
        Row {
            anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
            spacing: 4
            Repeater { model: [root.theme.accent, root.theme.red, root.theme.yellow, root.theme.green, root.theme.blue, root.theme.magenta]
                Rectangle { required property var modelData; width: 9; height: 9; radius: 4.5; color: modelData } }
        }
        Rectangle {
            id: check
            visible: root.applied
            anchors { right: parent.right; top: win.bottom; rightMargin: 10; topMargin: 8 }
            width: 16; height: 16; radius: 8
            color: root.theme.accent
            Icon { anchors.centerIn: parent; name: "check"; size: 10; strokeWidth: 3; color: root.theme.accent_fg }
        }
    }
}
