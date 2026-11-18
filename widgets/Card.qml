import QtQuick
import qs.services
import qs.components

// One widget tile. Two designs (Settings → Widgets → Style):
//  · Tahoe: a pale frosted pane (Hyprland blurs what's behind it), a thin bright rim, all
//    content in white monochrome. No drop shadow — a faint shadow counts as "opaque" to
//    Hyprland's blur and turns into a grey smudge around the card.
//  · Classic (Sequoia): graphite / frosted-white material in the theme's colours, a light
//    inner edge, a soft shadow, colour accents.
// Small is one unit; medium is two units plus the gap wide; large is that, square.
Rectangle {
    id: card
    // "s" 1×1 · "m" 2×1 · "l" 2×2 (WidgetLayout.size)
    property string size: "s"
    readonly property bool wide: size !== "s"
    readonly property bool large: size === "l"
    readonly property bool tahoe: WidgetLayout.tahoe
    readonly property int unit: WidgetLayout.unit
    readonly property int gap: WidgetLayout.gap
    readonly property string font: Config.saved.widgetFont || "Adwaita Sans"
    readonly property real glass: Config.saved.widgetsOpacity ?? 0.55

    // content colours, shared by every widget
    // Text colour (Appearance → Text colour, shared with all of Island): "auto" = white on
    // Tahoe, theme text on Classic.
    readonly property string textMode: Theme.textMode
    readonly property bool mono: tahoe || textMode !== "auto"
    readonly property color ink: textMode === "black" ? "black" : "white"
    readonly property color fg: mono ? ink : Theme.text
    readonly property color fgDim: mono ? Qt.alpha(ink, 0.62) : Theme.textDim
    readonly property color fgFaint: mono ? Qt.alpha(ink, 0.36) : Theme.textFaint
    readonly property color fgTrack: mono ? Qt.alpha(ink, 0.16) : Qt.alpha(Theme.text, 0.18)
    readonly property color hover: mono ? Qt.alpha(ink, 0.12) : Qt.alpha(Theme.text, 0.1)
    // text drawn on an fg-filled shape (calendar's today circle)
    readonly property color onFg: fg.hslLightness > 0.5 ? "black" : "white"

    // Accent colours (Settings → Desktop & Widgets → Colours):
    //  · system: macOS colours on Classic, white monochrome on Tahoe ("" = use fg)
    //  · theme: the shell theme's palette · wallpaper: matugen colours from the wallpaper
    readonly property string colorMode: Config.saved.widgetColors ?? "system"
    readonly property bool wallTint: colorMode === "wallpaper" && WallColors.ready
    readonly property var wp: WallColors.p
    function pickAccent(sys, themeKey, wallKey) {
        if (colorMode === "theme") return Theme.pal[themeKey] ?? sys;
        if (wallTint) return wp[wallKey] ?? sys;
        return tahoe ? "" : sys;
    }
    readonly property string cBlue: pickAccent("#0a84ff", "blue", "primary")
    readonly property string cGreen: pickAccent("#30d158", "green", "tertiary")
    readonly property string cOrange: pickAccent("#ff9f0a", "yellow", "secondary")
    readonly property string cPurple: pickAccent("#bf5af2", "magenta", "primary_fixed_dim")
    readonly property string cRed: pickAccent("#ff453a", "red", "error")
    readonly property string cPink: pickAccent("#ff375f", "magenta", "tertiary")
    readonly property string cCyan: pickAccent("#64d2ff", "cyan", "primary")

    width: wide ? unit * 2 + gap : unit
    height: large ? unit * 2 + gap : unit
    radius: tahoe ? 22 : 24
    antialiasing: true
    // Tahoe: widgetsOpacity 0..1 → white veil 0.06..0.30 over the blur (wallpaper-tinted when
    // Colours is Wallpaper). Classic: the wallpaper's container colour instead of graphite.
    color: tahoe && wallTint ? Qt.alpha(wp.primary_container, 0.10 + 0.30 * glass)
         : tahoe ? Qt.rgba(1, 1, 1, 0.06 + 0.24 * glass)
         : wallTint ? Qt.alpha(wp.surface_container, Theme.glass(Math.min(0.92, glass + 0.15)))
         : Theme.dark ? Qt.rgba(0.12, 0.12, 0.13, Theme.glass(Math.min(0.92, glass + 0.15)))
                      : Qt.rgba(0.97, 0.97, 0.97, Theme.glass(Math.min(0.95, glass + 0.25)))
    border { width: 1; color: tahoe ? Qt.rgba(1, 1, 1, 0.22 + 0.16 * glass)
                            : Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.08) }

    // Classic extras: inner highlight + liquid-glass sheen…
    Loader {
        anchors.fill: parent
        active: !card.tahoe
        sourceComponent: Item {
            Rectangle {
                anchors { fill: parent; margins: 1 }
                radius: card.radius - 1
                antialiasing: true
                color: "transparent"
                border { width: 1; color: Theme.liquid ? Theme.glassRim : Theme.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.7) }
            }
            GlassSheen { radius: card.radius }
        }
    }
    // …and a soft shadow drawn under the card (the widget window leaves room for it).
    Loader {
        z: -1
        anchors.fill: parent
        active: !card.tahoe
        sourceComponent: Item {
            Repeater {
                model: [[12, 0.022], [9, 0.028], [6, 0.035], [3.5, 0.045], [1.5, 0.06]]
                Rectangle {
                    required property var modelData
                    x: -modelData[0]; y: -modelData[0] + 4
                    width: card.width + modelData[0] * 2; height: card.height + modelData[0] * 2
                    radius: card.radius + modelData[0]
                    antialiasing: true
                    color: Qt.rgba(0, 0, 0, modelData[1])
                }
            }
        }
    }
}
