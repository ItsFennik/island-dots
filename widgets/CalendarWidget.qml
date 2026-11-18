import QtQuick
import Quickshell
import qs.services

// Calendar, Apple style. Small — Tahoe: the month grid; Classic: red weekday, big date, month.
// Medium: weekday, big date and month, plus the month grid with today circled. Large: the
// date on top and a big month grid. Click opens Notification Center.
Card {
    id: root
    property string screenName: ""
    readonly property color red: cRed || "#ff453a"
    readonly property color accent: cRed ? red : fg        // today's circle, classic weekday
    readonly property color onAccent: cRed ? (red.hslLightness > 0.6 ? "black" : "white") : onFg
    readonly property bool med: size === "m"

    SystemClock { id: clk; precision: SystemClock.Minutes }
    readonly property date today: clk.date
    readonly property int firstDow: Qt.locale().firstDayOfWeek % 7
    readonly property var cells: {
        const y = today.getFullYear(), m = today.getMonth();
        const lead = (new Date(y, m, 1).getDay() - firstDow + 7) % 7;
        const days = new Date(y, m + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < 42; i++) { const d = i - lead + 1; out.push(d >= 1 && d <= days ? d : 0); }
        return out.slice(35).every(d => d === 0) ? out.slice(0, 35) : out;
    }

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Popouts.toggle("notifs", root.screenName) }

    // ── Small (Tahoe): macOS month widget ──
    Column {
        visible: !root.wide && root.tahoe
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 15 }
        spacing: 4
        Text { text: Qt.locale().standaloneMonthName(root.today.getMonth()).toUpperCase(); color: root.fg
            font { family: root.font; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.3 } }
        Grid {
            columns: 7
            readonly property real cw: parent.width / 7
            Repeater {
                model: root.wide || !root.tahoe ? 0 : 7
                Text {
                    required property int index
                    width: parent.cw; height: 15
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().standaloneDayName((index + root.firstDow) % 7, Locale.NarrowFormat)
                    color: root.fg
                    font { family: root.font; pixelSize: 9; weight: Font.Bold }
                }
            }
            Repeater {
                model: root.wide || !root.tahoe ? [] : root.cells
                Item {
                    required property int modelData
                    required property int index
                    readonly property bool isToday: modelData === root.today.getDate()
                    readonly property bool weekend: { const dow = (index + root.firstDow) % 7; return dow === 0 || dow === 6; }
                    width: parent.cw; height: root.cells.length > 35 ? 17 : 20
                    Rectangle { anchors.centerIn: parent; width: 17; height: 17; radius: 8.5; antialiasing: true; visible: parent.isToday; color: root.fg }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData || ""
                        color: parent.isToday ? root.onFg : parent.weekend ? root.fgDim : root.fg
                        font { family: root.font; pixelSize: 10; weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    // ── Wide, and small Classic: weekday + big date on the left, month grid on the right ──
    Column {
        visible: root.med || (!root.wide && !root.tahoe)
        anchors { left: parent.left; top: parent.top; margins: 16 }
        width: root.unit - 32
        spacing: -4
        Text { text: Qt.formatDate(root.today, "dddd").toUpperCase(); color: root.tahoe ? root.fgDim : root.red
            font { family: root.font; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.4 } }
        Text { text: root.today.getDate(); color: root.fg
            font { family: root.font; pixelSize: 64; weight: Font.Light } }
    }
    Column {
        visible: root.med || (!root.wide && !root.tahoe)
        anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
        spacing: 1
        Text { text: Qt.locale().standaloneMonthName(root.today.getMonth()); color: root.fg
            font { family: root.font; pixelSize: 13; weight: Font.DemiBold } }
        Text {
            readonly property int week: {
                const d = new Date(Date.UTC(root.today.getFullYear(), root.today.getMonth(), root.today.getDate()));
                d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
                return Math.ceil(((d - new Date(Date.UTC(d.getUTCFullYear(), 0, 1))) / 864e5 + 1) / 7);
            }
            text: "Week " + week; color: root.fgDim
            font { family: root.font; pixelSize: 11; weight: Font.Medium } }
    }

    // Month grid
    Grid {
        visible: root.med
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        columns: 7
        Repeater {
            model: root.med ? 7 : 0
            Text {
                required property int index
                width: 24; height: 18
                horizontalAlignment: Text.AlignHCenter
                text: Qt.locale().standaloneDayName((index + root.firstDow) % 7, Locale.NarrowFormat)
                color: root.fgFaint
                font { family: root.font; pixelSize: 10; weight: Font.Bold }
            }
        }
        Repeater {
            model: root.med ? root.cells : []
            Item {
                required property int modelData
                required property int index
                readonly property bool isToday: modelData === root.today.getDate()
                readonly property bool weekend: { const dow = (index + root.firstDow) % 7; return dow === 0 || dow === 6; }
                width: 24; height: root.cells.length > 35 ? 18 : 21
                Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 10; visible: parent.isToday; color: root.accent; antialiasing: true }
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData || ""
                    color: parent.isToday ? root.onAccent : parent.weekend ? root.fgDim : root.fg
                    font { family: root.font; pixelSize: 11; weight: parent.isToday ? Font.Bold : Font.Medium }
                }
            }
        }
    }

    // ── Large: weekday + date + month on top, a big month grid below ──
    Item {
        visible: root.large
        anchors { fill: parent; margins: 18 }
        Row {
            id: head
            spacing: 12
            Text { text: root.today.getDate(); color: root.fg
                font { family: root.font; pixelSize: 54; weight: Font.Light } }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: Qt.formatDate(root.today, "dddd").toUpperCase(); color: root.tahoe ? root.fgDim : root.red
                    font { family: root.font; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.4 } }
                Text { text: Qt.locale().standaloneMonthName(root.today.getMonth()) + " " + root.today.getFullYear(); color: root.fg
                    font { family: root.font; pixelSize: 15; weight: Font.DemiBold } }
            }
        }
        Grid {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            columns: 7
            readonly property real cw: width / 7
            readonly property real rh: (parent.height - head.height - 12 - 20) / (root.cells.length / 7)
            Repeater {
                model: root.large ? 7 : 0
                Text {
                    required property int index
                    width: parent.cw; height: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().standaloneDayName((index + root.firstDow) % 7, Locale.NarrowFormat)
                    color: root.fgFaint
                    font { family: root.font; pixelSize: 11; weight: Font.Bold }
                }
            }
            Repeater {
                model: root.large ? root.cells : []
                Item {
                    required property int modelData
                    required property int index
                    readonly property bool isToday: modelData === root.today.getDate()
                    readonly property bool weekend: { const dow = (index + root.firstDow) % 7; return dow === 0 || dow === 6; }
                    width: parent.cw; height: parent.rh
                    Rectangle { anchors.centerIn: parent; width: 28; height: 28; radius: 14; visible: parent.isToday; color: root.accent; antialiasing: true }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData || ""
                        color: parent.isToday ? root.onAccent : parent.weekend ? root.fgDim : root.fg
                        font { family: root.font; pixelSize: 14; weight: parent.isToday ? Font.Bold : Font.Medium }
                    }
                }
            }
        }
    }
}
