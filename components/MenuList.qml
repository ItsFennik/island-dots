import QtQuick
import qs.services

// A macOS menu (Sonoma/Sequoia metrics): 22 px rows, a selection inset 5 px with 4 px corners,
// a check column, hairline separators inset to the text, and shortcuts laid out like AppKit —
// modifiers right-aligned, the key in its own column. Arrow keys / Return work too.
// items: [{ text, shortcut?, f, off?, check?, header? } | { sep: true }]
Item {
    id: root
    property var items: []
    property string family: Config.saved.widgetFont || "Adwaita Sans"
    property int minWidth: 236
    signal done()

    property real widest: 0
    property int hi: -1                     // highlighted row (mouse or keyboard)
    readonly property bool anyCheck: items.some(i => i.check !== undefined)
    implicitWidth: Math.max(minWidth, widest)
    implicitHeight: col.implicitHeight

    // "⌥⌘⎋" → modifiers "⌥⌘", key "⎋"
    function split(s) {
        if (!s) return ["", ""];
        const m = /^([⌃⌥⇧⌘]*)(.*)$/.exec(s);
        return [m[1], m[2]];
    }
    function selectable(i) { const it = items[i]; return it && !it.sep && !it.off && !it.header; }
    function move(d) {
        let i = hi;
        for (let n = 0; n < items.length; n++) {
            i = (i + d + items.length) % items.length;
            if (selectable(i)) { hi = i; return; }
        }
    }
    // Run the action first: closing destroys this menu (and its parent's functions the
    // action may call). Skip the close if the action opened another popout.
    function activate(i) {
        if (!selectable(i)) return;
        const f = items[i].f, cur = Popouts.current;
        if (f) f();
        if (Popouts.current === cur) done();
    }

    Component.onCompleted: Qt.callLater(() => root.forceActiveFocus())
    Keys.onDownPressed: move(1)
    Keys.onUpPressed: move(-1)
    Keys.onReturnPressed: activate(hi)
    Keys.onEnterPressed: activate(hi)
    Keys.onSpacePressed: activate(hi)

    Column {
        id: col
        width: root.implicitWidth
        Repeater {
            model: root.items
            delegate: MouseArea {
                id: row
                required property var modelData
                required property int index
                readonly property bool sep: !!modelData.sep
                readonly property bool header: !!modelData.header
                readonly property bool lit: root.hi === index && enabled
                readonly property var sc: root.split(modelData.shortcut)
                width: col.width
                height: sep ? 9 : 22
                enabled: !sep && !header && !modelData.off
                hoverEnabled: true
                onEntered: root.hi = index
                onExited: if (root.hi === index) root.hi = -1
                onClicked: root.activate(index)
                Component.onCompleted: if (!sep) root.widest = Math.max(root.widest,
                    label.implicitWidth + 22 + (modelData.shortcut ? mods.implicitWidth + 16 + 30 : 14))

                Rectangle { visible: row.sep; anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    height: 1; color: Qt.alpha(Theme.menuText, Theme.dark ? 0.13 : 0.11) }
                Rectangle { visible: row.lit; anchors { fill: parent; leftMargin: 0; rightMargin: 0 } radius: 4; color: Theme.menuSel }
                Text {
                    visible: !!row.modelData.check
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter; verticalCenterOffset: -0.5 }
                    text: "✓"
                    color: row.lit ? Theme.menuOnSel : Theme.menuText
                    font { family: root.family; pixelSize: 12; weight: Font.DemiBold }
                }
                Text {
                    id: label
                    visible: !row.sep
                    anchors { left: parent.left; leftMargin: row.header ? 8 : 20; verticalCenter: parent.verticalCenter }
                    text: row.modelData.text ?? ""
                    color: row.header ? Qt.alpha(Theme.menuText, 0.5)
                         : !row.enabled ? Qt.alpha(Theme.menuText, 0.28) : row.lit ? Theme.menuOnSel : Theme.menuText
                    font { family: root.family; pixelSize: row.header ? 11 : 13; weight: row.header ? Font.DemiBold : Font.Normal }
                }
                // Shortcut: key in a fixed column at the right edge, modifiers just left of it.
                Text {
                    id: key
                    visible: !row.sep && row.sc[1] !== ""
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 16
                    text: row.sc[1]
                    color: row.lit ? Qt.alpha(Theme.menuOnSel, 0.85) : !row.enabled ? Qt.alpha(Theme.menuText, 0.22) : Qt.alpha(Theme.menuText, 0.45)
                    font { family: root.family; pixelSize: 13 }
                }
                Text {
                    id: mods
                    visible: !row.sep && row.sc[0] !== ""
                    anchors { right: key.left; rightMargin: 1; verticalCenter: parent.verticalCenter }
                    text: row.sc[0]
                    color: key.color
                    font { family: root.family; pixelSize: 13; letterSpacing: 1 }
                }
            }
        }
    }
}
