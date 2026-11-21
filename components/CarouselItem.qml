import QtQuick

// A card in a Carousel. Children are clipped to the card.
Item {
    id: card

    required property int index
    property ListView carousel
    property color accent: "white"
    property color fill: "#111111"
    property bool selected: false              // the one currently applied
    default property alias content: inner.data

    readonly property bool current: carousel && carousel.currentIndex === index
    // Distance from the centre of the view, in item widths.
    readonly property real dist: carousel
        ? Math.min(3, Math.abs(x - carousel.contentX + width / 2 - carousel.width / 2) / width)
        : 0

    width: carousel ? carousel.itemWidth : 0
    height: carousel ? carousel.height * 0.86 : 0
    y: (carousel ? carousel.height - height : 0) / 2
    z: 10 - dist
    scale: 1 - Math.min(dist, 2) * 0.16

    Rectangle {
        id: inner
        anchors.fill: parent
        color: card.fill
        radius: 10
        clip: true
    }

    // Side cards are dimmed with a solid shade instead of transparency (no see-through clutter).
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "black"
        opacity: Math.min(card.dist, 2) * 0.32
    }

    // Border: accent on the centred card, a thin marker on the applied one.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: 13
        color: "transparent"
        border.width: card.current ? 3 : (card.selected ? 1 : 0)
        border.color: card.accent
        Behavior on border.width { NumberAnimation { duration: 120 } }
    }

    // Applied marker
    Rectangle {
        visible: card.selected
        anchors { top: parent.top; right: parent.right; margins: 10 }
        width: 10; height: 10; radius: 5
        color: card.accent
        border { width: 2; color: Qt.rgba(0, 0, 0, 0.4) }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: card.current ? card.carousel.activated() : card.carousel.currentIndex = card.index
    }
}
