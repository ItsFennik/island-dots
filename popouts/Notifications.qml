import QtQuick
import Quickshell
import qs.services
import qs.components

// Notification centre (the bell): everything that hasn't been dismissed, newest first,
// plus Do Not Disturb and Clear all. Right-click or middle-click a card to dismiss it.
Item {
    id: root

    readonly property bool closeOnLeave: true
    property real now: Date.now()

    implicitWidth: 420
    implicitHeight: col.implicitHeight + 4
    focus: true

    Keys.onDeletePressed: Notifs.clear()

    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    Column {
        id: col
        y: 2
        width: parent.width
        spacing: 8

        Item {
            width: parent.width; height: 32
            Text {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: "Notifications"
                color: Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.Bold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: Notifs.dnd ? Theme.text : Theme.textFaint
                    font { family: Theme.mono; pixelSize: 12 }
                }
                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Notifs.dnd
                    onToggled: v => Notifs.setDnd(v)
                }
                MouseArea {
                    id: clear
                    visible: Notifs.list.length > 0
                    width: clearLabel.implicitWidth + 20; height: 26
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.clear()
                    Rectangle { anchors.fill: parent; radius: 8; color: clear.containsMouse ? Theme.control : Theme.hover }
                    Text { id: clearLabel; anchors.centerIn: parent; text: "Clear all"; color: Theme.textDim
                        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold } }
                }
            }
        }

        // Empty state
        Column {
            visible: Notifs.list.length === 0
            width: parent.width
            topPadding: 18; bottomPadding: 22
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "" : ""
                color: Theme.textFaint
                font { family: Theme.mono; pixelSize: 26 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "Do Not Disturb is on" : "You're all caught up"
                color: Theme.textFaint
                font { family: Theme.font; pixelSize: 12 }
            }
        }

        ListView {
            id: listView
            visible: Notifs.list.length > 0
            width: parent.width
            height: Math.min(contentHeight, 520)
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: Notifs.list
            delegate: NotifCard {
                required property var modelData
                width: listView.width
                entry: modelData
                now: root.now
            }
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 } }
            displaced: Transition { NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic } }
        }
    }
}
