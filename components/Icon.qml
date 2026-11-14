import QtQuick
import QtQuick.Shapes
import "icons.js" as Icons

Item {
    id: root
    property string name
    property color color: "white"
    property real size: 16
    property real strokeWidth: 2
    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.centerIn: parent
        width: 24; height: 24
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: Icons.paths[root.name] ?? "" }
        }
    }
}
