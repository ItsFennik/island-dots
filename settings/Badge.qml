import QtQuick
import QtQuick.Shapes
import qs.services

// Rounded-square colour icon with a white glyph. Drawn as a Shape because the software
// renderer doesn't antialias gradient-filled Rectangles with a radius (jagged corners),
// and the glyph is unhinted so small Nerd Font icons don't snap to blocky pixels.
Item {
    id: root
    property color tint
    property color topColor: Qt.lighter(tint, 1.12)
    property string glyph
    property real radius: 5
    property real glyphSize: 12

    // Composite through a texture: the software renderer draws Shapes outside any clip and
    // above later siblings, so a header icon scrolled up used to paint over the toolbar.
    // A layer is a plain texture node, which clips and stacks normally.
    layer.enabled: true
    layer.smooth: true

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.height
                GradientStop { position: 0; color: root.topColor }
                GradientStop { position: 1; color: root.tint }
            }
            PathRectangle { width: root.width; height: root.height; radius: root.radius }
        }
    }
    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: "white"
        font { family: Theme.mono; pixelSize: root.glyphSize; hintingPreference: Font.PreferNoHinting }
    }
}
