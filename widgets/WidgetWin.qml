import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

// One desktop widget in its own card-sized layer surface, anchored to the corner or its saved spot.
// Dragging moves margins only, never the size: resizing mid-drag made Hyprland drop the pointer grab.
PanelWindow {
    id: win

    required property string wid
    required property Component content

    readonly property int pad: WidgetLayout.tahoe ? 0 : 14        // Classic shadow room
    readonly property int cw: WidgetLayout.width(wid)
    readonly property int ch: WidgetLayout.height(wid)
    readonly property var p: WidgetLayout.pos(wid)
    readonly property bool auto: p === null
    readonly property var o: WidgetLayout.autoOffset(wid)
    readonly property bool fromRight: auto && WidgetLayout.onRight
    readonly property bool fromBottom: auto && WidgetLayout.onBottom

    // card's distance from the anchored edges (kept on screen if the monitor shrank)
    readonly property int nx: auto ? o[0] : Math.max(0, Math.min(p[0], (screen?.width ?? 1e5) - cw))
    readonly property int ny: auto ? o[1] : Math.max(0, Math.min(p[1], (screen?.height ?? 1e5) - ch))
    // the surface starts `pad` before the card, but never past the edge
    readonly property int wx: Math.max(0, nx - pad)
    readonly property int wy: Math.max(0, ny - pad)

    anchors { left: !fromRight; right: fromRight; top: !fromBottom; bottom: fromBottom }
    margins { left: fromRight ? 0 : wx; right: fromRight ? wx : 0; top: fromBottom ? 0 : wy; bottom: fromBottom ? wy : 0 }
    exclusionMode: ExclusionMode.Normal      // stay clear of the bar
    exclusiveZone: 0
    implicitWidth: cw + (nx - wx) + pad
    implicitHeight: ch + (ny - wy) + pad
    color: "transparent"

    WlrLayershell.namespace: "island-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // No input while editing (the editor on top takes the drags); otherwise just the card.
    mask: WidgetLayout.editing ? none : cardRegion
    Region { id: none }
    Region { id: cardRegion; item: card }

    // direct drag
    // Desktop area in Hyprland's global coordinates: monitor minus the bar/dock reserved space.
    property real ox: 0
    property real oy: 0
    property real aw: 0
    property real ah: 0
    property point grab                      // pointer inside the card at press
    property bool free: false                // Shift held → no snapping

    function beginDrag() {
        const m = Hyprland.monitorFor(screen)?.lastIpcObject ?? {};
        const r = m.reserved ?? [0, 0, 0, 0];
        ox = (m.x ?? 0) + r[0];
        oy = (m.y ?? 0) + r[1];
        aw = (screen?.width ?? 1920) - r[0] - r[2];
        ah = (screen?.height ?? 1080) - r[1] - r[3];
        WidgetLayout.startDrag(wid, screen?.name ?? "");
        HyprCursor.query();
    }

    Connections {
        target: drag.active ? HyprCursor : null
        function onMoved(x, y) {
            if (!drag.active) return;
            WidgetLayout.place(win.wid, x - win.ox - win.grab.x, y - win.oy - win.grab.y,
                               win.free, win.aw, win.ah, WidgetLayout.resolved(win.aw, win.ah));
        }
    }

    Item {
        id: holder
        x: win.fromRight ? win.pad : win.nx - win.wx
        y: win.fromBottom ? win.pad : win.ny - win.wy
        width: card.width; height: card.height

        // Right-click anywhere on a widget → its menu (size, edit, remove). Sits under the
        // card's own mouse areas, which only take left/middle clicks, so right-clicks fall
        // through to it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: e => { win.menuAt = Qt.point(e.x, e.y); menuLoader.active = true; }
        }
        Loader {
            id: card
            sourceComponent: win.content
        }

        // Left-drag moves the widget. Sits on top with only a passive grab, so presses still
        // reach the widget's own mouse areas; it takes over once the pointer passes the drag
        // threshold, so clicks keep working.
        Item {
            anchors.fill: parent
            DragHandler {
                id: drag
                target: null
                acceptedButtons: Qt.LeftButton
                dragThreshold: 4
                enabled: !WidgetLayout.editing
                cursorShape: Qt.ClosedHandCursor
                onActiveChanged: {
                    if (active) {
                        const pr = drag.centroid.pressPosition;      // card coords
                        win.grab = Qt.point(pr.x, pr.y);
                        win.beginDrag();
                    } else {
                        WidgetLayout.endDrag(WidgetLayout.resolved(win.aw, win.ah));
                    }
                }
                onCentroidChanged: {
                    if (!active) return;
                    win.free = (drag.centroid.modifiers & Qt.ShiftModifier) !== 0;
                    HyprCursor.query();
                }
            }
        }
    }

    // right-click menu (a popup on this surface; exists only while open)
    property point menuAt
    readonly property var sizeNames: [["s", "Small"], ["m", "Medium"], ["l", "Large"]]
    LazyLoader {
        id: menuLoader
        active: false
        PopupWindow {
            id: menu
            visible: true
            onVisibleChanged: if (!visible) menuLoader.active = false
            grabFocus: true
            color: "transparent"
            anchor.item: holder
            anchor.rect: Qt.rect(win.menuAt.x, win.menuAt.y, 1, 1)
            anchor.edges: Edges.Top | Edges.Left
            anchor.gravity: Edges.Bottom | Edges.Right
            anchor.adjustment: PopupAdjustment.All
            implicitWidth: list.implicitWidth + 10
            implicitHeight: list.implicitHeight + 10
            Rectangle {
                anchors.fill: parent
                radius: 10
                antialiasing: true
                color: Theme.menuBg
                border { width: 1; color: Theme.menuEdge }
                MenuList {
                    id: list
                    x: 5; y: 5
                    minWidth: 170
                    items: win.sizeNames.map(n => ({ text: n[1], check: WidgetLayout.size(win.wid) === n[0],
                                                     f: () => WidgetLayout.setSize(win.wid, n[0]) }))
                           .concat([{ sep: true },
                                    { text: "Edit Widgets…", f: () => WidgetLayout.edit(win.screen?.name ?? "") },
                                    { text: "Remove Widget", f: () => WidgetLayout.remove(win.wid) }])
                    onDone: menu.visible = false
                }
            }
        }
    }
}
