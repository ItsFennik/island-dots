import QtQuick
import Quickshell
import qs.services

// Power. Log out / Reboot / Shut down need a second click (or Enter) to confirm.
// ←/→ pick, Enter run.
Item {
    id: root

    readonly property bool closeOnLeave: true
    property int index: 0
    property string armed: ""

    readonly property var actions: [
        { id: "lock", text: "Lock", glyph: "", confirm: false, f: () => Compositor.lock() },
        { id: "sleep", text: "Sleep", glyph: "", confirm: false, cmd: ["systemctl", "suspend"] },
        { id: "logout", text: "Log out", glyph: "", confirm: true, f: () => Compositor.logout() },
        { id: "reboot", text: "Reboot", glyph: "", confirm: true, cmd: ["systemctl", "reboot"] },
        { id: "off", text: "Shut down", glyph: "", confirm: true, cmd: ["systemctl", "poweroff"] }
    ]

    implicitWidth: actions.length * 84 + (actions.length - 1) * 6
    implicitHeight: 84

    focus: true
    function run(a) {
        if (a.confirm && armed !== a.id) { armed = a.id; return; }
        Popouts.close();
        if (a.f) a.f(); else Quickshell.execDetached(a.cmd);
    }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_L) { index = (index + 1) % actions.length; armed = ""; }
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_H) { index = (index + actions.length - 1) % actions.length; armed = ""; }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) run(actions[index]);
        else return;
        e.accepted = true;
    }

    Row {
        anchors.centerIn: parent
        spacing: 6
        Repeater {
            model: root.actions
            MouseArea {
                id: tile
                required property var modelData
                required property int index
                readonly property bool current: index === root.index
                readonly property bool isArmed: root.armed === modelData.id
                width: 84; height: 84
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { if (root.index !== index) root.armed = ""; root.index = index; }
                onClicked: root.run(modelData)

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: tile.isArmed ? Qt.alpha(Theme.pal.red, 0.22) : tile.current ? Theme.control : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.glyph
                        color: tile.isArmed ? Theme.pal.red : tile.current ? Theme.text : Theme.textDim
                        font { family: Theme.mono; pixelSize: 20 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.isArmed ? "Sure?" : tile.modelData.text
                        color: tile.isArmed ? Theme.pal.red : tile.current ? Theme.text : Theme.textDim
                        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                    }
                }
            }
        }
    }
}
