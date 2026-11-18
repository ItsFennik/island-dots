import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Desktop icons (setting desktopIcons), macOS style, in a column on the side the desktop
// widgets aren't on: Trash, mounted drives (the system drive, USB sticks, anything under
// /run/media, /media or /mnt), then the Dock's apps (desktopIconsApps).
// Click selects, double-click opens; right-click a removable drive for Eject.
// App icons follow Appearance → Icon style; drives and Trash keep their WhiteSur look with a thin rim.
PanelWindow {
    id: win

    required property ShellScreen modelData
    screen: modelData

    readonly property var s: Config.saved
    readonly property bool primary: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData
    readonly property bool onRight: !(s.widgets ?? true) ? false : !(s.widgetsPosition ?? "top-left").endsWith("right")
    readonly property int icon: s.desktopIconSize ?? 56
    readonly property int cellW: icon + 44
    property string selected: ""
    property string ejectFor: ""

    visible: (s.desktopIcons ?? false) && primary
    anchors { top: true; left: !onRight; right: onRight }
    margins { top: 16; left: 16; right: 16 }
    exclusionMode: ExclusionMode.Normal      // stay clear of the bar
    exclusiveZone: 0
    implicitWidth: cellW
    implicitHeight: col.implicitHeight
    color: "transparent"

    WlrLayershell.namespace: "island-desktop-icons"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ── Drives + Trash (polled; cheap, and only while the icons are on) ──
    property var drives: []
    property bool trashFull: false
    Process {
        id: probe
        command: ["sh", "-c", 'lsblk -J -o NAME,LABEL,MOUNTPOINT,RM,HOTPLUG,PATH 2>/dev/null; printf "\\n@@"; ls -A "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" 2>/dev/null | head -c1']
        stdout: StdioCollector {
            onStreamFinished: {
                const [json, trash] = text.split("\n@@");
                win.trashFull = (trash ?? "").length > 0;
                let tree;
                try { tree = JSON.parse(json).blockdevices ?? []; } catch (e) { return; }
                const out = [];
                const walk = list => {
                    for (const d of list ?? []) {
                        const mp = d.mountpoint ?? "";
                        const removable = d.rm || d.hotplug;
                        if (mp && mp !== "[SWAP]" && !mp.startsWith("/boot")
                            && (mp === "/" || removable || /^\/(run\/media|media|mnt)\//.test(mp)))
                            out.push({ id: "drive:" + d.path, name: d.label || d.name, mount: mp, dev: d.path, removable: mp !== "/" });
                        walk(d.children);
                    }
                };
                walk(tree);
                out.sort((a, b) => (a.mount === "/" ? -1 : b.mount === "/" ? 1 : a.name.localeCompare(b.name)));
                if (JSON.stringify(out) !== JSON.stringify(win.drives)) win.drives = out;
            }
        }
    }
    Timer { interval: 4000; running: win.visible; repeat: true; triggeredOnStart: true; onTriggered: probe.running = true }

    readonly property var items: {
        void DesktopEntries.applications.values; // rebuild (fresh entry objects) after a rescan
        const out = [{ id: "island:trash", kind: "trash", name: "Trash", icon: trashFull ? "user-trash-full" : "user-trash" }];
        for (const d of drives) out.push(Object.assign({ kind: "drive", icon: "drive-harddisk" }, d));
        if (s.desktopIconsApps ?? true)
            for (const id of DockPins.ids) {
                const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
                if (e) out.push({ id: e.id, kind: "app", name: e.name, icon: e.icon, entry: e });
            }
        return out;
    }

    function open(it) {
        if (it.kind === "app") Apps.launch(it.entry, it.id);
        else if (it.kind === "trash") Quickshell.execDetached(["gio", "open", "trash:///"]);
        else Quickshell.execDetached(["xdg-open", it.mount]);
        selected = ""; ejectFor = "";
    }
    function eject(it) {
        Quickshell.execDetached(["udisksctl", "unmount", "-b", it.dev]);
        ejectFor = ""; selected = "";
        refresh.restart();
    }
    Timer { id: refresh; interval: 800; onTriggered: probe.running = true }

    Column {
        id: col
        spacing: 12
        Repeater {
            model: win.items
            MouseArea {
                id: cell
                required property var modelData
                readonly property bool sel: win.selected === modelData.id
                width: win.cellW
                height: win.icon + label.height + 16
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: e => {
                    win.selected = modelData.id;
                    win.ejectFor = e.button === Qt.RightButton && modelData.removable ? modelData.id : "";
                }
                onDoubleClicked: e => { if (e.button === Qt.LeftButton) win.open(modelData); }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: win.icon + 10; height: win.icon + 10; radius: 10
                    color: cell.sel ? Qt.rgba(0, 0, 0, 0.25) : "transparent"
                    border { width: cell.sel ? 1 : 0; color: Qt.rgba(1, 1, 1, 0.25) }
                }
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 5
                    width: win.icon; height: win.icon
                    // drives + Trash: the real WhiteSur icon with a thin light rim
                    source: cell.modelData.kind === "app" ? AppIcons.source(cell.modelData.icon)
                          : AppIcons.source(cell.modelData.icon, "drive-harddisk", "border")
                    sourceSize { width: win.icon * 2; height: win.icon * 2 }
                    smooth: true; mipmap: true
                    asynchronous: true
                    opacity: cell.pressed ? 0.7 : 1
                }
                Rectangle {
                    anchors { fill: label; margins: -3 }
                    radius: 4
                    color: cell.sel ? Theme.accent : "transparent"
                }
                Text {
                    id: label
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.icon + 13
                    width: Math.min(implicitWidth, win.cellW - 6)
                    text: cell.modelData.name
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    color: cell.sel ? Theme.onAccent : "white"
                    style: cell.sel ? Text.Normal : Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.4)
                    font { family: Theme.font; pixelSize: 12; weight: Font.Bold }
                }

                // Eject (right-click on a removable drive)
                Rectangle {
                    visible: win.ejectFor === cell.modelData.id
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: win.icon * 0.35 }
                    width: ejectText.implicitWidth + 20; height: 24; radius: 7
                    color: Theme.menuBg
                    border { width: 1; color: Theme.menuEdge }
                    Text { id: ejectText; anchors.centerIn: parent; text: "⏏  Eject"; color: Theme.menuText; font { family: Theme.font; pixelSize: 12 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.eject(cell.modelData) }
                }
            }
        }
    }
}
