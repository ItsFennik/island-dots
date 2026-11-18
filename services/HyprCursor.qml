pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global cursor position from Hyprland's socket (j/cursorpos, < 1 ms). Used while dragging
// a desktop widget: its surface moves under the pointer, so surface-local coordinates
// can't be trusted. One query in flight at a time; asks again if more motion came in.
Singleton {
    id: root
    signal moved(real x, real y)

    property bool again: false
    property string buf: ""

    function query() {
        if (sock.connected) { again = true; return; }
        buf = "";
        sock.connected = true;
    }

    Socket {
        id: sock
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`
        onConnectedChanged: {
            if (connected) { write("j/cursorpos"); flush(); return; }
            try { const j = JSON.parse(root.buf); root.moved(j.x, j.y); } catch (e) {}
            if (root.again) { root.again = false; root.query(); }
        }
        parser: SplitParser { splitMarker: ""; onRead: d => root.buf += d }
    }
}
