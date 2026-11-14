import QtQuick
import qs.services

// macOS segmented control: a recessed track with a raised pill on the selected segment.
// options: [{ value, text }]
Rectangle {
    id: root
    property var options: []
    property var value
    signal picked(var value)

    implicitWidth: row.implicitWidth + 4; implicitHeight: 24
    radius: 7
    color: Theme.dark ? Qt.alpha(Theme.text, 0.08) : Qt.alpha(Theme.text, 0.07)

    Row {
        id: row
        anchors.centerIn: parent
        Repeater {
            model: root.options
            delegate: MouseArea {
                id: opt
                required property var modelData
                required property int index
                readonly property bool current: root.value === modelData.value
                width: Math.max(44, label.implicitWidth + 22); height: 20
                onClicked: root.picked(modelData.value)
                // divider between unselected neighbours
                Rectangle {
                    visible: opt.index > 0 && !opt.current && root.options[opt.index - 1]?.value !== root.value
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 1; height: 12; color: Qt.alpha(Theme.text, 0.15)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    visible: opt.current
                    color: Theme.dark ? Qt.alpha(Theme.text, 0.24) : "#ffffff"
                    border { width: Theme.dark ? 0 : 1; color: Qt.alpha(Theme.text, 0.08) }
                }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: opt.modelData.text
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 12; weight: opt.current ? Font.DemiBold : Font.Normal }
                }
            }
        }
    }
}
