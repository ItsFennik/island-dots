import QtQuick
import qs.services

// One widget tile: a frosted rounded square (Hyprland blurs what's behind it), sized
// like macOS widgets — small is one unit, wide is two units plus the gap.
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
    color: Qt.alpha(Theme.bg, glass)
    border { width: 1; color: Theme.hairline }
    antialiasing: true
}
