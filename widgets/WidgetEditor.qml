import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Edit Widgets: a see-through layer over the free desktop area, only while editing. Each
// widget gets an outline you can drag; the real widget windows underneath follow live.
// Edges snap to the screen margin and to the other widgets (hold Shift to place freely).
// Done / Esc / click the empty desktop saves; Reset goes back to the corner layout.
PanelWindow {
    id: ed

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal      // same coordinates as the widget windows
    exclusiveZone: 0
    color: Qt.rgba(0, 0, 0, 0.14)

    WlrLayershell.namespace: "island-widget-editor"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property var at: WidgetLayout.resolved(width, height)
    function finish() { WidgetLayout.done(WidgetLayout.resolved(width, height)); }
    function place(id, x, y, free) { WidgetLayout.place(id, x, y, free, width, height, at); }

    // Empty desktop: click to finish.
    MouseArea { anchors.fill: parent; onClicked: ed.finish() }
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ed.finish()
        Keys.onReturnPressed: ed.finish()
    }

    Repeater {
        model: WidgetLayout.ids
        MouseArea {
            id: box
            required property string modelData
            x: ed.at[modelData]?.[0] ?? 0
            y: ed.at[modelData]?.[1] ?? 0
            width: WidgetLayout.width(modelData); height: WidgetLayout.height(modelData)
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point grab
            onPressed: e => grab = Qt.point(e.x, e.y)
            // the editor never moves, so positions in it are stable while dragging
            onPositionChanged: e => { if (pressed) ed.place(modelData, x + e.x - grab.x, y + e.y - grab.y, e.modifiers & Qt.ShiftModifier); }
            Rectangle {
                anchors.fill: parent
                radius: WidgetLayout.tahoe ? 22 : 24
                antialiasing: true
                color: Qt.rgba(1, 1, 1, box.pressed ? 0.14 : box.containsMouse ? 0.08 : 0.03)
                border { width: 2; color: Qt.rgba(1, 1, 1, box.pressed || box.containsMouse ? 0.9 : 0.5) }
            }
        }
    }

    // Toolbar
    Rectangle {
        anchors { top: parent.top; topMargin: 14; horizontalCenter: parent.horizontalCenter }
        width: bar.implicitWidth + 28; height: 40
        radius: 12
        antialiasing: true
        color: Theme.menuBg
        border { width: 1; color: Theme.menuEdge }
        MouseArea { anchors.fill: parent }          // don't finish on a click between the buttons
        Row {
            id: bar
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Drag widgets anywhere. You can also drag them straight on the desktop · Shift to skip snapping"
                color: Theme.textDim
                font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 }
            }
            Item { width: 4; height: 1 }
            PushButton { anchors.verticalCenter: parent.verticalCenter; text: "Reset"; onClicked: WidgetLayout.reset() }
            PushButton { anchors.verticalCenter: parent.verticalCenter; text: "Done"; prominent: true; onClicked: ed.finish() }
        }
    }
}
