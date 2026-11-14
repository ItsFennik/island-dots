import QtQuick
import qs.services

// Weather, Apple style: place, big temperature, condition, high/low, on a sky gradient.
// Wide: plus the next few hours. Click for the forecast, right-click to refresh.
Card {
    id: root
    readonly property var sky: Weather.sky(Weather.code, Weather.isDay)
    readonly property string unit: "°"

    border.color: Qt.rgba(1, 1, 1, 0.12)
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.alpha(root.sky[0], Math.max(0.75, root.glass)) }
        GradientStop { position: 1; color: Qt.alpha(root.sky[1], Math.max(0.75, root.glass)) }
    }

    // Click: forecast popout · right/middle click: refresh
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => e.button === Qt.LeftButton && Weather.ok ? Popouts.toggle("weather") : Weather.refresh() }

    // ── Loading / offline ──
    Column {
        visible: !Weather.ok
        anchors.centerIn: parent
        spacing: 6
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: ""; color: "white"; opacity: 0.8
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 34 } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.badLocation ? "Unknown location" : Weather.failed ? "Weather unavailable" : "Loading…"
            color: "white"; opacity: 0.8; font { family: root.font; pixelSize: 12; weight: Font.DemiBold } }
    }

    Item {
        visible: Weather.ok
        anchors { fill: parent; margins: 14; leftMargin: 16 }

        Column {
            id: now
            width: root.wide ? parent.width * 0.45 : parent.width
            spacing: -2
            Row {
                spacing: 4
                Text { text: Weather.place || "Weather"; color: "white"; elide: Text.ElideRight; width: Math.min(implicitWidth, now.width - 16)
                    font { family: root.font; pixelSize: 14; weight: Font.Bold } }
                Text { visible: !Weather.location; text: ""; color: "white"; anchors.verticalCenter: parent.verticalCenter
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 } }
            }
            Text { text: Weather.temp + root.unit; color: "white"
                font { family: root.font; pixelSize: 44; weight: Font.Light } }
        }

        Column {
            anchors { left: parent.left; bottom: parent.bottom }
            width: root.wide ? parent.width * 0.45 : parent.width
            spacing: 2
            Text { text: Weather.glyph(Weather.code, Weather.isDay); color: "white"
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 } }
            Text { width: parent.width; text: Weather.desc; color: "white"; elide: Text.ElideRight
                font { family: root.font; pixelSize: 12; weight: Font.DemiBold } }
            Text { text: "H:" + Weather.hi + root.unit + "  L:" + Weather.lo + root.unit; color: "white"; opacity: 0.85
                font { family: root.font; pixelSize: 12; weight: Font.DemiBold } }
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
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: "white"; opacity: 0.85
                        font { family: root.font; pixelSize: 10; weight: Font.DemiBold } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.glyph(modelData.code, modelData.day); color: "white"
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + root.unit; color: "white"
                        font { family: root.font; pixelSize: 12; weight: Font.DemiBold } }
                }
            }
        }
    }
}
