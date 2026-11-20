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
    implicitHeight: tabs.height + 14 + searchBar.height + band.height + strip.height + strip.anchors.topMargin + 14 + hints.implicitHeight + 6

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

    // ── Theme → paired wallpapers (services/ThemeWalls.qml) ────────────
    // Enter on a theme applies it and drops into the wallpaper row below; Enter there sets the
    // wallpaper and closes. ↓/↑ move between the rows.
    readonly property bool onThemes: tab === "themes"
    readonly property var centredTheme: Theme.themes[themeView.currentIndex] ?? null
    readonly property var themeWalls: onThemes && centredTheme ? ThemeWalls.forTheme(centredTheme.id) : []
    property bool stripFocus: false
    property int stripIndex: 0
    onThemeWallsChanged: { stripFocus = false; stripIndex = Math.max(0, themeWalls.indexOf(currentWall)); }

    function isVideo(p) { return /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(p); }

    // A hand-picked theme replaces wallpaper colours (same as Settings' theme cards). Returns true
    // if matugen was on, so the caller can hold the wallpaper back until that setting is saved
    // (otherwise wallpaper-set.sh would rebuild matugen and re-apply it over this theme).
    function applyTheme(id) {
        const wasMatugen = id !== "matugen" && (Config.saved.matugen || Config.values.matugen);
        if (wasMatugen) Config.commit("matugen", false);
        if (id !== Theme.current) Theme.apply(id);
        return wasMatugen;
    }
    property string lastRandom: ""         // set by themeRandom(); not yet in the state file
    function applyThemeWall() {
        const t = centredTheme, w = themeWalls[stripIndex];
        if (!t || !w) return;
        const wait = applyTheme(t.id);
        if (w === currentWall || w === lastRandom) return;
        lastRandom = "";
        ThemeWalls.setWall(w, wait);
    }
    // Apply the centred theme plus a random wallpaper of its own; highlight that one in the row.
    function themeRandom() {
        if (!centredTheme) return "";
        const w = ThemeWalls.applyRandom(centredTheme.id, applyTheme(centredTheme.id));
        lastRandom = w;
        if (w) stripIndex = Math.max(0, themeWalls.indexOf(w));
        return w;
    }
    function themeEnter() {
        if (stripFocus) { applyThemeWall(); Popouts.close(); return; }
        if (themeRandom()) stripFocus = true;
        else Popouts.close();
    }

    function apply() {
        const i = view.currentIndex;
        if (i < 0) return;
        if (onThemes && stripFocus) { applyThemeWall(); return; }
        if (onWalls && walls.get(i).isDir) openFolder(walls.get(i).fileBaseName);
        else if (onWalls) Quickshell.execDetached([wallSetter, walls.get(i).filePath]);
        else if (onHaven) {
            const it = haven.get(i);
            if (it.file === currentWall) return;
            havenBusy = it.wid;
            // Detached: the download keeps going after the picker closes.
            Quickshell.execDetached([Wallhaven.script, "set", it.wid, it.full]);
        }
        else themeRandom();                 // Space again re-rolls the wallpaper
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
        // Wallpaper row under the theme carousel.
        if (onThemes && stripFocus) {
            const n = themeWalls.length;
            switch (event.key) {
            case Qt.Key_Left: case Qt.Key_H: stripIndex = Math.max(0, stripIndex - 1); break;
            case Qt.Key_Right: case Qt.Key_L: stripIndex = Math.min(n - 1, stripIndex + 1); break;
            case Qt.Key_Home: stripIndex = 0; break;
            case Qt.Key_End: stripIndex = n - 1; break;
            case Qt.Key_Up: case Qt.Key_K: stripFocus = false; break;
            case Qt.Key_Escape: stripFocus = false; break;
            case Qt.Key_Space: applyThemeWall(); break;
            case Qt.Key_Return: case Qt.Key_Enter: themeEnter(); break;
            case Qt.Key_Tab: case Qt.Key_Backtab: switchTab(event.key === Qt.Key_Backtab); break;
            default: return;
            }
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_Tab: case Qt.Key_Backtab: switchTab(event.key === Qt.Key_Backtab); break;
        case Qt.Key_Left: case Qt.Key_H: view.decrementCurrentIndex(); break;
        case Qt.Key_Right: case Qt.Key_L: view.incrementCurrentIndex(); break;
        case Qt.Key_Home: view.currentIndex = 0; break;
        case Qt.Key_End: view.currentIndex = view.count - 1; break;
        case Qt.Key_Down: case Qt.Key_J:
            if (!onThemes || !themeWalls.length) return;
            stripFocus = true; break;
        case Qt.Key_P:
            // Pair / unpair the highlighted wallpaper with the current theme.
            if (!onWalls || wallView.currentIndex < 0 || walls.get(wallView.currentIndex).isDir) return;
            ThemeWalls.toggle(Theme.current, walls.get(wallView.currentIndex).filePath); break;
        case Qt.Key_Backspace: case Qt.Key_Escape:
            if (!onWalls || !inFolder) return;
            closeFolder(); break;
        case Qt.Key_Space: apply(); break;
        case Qt.Key_Return: case Qt.Key_Enter:
            if (onThemes) themeEnter();
            else if (onWalls && wallView.currentIndex >= 0 && walls.get(wallView.currentIndex)?.isDir) apply();
            else { apply(); Popouts.close(); }
            break;
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

    // Subfolders of wallDir / videoDir show as folder cards (named after the theme when the folder
    // is a theme id); Enter opens one, Backspace/Esc goes back. Loose files sit after the folders.
    // Inside a folder: its images (wallDir/<folder>) followed by its videos (videoDir/<folder>).
    readonly property var imageFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.avif", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]
    property string wallFolder: ""         // "" = top level
    property string wantSel: ""            // path to select once the model is rebuilt
    readonly property bool inFolder: wallFolder !== ""
    function folderName(n) { return Theme.themes.find(t => t.id === n)?.name ?? n; }
    function openFolder(n) { wantSel = ""; wallFolder = n; }
    function closeFolder() { wantSel = Config.wallDir + "/" + wallFolder; wallFolder = ""; }

    FolderListModel {
        id: imgs
        folder: "file://" + Config.wallDir + (root.inFolder ? "/" + root.wallFolder : "")
        nameFilters: root.imageFilters
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: Qt.callLater(root.rebuild)
        onCountChanged: Qt.callLater(root.rebuild)
    }
    FolderListModel {
        id: vids
        folder: "file://" + Config.videoDir + (root.inFolder ? "/" + root.wallFolder : "")
        nameFilters: ["*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.MP4", "*.WEBM", "*.MKV", "*.MOV"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: Qt.callLater(root.rebuild)
        onCountChanged: Qt.callLater(root.rebuild)
    }
    FolderListModel {
        id: imgDirs
        folder: "file://" + Config.wallDir
        showFiles: false
        sortField: FolderListModel.Name
        onStatusChanged: Qt.callLater(root.rebuild)
        onCountChanged: Qt.callLater(root.rebuild)
    }
    FolderListModel {
        id: vidDirs
        folder: "file://" + Config.videoDir
        showFiles: false
        sortField: FolderListModel.Name
        onStatusChanged: Qt.callLater(root.rebuild)
        onCountChanged: Qt.callLater(root.rebuild)
    }
    ListModel { id: walls }
    function rebuild() {
        if ([imgs, vids, imgDirs, vidDirs].some(m => m.status === FolderListModel.Loading)) return;
        const items = [];
        if (!inFolder) {
            // Folders from both roots, merged by name; the card opens wallDir/<name> + videoDir/<name>.
            const names = [];
            for (const m of [imgDirs, vidDirs])
                for (let i = 0; i < m.count; i++) { const n = m.get(i, "fileName"); if (!names.includes(n)) names.push(n); }
            names.sort((a, b) => folderName(a).localeCompare(folderName(b)));
            for (const n of names)
                items.push({ filePath: Config.wallDir + "/" + n, fileBaseName: n, video: false, isDir: true });
        }
        for (let i = 0; i < imgs.count; i++)
            items.push({ filePath: imgs.get(i, "filePath"), fileBaseName: imgs.get(i, "fileBaseName"), video: false, isDir: false });
        for (let i = 0; i < vids.count; i++)
            items.push({ filePath: vids.get(i, "filePath"), fileBaseName: vids.get(i, "fileBaseName"), video: true, isDir: false });
        if (items.length !== walls.count || !items.every((it, i) => walls.get(i).filePath === it.filePath)) {
            walls.clear();
            for (const it of items) walls.append(it);
        }
        // Select what we came back from, else the current wallpaper (or its folder), else the first.
        let sel = items.findIndex(it => it.filePath === wantSel);
        if (sel < 0) sel = items.findIndex(it => it.isDir ? wallInDir(it.fileBaseName) : it.filePath === currentWall);
        wantSel = "";
        wallView.currentIndex = Math.max(0, sel);
        wallView.positionViewAtIndex(wallView.currentIndex, ListView.Center);
    }
    function wallInDir(n) {
        return currentWall.startsWith(Config.wallDir + "/" + n + "/") || currentWall.startsWith(Config.videoDir + "/" + n + "/");
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
            onActivated: { const it = walls.get(currentIndex); root.apply(); if (!it?.isDir) Popouts.close(); }
            initialIndex: {
                for (let i = 0; i < walls.count; i++) {
                    const it = walls.get(i);
                    if (it.isDir ? root.wallInDir(it.fileBaseName) : it.filePath === root.currentWall) return i;
                }
                return 0;
            }

            delegate: CarouselItem {
                id: wd
                required property string filePath
                required property string fileBaseName
                required property bool video
                required property bool isDir
                carousel: wallView
                accent: Theme.accent
                selected: isDir ? root.wallInDir(fileBaseName) : filePath === root.currentWall

                // A folder's cover is its first image (only listed while the card exists).
                FolderListModel {
                    id: cover
                    folder: wd.isDir ? "file://" + wd.filePath : ""
                    nameFilters: root.imageFilters
                    showDirs: false
                    sortField: FolderListModel.Name
                }
                readonly property string coverPath: isDir && cover.count > 0 ? cover.get(0, "filePath") : ""

                Image {
                    id: wimg
                    anchors.fill: parent
                    source: wd.isDir ? (wd.coverPath ? "file://" + wd.coverPath : "")
                        : "file://" + (wd.video ? root.thumbDir + "/" + Qt.md5(wd.filePath) + ".jpg" : wd.filePath)
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

                // Folder: dark band along the bottom with the theme's name and item count.
                Rectangle {
                    visible: wd.isDir
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 54
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "📁"; font.pixelSize: 20 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: wd.isDir ? root.folderName(wd.fileBaseName) : ""; color: "white"
                                font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold } }
                            Text { text: cover.count + (cover.count === 1 ? " picture" : " pictures"); color: Qt.rgba(1, 1, 1, 0.7)
                                font { family: Theme.font; pixelSize: 11 } }
                        }
                    }
                }

                // Paired with the current theme (P toggles)
                Rectangle {
                    visible: !wd.isDir && ThemeWalls.has(Theme.current, wd.filePath)
                    anchors { left: parent.left; top: parent.top; margins: 10 }
                    width: pairText.implicitWidth + 16; height: 22; radius: 11
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text { id: pairText; anchors.centerIn: parent; text: "♥ " + (Theme.pal.name ?? Theme.current); color: "white"
                        font { family: Theme.font; pixelSize: 10; weight: Font.DemiBold } }
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
            onActivated: root.themeEnter()
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

    // ── Wallpapers paired with the centred theme ──────────────────────
    Item {
        id: strip
        anchors { top: band.bottom; topMargin: root.onThemes ? 10 : 0 }
        width: parent.width
        height: root.onThemes ? 84 : 0
        visible: root.onThemes

        ListView {
            id: stripView
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
            width: Math.min(contentWidth, parent.width - 40)
            height: 78
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            model: root.themeWalls
            currentIndex: root.stripIndex
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
                id: sw
                required property string modelData
                required property int index
                readonly property bool focused: root.stripFocus && root.stripIndex === index
                readonly property bool applied: modelData === root.currentWall
                width: 128; height: 78

                Rectangle {
                    id: frame
                    anchors { fill: parent; margins: 3 }
                    radius: 7
                    color: Theme.control
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: "file://" + (root.isVideo(sw.modelData) ? root.thumbDir + "/" + Qt.md5(sw.modelData) + ".jpg" : sw.modelData)
                        sourceSize { width: 122 * Screen.devicePixelRatio; height: 72 * Screen.devicePixelRatio }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        opacity: status === Image.Ready ? (root.stripFocus || sw.applied ? 1 : 0.75) : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                    }
                    Text {
                        visible: root.isVideo(sw.modelData)
                        anchors { left: parent.left; bottom: parent.bottom; margins: 5 }
                        text: "▶"; color: "white"; font.pixelSize: 10
                        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.width: sw.focused ? 3 : (sw.applied ? 1 : 0)
                    border.color: root.centredTheme?.accent ?? Theme.accent
                    Behavior on border.width { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const again = root.stripFocus && root.stripIndex === sw.index;
                        root.stripIndex = sw.index; root.stripFocus = true;
                        if (again) { root.applyThemeWall(); Popouts.close(); } else root.applyThemeWall();
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: root.themeWalls.length === 0
            text: "No wallpapers paired with this theme. Press P on one in the Wallpapers tab to pair it."
            color: Theme.textDim
            font { family: Theme.font; pixelSize: 11 }
        }
    }

    // ── Caption + hints ───────────────────────────────────────────────
    Column {
        id: hints
        anchors { horizontalCenter: parent.horizontalCenter; top: strip.bottom; topMargin: 14 }
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.onWalls
                ? (wallView.currentIndex >= 0 && walls.count ? (() => { const it = walls.get(wallView.currentIndex);
                      if (!it) return " ";
                      if (it.isDir) return root.folderName(it.fileBaseName);
                      return (root.inFolder ? root.folderName(root.wallFolder) + "  /  " : "") + it.fileBaseName + (it.video ? "  ·  video" : ""); })()
                   : "No images in " + Config.wallDir.replace(root.home, "~") + (root.inFolder ? "/" + root.wallFolder : ""))
                : root.onHaven
                ? (havenView.currentIndex >= 0 && haven.count ? (() => { const it = haven.get(havenView.currentIndex);
                      if (!it) return " ";
                      return it.wid + "  ·  " + it.res + "  ·  " + it.category + (it.purity !== "sfw" ? "  ·  " + it.purity : "")
                           + "  ·  ♥ " + it.favs + "      " + (havenView.currentIndex + 1) + " / " + root.havenTotal
                           + (root.havenError !== "" ? "      " + root.havenError : ""); })()
                   : " ")
                : root.stripFocus && root.themeWalls[root.stripIndex]
                ? (root.centredTheme?.name ?? "") + "  ·  " + root.themeWalls[root.stripIndex].split("/").pop().replace(/\.[^.]+$/, "")
                : (root.centredTheme?.name ?? "")
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.onHaven
                ? "←/→ browse   enter download + apply   space preview   / search   tab switch   esc close"
                : root.onThemes
                ? (root.stripFocus
                    ? "←/→ wallpaper   enter apply + close   space preview   ↑ back to themes   esc close"
                    : "←/→ browse   enter apply + random wallpaper   space re-roll   ↓ wallpapers   tab switch   esc close")
                : root.inFolder
                ? "←/→ browse   enter apply   space preview   p pair with current theme   backspace/esc back to folders"
                : "←/→ browse   enter open folder   tab switch   esc close"
            color: Theme.textDim
            font { family: Theme.font; pixelSize: 10 }
        }
    }
}
