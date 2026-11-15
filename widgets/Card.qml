import QtQuick
import qs.services

// One widget tile, like macOS desktop widgets: a frosted rounded square (Hyprland blurs what's
// behind it) with a light inner edge and a soft shadow. Small is one unit, wide is two units
// plus the gap.
Rectangle {
    id: card
    property bool wide: false
    readonly property int unit: 164
    readonly property int gap: 14
    readonly property string font: Config.saved.widgetFont || "Adwaita Sans"
    readonly property real glass: Config.saved.widgetsOpacity ?? 0.55

    width: wide ? unit * 2 + gap : unit
    height: unit
    radius: 24
    antialiasing: true
    // macOS widget material: graphite / frosted white, never the theme's flat background.
    color: Theme.dark ? Qt.rgba(0.12, 0.12, 0.13, Math.min(0.92, glass + 0.15))
                      : Qt.rgba(0.97, 0.97, 0.97, Math.min(0.95, glass + 0.25))
    border { width: 1; color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.08) }

    // inner highlight
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: parent.radius - 1
        antialiasing: true
        color: "transparent"
        border { width: 1; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.7) }
    }
    // soft shadow (drawn under the card)
    Repeater {
        model: [[12, 0.022], [9, 0.028], [6, 0.035], [3.5, 0.045], [1.5, 0.06]]
        Rectangle {
            required property var modelData
            z: -1
            x: -modelData[0]; y: -modelData[0] + 4
            width: card.width + modelData[0] * 2; height: card.height + modelData[0] * 2
            radius: card.radius + modelData[0]
            antialiasing: true
            color: Qt.rgba(0, 0, 0, modelData[1])
        }
    }
}
