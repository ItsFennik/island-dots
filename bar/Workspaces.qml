import QtQuick
import qs.services

// Workspace indicator (menu bar, bottom bar, compact bar). Setting barWorkspaceStyle:
//   "numbers"   [1] [2] [3]     active = filled box, occupied = outlined, empty = faint number
//   "dots"      o-o-●-o         dots in a grey pill; active = wide capsule, occupied = solid dot
//   "pill"      · ● ━━ · ·      no track; one accent capsule glides to the active workspace
//   "glide"     1 [2] 3 4       plain numbers; an accent box slides under the active one
//   "line"      ── ━━━━ ── ┄┄   thin segments; active = long accent segment
//   "activity"  ▂ █ ▅ ▁         one bar per workspace, as tall as its window count
//   "kanji"     一 [二] 三      like glide, with Japanese numerals
//   "roman"     I [II] III      like glide, with Roman numerals
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
    readonly property string style: preview ? previewStyle : (s.barWorkspaceStyle ?? "numbers")
    readonly property bool dots: style === "dots"
    readonly property bool numbers: style === "numbers"
    readonly property bool pill: style === "pill"
    readonly property bool line: style === "line"
    readonly property bool activity: style === "activity"
    // glide, kanji and roman: equal-width labels with one sliding accent box
    readonly property bool glide: style === "glide" || style === "kanji" || style === "roman"
    readonly property bool sliding: glide || pill

    readonly property var known: preview
        ? [1, 2, 3, 4].map(i => ({ id: i, active: i === 2, occupied: i <= 3, windows: [2, 3, 1, 0][i - 1], urgent: false }))
        : Compositor.workspaces(screenName)
    readonly property var list: {
        let n = preview ? 4 : Math.max(1, s.barWorkspaceCount ?? 5);
        for (const w of known) if (w.active || w.occupied) n = Math.max(n, w.id);
        const out = [];
        for (let i = 1; i <= n; i++) out.push(known.find(w => w.id === i) ?? { id: i, active: false, occupied: false, windows: 0, urgent: false });
        return out;
    }
    readonly property int activeId: (known.find(w => w.active) ?? { id: -1 }).id
    readonly property int activeIndex: list.findIndex(w => w.active)

    readonly property var kanji: ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    function roman(n) {
        const t = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];
        let out = "";
        for (const [v, r] of t) while (n >= v) { out += r; n -= v; }
        return out;
    }
    function label(id) {
        return style === "kanji" ? (kanji[id] ?? String(id)) : style === "roman" ? roman(id) : String(id);
    }

    // Sizes shared by the styles
    readonly property int pip: Math.round(fontPx * 0.6)                     // dot diameter
    readonly property int cellW: pill ? pip                                // equal cells for sliding styles
                               : style === "roman" ? Math.round(fontPx * 2.2)
                               : fontPx + 9
    readonly property int gap: dots ? 7 : pill ? pip + 3 : line ? 4 : activity ? 4 : glide ? 2 : 3

    visible: known.length > 0
    implicitWidth: row.implicitWidth + 16
    height: barH
    acceptedButtons: preview ? Qt.NoButton : Qt.RightButton
    onClicked: Popouts.toggleOverview()

    // Wheel: one step per notch, trackpads need a full notch's worth of travel.
    // The leftover resets after a pause, so a stray nudge (or a scroll long ago) can't tip a
    // later click over into switching workspace.
    property real acc: 0
    Timer { id: accReset; interval: 400; onTriggered: root.acc = 0 }
    WheelHandler {
        enabled: !root.preview
        onWheel: e => {
            if (hit.pressed) return;
            accReset.restart();
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
        height: root.pip + 10
        radius: height / 2
        color: Qt.alpha(Theme.text, Theme.dark ? 0.14 : 0.1)
        border { width: 1; color: Qt.alpha(Theme.text, 0.12) }
    }

    // pill / glide / kanji / roman: the one highlight that slides to the active workspace
    Rectangle {
        id: slider
        visible: root.sliding && root.activeIndex >= 0
        readonly property real cx: row.x + root.activeIndex * (root.cellW + root.gap) + root.cellW / 2
        width: root.pill ? root.pip + (root.gap - 4) * 2 : root.cellW
        height: root.pill ? root.pip : root.fontPx + 7
        x: Math.round(cx - width / 2)
        anchors.verticalCenter: parent.verticalCenter
        radius: root.pill ? height / 2 : Math.round(height * 0.3)
        color: (root.list[root.activeIndex]?.urgent ?? false) ? "#ff453a" : Theme.accent
        Behavior on x { enabled: !root.preview; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    // One click area for all cells: the press picks the cell whose centre is nearest, so there
    // are no gaps or overlapping strips (per-cell areas stretched into the gaps sent clicks just
    // past a small dot to the next workspace), and widths animating mid-click don't matter.
    MouseArea {
        id: hit
        // Off in Settings' preview tiles, or it swallows the click meant for the tile.
        visible: !root.preview
        enabled: !root.preview
        anchors { fill: row; leftMargin: -root.gap; rightMargin: -root.gap }
        height: root.barH
        cursorShape: Qt.PointingHandCursor
        property int target: -1
        function nearest(mx) {
            let best = -1, bestD = 1e9;
            for (let i = 0; i < cells.count; i++) {
                const c = cells.itemAt(i);
                if (!c) continue;
                const d = Math.abs(row.x + c.x + c.width / 2 - (x + mx));
                if (d < bestD) { bestD = d; best = i; }
            }
            return best;
        }
        onPressed: e => target = nearest(e.x)
        onClicked: e => {
            const w = root.list[target];
            if (w && !w.active) Compositor.focusWorkspace(w.id);
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.gap

        Repeater {
            id: cells
            model: root.list
            Item {
                id: cell
                required property var modelData
                readonly property bool on: modelData.active
                readonly property bool occ: modelData.occupied
                readonly property bool urgent: modelData.urgent
                width: root.dots ? (on ? root.pip * 2.4 : root.pip)
                     : root.line ? (on ? 22 : 10)
                     : root.activity ? Math.max(5, Math.round(root.fontPx * 0.45))
                     : root.sliding ? root.cellW
                     : box.width
                height: root.barH
                Behavior on width { enabled: (root.dots || root.line) && !root.preview; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                // ── dots ── (active = wide capsule, occupied = solid, empty = hollow ring)
                Rectangle {
                    visible: root.dots
                    width: parent.width; height: root.pip
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: cell.urgent ? "#ff453a" : cell.on ? Theme.text : cell.occ ? Qt.alpha(Theme.text, 0.8) : "transparent"
                    border { width: cell.on || cell.occ ? 0 : 1.5; color: Qt.alpha(Theme.text, 0.6) }
                }

                // ── pill ── (dots under the gliding capsule; the active one is hidden by it)
                Rectangle {
                    visible: root.pill && !cell.on
                    width: root.pip; height: root.pip
                    anchors.centerIn: parent
                    radius: height / 2
                    color: cell.urgent ? "#ff453a" : Qt.alpha(Theme.text, cell.occ ? 0.75 : 0.25)
                }

                // ── glide / kanji / roman ── (label over the sliding box; dot under occupied ones)
                Text {
                    visible: root.glide
                    anchors.centerIn: parent
                    text: root.label(cell.modelData.id)
                    color: cell.on || cell.urgent ? Theme.onAccent : cell.occ ? Theme.text : Qt.alpha(Theme.text, 0.4)
                    Behavior on color { enabled: !root.preview; ColorAnimation { duration: 160 } }
                    font { family: root.family; pixelSize: root.style === "roman" ? root.fontPx - 2 : root.fontPx - 1
                        weight: Theme.w(cell.on ? Font.Bold : Font.Medium); features: { "tnum": 1 } }
                }
                Rectangle {
                    visible: root.glide && cell.occ && !cell.on
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: Math.round(root.fontPx * 0.5) + 5 }
                    width: 3; height: 3; radius: 1.5
                    color: Qt.alpha(Theme.text, 0.6)
                }

                // ── line ── (thin segments; active = long accent segment)
                Rectangle {
                    visible: root.line
                    width: parent.width; height: cell.on ? 4 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: cell.urgent ? "#ff453a" : cell.on ? Theme.accent : Qt.alpha(Theme.text, cell.occ ? 0.6 : 0.18)
                }

                // ── activity ── (bar height follows the window count, 0…4+)
                Rectangle {
                    visible: root.activity
                    readonly property int full: Math.round(Math.min(root.barH * 0.6, root.fontPx * 1.6))
                    readonly property int n: Math.min(4, cell.modelData.windows ?? (cell.occ ? 1 : 0))
                    width: parent.width
                    height: Math.max(3, Math.round(full * (n === 0 ? 0 : (n + 0.6) / 4.6)))
                    anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: Math.round((full - height) / 2) }
                    radius: 2
                    color: cell.urgent ? "#ff453a" : cell.on ? Theme.accent : Qt.alpha(Theme.text, n > 0 ? 0.6 : 0.2)
                    Behavior on height { enabled: !root.preview; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                // ── numbers ──
                Rectangle {
                    id: box
                    visible: root.numbers
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(height, num.implicitWidth + 10)
                    height: root.fontPx + 6
                    radius: 5
                    color: cell.urgent ? "#ff453a" : cell.on ? Theme.text : "transparent"
                    border { width: !cell.on && cell.occ ? 1 : 0; color: Qt.alpha(Theme.text, 0.5) }
                    Text {
                        id: num
                        anchors.centerIn: parent
                        text: cell.modelData.id
                        color: cell.on || cell.urgent ? Theme.bg : cell.occ ? Theme.text : Qt.alpha(Theme.text, 0.45)
                        font { family: root.family; pixelSize: root.fontPx - 1; weight: Theme.w(cell.on ? Font.Bold : Font.Medium); features: { "tnum": 1 } }
                    }
                }

            }
        }
    }
}
