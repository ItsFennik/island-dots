import QtQuick
import qs.services

// Workspace indicator, centred in the menu bar. Setting barWorkspaceStyle:
//   "numbers"  [1] [2] [3]   active = filled box, occupied = outlined, empty = faint number
//   "dots"     o-o-●-o       dots on a thin line; active = wide capsule, occupied = solid dot
// Shows 1…barWorkspaceCount (default 5), stretched to include any higher occupied/active one.
// Click = go there, scroll = previous/next, right-click = Overview.
MouseArea {
    id: root

    required property string screenName
    property string family
    property int fontPx: 13
    property int barH: 30

    readonly property var s: Config.saved
    // Preview mode (Settings' style picker): fixed sample workspaces in a given style, no input.
    property string previewStyle: ""
    readonly property bool preview: previewStyle !== ""
    enabled: !preview
    readonly property bool dots: (preview ? previewStyle : (s.barWorkspaceStyle ?? "numbers")) === "dots"

    readonly property var known: preview
        ? [1, 2, 3, 4].map(i => ({ id: i, active: i === 2, occupied: i <= 3, urgent: false }))
        : Compositor.workspaces(screenName)
    readonly property var list: {
        let n = preview ? 4 : Math.max(1, s.barWorkspaceCount ?? 5);
        for (const w of known) if (w.active || w.occupied) n = Math.max(n, w.id);
        const out = [];
        for (let i = 1; i <= n; i++) out.push(known.find(w => w.id === i) ?? { id: i, active: false, occupied: false, urgent: false });
        return out;
    }
    readonly property int activeId: (known.find(w => w.active) ?? { id: -1 }).id

    visible: known.length > 0
    implicitWidth: row.implicitWidth + 16
    height: barH
    acceptedButtons: Qt.RightButton
    onClicked: Popouts.toggleOverview()

    // Wheel: one step per notch, trackpads need a full notch's worth of travel.
    property real acc: 0
    WheelHandler {
        onWheel: e => {
            root.acc += e.angleDelta.y || e.angleDelta.x;
            if (Math.abs(root.acc) < 120) return;
            const step = root.acc > 0 ? -1 : 1;
            root.acc = 0;
            const n = root.list.length;
            const cur = root.activeId > 0 ? root.activeId : 1;
            Compositor.focusWorkspace(((cur - 1 + step + n) % n) + 1);
        }
    }

    // dots: one rounded pill behind all the dots (macOS page-indicator style)
    Rectangle {
        visible: root.dots
        anchors.centerIn: row
        width: row.width + height - 4
        height: Math.round(root.fontPx * 0.6) + 10
        radius: height / 2
        color: Qt.alpha(Theme.text, Theme.dark ? 0.14 : 0.1)
        border { width: 1; color: Qt.alpha(Theme.text, 0.12) }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.dots ? 7 : 3

        Repeater {
            model: root.list
            Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool on: modelData.active
                readonly property int pip: Math.round(root.fontPx * 0.6)
                width: root.dots ? (on ? pip * 2.4 : pip) : box.width
                height: root.barH
                Behavior on width { enabled: root.dots; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                // ── dots ── (active = wide capsule, occupied = solid, empty = hollow ring)
                Rectangle {
                    visible: root.dots
                    width: parent.width; height: cell.pip
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: cell.modelData.urgent ? "#ff453a"
                         : cell.on ? Theme.text
                         : cell.modelData.occupied ? Qt.alpha(Theme.text, 0.8) : "transparent"
                    border { width: cell.on || cell.modelData.occupied ? 0 : 1.5; color: Qt.alpha(Theme.text, 0.6) }
                }

                // ── numbers ──
                Rectangle {
                    id: box
                    visible: !root.dots
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(height, num.implicitWidth + 10)
                    height: root.fontPx + 6
                    radius: 5
                    color: cell.modelData.urgent ? "#ff453a" : cell.on ? Theme.text : "transparent"
                    border { width: !cell.on && cell.modelData.occupied ? 1 : 0; color: Qt.alpha(Theme.text, 0.5) }
                    Text {
                        id: num
                        anchors.centerIn: parent
                        text: cell.modelData.id
                        color: cell.on || cell.modelData.urgent ? Theme.bg
                             : cell.modelData.occupied ? Theme.text : Qt.alpha(Theme.text, 0.45)
                        font { family: root.family; pixelSize: root.fontPx - 1; weight: cell.on ? Font.Bold : Font.Medium; features: { "tnum": 1 } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!cell.on) Compositor.focusWorkspace(cell.modelData.id)
                }
            }
        }
    }
}
