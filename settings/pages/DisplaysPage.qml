import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services
import qs.components
import qs.settings

// Displays pane: an arrangement preview, then each display's details. Brightness appears
// when the monitor answers DDC/CI (checked from Control Centre). On Hyprland, resolution,
// refresh rate, scale and rotation can be changed: they apply at once, and revert after
// 15 s unless kept (like macOS); kept changes go to ~/.config/hypr/displays.lua.
Column {
    id: root
    spacing: 20

    // One shape for every compositor: Hyprland reports make/model/refresh rate over IPC;
    // elsewhere Quickshell's screen list gives geometry and scale (no refresh rate).
    readonly property var mons: Compositor.hyprland
        ? hmons.map(m => ({ name: m.name, x: m.x, y: m.y, width: m.width, height: m.height, scale: m.scale, focused: m.focused,
                            title: ((m.make ?? "") + " " + (m.model ?? "")).trim(), refresh: m.refreshRate ?? 0,
                            transform: m.transform ?? 0, modes: m.availableModes ?? [] }))
        : Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: Math.round(s.width * s.devicePixelRatio), height: Math.round(s.height * s.devicePixelRatio),
                                         scale: s.devicePixelRatio, focused: s.name === Compositor.focusedScreen, title: s.model || "", refresh: 0, transform: 0, modes: [] }))
    property int sel: 0
    readonly property var m: mons[Math.min(sel, mons.length - 1)] ?? null
    property var hmons: []
    function refreshMons() { monProc.running = false; monProc.running = true; }
    Process {
        id: monProc
        running: Compositor.hyprland
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { onStreamFinished: { try { root.hmons = JSON.parse(text); } catch (e) {} } }
    }

    // Arrangement
    Rectangle {
        width: parent.width; height: 170
        radius: 10
        color: Theme.dark ? Qt.alpha(Theme.text, 0.045) : Qt.alpha(Theme.text, 0.03)
        border { width: 1; color: Qt.alpha(Theme.text, 0.07) }
        readonly property real minX: Math.min(...root.mons.map(m => m.x), 0)
        readonly property real minY: Math.min(...root.mons.map(m => m.y), 0)
        readonly property real spanW: Math.max(...root.mons.map(m => m.x + m.width / m.scale), 1) - minX
        readonly property real spanH: Math.max(...root.mons.map(m => m.y + m.height / m.scale), 1) - minY
        readonly property real k: Math.min((width - 60) / spanW, (height - 50) / spanH)
        Repeater {
            model: root.mons
            MouseArea {
                required property var modelData
                required property int index
                readonly property var box: parent
                x: (box.width - box.spanW * box.k) / 2 + (modelData.x - box.minX) * box.k
                y: (box.height - box.spanH * box.k) / 2 + (modelData.y - box.minY) * box.k
                width: modelData.width / modelData.scale * box.k
                height: modelData.height / modelData.scale * box.k
                onClicked: root.sel = index
                Rectangle {
                    anchors.fill: parent; radius: 4
                    gradient: Gradient { GradientStop { position: 0; color: "#5ac8fa" } GradientStop { position: 1; color: "#0a84ff" } }
                    border { width: root.sel === index ? 3 : 0; color: Theme.text }
                }
                Rectangle { visible: modelData.focused; x: 0; y: 0; width: parent.width; height: 4; radius: 2; color: "white"; opacity: 0.8 }
                Text { anchors.centerIn: parent; text: modelData.name; color: "white"; font { family: Theme.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
            }
        }
    }

    // ── Changing modes (Hyprland) ─────────────────────────────────────
    readonly property bool editable: Compositor.hyprland && !!m && m.modes.length > 0
    readonly property string script: Quickshell.shellDir + "/scripts/displays.sh"
    // availableModes look like "1920x1080@180.00Hz"
    readonly property var modes: (m?.modes ?? []).map(s => { const r = /^(\d+)x(\d+)@([\d.]+)/.exec(s); return r ? { w: +r[1], h: +r[2], hz: +r[3] } : null; }).filter(x => x)
    readonly property var resolutions: {
        const seen = {}, out = [];
        for (const md of modes) { const k = md.w + "x" + md.h; if (!seen[k]) { seen[k] = 1; out.push(md); } }
        return out.sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w).map(md => [md.w + "x" + md.h, md.w + " × " + md.h + (md.w === modes[0]?.w && md.h === modes[0]?.h ? "  (native)" : "")]);
    }
    readonly property string curRes: m ? m.width + "x" + m.height : ""
    // Hyprland repeats near-identical rates (119.88 / 120.00): keep the higher of each rounded rate.
    function ratesFor(res) {
        const best = {};
        for (const md of modes) if (md.w + "x" + md.h === res) { const k = Math.round(md.hz); if (!best[k] || md.hz > best[k]) best[k] = md.hz; }
        return Object.keys(best).map(Number).sort((a, b) => b - a).map(k => [best[k].toFixed(2), k + " Hz"]);
    }
    readonly property var rates: ratesFor(curRes)
    readonly property string curRate: { if (!m) return ""; let b = rates[0]?.[0] ?? ""; let d = 1e9;
        for (const r of rates) { const e = Math.abs(+r[0] - m.refresh); if (e < d) { d = e; b = r[0]; } } return b; }
    readonly property var scales: [[1, "100%"], [1.25, "125%"], [1.5, "150%"], [1.6, "160%"], [1.75, "175%"], [2, "200%"]]
    readonly property var rotations: [[0, "Standard"], [1, "90°"], [2, "180°"], [3, "270°"]]

    property var previous: null       // settings to go back to while a change awaits Keep
    property int countdown: 0
    property string error: ""

    function current() { return { name: m.name, mode: curRes + "@" + curRate, pos: m.x + "x" + m.y, scale: m.scale, transform: m.transform }; }
    function change(over) {
        if (!editable) return;
        const before = current();
        const next = Object.assign({}, before, over);
        if (!previous) previous = before;
        apply(next, true);
    }
    function apply(c, confirm) {
        error = "";
        applier.confirm = confirm;
        applier.command = [script, "apply", c.name, c.mode, c.pos, String(c.scale), String(c.transform)];
        applier.running = true;
    }
    function keep() { previous = null; countdown = 0; saver.running = true; }
    function revert() { if (!previous) return; const p = previous; previous = null; countdown = 0; apply(p, false); }

    Process {
        id: applier
        property bool confirm: false
        stderr: StdioCollector { id: applyErr }
        onExited: code => {
            root.refreshMons();
            if (code !== 0) { root.error = applyErr.text.trim() || "Hyprland refused that setting."; return; }
            if (confirm) root.countdown = 15;
        }
    }
    Process { id: saver; command: [root.script, "save"] }
    Timer { running: root.countdown > 0; interval: 1000; repeat: true
        onTriggered: { root.countdown--; if (root.countdown === 0) root.revert(); } }
    // Leaving the pane (or closing Settings) without keeping goes back, like macOS.
    Component.onDestruction: if (previous) Quickshell.execDetached([script, "apply", previous.name, previous.mode, previous.pos, String(previous.scale), String(previous.transform)])

    Group {
        visible: root.countdown > 0
        SettingRow {
            title: "Keep these display settings?"
            subtitle: "Reverting in " + root.countdown + " s"
            glyph: "\uf071"; glyphTint: "#ff9500"
            Row {
                spacing: 8
                PushButton { text: "Revert"; onClicked: root.revert() }
                PushButton { text: "Keep Changes"; prominent: true; onClicked: root.keep() }
            }
        }
    }

    Group {
        visible: !!root.m
        title: root.m ? root.m.title || root.m.name : ""
        SettingRow {
            visible: Popouts.ddc >= 0
            title: "Brightness"
            Slider { width: 230; from: 0; to: 100; value: Math.max(0, Popouts.ddc)
                onMoved: v => { Popouts.ddc = Math.round(v); setBright.restart(); } }
            Timer { id: setBright; interval: 350; onTriggered: Quickshell.execDetached(["ddcutil", "setvcp", "10", String(Popouts.ddc), "--noverify"]) }
        }
        SettingRow {
            visible: root.editable
            title: "Resolution"
            PopupButton { options: root.resolutions; value: root.curRes; enabled: root.countdown === 0
                onPicked: v => root.change({ mode: v + "@" + (root.ratesFor(v)[0]?.[0] ?? "60") }) }
        }
        SettingRow {
            visible: root.editable
            title: "Refresh rate"
            PopupButton { options: root.rates; value: root.curRate; enabled: root.countdown === 0
                onPicked: v => root.change({ mode: root.curRes + "@" + v }) }
        }
        SettingRow {
            visible: root.editable
            title: "Scale"
            subtitle: "Larger makes text and windows bigger"
            PopupButton { options: root.scales; value: root.m ? Math.round(root.m.scale * 100) / 100 : 1; enabled: root.countdown === 0
                onPicked: v => root.change({ scale: v }) }
        }
        SettingRow {
            visible: root.editable
            title: "Rotation"
            PopupButton { options: root.rotations; value: root.m?.transform ?? 0; enabled: root.countdown === 0
                onPicked: v => root.change({ transform: v }) }
        }
        Repeater {
            model: root.m ? [["Resolution", root.editable ? "" : root.m.width + " × " + root.m.height],
                             ["Refresh rate", root.editable || !root.m.refresh ? "" : Math.round(root.m.refresh) + " Hz"],
                             ["Scale", root.editable ? "" : Math.round(root.m.scale * 100) / 100 + "×"],
                             ["Connection", root.m.name]] : []
            delegate: SettingRow {
                required property var modelData
                visible: !!modelData[1]
                title: modelData[0]
                Text { text: modelData[1]; color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 } }
            }
        }
    }
    Text {
        visible: root.error !== ""
        width: parent.width
        text: root.error
        color: "#ff453a"; wrapMode: Text.WordWrap
        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
    }
    Text {
        width: parent.width
        visible: !root.editable
        text: "Resolution, refresh rate and arrangement are set in your compositor's config"
              + ({ hyprland: " (~/.config/hypr, monitor rules).", niri: " (~/.config/niri/config.kdl, output blocks).",
                   sway: " (~/.config/sway/config, output lines).", mango: " (~/.config/mango/config.conf, monitorrule)." })[Compositor.name] ?? "."
        color: Theme.textDim; wrapMode: Text.WordWrap
        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
    }
}
