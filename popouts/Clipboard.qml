import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Clipboard history (cliphist). Type to filter, ↑/↓ or hover to pick, Enter/click to copy,
// Shift+Delete removes an entry.
Item {
    id: root

    readonly property bool closeOnLeave: true
    property var entries: []        // raw cliphist lines: "<id>\t<preview>"
    property string query: ""
    property int index: 0
    readonly property var shown: {
        const q = query.toLowerCase();
        const out = [];
        for (const e of entries) {
            if (q === "" || e.toLowerCase().includes(q)) out.push(e);
            if (out.length >= 60) break;
        }
        return out;
    }

    implicitWidth: 460
    implicitHeight: col.implicitHeight

    onQueryChanged: index = 0
    onActiveFocusChanged: if (activeFocus) input.forceActiveFocus()

    function preview(line) {
        const t = line.slice(line.indexOf("\t") + 1).replace(/\s+/g, " ").trim();
        return t.startsWith("[[ binary data") ? "Image  " + t.replace(/^\[\[ binary data\s*/, "").replace(/\s*\]\]$/, "") : t;
    }
    function copy(line) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "sh", line]);
        Popouts.close();
    }
    function remove(line) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "sh", line]);
        entries = entries.filter(e => e !== line);
    }

    Process {
        running: true
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: root.entries = text.split("\n").filter(l => l.indexOf("\t") > 0) }
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        Item {
            width: parent.width; height: 32
            Icon { id: glass; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                name: "search"; size: 14; color: Theme.textFaint }
            TextInput {
                id: input
                anchors { left: glass.right; leftMargin: 10; right: count.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                focus: true
                clip: true
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent
                font { family: Theme.font; pixelSize: 13 }
                onTextChanged: root.query = text
                onAccepted: if (root.shown.length) root.copy(root.shown[root.index])
                Keys.onPressed: e => {
                    const n = root.shown.length;
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) root.index = Math.min(n - 1, root.index + 1);
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) root.index = Math.max(0, root.index - 1);
                    else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier) && n) root.remove(root.shown[root.index]);
                    else if (e.key === Qt.Key_Escape) Popouts.close();
                    else return;
                    e.accepted = true;
                }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: input.text === ""; text: "Clipboard"; color: Theme.textFaint; font: input.font }
            }
            Text {
                id: count
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: root.shown.length + (root.entries.length > root.shown.length ? "/" + root.entries.length : "")
                color: Theme.textFaint
                font { family: Theme.font; pixelSize: 11 }
            }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.hairline }

        Text {
            visible: root.shown.length === 0
            width: parent.width; height: 40
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: root.entries.length ? "No matches" : "Clipboard is empty"
            color: Theme.textFaint
            font { family: Theme.font; pixelSize: 12 }
        }

        ListView {
            id: view
            width: parent.width
            height: Math.min(contentHeight, 34 * 10)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.shown
            currentIndex: root.index
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: MenuItem {
                required property string modelData
                required property int index
                text: root.preview(modelData)
                glyph: modelData.includes("[[ binary data") ? "\uf03e" : /^\d+\thttps?:\/\//.test(modelData) ? "\uf0c1" : "\uf15c"
                current: index === root.index
                onEntered: root.index = index
                onClicked: root.copy(modelData)
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "type to filter · enter copy · shift+del remove"
            color: Theme.textFaint
            font { family: Theme.font; pixelSize: 10 }
            bottomPadding: 2
        }
    }
}
