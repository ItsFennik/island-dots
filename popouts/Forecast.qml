import QtQuick
import qs.services
import qs.components

// Forecast popout (the temperature in the bar, or a click on the desktop widget):
// now, the next hours, details and the next three days.   R refresh
Item {
    id: root

    readonly property bool closeOnLeave: true
    readonly property string deg: "°"
    readonly property var sky: Weather.sky(Weather.code, Weather.isDay)

    implicitWidth: 360
    implicitHeight: (Weather.ok ? body.implicitHeight : empty.implicitHeight) + 8
    focus: true
    Keys.onPressed: e => { if (e.key === Qt.Key_R) { Weather.refresh(); e.accepted = true; } }

    // ── Loading / offline ─────────────────────────────────────────────
    Column {
        id: empty
        visible: !Weather.ok
        width: parent.width
        topPadding: 22; bottomPadding: 20
        spacing: 8
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.failed ? "\u{f0599}" : "\u{f0590}"
            color: Theme.textFaint; font { family: Theme.mono; pixelSize: 30 } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: Weather.failed ? (Weather.badLocation ? Weather.status : "Weather unavailable — are you online?") : "Loading…"
            color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 } }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            topPadding: 4
            PushButton { text: "Try Again"; visible: Weather.failed; onClicked: Weather.refresh() }
            PushButton { text: "Change Location…"; onClicked: { Popouts.close(); Popouts.openSettings("desktop"); } }
        }
    }

    Column {
        id: body
        visible: Weather.ok
        width: parent.width
        spacing: 10

        // ── Now ──
        Rectangle {
            width: parent.width
            height: 132
            radius: 14
            gradient: Gradient {
                GradientStop { position: 0; color: root.sky[0] }
                GradientStop { position: 1; color: root.sky[1] }
            }
            Column {
                anchors { left: parent.left; top: parent.top; margins: 14; leftMargin: 16 }
                width: parent.width * 0.6
                spacing: -2
                Row {
                    spacing: 5
                    Text { text: Weather.place || "Weather"; color: Theme.inkSet ? Theme.ink : "white"; elide: Text.ElideRight; width: Math.min(implicitWidth, 190)
                        font { family: Theme.font; pixelSize: 15; weight: Theme.w(Font.Bold) } }
                    Text { visible: !Weather.location; text: "\u{f0124}"; color: Theme.inkSet ? Theme.ink : "white"; anchors.verticalCenter: parent.verticalCenter
                        font { family: Theme.mono; pixelSize: 10 } }
                }
                Text { text: Weather.resolved; visible: text !== "" && text !== Weather.place; color: Theme.inkSet ? Theme.ink : "white"; opacity: 0.75
                    width: parent.width; elide: Text.ElideRight; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 } }
                Text { text: Weather.temp + root.deg; color: Theme.inkSet ? Theme.ink : "white"; topPadding: 2
                    font { family: Theme.font; pixelSize: 50; weight: Theme.w(Font.Light) } }
            }
            Column {
                anchors { right: parent.right; bottom: parent.bottom; margins: 14; rightMargin: 16 }
                spacing: 2
                Text { anchors.right: parent.right; text: Weather.glyph(Weather.code, Weather.isDay); color: Theme.inkSet ? Theme.ink : "white"
                    font { family: Theme.mono; pixelSize: 28 } }
                Text { anchors.right: parent.right; text: Weather.desc; color: Theme.inkSet ? Theme.ink : "white"
                    font { family: Theme.font; pixelSize: 13; weight: Theme.w(Font.DemiBold) } }
                Text { anchors.right: parent.right; text: "H:" + Weather.hi + root.deg + "  L:" + Weather.lo + root.deg; color: Theme.inkSet ? Theme.ink : "white"; opacity: 0.85
                    font { family: Theme.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
            }
        }

        // ── Next hours ──
        Rectangle {
            width: parent.width
            height: 84
            radius: 12
            color: Theme.card
            Row {
                anchors.centerIn: parent
                Repeater {
                    model: Weather.hours(8)
                    Column {
                        required property var modelData
                        width: (root.width - 16) / 8
                        spacing: 4
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Theme.textDim
                            font { family: Theme.font; pixelSize: 10; weight: Theme.w(Font.DemiBold) } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.glyph(modelData.code, modelData.day); color: Theme.text
                            font { family: Theme.mono; pixelSize: 16 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + root.deg; color: Theme.text
                            font { family: Theme.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.rain >= 20 ? modelData.rain + "%" : " "
                            color: "#5aa9ff"; font { family: Theme.font; pixelSize: 9; weight: Theme.w(Font.Bold) } }
                    }
                }
            }
        }

        // ── Details ──
        Grid {
            width: parent.width
            columns: 3
            spacing: 8
            Repeater {
                model: [
                    { g: "\u{f050f}", k: "Feels like", v: Weather.feels + root.deg },
                    { g: "\u{f058e}", k: "Humidity", v: Weather.humidity + "%" },
                    { g: "\u{f059d}", k: "Wind", v: Weather.wind },
                    { g: "\u{f0599}", k: "UV index", v: Weather.uv + (Weather.uv >= 8 ? " · very high" : Weather.uv >= 6 ? " · high" : Weather.uv >= 3 ? " · moderate" : " · low") },
                    { g: "\u{f059c}", k: "Sunrise", v: root.clock(Weather.sunrise) },
                    { g: "\u{f059b}", k: "Sunset", v: root.clock(Weather.sunset) }
                ]
                Rectangle {
                    required property var modelData
                    width: (body.width - 16) / 3
                    height: 52
                    radius: 10
                    color: Theme.card
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 8 }
                        spacing: 3
                        Row {
                            spacing: 4
                            Text { text: modelData.g; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                                font { family: Theme.mono; pixelSize: 10 } }
                            Text { text: modelData.k.toUpperCase(); color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                                font { family: Theme.font; pixelSize: 9; weight: Theme.w(Font.Bold); letterSpacing: 0.5 } }
                        }
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.v; color: Theme.text
                            font { family: Theme.font; pixelSize: 13; weight: Theme.w(Font.DemiBold) } }
                    }
                }
            }
        }

        // ── Next days ──
        Rectangle {
            id: days
            width: parent.width
            height: dayCol.implicitHeight + 12
            radius: 12
            color: Theme.card
            readonly property int minT: Math.min(...Weather.daily.map(d => d.lo))
            readonly property int maxT: Math.max(...Weather.daily.map(d => d.hi))
            Column {
                id: dayCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                Repeater {
                    model: Weather.daily
                    Item {
                        required property var modelData
                        required property int index
                        width: dayCol.width; height: 30
                        Rectangle { visible: index > 0; width: parent.width; height: 1; color: Theme.hairline }
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 82; elide: Text.ElideRight; text: modelData.label; color: Theme.text
                            font { family: Theme.font; pixelSize: 13; weight: Theme.w(Font.Medium) } }
                        Text { x: 88; anchors.verticalCenter: parent.verticalCenter; text: Weather.glyph(modelData.code, true); color: Theme.text
                            font { family: Theme.mono; pixelSize: 15 } }
                        Text { x: 108; anchors.verticalCenter: parent.verticalCenter; text: modelData.rain >= 20 ? modelData.rain + "%" : ""
                            color: "#5aa9ff"; font { family: Theme.font; pixelSize: 10; weight: Theme.w(Font.Bold) } }
                        // lo ─ range bar ─ hi, scaled across all days (Apple style)
                        Text { id: lo; x: 146; width: 30; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.lo + root.deg; color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 } }
                        Rectangle {
                            id: track
                            anchors { left: lo.right; leftMargin: 8; right: hi.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            height: 4; radius: 2
                            color: Theme.control
                            readonly property real span: Math.max(1, days.maxT - days.minT)
                            Rectangle {
                                x: track.width * (modelData.lo - days.minT) / track.span
                                width: Math.max(6, track.width * (modelData.hi - modelData.lo) / track.span)
                                height: parent.height; radius: 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "#7cc4ff" }
                                    GradientStop { position: 1; color: "#ffb347" }
                                }
                            }
                        }
                        Text { id: hi; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 30; horizontalAlignment: Text.AlignRight
                            text: modelData.hi + root.deg; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Theme.w(Font.DemiBold) } }
                    }
                }
            }
        }

        // ── Footer ──
        Item {
            width: parent.width; height: 26
            Text {
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                text: Weather.loading ? "Updating…" : Weather.updatedAt ? "Updated " + Qt.formatTime(Weather.updatedAt, (Config.saved.clock24h ?? true) ? "HH:mm" : "h:mm AP") : ""
                color: Theme.textFaint; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                PushButton { text: "Location…"; onClicked: { Popouts.close(); Popouts.openSettings("desktop"); } }
                PushButton { text: "Refresh"; enabled: !Weather.loading; onClicked: Weather.refresh() }
            }
        }
    }

    // wttr.in gives "06:12 AM"; follow the 24-hour clock setting.
    function clock(t) {
        const m = Weather.parseClock(t);
        if (m < 0) return t || "—";
        const d = new Date(2000, 0, 1, Math.floor(m / 60), m % 60);
        return Qt.formatTime(d, (Config.saved.clock24h ?? true) ? "HH:mm" : "h:mm AP");
    }
}
