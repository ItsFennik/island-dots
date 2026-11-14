import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Spotlight-style search (Super+D, the bar's search icon). A floating glass bar in the upper
// middle of the screen; results appear under it: Top Hit, Applications, a calculator,
// "$ command" to run in a shell, and a web search. Only exists while open.
//   ↑/↓ pick · Enter open · Ctrl+Enter / right-click: Keep in Dock · Esc close
PanelWindow {
    id: win

    readonly property string family: Config.saved.widgetFont || "Adwaita Sans"
    readonly property int w: 680
    readonly property int fieldH: 58
    readonly property int rowH: 42
    readonly property int maxRows: 8

    // Without focus grabs it covers the whole screen (click outside the card closes it).
    readonly property bool catchAll: !Compositor.focusGrab
    readonly property int topGap: Math.round((screen?.height ?? 1080) * 0.2)
    anchors { top: true; bottom: catchAll; left: catchAll; right: catchAll }
    margins.top: catchAll ? 0 : topGap
    exclusionMode: ExclusionMode.Ignore
    // Fixed size (the biggest it can get) so typing never reallocates the surface.
    implicitWidth: w + 40
    implicitHeight: fieldH + maxRows * rowH + 3 * 26 + 60
    color: "transparent"
    mask: Region { item: card; Region { item: win.catchAll ? catcher : null } }

    WlrLayershell.namespace: "island-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property bool armed: false
    Timer { interval: 60; running: true; onTriggered: win.armed = true }
    HyprlandFocusGrab { windows: [win]; active: Compositor.focusGrab && win.armed; onCleared: Popouts.closeOverlays() }
    MouseArea {
        id: catcher
        anchors.fill: parent
        z: -1
        visible: win.catchAll
        acceptedButtons: Qt.AllButtons
        onPressed: Popouts.closeOverlays()
    }

    // ── Search ────────────────────────────────────────────────────────
    property string query: ""
    property int index: 0
    readonly property string q: query.trim()
    readonly property bool cmd: q.startsWith(">") || q.startsWith("$")
    readonly property string calc: {
        if (cmd || !/^[\d\s+\-*/%().,^]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q)) return "";
        try {
            const v = Function('"use strict"; return (' + q.replace(/,/g, ".").replace(/\^/g, "**") + ")")();
            return typeof v === "number" && isFinite(v) ? String(Math.round(v * 1e10) / 1e10) : "";
        } catch (e) { return ""; }
    }
    readonly property var apps: q === "" || cmd ? [] : Apps.search(q).slice(0, 7)

    // Flat list of rows: { kind, section?, ... }
    readonly property var rows: {
        const out = [];
        if (q === "") return out;
        if (cmd) {
            const c = q.slice(1).trim();
            out.push({ kind: "cmd", title: c ? "Run  " + c : "Run a shell command", sub: "Shell", icon: "utilities-terminal", section: "Command", cmd: c });
            return out;
        }
        if (calc !== "") out.push({ kind: "calc", title: calc, sub: q + " =", icon: "accessories-calculator", section: "Calculator" });
        apps.forEach((e, i) => out.push({ kind: "app", entry: e, title: e.name, sub: e.genericName || e.comment || "", icon: e.icon,
                                          section: i === 0 ? (calc ? "Applications" : "Top Hit") : i === 1 && !calc ? "Applications" : "" }));
        out.push({ kind: "web", title: "Search the web for “" + q + "”", sub: "DuckDuckGo", icon: "web-browser", section: "Web" });
        return out;
    }
    onRowsChanged: index = 0

    function run(r) {
        if (!r) return;
        if (r.kind === "app") Apps.launch(r.entry);
        else if (r.kind === "cmd") { if (!r.cmd) return; Apps.run(r.cmd); }
        else if (r.kind === "calc") Quickshell.execDetached(["wl-copy", r.title]);
        else if (r.kind === "web") Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(q)]);
        Popouts.closeOverlays();
    }

    // ── Card ──────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: (win.catchAll ? win.topGap : 0) + 10
        width: win.w
        height: win.fieldH + (win.rows.length ? results.height + 8 : 0)
        radius: 26
        color: Qt.alpha(Theme.bg, 0.82)
        border { width: 1; color: Qt.alpha(Theme.text, 0.14) }
        clip: true

        opacity: 0; scale: 0.96
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Field
        Item {
            width: parent.width; height: win.fieldH
            Text {
                id: glass
                anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                text: ""; color: Theme.textDim
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 20 }
            }
            TextInput {
                id: input
                anchors { left: glass.right; leftMargin: 14; right: hint.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                focus: true
                clip: true
                color: Theme.text
                selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                font { family: win.family; pixelSize: 24; weight: Font.Light }
                Component.onCompleted: forceActiveFocus()
                onTextChanged: win.query = text
                Text {
                    visible: !input.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Spotlight Search"
                    color: Theme.textFaint
                    font: input.font
                }
                Keys.onPressed: e => {
                    const n = win.rows.length, ctrl = e.modifiers & Qt.ControlModifier;
                    if (e.key === Qt.Key_Escape) { if (input.text) input.text = ""; else Popouts.closeOverlays(); }
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || (ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N))) { if (n) win.index = (win.index + 1) % n; }
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || (ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P))) { if (n) win.index = (win.index + n - 1) % n; }
                    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && ctrl) { const r = win.rows[win.index]; if (r?.kind === "app") DockPins.toggle(r.entry.id); }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.run(win.rows[win.index]);
                    else return;
                    e.accepted = true;
                }
            }
            Text {
                id: hint
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                visible: win.rows[win.index]?.kind === "app"
                text: DockPins.has(win.rows[win.index]?.entry?.id ?? "") ? "⌃↵ Remove from Dock" : "⌃↵ Keep in Dock"
                color: Theme.textFaint
                font { family: win.family; pixelSize: 11 }
            }
        }

        Rectangle { visible: win.rows.length > 0; y: win.fieldH; width: parent.width; height: 1; color: Theme.hairline }

        // Results
        Column {
            id: results
            y: win.fieldH + 6
            x: 8
            width: parent.width - 16
            Repeater {
                model: win.rows
                delegate: Column {
                    id: rowCol
                    required property var modelData
                    required property int index
                    width: results.width
                    Text {
                        visible: !!rowCol.modelData.section
                        leftPadding: 12; topPadding: rowCol.index === 0 ? 2 : 6; bottomPadding: 3
                        text: rowCol.modelData.section ?? ""
                        color: Theme.textFaint
                        font { family: win.family; pixelSize: 11; weight: Font.Bold }
                    }
                    MouseArea {
                        id: row
                        readonly property bool hot: win.index === rowCol.index
                        readonly property bool topHit: rowCol.modelData.section === "Top Hit"
                        width: parent.width
                        height: topHit ? win.rowH + 10 : win.rowH
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.index = rowCol.index
                        onClicked: e => {
                            if (e.button === Qt.RightButton) { if (rowCol.modelData.kind === "app") DockPins.toggle(rowCol.modelData.entry.id); }
                            else win.run(rowCol.modelData);
                        }
                        Rectangle { anchors.fill: parent; radius: 10; color: row.hot ? Theme.accent : "transparent" }
                        Image {
                            id: ic
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: row.topHit ? 40 : 28; height: width
                            sourceSize { width: 40 * Screen.devicePixelRatio; height: 40 * Screen.devicePixelRatio }
                            source: Quickshell.iconPath(rowCol.modelData.icon ?? "", "application-x-executable")
                            asynchronous: true
                        }
                        Column {
                            anchors { left: ic.right; leftMargin: 12; right: pin.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 0
                            Text {
                                width: parent.width
                                text: rowCol.modelData.title
                                elide: Text.ElideRight
                                color: row.hot ? Theme.onAccent : Theme.text
                                font { family: win.family; pixelSize: rowCol.modelData.kind === "calc" ? 20 : row.topHit ? 16 : 14; weight: row.topHit ? Font.DemiBold : Font.Normal }
                            }
                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: rowCol.modelData.sub ?? ""
                                elide: Text.ElideRight
                                color: row.hot ? Qt.alpha(Theme.onAccent, 0.75) : Theme.textDim
                                font { family: win.family; pixelSize: 11 }
                            }
                        }
                        Text {
                            id: pin
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            visible: rowCol.modelData.kind === "app" && DockPins.has(rowCol.modelData.entry.id)
                            text: "In Dock"
                            color: row.hot ? Qt.alpha(Theme.onAccent, 0.75) : Theme.textFaint
                            font { family: win.family; pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }
}
