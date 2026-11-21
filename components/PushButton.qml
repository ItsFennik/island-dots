import QtQuick
import qs.services

// macOS push button. `prominent` uses the accent colour (default button).
MouseArea {
    id: root
    property string text
    property bool prominent: false
    property bool destructive: false
    implicitWidth: Math.max(64, label.implicitWidth + 24); implicitHeight: 24
    opacity: enabled ? 1 : 0.45
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: 7
        antialiasing: true
        color: root.prominent ? Theme.accent : Theme.button
        border { width: root.prominent ? 0 : 1; color: Theme.buttonBorder }
        Rectangle { anchors.fill: parent; radius: parent.radius; antialiasing: true
            color: root.pressed ? Qt.rgba(0, 0, 0, 0.14) : root.containsMouse ? Qt.alpha(Theme.pal.fg, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } } }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.prominent ? Theme.onAccent : root.destructive ? Theme.pal.red : Theme.text
        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 }
    }
}
