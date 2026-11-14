pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / memory / temperature / disk for the desktop system widget.
// Polls only while that widget is on.
Singleton {
    id: root

    readonly property bool wanted: (Config.saved.widgets ?? true) && (Config.saved.widgetSystem ?? true)

    property real cpu: 0
    property real mem: 0
    property real memUsed: 0          // KiB
    property real memTotal: 0
    property int temp: -1
    property real disk: 0
    property string diskFree: ""
    property var prev: null
    property string tempPath: ""

    function readCpu(t) {
        const f = t.slice(0, t.indexOf("\n")).trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
        if (prev) { const dt = total - prev.total; cpu = dt > 0 ? 1 - (idle - prev.idle) / dt : 0; }
        prev = { idle, total };
    }
    function readMem(t) {
        const v = k => Number((t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m")) ?? [0, 0])[1]);
        memTotal = v("MemTotal"); memUsed = memTotal - v("MemAvailable");
        mem = memTotal ? memUsed / memTotal : 0;
    }

    FileView { id: procStat; path: "/proc/stat"; onLoaded: root.readCpu(text()) }
    FileView { id: procMem; path: "/proc/meminfo"; onLoaded: root.readMem(text()) }
    FileView { id: hwTemp; path: root.tempPath; printErrors: false
        onLoaded: root.temp = Math.round(Number(text().trim()) / 1000) }
    Process {
        running: root.wanted
        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do case "$(cat $h/name 2>/dev/null)" in k10temp|zenpower|coretemp|cpu_thermal) echo $h/temp1_input; exit;; esac; done']
        stdout: StdioCollector { onStreamFinished: root.tempPath = text.trim() }
    }
    Process {
        id: df
        command: ["df", "-B1", "--output=size,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (n.length === 2 && n[0] > 0) {
                    root.disk = 1 - n[1] / n[0];
                    root.diskFree = (n[1] / 1e9 >= 100 ? Math.round(n[1] / 1e9) : (n[1] / 1e9).toFixed(1)) + " GB free";
                }
            }
        }
    }
    Timer {
        interval: 2000; running: root.wanted; repeat: true; triggeredOnStart: true
        onTriggered: { procStat.reload(); procMem.reload(); if (root.tempPath) hwTemp.reload(); }
    }
    Timer { interval: 60000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: df.running = true }
}
