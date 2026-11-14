import QtQuick
import qs.services

// macOS switch: accent track when on, grey when off, white knob with a soft edge.
MouseArea {
    id: root
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: 38; implicitHeight: 22
    cursorShape: Qt.PointingHandCursor
    onClicked: toggled(!checked)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.switchOff
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {                                        // knob shadow
            x: knob.x; y: knob.y + 0.5
            width: knob.width; height: knob.height; radius: knob.radius
            color: Qt.rgba(0, 0, 0, 0.18)
        }
        Rectangle {
            id: knob
            x: root.checked ? parent.width - width - 2 : 2
            y: 2
            width: parent.height - 4; height: width; radius: width / 2
            color: Theme.knob
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }
}
