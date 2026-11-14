import QtQuick
import Quickshell
import qs.services

// Calendar, Apple style. Small: red weekday, big date, month name.
// Wide: plus the month grid with today circled. Click opens Notification Center.
Card {
    id: root
    property string screenName: ""
    readonly property color red: "#ff453a"

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

    Column {
        anchors { left: parent.left; top: parent.top; margins: 16 }
        width: root.unit - 32
        spacing: -4
        Text { text: Qt.formatDate(root.today, "dddd").toUpperCase(); color: root.red
            font { family: root.font; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.4 } }
        Text { text: root.today.getDate(); color: Theme.text
            font { family: root.font; pixelSize: 64; weight: Font.Light } }
    }
    Column {
        anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
        spacing: 1
        Text { text: Qt.locale().standaloneMonthName(root.today.getMonth()); color: Theme.text
            font { family: root.font; pixelSize: 13; weight: Font.DemiBold } }
        Text {
            readonly property int week: {
                const d = new Date(Date.UTC(root.today.getFullYear(), root.today.getMonth(), root.today.getDate()));
                d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
                return Math.ceil(((d - new Date(Date.UTC(d.getUTCFullYear(), 0, 1))) / 864e5 + 1) / 7);
            }
            text: "Week " + week; color: Theme.textDim
            font { family: root.font; pixelSize: 11; weight: Font.Medium } }
    }

    // Month grid
    Grid {
        visible: root.wide
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        columns: 7
        Repeater {
            model: root.wide ? 7 : 0
            Text {
                required property int index
                width: 24; height: 18
                horizontalAlignment: Text.AlignHCenter
                text: Qt.locale().standaloneDayName((index + root.firstDow) % 7, Locale.NarrowFormat)
                color: Theme.textFaint
                font { family: root.font; pixelSize: 10; weight: Font.Bold }
            }
        }
        Repeater {
            model: root.wide ? root.cells : []
            Item {
                required property int modelData
                required property int index
                readonly property bool isToday: modelData === root.today.getDate()
                readonly property bool weekend: { const dow = (index + root.firstDow) % 7; return dow === 0 || dow === 6; }
                width: 24; height: root.cells.length > 35 ? 18 : 21
                Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 10; visible: parent.isToday; color: root.red }
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData || ""
                    color: parent.isToday ? "white" : parent.weekend ? Theme.textDim : Theme.text
                    font { family: root.font; pixelSize: 11; weight: parent.isToday ? Font.Bold : Font.Medium }
                }
            }
        }
    }
}
