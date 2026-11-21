import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

// The screenshot toolbar (⇧⌘S), like macOS's ⇧⌘5: a glass strip at the bottom of the screen.
//   [×] | Entire Screen · Window · Selection | Options ⌄  [Capture]
//   1 2 3 pick · ←/→ · Enter capture · Esc close. Only exists while open.
PanelWindow {
    id: win

    readonly property string family: Theme.font
    readonly property var s: Config.values
    readonly property bool catchAll: !Compositor.focusGrab
    property bool optionsOpen: false

    anchors { bottom: true; left: catchAll; right: catchAll; top: catchAll }
    margins.bottom: catchAll ? 0 : 60
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 560
    implicitHeight: 420                      // room for the Options menu above the strip
    color: "transparent"
    mask: Region { item: bar; Region { item: win.optionsOpen ? menu : null } Region { item: win.catchAll ? catcher : null } }

    WlrLayershell.namespace: "island-screenshot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property bool armed: false
    Timer { interval: 60; running: true; onTriggered: win.armed = true }
    HyprlandFocusGrab { windows: [win]; active: Compositor.focusGrab && win.armed; onCleared: Screenshot.toolbar = false }
    MouseArea {
        id: catcher
        anchors.fill: parent
        z: -1
        visible: win.catchAll
        onPressed: Screenshot.toolbar = false
    }

    readonly property var modes: [
        { id: "screen", text: "Capture Entire Screen" },
        { id: "window", text: "Capture Selected Window" },
        { id: "region", text: "Capture Selected Portion" }
    ]
    readonly property string dest: s.screenshotDest ?? "~/Pictures/Screenshots"
    function pick(i) { Screenshot.mode = modes[(i + modes.length) % modes.length].id; }
    function modeIndex() { return modes.findIndex(m => m.id === Screenshot.mode); }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { if (win.optionsOpen) win.optionsOpen = false; else Screenshot.toolbar = false; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) Screenshot.captureFromToolbar();
            else if (e.key === Qt.Key_Left) win.pick(win.modeIndex() - 1);
            else if (e.key === Qt.Key_Right) win.pick(win.modeIndex() + 1);
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_3) win.pick(e.key - Qt.Key_1);
            else return;
            e.accepted = true;
        }
    }

    // Options menu (opens upward from the Options button)
    Rectangle {
        id: menu
        visible: win.optionsOpen
        x: Math.min(win.width - width - 4, optionsBtn.mapToItem(win.contentItem, 0, 0).x)
        anchors { bottom: bar.top; bottomMargin: 8 }
        width: list.implicitWidth + 12
        height: list.implicitHeight + 12
        radius: 12
        color: Qt.alpha(Theme.bg, 0.92)
        border { width: 1; color: Qt.alpha(Theme.text, 0.14) }
        MenuList {
            id: list
            x: 6; y: 6
            minWidth: 230
            family: win.family
            onDone: win.optionsOpen = false
            items: [
                { text: "Save to", off: true },
                { text: "Screenshots folder", check: win.dest === "~/Pictures/Screenshots", f: () => Config.commit("screenshotDest", "~/Pictures/Screenshots") },
                { text: "Pictures", check: win.dest === "~/Pictures", f: () => Config.commit("screenshotDest", "~/Pictures") },
                { text: "Desktop", check: win.dest === "~/Desktop", f: () => Config.commit("screenshotDest", "~/Desktop") },
                { text: "Clipboard only", check: win.dest === "clipboard", f: () => Config.commit("screenshotDest", "clipboard") },
                { sep: true },
                { text: "Timer", off: true },
                { text: "None", check: Screenshot.delay === 0, f: () => Screenshot.delay = 0 },
                { text: "3 Seconds", check: Screenshot.delay === 3, f: () => Screenshot.delay = 3 },
                { text: "5 Seconds", check: Screenshot.delay === 5, f: () => Screenshot.delay = 5 },
                { text: "10 Seconds", check: Screenshot.delay === 10, f: () => Screenshot.delay = 10 },
                { sep: true },
                { text: "Options", off: true },
                { text: "Show Floating Thumbnail", check: win.s.screenshotThumb ?? true, f: () => Config.commit("screenshotThumb", !(win.s.screenshotThumb ?? true)) },
                { text: "Also Copy to Clipboard", check: win.s.screenshotCopy ?? true, off: win.dest === "clipboard", f: () => Config.commit("screenshotCopy", !(win.s.screenshotCopy ?? true)) },
                { text: "Show Mouse Pointer", check: win.s.screenshotPointer ?? false, f: () => Config.commit("screenshotPointer", !(win.s.screenshotPointer ?? false)) },
                { text: "Play Sound", check: win.s.screenshotSound ?? true, f: () => Config.commit("screenshotSound", !(win.s.screenshotSound ?? true)) }
            ]
        }
    }

    // The strip
    Rectangle {
        id: bar
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: win.catchAll ? 60 : 4 }
        width: row.implicitWidth + 16
        height: 52
        radius: 14
        color: Qt.alpha(Theme.bg, 0.85)
        border { width: 1; color: Qt.alpha(Theme.text, 0.14) }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 4

            // Close
            ToolButton {
                width: 32
                tip: "Close (Esc)"
                onClicked: Screenshot.toolbar = false
                Rectangle {
                    anchors.centerIn: parent; width: 18; height: 18; radius: 9
                    color: Qt.alpha(Theme.text, parent.containsMouse ? 0.3 : 0.18)
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font { family: win.family; pixelSize: 10; weight: Theme.w(Font.Bold) } }
                }
            }
            Divider {}

            Repeater {
                model: win.modes
                delegate: ToolButton {
                    id: mb
                    required property var modelData
                    required property int index
                    width: 44
                    tip: modelData.text + "  (" + (index + 1) + ")"
                    selected: Screenshot.mode === modelData.id
                    onClicked: Screenshot.mode = modelData.id
                    onDoubleClicked: Screenshot.capture(modelData.id, Screenshot.delay)
                    ModeIcon { anchors.centerIn: parent; kind: mb.modelData.id; color: mb.selected ? Theme.accent : Theme.text }
                }
            }
            Divider {}

            // Options ⌄
            ToolButton {
                id: optionsBtn
                width: optLabel.implicitWidth + 20
                selected: win.optionsOpen
                onClicked: win.optionsOpen = !win.optionsOpen
                Text {
                    id: optLabel
                    anchors.centerIn: parent
                    text: (Screenshot.delay ? Screenshot.delay + "s · " : "") + "Options  ⌄"
                    color: Theme.text
                    font { family: win.family; weight: Theme.fontWeight; pixelSize: 13 }
                }
            }

            // Capture
            MouseArea {
                width: capLabel.implicitWidth + 28; height: 32
                anchors.verticalCenter: parent.verticalCenter
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Screenshot.captureFromToolbar()
                Rectangle { anchors.fill: parent; radius: 8; color: parent.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent }
                Text {
                    id: capLabel
                    anchors.centerIn: parent
                    text: "Capture"
                    color: Theme.onAccent
                    font { family: win.family; pixelSize: 13; weight: Theme.w(Font.DemiBold) }
                }
            }
        }

        // Tooltip for the hovered button
        Rectangle {
            visible: tipText.text !== ""
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
            width: tipText.implicitWidth + 16; height: 24; radius: 6
            color: Qt.alpha(Theme.bg, 0.92)
            border { width: 1; color: Qt.alpha(Theme.text, 0.12) }
            Text { id: tipText; anchors.centerIn: parent; text: win.optionsOpen ? "" : win.tip; color: Theme.textDim; font { family: win.family; weight: Theme.fontWeight; pixelSize: 12 } }
        }

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    property string tip: ""

    component Divider: Rectangle { width: 1; height: 26; anchors.verticalCenter: parent?.verticalCenter; color: Qt.alpha(Theme.text, 0.15) }

    component ToolButton: MouseArea {
        property bool selected: false
        property string tip: ""
        height: 36
        anchors.verticalCenter: parent?.verticalCenter
        hoverEnabled: true
        onContainsMouseChanged: if (tip) win.tip = containsMouse ? tip : (win.tip === tip ? "" : win.tip)
        Rectangle {
            anchors.fill: parent; radius: 8
            color: parent.selected ? Qt.alpha(Theme.text, 0.16) : parent.containsMouse ? Qt.alpha(Theme.text, 0.08) : "transparent"
        }
    }

    // Little line drawings of the three modes (Canvas: drawn once, cheap on the software backend)
    component ModeIcon: Canvas {
        property string kind
        property color color: Theme.text
        width: 26; height: 20
        onColorChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.strokeStyle = color; c.fillStyle = color; c.lineWidth = 1.5;
            if (kind === "screen") {
                c.strokeRect(1.5, 1.5, 23, 15);
                c.fillRect(9, 17.5, 8, 1.5);
            } else if (kind === "window") {
                c.strokeRect(1.5, 2.5, 23, 15);
                c.fillRect(1.5, 2.5, 23, 4);
                c.strokeRect(5.5, 9.5, 15, 5);
            } else {
                c.setLineDash([2, 2]);
                c.strokeRect(1.5, 2.5, 23, 15);
                c.setLineDash([]);
                c.fillRect(0, 1, 3, 3); c.fillRect(23, 1, 3, 3); c.fillRect(0, 16, 3, 3); c.fillRect(23, 16, 3, 3);
            }
        }
    }
}
