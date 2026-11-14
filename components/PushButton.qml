import QtQuick
import qs.services

// macOS push button. `prominent` uses the accent colour (default button).
MouseArea {
    id: root
    property string text
    property bool prominent: false
    property bool destructive: false
    implicitWidth: Math.max(64, label.implicitWidth + 24); implicitHeight: 22
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.prominent ? Theme.accent : Theme.button
        border { width: root.prominent ? 0 : 1; color: Theme.buttonBorder }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Qt.rgba(0, 0, 0, root.pressed ? 0.12 : 0) }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.prominent ? Theme.onAccent : root.destructive ? Theme.pal.red : Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
}
