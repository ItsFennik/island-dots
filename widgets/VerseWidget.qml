import QtQuick
import qs.services

// ESV verse of the day (services/Verse). The text shrinks to fit every size.
// Middle-click: fetch again.
Card {
    id: root

    Column {
        anchors { fill: parent; margins: root.size === "s" ? 14 : 18 }
        spacing: 6

        Text {
            text: "VERSE OF THE DAY"
            color: root.cOrange || root.fgDim
            font { family: root.font; pixelSize: 11; weight: Font.Bold; letterSpacing: 0.6 }
        }
        Text {
            width: parent.width
            height: parent.height - y - refText.height - parent.spacing
            text: Verse.ok ? "“" + Verse.text + "”" : "…"
            color: root.fg
            wrapMode: Text.WordWrap
            fontSizeMode: Text.Fit
            minimumPixelSize: 9
            verticalAlignment: Text.AlignVCenter
            lineHeight: 1.08
            font { family: root.font; pixelSize: root.large ? 26 : root.wide ? 18 : 15; weight: Font.DemiBold }
        }
        Text {
            id: refText
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: Verse.ref
            elide: Text.ElideLeft
            color: root.fgDim
            font { family: root.font; pixelSize: 12; weight: Font.DemiBold; italic: true }
        }
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.MiddleButton; onClicked: Verse.refresh() }
}
