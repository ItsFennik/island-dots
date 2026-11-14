pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification daemon (org.freedesktop.Notifications). New notifications grow out of the
// island on the focused monitor as a toast; every notification stays in the centre
// (the bell in the pill) until it is dismissed or its app closes it.
//   qs -c island ipc call notifs <toggle|dnd|clear|dismiss>
Singleton {
    id: root

    property var list: []                         // [Entry], newest first
    property string screen: ""                    // monitor the current toast is on
    property int unread: 0                        // arrived since the centre was last opened
    readonly property bool dnd: Config.saved.notifDnd ?? false
    readonly property int timeout: Math.round((Config.saved.notifTimeout ?? 5) * 1000)
    readonly property var popups: list.filter(e => e.popup)
    readonly property var current: popups[0] ?? null

    function setDnd(on) { Config.commit("notifDnd", on); }
    function clear() { for (const e of list.slice()) e.n?.dismiss(); }
    function dismissLatest() { list[0]?.n?.dismiss(); }
    function hide(e) { if (e) e.popup = false; root.listChanged(); }

    // Default action if the app has one, otherwise just dismiss.
    function activate(e) {
        const a = Array.from(e?.n?.actions ?? []).find(a => a.identifier === "default");
        if (a) a.invoke(); else e?.n?.dismiss();
    }

    function iconFor(n) {
        if (!n) return "";
        const src = n.appIcon || DesktopEntries.byId(n.desktopEntry)?.icon || "";
        if (src === "") return "";
        if (src.startsWith("/")) return "file://" + src;
        if (src.includes("://")) return src;
        return Quickshell.iconPath(src, true);
    }

    function ago(t, now) {
        const s = Math.max(0, (now - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    function add(n, quiet) {
        const old = list.find(e => e.n === n);
        if (old) { root.bump(old); return; }
        n.tracked = true;
        const e = entry.createObject(root, { n });
        list = [e].concat(list);
        if (!quiet) root.show(e);
    }

    // A notification arrived or was replaced: move it to the top and pop it up.
    function bump(e) {
        e.time = Date.now();
        list = [e].concat(list.filter(x => x !== e));
        root.show(e);
    }

    function show(e) {
        if (Popouts.current !== "notifs") unread++;
        const critical = e.n.urgency === NotificationUrgency.Critical;
        if (dnd && !critical) { if (e.n.transient) e.n.expire(); return; }
        screen = Compositor.screenName();
        e.popup = true;
        e.restart();
        root.listChanged();
    }

    Connections {
        target: Popouts
        function onCurrentChanged() { if (Popouts.current === "notifs") root.unread = 0; }
    }

    component Entry: QtObject {
        id: entryObj
        required property Notification n
        property real time: Date.now()
        property bool popup: false
        property bool hovered: false             // a hovered toast doesn't time out

        readonly property int life: n?.urgency === NotificationUrgency.Critical ? 0
                                  : (n?.expireTimeout ?? 0) > 0 ? n.expireTimeout * 1000 : root.timeout
        function restart() { if (life > 0) timer.restart(); else timer.stop(); }

        property Timer timer: Timer {
            interval: entryObj.life
            running: false
            onTriggered: {
                if (entryObj.hovered) { restart(); return; }
                if (entryObj.n?.transient) entryObj.n.expire();
                else root.hide(entryObj);
            }
        }
        onHoveredChanged: if (!hovered && popup && life > 0) timer.restart()

        // Replacements (replaces_id) update the same object in place.
        property Connections watch: Connections {
            target: entryObj.n
            function onSummaryChanged() { root.bump(entryObj); }
            function onBodyChanged() { root.bump(entryObj); }
            function onClosed() {
                root.list = root.list.filter(x => x !== entryObj);
                entryObj.destroy();
            }
        }
    }
    Component { id: entry; Entry {} }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        onNotification: n => root.add(n, false)
    }

    // After a shell reload the server keeps its notifications; rebuild the list quietly.
    Component.onCompleted: { for (const n of server.trackedNotifications.values) root.add(n, true); }
}
