import QtQuick
import QtQuick.Shapes
import qs.services

// Weather, Apple style: place, big temperature, condition, high/low, on the frosted card (Tahoe)
// or a sky gradient (Classic). Medium: plus the next few hours. Large: plus the next days. Click for the forecast,
// middle-click to refresh (right-click is Edit Widgets, like every widget).
Card {
    id: root
    readonly property string unit: "°"
    readonly property real dimText: tahoe ? 0.62 : 0.85
    // Classic draws its own sky below; drop the card's material there.
    color: tahoe ? Qt.rgba(1, 1, 1, 0.06 + 0.24 * glass) : "transparent"
    border.color: tahoe ? Qt.rgba(1, 1, 1, 0.22 + 0.16 * glass) : "transparent"

    // Classic sky. A Shape, not a gradient Rectangle: the software renderer leaves
    // gradient+radius Rectangles with jagged corners.
    Loader {
        anchors.fill: parent
        active: !root.tahoe
        sourceComponent: Shape {
            readonly property var sky: Weather.sky(Weather.code, Weather.isDay)
            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.rgba(1, 1, 1, 0.12)
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: root.height
                    GradientStop { position: 0; color: Qt.alpha(sky[0], Math.max(0.75, root.glass)) }
                    GradientStop { position: 1; color: Qt.alpha(sky[1], Math.max(0.75, root.glass)) }
                }
                PathRectangle { x: 0.5; y: 0.5; width: root.width - 1; height: root.height - 1; radius: root.radius - 0.5 }
            }
        }
    }


    // Click: forecast popout · right/middle click: refresh
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: e => e.button === Qt.LeftButton && Weather.ok ? Popouts.toggle("weather") : Weather.refresh() }

    // Loading / offline
    Column {
        visible: !Weather.ok
        anchors.centerIn: parent
        spacing: 6
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: ""; color: root.ink; opacity: 0.8
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 34 } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.badLocation ? "Unknown location" : Weather.failed ? "Weather unavailable" : "Loading…"
            color: root.ink; opacity: 0.8; font { family: root.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
    }

    Item {
        id: top
        visible: Weather.ok
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 16 }
        height: WidgetLayout.unit - 28

        Column {
            id: now
            width: root.wide ? parent.width * 0.45 : parent.width
            spacing: -2
            Row {
                spacing: 4
                Text { text: Weather.place || "Weather"; color: root.ink; elide: Text.ElideRight; width: Math.min(implicitWidth, now.width - 16)
                    font { family: root.font; pixelSize: 14; weight: Theme.w(Font.Bold) } }
                Text { visible: !Weather.location; text: ""; color: root.ink; anchors.verticalCenter: parent.verticalCenter
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 } }
            }
            Text { text: Weather.temp + root.unit; color: root.ink
                font { family: root.font; pixelSize: 44; weight: Theme.w(Font.Light) } }
        }

        Column {
            anchors { left: parent.left; bottom: parent.bottom }
            width: root.wide ? parent.width * 0.45 : parent.width
            spacing: 2
            Text { text: Weather.glyph(Weather.code, Weather.isDay); color: root.ink
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 } }
            Text { width: parent.width; text: Weather.desc; color: root.ink; elide: Text.ElideRight
                font { family: root.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
            Text { text: "H:" + Weather.hi + root.unit + "  L:" + Weather.lo + root.unit; color: root.ink; opacity: root.dimText
                font { family: root.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
        }

        // Hourly strip (wide only)
        Row {
            visible: root.wide
            anchors { right: parent.right; bottom: parent.bottom }
            spacing: 0
            Repeater {
                model: root.wide ? Weather.hourly : []
                Column {
                    required property var modelData
                    width: 34
                    spacing: 6
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.ink; opacity: root.dimText
                        font { family: root.font; pixelSize: 10; weight: Theme.w(Font.DemiBold) } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.glyph(modelData.code, modelData.day); color: root.ink
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + root.unit; color: root.ink
                        font { family: root.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
                }
            }
        }
    }

    // Large: the next days, under a hairline
    Column {
        visible: Weather.ok && root.large
        anchors { left: parent.left; right: parent.right; top: top.bottom; topMargin: 14; leftMargin: 16; rightMargin: 16 }
        Rectangle { width: parent.width; height: 1; color: Qt.alpha(root.ink, 0.22) }
        Item { width: 1; height: 6 }
        Repeater {
            model: root.large ? Weather.daily : []
            Item {
                id: day
                required property var modelData
                // week-wide range, for the bar
                readonly property int minT: Math.min(...Weather.daily.map(d => d.lo))
                readonly property int maxT: Math.max(...Weather.daily.map(d => d.hi))
                width: parent.width; height: 46
                Text { anchors.verticalCenter: parent.verticalCenter; width: 92; text: day.modelData.label; color: root.ink; elide: Text.ElideRight
                    font { family: root.font; pixelSize: 14; weight: Theme.w(Font.DemiBold) } }
                Column {
                    x: 96; width: 34
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.glyph(day.modelData.code, true); color: root.ink
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 17 } }
                    Text { visible: day.modelData.rain >= 30; anchors.horizontalCenter: parent.horizontalCenter
                        text: day.modelData.rain + "%"; color: root.cCyan || "#64d2ff"
                        font { family: root.font; pixelSize: 9; weight: Theme.w(Font.Bold) } }
                }
                Text { x: 140; width: 34; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                    text: day.modelData.lo + root.unit; color: root.ink; opacity: root.dimText
                    font { family: root.font; pixelSize: 14; weight: Theme.w(Font.DemiBold) } }
                Rectangle {
                    id: track
                    x: 182; width: parent.width - 182 - 42; height: 4; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    antialiasing: true
                    color: Qt.alpha(root.ink, 0.2)
                    readonly property real span: Math.max(1, day.maxT - day.minT)
                    Rectangle {
                        x: track.width * (day.modelData.lo - day.minT) / track.span
                        width: Math.max(4, track.width * (day.modelData.hi - day.modelData.lo) / track.span)
                        height: 4; radius: 2
                        antialiasing: true
                        color: root.ink
                    }
                }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: day.modelData.hi + root.unit; color: root.ink
                    font { family: root.font; pixelSize: 14; weight: Theme.w(Font.DemiBold) } }
            }
        }
    }
}
