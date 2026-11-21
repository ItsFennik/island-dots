import QtQuick
import Quickshell
import qs.services

// A tray app's right-click menu, drawn by Island (grows out of the bar like every other
// menu) instead of a platform Qt menu. Submenus slide in with a back row.
//   ↑/↓ pick · Enter/→ open · ←/Backspace back · Esc close
Item {
    id: root

    readonly property bool closeOnLeave: true
    readonly property var tray: Popouts.trayItem
    readonly property string family: Config.saved.widgetFont || "Adwaita Sans"

    // Navigation stack of QsMenuHandles; the last one is shown.
    property var stack: tray?.menu ? [tray.menu] : []
    readonly property var current: stack.length ? stack[stack.length - 1] : null
    property var titles: []
    property int index: -1

    readonly property var entries: (opener.children?.values ?? [])
    readonly property var selectable: entries.map((e, i) => (!e.isSeparator && e.enabled) ? i : -1).filter(i => i >= 0)

    implicitWidth: Math.max(220, Math.min(380, list.implicitW + 16))
    implicitHeight: col.implicitHeight + 8
    focus: true

    QsMenuOpener { id: opener; menu: root.current }

    function enter(e) {
        if (e.hasChildren) { titles = titles.concat([e.text]); stack = stack.concat([e]); index = -1; return; }
        e.triggered();
        Popouts.close();
    }
    function back() {
        if (stack.length <= 1) { Popouts.close(); return; }
        stack = stack.slice(0, -1); titles = titles.slice(0, -1); index = -1;
    }
    function move(d) {
        if (!selectable.length) return;
        const pos = selectable.indexOf(index);
        index = selectable[pos < 0 ? (d > 0 ? 0 : selectable.length - 1) : (pos + d + selectable.length) % selectable.length];
    }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || e.key === Qt.Key_J) move(1);
        else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || e.key === Qt.Key_K) move(-1);
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || e.key === Qt.Key_Right) && index >= 0) enter(entries[index]);
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backspace) back();
        else return;
        e.accepted = true;
    }
    // Tray app went away while open.
    onTrayChanged: if (!tray) Popouts.close()

    Column {
        id: col
        x: 0; y: 4
        width: parent.width

        // Header: app name, or back row inside a submenu
        MouseArea {
            width: parent.width; height: 30
            enabled: root.stack.length > 1
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.back()
            Rectangle { anchors.fill: parent; radius: 8; color: parent.enabled && parent.containsMouse ? Theme.hover : "transparent" }
            Row {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text { visible: root.stack.length > 1; text: ""; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter
                    font { family: Theme.mono; pixelSize: 10 } }
                Image {
                    visible: root.stack.length <= 1 && status === Image.Ready
                    width: 14; height: 14; sourceSize { width: 28; height: 28 }
                    anchors.verticalCenter: parent.verticalCenter
                    source: root.tray?.icon ?? ""
                    asynchronous: true
                }
                Text {
                    text: root.stack.length > 1 ? root.titles[root.titles.length - 1].replace(/_/g, "")
                                                : (root.tray?.tooltipTitle || root.tray?.title || root.tray?.id || "")
                    color: Theme.textDim
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, col.width - 50)
                    font { family: root.family; pixelSize: 11; weight: Theme.w(Font.DemiBold); letterSpacing: 0.6; capitalization: Font.AllUppercase }
                }
            }
        }
        Rectangle { width: parent.width - 16; x: 8; height: 1; color: Theme.hairline }
        Item { width: 1; height: 4 }

        Column {
            id: list
            width: parent.width
            property real implicitW: 0
            Repeater {
                model: root.entries
                delegate: MouseArea {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sep: modelData.isSeparator
                    readonly property bool hot: root.index === index
                    width: list.width
                    height: sep ? 9 : 28
                    enabled: !sep && modelData.enabled
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: root.index = index
                    onClicked: root.enter(modelData)
                    Component.onCompleted: if (!sep) list.implicitW = Math.max(list.implicitW, label.implicitWidth + 70)

                    Rectangle { visible: row.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.hairline }
                    Rectangle { visible: !row.sep; anchors.fill: parent; radius: 8; color: row.hot ? Theme.accent : "transparent" }

                    // Check / radio mark, else the entry's icon
                    Item {
                        visible: !row.sep
                        x: 8; width: 16; height: parent.height
                        Text {
                            anchors.centerIn: parent
                            visible: row.modelData.buttonType !== QsMenuButtonType.None && row.modelData.checkState === Qt.Checked
                            text: row.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓"
                            color: row.hot ? Theme.onAccent : Theme.text
                            font { family: root.family; weight: Theme.fontWeight; pixelSize: row.modelData.buttonType === QsMenuButtonType.RadioButton ? 8 : 12 }
                        }
                        Image {
                            anchors.centerIn: parent
                            visible: row.modelData.buttonType === QsMenuButtonType.None && (row.modelData.icon ?? "") !== "" && status === Image.Ready
                            width: 14; height: 14; sourceSize { width: 28; height: 28 }
                            source: row.sep ? "" : (row.modelData.icon ?? "")
                            asynchronous: true
                        }
                    }
                    Text {
                        id: label
                        visible: !row.sep
                        anchors { left: parent.left; leftMargin: 32; right: arrow.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: row.sep ? "" : (row.modelData.text ?? "").replace(/_(?!_)/g, "")    // drop mnemonic underscores
                        elide: Text.ElideRight
                        color: !row.enabled ? Theme.textFaint : row.hot ? Theme.onAccent : Theme.text
                        font { family: root.family; weight: Theme.fontWeight; pixelSize: 13 }
                    }
                    Text {
                        id: arrow
                        visible: !row.sep && row.modelData.hasChildren
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: ""
                        color: row.hot ? Theme.onAccent : Theme.textDim
                        font { family: Theme.mono; pixelSize: 9 }
                    }
                }
            }
        }
        Text {
            visible: root.entries.length === 0
            x: 12; height: 28; verticalAlignment: Text.AlignVCenter
            text: "No menu"
            color: Theme.textFaint
            font { family: root.family; weight: Theme.fontWeight; pixelSize: 12 }
        }
    }
}
