import QtQuick
import qs.services

MouseArea {
    id: root
    property string text
    property string detail
    property string glyph
    property bool current: false
    property color tint: Theme.text

    width: parent ? parent.width : 0
    height: 34
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    // Same as the Settings sidebar: soft accent wash + a short accent pill for the current
    // row, a faint wash under the pointer for the rest.
    Rectangle {
        anchors.fill: parent
        radius: 10
        antialiasing: true
        color: root.current ? Qt.alpha(Theme.accent, Theme.dark ? 0.22 : 0.16)
             : root.pressed ? Qt.alpha(Theme.pal.fg, 0.1)
             : root.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 110 } }
    }
    Rectangle {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 3; height: root.current ? 14 : 0
        radius: 1.5; antialiasing: true
        color: Theme.accent
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    Text {
        id: g
        visible: root.glyph !== ""
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 18
        text: root.glyph
        color: root.current ? Theme.accent : Theme.textDim
        font { family: Theme.mono; pixelSize: 14 }
    }
    Text {
        anchors { left: g.visible ? g.right : parent.left; leftMargin: g.visible ? 10 : 12; right: d.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.text
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        color: root.current || root.containsMouse ? root.tint : Theme.textDim
        font { family: Theme.font; pixelSize: 13; weight: root.current ? Font.Medium : Font.Normal }
    }
    Text {
        id: d
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: root.detail
        color: Theme.textFaint
        font { family: Theme.font; pixelSize: 11 }
    }
}
