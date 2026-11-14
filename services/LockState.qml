pragma Singleton
import QtQuick
import Quickshell

// Whether the session is locked. Set it to lock; only a correct password (overlays/Lock.qml)
// unlocks, so there's deliberately no IPC call to unlock.
//   qs -c island ipc call lock lock        (also: loginctl lock-session)
Singleton {
    property bool locked: false
    function lock() { locked = true; }
}
