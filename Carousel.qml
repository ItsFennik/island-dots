import QtQuick

// Horizontal cover-flow: the current item sits centred, neighbours shrink and fade.
// Only transforms change while scrolling (no relayout), so it stays cheap.
ListView {
    id: view

    property real itemWidth: 400
    property int initialIndex: 0
    signal activated()

    orientation: ListView.Horizontal
    spacing: -itemWidth * 0.12
    clip: false
    cacheBuffer: itemWidth          // one card of preload each side; every card holds a decoded image
    boundsBehavior: Flickable.StopAtBounds
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: (width - itemWidth) / 2
    preferredHighlightEnd: (width + itemWidth) / 2
    highlightMoveDuration: 260
    keyNavigationEnabled: false

    Component.onCompleted: positionViewAtIndex(initialIndex, ListView.Center)
    onCountChanged: if (currentIndex <= 0 && initialIndex > 0) { currentIndex = initialIndex; positionViewAtIndex(initialIndex, ListView.Center); }

    // Mouse wheel / touchpad steps one item at a time.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
            if (d < 0) view.incrementCurrentIndex(); else if (d > 0) view.decrementCurrentIndex();
        }
    }
}
