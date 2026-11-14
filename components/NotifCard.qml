import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.services

// One notification: icon, app · age, summary, body, actions. Used by the toast that grows
// out of the island and by the notification centre. Click = default action (or dismiss).
MouseArea {
    id: root

    required property var entry
    property bool card: true                 // tinted background (centre); the toast sits on the island itself
    property int bodyLines: 4
    property real now: Date.now()

    readonly property var n: entry?.n ?? null
    readonly property bool critical: n?.urgency === NotificationUrgency.Critical
    readonly property var actions: Array.from(n?.actions ?? []).filter(a => a.identifier !== "default" && a.text !== "")
    readonly property string icon: Notifs.iconFor(n)

    implicitHeight: Math.max(38, body.implicitHeight - 1) + (card ? 24 : 8)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: e => e.button === Qt.LeftButton ? Notifs.activate(root.entry) : root.n?.dismiss()
    onContainsMouseChanged: if (root.entry) root.entry.hovered = containsMouse

    Rectangle {
        anchors.fill: parent
        visible: root.card
        radius: 12
        color: root.containsMouse ? Theme.control : Theme.hover
        border { width: root.critical ? 1 : 0; color: Qt.alpha(Theme.pal.red, 0.6) }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // Picture: the notification's image, else the app icon, else a bell.
    Rectangle {
        id: pic
        x: root.card ? 12 : 4
        y: root.card ? 12 : 4
        width: 38; height: 38; radius: 10
        color: Theme.control
        clip: true
        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready && appIcon.status !== Image.Ready
            text: ""
            color: root.critical ? Theme.pal.red : Theme.textDim
            font { family: Theme.mono; pixelSize: 16 }
        }
        Image {
            id: appIcon
            anchors.centerIn: parent
            width: 26; height: 26
            sourceSize { width: 52; height: 52 }
            source: img.status === Image.Ready ? "" : root.icon
            asynchronous: true
            visible: status === Image.Ready
        }
        Image {
            id: img
            anchors.fill: parent
            source: root.n?.image ?? ""
            sourceSize { width: 76; height: 76 }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
    }

    Column {
        id: body
        anchors { left: pic.right; leftMargin: 12; right: parent.right; rightMargin: root.card ? 12 : 4 }
        y: pic.y - 1
        spacing: 3

        Item {
            width: parent.width; height: 16
            Row {
                anchors { left: parent.left; right: close.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 6
                Rectangle {
                    visible: root.critical
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3
                    color: Theme.pal.red
                }
                Text {
                    text: (root.n?.appName || "Notification")
                    color: Theme.textFaint
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - age.width - 20)
                    font { family: Theme.font; pixelSize: 10; weight: Font.Bold; capitalization: Font.AllUppercase }
                }
                Text {
                    id: age
                    text: "· " + Notifs.ago(root.entry?.time ?? 0, root.now)
                    color: Theme.textFaint
                    font { family: Theme.font; pixelSize: 10 }
                }
            }
            MouseArea {
                id: close
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 20; height: 20
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                opacity: root.containsMouse || containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                onClicked: root.n?.dismiss()
                Rectangle { anchors.fill: parent; radius: 10; color: close.containsMouse ? Theme.control : "transparent" }
                Text { anchors.centerIn: parent; text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 10 } }
            }
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.n?.summary ?? ""
            color: Theme.text
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: (root.n?.body ?? "").replace(/\n/g, "<br>")
            color: Theme.textDim
            linkColor: Theme.text
            elide: Text.ElideRight
            maximumLineCount: root.bodyLines
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            font { family: Theme.font; pixelSize: 11 }
            onLinkActivated: link => { Qt.openUrlExternally(link); root.n?.dismiss(); }
        }

        Flow {
            width: parent.width
            visible: root.actions.length > 0
            topPadding: 5
            spacing: 6
            Repeater {
                model: root.actions
                MouseArea {
                    id: act
                    required property var modelData
                    width: Math.min(label.implicitWidth + 22, body.width); height: 26
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.invoke()
                    Rectangle { anchors.fill: parent; radius: 8; color: act.containsMouse ? Theme.text : Theme.control
                        Behavior on color { ColorAnimation { duration: 120 } } }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, body.width - 22)
                        elide: Text.ElideRight
                        text: act.modelData.text
                        color: act.containsMouse ? Theme.bg : Theme.text
                        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                    }
                }
            }
        }
    }
}
