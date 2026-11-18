pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ESV verse of the day for the lock screen and the desktop Verse widget (scripts/votd.sh:
// Bible Gateway's feed, cached per day; a random ESV verse from a built-in pool when offline).
// Re-checked every 15 min, so it rolls over after midnight and recovers once the network is back.
Singleton {
    id: root

    readonly property var s: Config.saved
    readonly property bool wanted: ((s.widgets ?? true) && (s.widgetVerse ?? true)) || (s.lockVerse ?? true)

    property string text: ""
    property string ref: ""
    readonly property bool ok: text !== ""

    function refresh() { if (wanted && !proc.running) proc.running = true; }

    Process {
        id: proc
        command: [Quickshell.shellDir + "/scripts/votd.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.trim(), i = line.lastIndexOf("|");
                if (i > 0) { root.text = line.slice(0, i); root.ref = line.slice(i + 1) + " ESV"; }
            }
        }
    }
    Timer { interval: 15 * 60 * 1000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
