import QtQuick
import QtQuick.Window
import qs.services

// macOS pop-up button: shows the current choice with a ⌃⌄ chevron; clicking opens a menu
// over the window with the current item checked, positioned so that item sits on the button.
// options: [[value, text], ...]
MouseArea {
    id: root
    property var options: []
    property var value
    property int maxWidth: 240
    signal picked(var value)

    readonly property int current: Math.max(0, options.findIndex(o => o[0] === value))
    readonly property string currentText: options.find(o => o[0] === value)?.[1] ?? String(value ?? "")
    property bool open: false

    implicitWidth: Math.min(maxWidth, label.implicitWidth + 40); implicitHeight: 22
    onClicked: open = !open

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.button
        border { width: 1; color: Theme.buttonBorder }
    }
    Text {
        id: label
        anchors { left: parent.left; leftMargin: 9; right: chev.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
        text: root.currentText
        elide: Text.ElideRight
        color: Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
    Rectangle {
        id: chev
        anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
        width: 16; height: 16; radius: 4
        color: Theme.accent
        Text { anchors.centerIn: parent; text: "⌃\n⌄"; lineHeight: 0.45; color: Theme.onAccent
            horizontalAlignment: Text.AlignHCenter; font { family: Theme.font; pixelSize: 9; weight: Font.Bold } }
    }

    // The menu lives on the window's content item so it can overlap everything.
    Loader {
        active: root.open
        parent: root.Window.window ? root.Window.window.contentItem : root
        anchors.fill: parent
        z: 1000
        sourceComponent: Item {
            MouseArea { anchors.fill: parent; onClicked: root.open = false; onWheel: w => w.accepted = true }
            Rectangle {
                id: menu
                readonly property point at: root.mapToItem(parent, 0, 0)
                readonly property int rowH: 22
                width: Math.max(root.width + 16, list.contentW + 20)
                height: Math.min(list.contentHeight, parent.height - 40) + 10
                x: Math.max(6, Math.min(parent.width - width - 6, at.x - 8))
                y: Math.max(6, Math.min(parent.height - height - 6, at.y - 5 - root.current * rowH + list.contentY))
                radius: 8
                color: Theme.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.98) : Qt.rgba(0.97, 0.97, 0.97, 0.98)
                border { width: 1; color: Qt.alpha(Theme.text, 0.14) }
                ListView {
                    id: list
                    property real contentW: 0
                    x: 5; y: 5; width: parent.width - 10; height: parent.height - 10
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.options
                    Component.onCompleted: positionViewAtIndex(root.current, ListView.Center)
                    delegate: MouseArea {
                        id: it
                        required property var modelData
                        required property int index
                        width: list.width; height: menu.rowH
                        hoverEnabled: true
                        onClicked: { root.open = false; if (modelData[0] !== root.value) root.picked(modelData[0]); }
                        Component.onCompleted: list.contentW = Math.max(list.contentW, t.implicitWidth + 40)
                        Rectangle { anchors.fill: parent; radius: 4; color: it.containsMouse ? Theme.accent : "transparent" }
                        Text { visible: it.index === root.current; anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            text: "✓"; color: it.containsMouse ? Theme.onAccent : Theme.text; font { family: Theme.font; pixelSize: 11 } }
                        Text { id: t; anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                            text: it.modelData[1]; color: it.containsMouse ? Theme.onAccent : Theme.text
                            font { family: Theme.font; pixelSize: 13 } }
                    }
                }
            }
        }
    }
}
