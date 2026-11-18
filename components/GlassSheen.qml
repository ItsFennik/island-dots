import QtQuick
import QtQuick.Shapes
import qs.services

// Liquid glass highlight: a soft white sheen over the top of a glass panel, fading out by the
// middle. Only exists while "Liquid glass" is on. A Shape, not a gradient Rectangle — the
// software renderer leaves gradient+radius Rectangles jagged. Rasterised once; it only
// redraws when the panel changes size.
Loader {
    id: root
    property real radius: 0
    property real strength: Theme.dark ? 0.16 : 0.45
    anchors { left: parent.left; right: parent.right; top: parent.top }
    height: parent ? parent.height : 0
    active: Theme.liquid && width > 2 && height > 2
    sourceComponent: Shape {
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.height * 0.6
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.strength) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, root.strength * 0.3) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathRectangle { x: 1; y: 1; width: root.width - 2; height: root.height - 2; radius: Math.max(0, root.radius - 1) }
        }
    }
}
