import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.services

// Launchpad: every app in a full-screen paged grid over the blurred desktop, with a search
// field on top and page dots below. Scroll, swipe or ←/→ to change page; type to filter;
// click empty space or Esc to close; right-click an app to keep it in the Dock.
// Only exists while open (it's a full-screen surface, so it's freed as soon as it closes).
PanelWindow {
    id: win

    readonly property string family: Config.saved.widgetFont || "Adwaita Sans"
    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property int cols: 7
    readonly property int rows: 5
    readonly property int perPage: cols * rows
    readonly property int icon: Math.round(Math.min(sw / cols, (sh - 220) / rows) * 0.5)
    readonly property real cellW: Math.min(sw * 0.8, icon * 2.2 * cols) / cols
    readonly property real cellH: (sh - 330) / rows      // fits between the search field and the page dots

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "island-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string query: ""
    readonly property var apps: query.trim() ? Apps.search(query) : Apps.apps
    readonly property int pages: Math.max(1, Math.ceil(apps.length / perPage))
    property int page: 0
    onAppsChanged: { page = 0; sel = query.trim() ? 0 : -1; }
    property int sel: -1          // keyboard selection while searching
    property var menuApp: null

    function close() { Popouts.closeOverlays(); }
    function go(p) { page = Math.max(0, Math.min(pages - 1, p)); }
    function launch(e) { Apps.launch(e); close(); }

    // Dim + Hyprland blur behind. The open/close zoom-fade is a Hyprland layer animation
    // (island-launchpad-anim in hypr/island.lua): Island renders on the CPU, where animating a
    // full-screen surface is ~20 fps, while the compositor does it on the GPU for free.
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.38)
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: { if (win.menuApp) win.menuApp = null; else win.close(); } }

    Item {
        id: content
        anchors.fill: parent

        // Search field
        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            y: 56
            width: 260; height: 30; radius: 9
            color: Qt.rgba(1, 1, 1, 0.14)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.18) }
            Row {
                anchors.centerIn: parent
                spacing: 6
                visible: !input.text
                Text { text: ""; color: Qt.rgba(1, 1, 1, 0.6); anchors.verticalCenter: parent.verticalCenter
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } }
                Text { text: "Search"; color: Qt.rgba(1, 1, 1, 0.6); font { family: win.family; pixelSize: 14 } }
            }
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                clip: true
                color: "white"
                selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                font { family: win.family; pixelSize: 14 }
                Component.onCompleted: forceActiveFocus()
                onTextChanged: win.query = text
                Keys.onPressed: e => {
                    const searching = win.query.trim() !== "";
                    if (e.key === Qt.Key_Escape) { if (win.menuApp) win.menuApp = null; else if (input.text) input.text = ""; else win.close(); }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { const a = win.apps[Math.max(0, win.sel)]; if (searching && a) win.launch(a); }
                    else if (e.key === Qt.Key_Right && (!searching || win.sel < 0)) win.go(win.page + 1);
                    else if (e.key === Qt.Key_Left && (!searching || win.sel < 0)) win.go(win.page - 1);
                    else if (searching && e.key === Qt.Key_Right) win.sel = Math.min(win.apps.length - 1, win.sel + 1);
                    else if (searching && e.key === Qt.Key_Left) win.sel = Math.max(0, win.sel - 1);
                    else if (searching && e.key === Qt.Key_Down) win.sel = Math.min(win.apps.length - 1, win.sel + win.cols);
                    else if (searching && e.key === Qt.Key_Up) win.sel = Math.max(0, win.sel - win.cols);
                    else if (e.key === Qt.Key_PageDown) win.go(win.page + 1);
                    else if (e.key === Qt.Key_PageUp) win.go(win.page - 1);
                    else return;
                    e.accepted = true;
                }
            }
        }

        // Pages
        ListView {
            id: pager
            anchors { left: parent.left; right: parent.right; top: field.bottom; topMargin: 40; bottom: dots.top; bottomMargin: 20 }
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 260
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: width                 // neighbours prebuilt, so a swipe doesn't stall creating 35 icons
            reuseItems: true
            model: win.pages
            currentIndex: win.page
            onCurrentIndexChanged: win.page = currentIndex
            interactive: true

            delegate: Item {
                id: pageItem
                required property int index
                width: pager.width; height: pager.height
                // While sliding, draw the page from a cached image: the CPU renderer then just
                // blits one picture per frame instead of redrawing every icon and label.
                layer.enabled: pager.moving
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: { if (win.menuApp) win.menuApp = null; else win.close(); } }
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: win.cols
                    Repeater {
                        model: win.apps.slice(pageItem.index * win.perPage, (pageItem.index + 1) * win.perPage)
                        delegate: MouseArea {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property int flat: pageItem.index * win.perPage + index
                            width: win.cellW; height: win.cellH
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: e => {
                                if (e.button === Qt.RightButton) { win.menuApp = modelData; menu.at = mapToItem(content, width / 2, win.icon + 8); }
                                else win.launch(modelData);
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 4; width: win.icon + 16; height: win.icon + 16; radius: 18
                                color: Qt.rgba(1, 1, 1, 0.16)
                                visible: win.sel === cell.flat
                            }
                            Image {
                                id: img
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 12
                                width: win.icon; height: win.icon
                                sourceSize { width: win.icon * Screen.devicePixelRatio; height: win.icon * Screen.devicePixelRatio }
                                source: AppIcons.source(cell.modelData.icon)
                                asynchronous: true
                                scale: cell.pressed ? 0.9 : 1
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; top: img.bottom; topMargin: 10 }
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.name
                                elide: Text.ElideRight
                                color: "white"
                                style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
                                font { family: win.family; pixelSize: 13; weight: Font.Medium }
                            }
                        }
                    }
                }
            }

            WheelHandler {
                property real acc: 0
                onWheel: e => {
                    acc += (e.angleDelta.y || e.angleDelta.x);
                    if (Math.abs(acc) >= 120) { win.go(win.page + (acc < 0 ? 1 : -1)); acc = 0; }
                }
            }
        }

        Text {
            visible: win.apps.length === 0
            anchors.centerIn: pager
            text: "No Results"
            color: Qt.rgba(1, 1, 1, 0.7)
            font { family: win.family; pixelSize: 22; weight: Font.Light }
        }

        // Page dots
        Row {
            id: dots
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 150 }
            spacing: 10
            visible: win.pages > 1
            Repeater {
                model: win.pages
                MouseArea {
                    required property int index
                    width: 8; height: 8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.go(index)
                    Rectangle { anchors.fill: parent; radius: 4; color: index === win.page ? "white" : Qt.rgba(1, 1, 1, 0.35) }
                }
            }
        }

        // Right-click menu
        Rectangle {
            id: menu
            property point at: Qt.point(0, 0)
            visible: win.menuApp !== null
            x: Math.max(8, Math.min(win.width - width - 8, at.x - width / 2))
            y: at.y + 8
            width: 190; height: mcol.implicitHeight + 10
            radius: 12
            color: Qt.alpha(Theme.bg, 0.96)
            border { width: 1; color: Qt.alpha(Theme.text, 0.14) }
            Column {
                id: mcol
                x: 5; y: 5; width: parent.width - 10
                Repeater {
                    model: win.menuApp ? [
                        { text: "Open", f: () => win.launch(win.menuApp) },
                        { text: DockPins.has(win.menuApp.id) ? "Remove from Dock" : "Keep in Dock", f: () => { DockPins.toggle(win.menuApp.id); win.menuApp = null; } }
                    ] : []
                    MouseArea {
                        id: mi
                        required property var modelData
                        width: mcol.width; height: 28
                        hoverEnabled: true
                        onClicked: modelData.f()
                        Rectangle { anchors.fill: parent; radius: 6; color: mi.containsMouse ? Theme.accent : "transparent" }
                        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: mi.modelData.text; color: mi.containsMouse ? Theme.onAccent : Theme.text
                            font { family: win.family; pixelSize: 13 } }
                    }
                }
            }
        }
    }
}
