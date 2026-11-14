import QtQuick
import QtQuick.Window
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
import qs

// Wallpaper + Wallhaven + theme carousel, grown out of the bar. Thumbnails only exist while it's open.
//   ←/→ browse · Enter apply · Space preview · Tab switch · Esc close · / search (Wallhaven)
Item {
    id: root

    readonly property bool closeOnLeave: false
    readonly property string tab: Popouts.current === "themes" || Popouts.current === "wallhaven" ? Popouts.current : "wallpapers"
    readonly property bool onWalls: tab === "wallpapers"
    readonly property bool onHaven: tab === "wallhaven"
    readonly property var tabOrder: ["wallpapers", "wallhaven", "themes"]
    readonly property var view: onWalls ? wallView : onHaven ? havenView : themeView
    readonly property string home: Quickshell.env("HOME")
    readonly property string wallSetter: Quickshell.shellDir + "/scripts/wallpaper-set.sh"
    property string currentWall: ""
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/island/video-thumbs"
    property int thumbRev: 0

    implicitWidth: Math.min(Screen.width - 120, 1400)
    implicitHeight: tabs.height + 14 + searchBar.height + band.height + 14 + hints.implicitHeight + 6

    focus: true
    Component.onCompleted: { Theme.rescan(); thumbs.running = true; if (onHaven) havenStart(); }
    onTabChanged: if (onHaven) havenStart(); else root.forceActiveFocus()

    // ── Wallhaven ─────────────────────────────────────────────────────
    // Results come from scripts/wallhaven.sh (filters + API key handled there).
    ListModel { id: haven }
    property string havenQuery: ""
    property int havenPage: 0
    property int havenLast: 0
    property int havenTotal: 0
    property string havenSeed: ""
    property string havenError: ""
    property string havenBusy: ""          // id being downloaded; cleared when the wallpaper changes
    readonly property bool havenLoading: havenProc.running
    onCurrentWallChanged: havenBusy = ""

    function havenStart() {
        if (haven.count === 0 && !havenLoading) havenSearch(Config.values.wallhavenQuery ?? "");
    }
    function havenSearch(q) {
        havenQuery = q; havenSeed = ""; havenError = "";
        haven.clear();
        havenRow = {};
        thumbQueue = [];
        havenFetch(1);
    }
    property var havenRow: ({})            // wid → row in `haven`

    // Thumbnails and the big preview are fetched by the script (curl) into ~/.cache/island/wallhaven,
    // so Quickshell only ever opens local files and never loads Qt's network/TLS stack.
    property var thumbQueue: []            // [wid, url, wid, url, …] waiting for thumbProc
    function queueThumbs(items) {
        for (const it of items) thumbQueue.push(it.wid, it.thumb);
        runThumbs();
    }
    function runThumbs() {
        if (thumbProc.running || thumbQueue.length === 0) return;
        thumbProc.command = [Wallhaven.script, "thumbs"].concat(thumbQueue);
        thumbQueue = [];
        thumbProc.running = true;
    }
    Process {
        id: thumbProc
        stdout: SplitParser {             // one wid per line, as each file lands
            onRead: wid => { const i = root.havenRow[wid]; if (i !== undefined) haven.setProperty(i, "ready", true); }
        }
        onExited: root.runThumbs()
    }

    // Full image for the card you've settled on; only one is decoded at a time.
    property string previewId: ""
    property string previewPath: ""
    property var previewNext: null         // [wid, url] asked for while one was downloading
    function requestPreview(wid, url) {
        if (previewProc.running) { previewNext = [wid, url]; return; }
        previewNext = null;
        previewProc.wid = wid;
        previewProc.command = [Wallhaven.script, "preview", wid, url];
        previewProc.running = true;
    }
    Process {
        id: previewProc
        property string wid
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p !== "") { root.previewPath = p; root.previewId = previewProc.wid; } }
        }
        onExited: if (root.previewNext) root.requestPreview(root.previewNext[0], root.previewNext[1])
    }
    function havenFetch(page) {
        if (havenProc.running) return;
        havenProc.page = page;
        havenProc.command = [Wallhaven.script, "search", havenQuery, String(page), havenSeed];
        havenProc.running = true;
    }
    Process {
        id: havenProc
        property int page: 1
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { root.havenError = "Couldn't read Wallhaven's reply"; return; }
                if (r.error) { root.havenError = r.error; return; }
                root.havenPage = r.page; root.havenLast = r.last; root.havenTotal = r.total; root.havenSeed = r.seed || "";
                for (const it of r.items) { root.havenRow[it.wid] = haven.count; haven.append(it); }
                root.queueThumbs(r.items);
                if (havenProc.page === 1) havenView.currentIndex = 0;
            }
        }
    }

    // Posters for video wallpapers (cached by wallpaper-set.sh; only new videos cost anything).
    Process {
        id: thumbs
        command: [root.wallSetter, "--thumbs"]
        onExited: root.thumbRev++
    }

    function apply() {
        const i = view.currentIndex;
        if (i < 0) return;
        if (onWalls) Quickshell.execDetached([wallSetter, walls.get(i).filePath]);
        else if (onHaven) {
            const it = haven.get(i);
            if (it.file === currentWall) return;
            havenBusy = it.wid;
            // Detached: the download keeps going after the picker closes.
            Quickshell.execDetached([Wallhaven.script, "set", it.wid, it.full]);
        }
        else Theme.apply(Theme.themes[i].id);
    }
    function switchTab(back) {
        const n = tabOrder.length, i = tabOrder.indexOf(tab);
        Popouts.open(tabOrder[(i + (back ? n - 1 : 1)) % n], Popouts.screen);
    }

    property bool swallowEnter: false

    // Never let the popout be destroyed while the search field has focus: that crashes Qt's
    // input method (QInputMethod::commit). Closing starts here; destruction follows ~300 ms later.
    Connections {
        target: Popouts
        function onCurrentChanged() { if (!root.tabOrder.includes(Popouts.current)) root.forceActiveFocus(); }
    }

    Keys.onPressed: event => {
        if (swallowEnter && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            swallowEnter = false;
            event.accepted = true;
            return;
        }
        // While typing a search, only Tab / ↓ / Esc mean something to the picker.
        if (search.input.activeFocus) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) switchTab(event.key === Qt.Key_Backtab);
            else if (event.key === Qt.Key_Down) root.forceActiveFocus();
            else if (event.key === Qt.Key_Escape) { root.forceActiveFocus(); event.accepted = false; return; }
            else return;
            event.accepted = true;
            return;
        }
        if (onHaven && (event.key === Qt.Key_Slash || event.key === Qt.Key_Up)) {
            search.input.forceActiveFocus(); search.input.selectAll();
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_Tab: case Qt.Key_Backtab: switchTab(event.key === Qt.Key_Backtab); break;
        case Qt.Key_Left: case Qt.Key_H: view.decrementCurrentIndex(); break;
        case Qt.Key_Right: case Qt.Key_L: view.incrementCurrentIndex(); break;
        case Qt.Key_Home: view.currentIndex = 0; break;
        case Qt.Key_End: view.currentIndex = view.count - 1; break;
        case Qt.Key_Space: apply(); break;
        case Qt.Key_Return: case Qt.Key_Enter: apply(); Popouts.close(); break;
        default: return;
        }
        event.accepted = true;
    }

    // Written by wallpaper-set.sh; watched, never polled.
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/island/wallpaper"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: root.currentWall = text().trim()
    }

    // Images (wallDir) followed by videos (videoDir, played with mpvpaper).
    FolderListModel {
        id: imgs
        folder: "file://" + Config.wallDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.avif", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: Qt.callLater(root.rebuild)
        onCountChanged: Qt.callLater(root.rebuild)
    }
    FolderListModel {
        id: vids
        folder: "file://" + Config.videoDir
        nameFilters: ["*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.MP4", "*.WEBM", "*.MKV", "*.MOV"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: Qt.callLater(root.rebuild)
        onCountChanged: Qt.callLater(root.rebuild)
    }
    ListModel { id: walls }
    function rebuild() {
        if (imgs.status !== FolderListModel.Ready || vids.status !== FolderListModel.Ready) return;
        const items = [];
        for (let i = 0; i < imgs.count; i++)
            items.push({ filePath: imgs.get(i, "filePath"), fileBaseName: imgs.get(i, "fileBaseName"), video: false });
        for (let i = 0; i < vids.count; i++)
            items.push({ filePath: vids.get(i, "filePath"), fileBaseName: vids.get(i, "fileBaseName"), video: true });
        if (items.length === walls.count && items.every((it, i) => walls.get(i).filePath === it.filePath)) return;
        walls.clear();
        for (const it of items) walls.append(it);
    }

    // ── Tabs ──────────────────────────────────────────────────────────
    Row {
        id: tabs
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        height: 30
        spacing: 6
        Repeater {
            model: [["wallpapers", "Wallpapers"], ["wallhaven", "Wallhaven"], ["themes", "Themes"]]
            Rectangle {
                required property var modelData
                readonly property bool active: modelData[0] === root.tab
                width: label.implicitWidth + 30; height: 30; radius: 15
                color: active ? Theme.text : Theme.control
                Behavior on color { ColorAnimation { duration: 140 } }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData[1]
                    color: active ? Theme.bg : Theme.textDim
                    font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (!parent.active) Popouts.open(parent.modelData[0], Popouts.screen) }
            }
        }
    }

    // ── Wallhaven search ──────────────────────────────────────────────
    Item {
        id: searchBar
        anchors { top: tabs.bottom; topMargin: root.onHaven ? 12 : 0 }
        width: parent.width
        height: root.onHaven ? 30 : 0
        visible: root.onHaven
        TextField {
            id: search
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(420, parent.width - 40); height: 30
            text: root.havenQuery
            placeholder: "Search Wallhaven — tags, +include -exclude, @user, id:37   (Enter)"
            // Also fires on focus loss; only search when the text actually changed.
            onAccepted: {
                if (text !== root.havenQuery || root.havenError !== "") root.havenSearch(text);
                if (input.activeFocus) {
                    // TextInput passes Enter on to its parents after `accepted`; without this the
                    // same keypress reaches the picker as "apply + close".
                    root.swallowEnter = true;
                    Qt.callLater(() => root.swallowEnter = false);
                    root.forceActiveFocus();
                }
            }
        }
        Text {
            anchors { left: search.right; leftMargin: 10; verticalCenter: search.verticalCenter }
            visible: !Wallhaven.hasKey && Config.values.wallhavenNsfw === true
            text: "NSFW needs an API key (Settings → Wallpaper)"
            color: Theme.textDim
            font { family: Theme.font; pixelSize: 10 }
        }
    }

    // ── Carousel band ─────────────────────────────────────────────────
    Item {
        id: band
        anchors { top: searchBar.bottom; topMargin: 14 }
        width: parent.width
        height: Math.min(Math.round(Screen.height * 0.3), 320)
        clip: true

        Carousel {
            id: wallView
            anchors.fill: parent
            visible: root.onWalls
            itemWidth: Math.round(height * 16 / 9 * 0.9)
            model: walls
            onActivated: { root.apply(); Popouts.close(); }
            initialIndex: {
                for (let i = 0; i < walls.count; i++)
                    if (walls.get(i).filePath === root.currentWall) return i;
                return 0;
            }

            delegate: CarouselItem {
                id: wd
                required property string filePath
                required property bool video
                carousel: wallView
                accent: Theme.accent
                selected: filePath === root.currentWall

                Image {
                    id: wimg
                    anchors.fill: parent
                    source: "file://" + (wd.video ? root.thumbDir + "/" + Qt.md5(wd.filePath) + ".jpg" : wd.filePath)
                    // Decoded at the centre card's exact size (side cards are scaled down), off the GUI thread.
                    sourceSize { width: wd.width * Screen.devicePixelRatio; height: wd.height * Screen.devicePixelRatio }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false            // freed as soon as the picker closes
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    // A video's poster may only exist once the --thumbs run finishes.
                    Connections {
                        target: root
                        function onThumbRevChanged() {
                            if (wd.video && wimg.status !== Image.Ready) { const s = wimg.source; wimg.source = ""; wimg.source = s; }
                        }
                    }
                }

                // Video badge
                Rectangle {
                    visible: wd.video
                    anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                    width: 26; height: 26; radius: 13
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; text: "▶"; color: "white"; font.pixelSize: 11 }
                }
            }
        }

        Carousel {
            id: havenView
            anchors.fill: parent
            visible: root.onHaven
            itemWidth: Math.round(height * 16 / 9 * 0.9)
            model: haven
            onActivated: { root.apply(); Popouts.close(); }
            // Near the end: fetch the next page.
            onCurrentIndexChanged: if (count > 0 && currentIndex >= count - 4 && root.havenPage < root.havenLast) root.havenFetch(root.havenPage + 1)

            delegate: CarouselItem {
                id: hd
                required property string wid
                required property string tfile
                required property bool ready
                required property string full
                required property string file
                required property string res
                carousel: havenView
                accent: Theme.accent
                selected: file === root.currentWall

                // Small cached thumbnail as soon as it's on disk…
                Image {
                    anchors.fill: parent
                    source: hd.ready ? "file://" + hd.tfile : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                // …and the full image once you've settled on a card (dropped again when you move on).
                Timer { interval: 450; running: hd.current; onTriggered: root.requestPreview(hd.wid, hd.full) }
                Image {
                    anchors.fill: parent
                    source: hd.current && root.previewId === hd.wid ? "file://" + root.previewPath : ""
                    sourceSize { width: hd.width * Screen.devicePixelRatio; height: hd.height * Screen.devicePixelRatio }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }

                // Resolution badge
                Rectangle {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                    width: resText.implicitWidth + 16; height: 22; radius: 11
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text { id: resText; anchors.centerIn: parent; text: root.havenBusy === hd.wid ? "downloading…" : hd.res; color: "white"
                        font { family: Theme.font; pixelSize: 10; weight: Font.DemiBold } }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.onHaven && haven.count === 0
            text: root.havenLoading ? "Searching Wallhaven…" : root.havenError !== "" ? root.havenError : "No results"
            color: Theme.textDim
            font { family: Theme.font; pixelSize: 13 }
        }

        Carousel {
            id: themeView
            anchors.fill: parent
            visible: root.tab === "themes"
            itemWidth: Math.round(height * 1.25)
            model: Theme.themes
            onActivated: root.apply()
            initialIndex: Math.max(0, Theme.themes.findIndex(t => t.id === Theme.current))

            delegate: CarouselItem {
                id: td
                required property var modelData
                readonly property var t: modelData
                carousel: themeView
                accent: t.accent
                selected: t.id === Theme.current
                fill: t.bg

                // Mini "window" preview drawn in the theme's own colours.
                Rectangle {
                    anchors { fill: parent; margins: parent.height * 0.1; bottomMargin: parent.height * 0.3 }
                    color: td.t.bg_alt
                    border { width: 1; color: td.t.overlay }
                    Rectangle {
                        id: bar
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                        height: parent.height * 0.2
                        color: td.t.surface
                        Row {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 5
                            Repeater {
                                model: [td.t.red, td.t.yellow, td.t.green]
                                Rectangle { required property var modelData; width: 8; height: 8; radius: 4; color: modelData }
                            }
                        }
                    }
                    Column {
                        anchors { left: parent.left; top: bar.bottom; margins: 12 }
                        spacing: 7
                        Repeater {
                            model: [0.7, 0.45, 0.55]
                            Rectangle { required property var modelData; required property int index
                                width: (td.width * 0.8 - 24) * modelData; height: 6; radius: 3
                                color: index === 0 ? td.t.fg : td.t.fg_faint }
                        }
                    }
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                        width: 54; height: 20; radius: 4
                        color: td.t.accent
                        Text { anchors.centerIn: parent; text: "OK"; color: td.t.accent_fg
                            font { family: Theme.font; pixelSize: 10; weight: Font.Bold } }
                    }
                }
                Text {
                    anchors { left: parent.left; bottom: swatches.top; margins: parent.height * 0.1; bottomMargin: 6 }
                    text: td.t.name
                    color: td.t.fg
                    font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
                }
                Row {
                    id: swatches
                    anchors { left: parent.left; bottom: parent.bottom; margins: parent.height * 0.1; bottomMargin: parent.height * 0.08 }
                    spacing: 6
                    Repeater {
                        model: [td.t.accent, td.t.red, td.t.yellow, td.t.green, td.t.cyan, td.t.blue, td.t.magenta]
                        Rectangle { required property var modelData; width: 14; height: 14; radius: 7; color: modelData }
                    }
                }
            }
        }
    }

    // ── Caption + hints ───────────────────────────────────────────────
    Column {
        id: hints
        anchors { horizontalCenter: parent.horizontalCenter; top: band.bottom; topMargin: 14 }
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.onWalls
                ? (wallView.currentIndex >= 0 && walls.count ? walls.get(wallView.currentIndex).fileBaseName + (walls.get(wallView.currentIndex).video ? "  ·  video" : "") : "No images in " + Config.wallDir.replace(root.home, "~"))
                : root.onHaven
                ? (havenView.currentIndex >= 0 && haven.count ? (() => { const it = haven.get(havenView.currentIndex);
                      if (!it) return " ";
                      return it.wid + "  ·  " + it.res + "  ·  " + it.category + (it.purity !== "sfw" ? "  ·  " + it.purity : "")
                           + "  ·  ♥ " + it.favs + "      " + (havenView.currentIndex + 1) + " / " + root.havenTotal
                           + (root.havenError !== "" ? "      " + root.havenError : ""); })()
                   : " ")
                : (Theme.themes[themeView.currentIndex]?.name ?? "")
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.onHaven
                ? "←/→ browse   enter download + apply   space preview   / search   tab switch   esc close"
                : "←/→ browse   enter apply   space preview   tab switch   esc close"
            color: Theme.textDim
            font { family: Theme.font; pixelSize: 10 }
        }
    }
}
