pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Drives you can mount (Settings → Drives) and automounting, through udisks2 (`udisksctl`,
// no root, no fstab). System partitions (/, /boot, /home, swap…) and the other partitions of
// the system disk are left out.
//   automount         mount a drive when it's plugged in (USB sticks, SD cards, external disks)
//   automountOpen     …and open it in the file manager
//   automountNotify   …and post a notification
//   mountAtLogin      [UUID…] mounted when Island starts
// `udisksctl monitor` only runs while automount or mount-at-login is on (or the pane is open).
Singleton {
    id: root

    readonly property var s: Config.saved
    readonly property bool automount: s.automount ?? false
    readonly property var atLogin: s.mountAtLogin ?? []
    property bool pageOpen: false                  // Settings pane visible: keep the list live
    readonly property bool watching: automount || atLogin.length > 0 || pageOpen

    // [{ dev, disk, name, size, fstype, uuid, mount, removable }]
    property var list: []
    property var busy: ({})                        // dev → true while a mount/unmount runs
    property string error: ""
    property bool scanned: false
    property var seen: []                          // devs present at the last scan

    readonly property var skipFs: ["swap", "crypto_LUKS", "LVM2_member", "linux_raid_member", "zfs_member", "squashfs", ""]
    function isSystemMount(mp) { return mp !== "" && !/^\/(run\/media|media|mnt)\//.test(mp); }

    function refresh() { if (!scan.running) scan.running = true; else rescan.restart(); }
    Timer { id: rescan; interval: 600; onTriggered: root.refresh() }

    Process {
        id: scan
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,FSTYPE,SIZE,MOUNTPOINT,RM,HOTPLUG,UUID,TYPE,TRAN"]
        stdout: StdioCollector {
            onStreamFinished: {
                let devs;
                try { devs = JSON.parse(text).blockdevices ?? []; } catch (e) { return; }
                const out = [];
                for (const d of devs) {
                    if (d.type === "loop" || d.type === "rom" || d.name.startsWith("zram")) continue;
                    const parts = d.children?.length ? d.children : [d];
                    // the disk holding the system: leave all of it out (EFI, recovery…)
                    if (parts.some(p => root.isSystemMount(p.mountpoint ?? "") || (p.children ?? []).some(c => root.isSystemMount(c.mountpoint ?? "")))) continue;
                    for (const p of parts) {
                        const fs = p.fstype ?? "";
                        if (root.skipFs.includes(fs)) continue;
                        out.push({ dev: p.path, disk: d.path, name: p.label || p.name,
                                   size: Number(p.size) || 0, fstype: fs, uuid: p.uuid ?? "", mount: p.mountpoint ?? "",
                                   // USB / SD / truly removable; SATA reports hotplug too, but that's an internal disk
                                   removable: !!(d.rm || p.rm || d.tran === "usb" || d.tran === "mmc" || d.tran === "sdio") });
                    }
                }
                const before = root.seen;
                root.seen = out.map(x => x.dev);
                if (JSON.stringify(out) !== JSON.stringify(root.list)) root.list = out;
                if (!root.scanned) {
                    root.scanned = true;
                    for (const x of out) if (!x.mount && x.uuid && root.atLogin.includes(x.uuid)) root.mount(x, false);
                    return;
                }
                if (root.automount)
                    for (const x of out) if (!before.includes(x.dev) && !x.mount && x.removable) root.mount(x, true);
            }
        }
    }

    // Any udisks change (plug, unplug, mount, unmount from anywhere) → rescan shortly after.
    Process {
        id: monitor
        running: root.watching
        command: ["udisksctl", "monitor"]
        stdout: SplitParser { onRead: line => { if (/^(Added|Removed|Properties Changed)/.test(line.replace(/^\d\d:\d\d:\d\d\.\d+:\s*/, ""))) rescan.restart(); } }
    }
    onWatchingChanged: if (watching) refresh()
    Component.onCompleted: if (watching) refresh()

    function setBusy(dev, on) { const b = Object.assign({}, busy); if (on) b[dev] = true; else delete b[dev]; busy = b; }

    // auto: plugged in just now (no password prompt; may open it / notify)
    function mount(x, auto) {
        setBusy(x.dev, true);
        const p = mountProc.createObject(root, { drive: x, auto: auto });
        p.running = true;
    }
    function unmount(x) {
        setBusy(x.dev, true);
        const p = cmdProc.createObject(root, { dev: x.dev, command: ["udisksctl", "unmount", "-b", x.dev] });
        p.running = true;
    }
    // Unmount every partition on the disk, then power it off so it can be pulled out.
    function eject(x) {
        setBusy(x.dev, true);
        const parts = list.filter(y => y.disk === x.disk && y.mount).map(y => "udisksctl unmount -b '" + y.dev + "'").join(" && ");
        const p = cmdProc.createObject(root, { dev: x.dev, command: ["sh", "-c", (parts ? parts + " && " : "") + "udisksctl power-off -b '" + x.disk + "'"] });
        p.running = true;
    }
    function setAtLogin(x, on) {
        if (!x.uuid) return;
        const l = atLogin.filter(u => u !== x.uuid);
        if (on) l.push(x.uuid);
        Config.set("mountAtLogin", l);
    }

    Component {
        id: mountProc
        Process {
            property var drive
            property bool auto
            command: ["udisksctl", "mount", "-b", drive.dev].concat(auto ? ["--no-user-interaction"] : [])
            stdout: StdioCollector { id: mout }
            stderr: StdioCollector { id: merr }
            onExited: code => {
                root.setBusy(drive.dev, false);
                const at = (/ at (.+?)\.?\s*$/m.exec(mout.text) ?? [])[1] ?? "";
                if (code !== 0) root.error = drive.name + ": " + (merr.text.trim().split("\n").pop() || "couldn't mount");
                else {
                    root.error = "";
                    if (auto && at && (root.s.automountOpen ?? false)) Quickshell.execDetached(["xdg-open", at]);
                    if (auto && (root.s.automountNotify ?? true))
                        Quickshell.execDetached(["notify-send", "-a", "Drives", "-i", "drive-removable-media", drive.name + " mounted", at]);
                }
                root.refresh();
                destroy();
            }
        }
    }
    Component {
        id: cmdProc
        Process {
            property string dev
            stderr: StdioCollector { id: cerr }
            onExited: code => {
                root.setBusy(dev, false);
                root.error = code === 0 ? "" : (cerr.text.trim().split("\n").pop() || "failed");
                root.refresh();
                destroy();
            }
        }
    }

    function sizeText(b) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i];
    }
}
