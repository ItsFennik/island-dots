import QtQuick
import qs.services

// A macOS-style menu: rows with optional shortcut text, separators, disabled rows.
// items: [{ text, shortcut?, f, off?, check? } | { sep: true }]
Item {
    id: root
    property var items: []
    property string family: Config.saved.widgetFont || "Adwaita Sans"
    property int minWidth: 220
    signal done()

    property real widest: 0
    implicitWidth: Math.max(minWidth, widest)
    implicitHeight: col.implicitHeight

    Column {
    id: col
    width: root.implicitWidth
    Repeater {
        model: root.items
        delegate: MouseArea {
            id: row
            required property var modelData
            readonly property bool sep: !!modelData.sep
            width: col.width
            height: sep ? 11 : 24
            enabled: !sep && !modelData.off
            hoverEnabled: true
            onClicked: { const f = modelData.f; root.done(); if (f) f(); }
            Component.onCompleted: if (!sep) root.widest = Math.max(root.widest, label.implicitWidth + keys.implicitWidth + 64)

            Rectangle { visible: row.sep; anchors.centerIn: parent; width: parent.width - 20; height: 1; color: Theme.hairline }
            Rectangle { visible: !row.sep && row.containsMouse && row.enabled; anchors.fill: parent; radius: 5; color: Theme.accent }
            Text {
                visible: !!row.modelData.check
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: "✓"
                color: row.containsMouse ? Theme.onAccent : Theme.text
                font { family: root.family; pixelSize: 11 }
            }
            Text {
                id: label
                visible: !row.sep
                anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                text: row.modelData.text ?? ""
                color: !row.enabled ? Theme.textFaint : row.containsMouse ? Theme.onAccent : Theme.text
                font { family: root.family; pixelSize: 13 }
            }
            Text {
                id: keys
                visible: !row.sep
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: row.modelData.shortcut ?? ""
                color: row.containsMouse && row.enabled ? Qt.alpha(Theme.onAccent, 0.8) : Theme.textFaint
                font { family: root.family; pixelSize: 13 }
            }
        }
    }
    }
}
