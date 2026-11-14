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

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.current ? Theme.control : "transparent"
    }
    Text {
        id: g
        visible: root.glyph !== ""
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 18
        text: root.glyph
        color: root.current ? root.tint : Theme.textDim
        font { family: Theme.mono; pixelSize: 14 }
    }
    Text {
        anchors { left: g.visible ? g.right : parent.left; leftMargin: g.visible ? 10 : 12; right: d.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.text
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        color: root.current ? root.tint : Theme.textDim
        font { family: Theme.font; pixelSize: 13 }
    }
    Text {
        id: d
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: root.detail
        color: Theme.textFaint
        font { family: Theme.font; pixelSize: 11 }
    }
}
