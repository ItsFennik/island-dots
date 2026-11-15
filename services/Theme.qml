pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Theme palettes (themes/*.json) and the applied one. UI colours for Island's own windows.
Singleton {
    id: root

    property var themes: []                 // [{ id, name, dark, bg, ... }]
    property string current: ""
    readonly property var pal: themes.find(t => t.id === current) ?? fallback
    readonly property var fallback: ({ dark: true, bg: "#0a0a0a", bg_alt: "#050505", surface: "#161616", overlay: "#2a2a2a",
        fg: "#f2f2f2", fg_dim: "#8a8a8a", fg_faint: "#4a4a4a", accent: "#dddddd", accent_fg: "#0a0a0a",
        red: "#dddddd", green: "#cccccc", yellow: "#aaaaaa", blue: "#a7a7a7", magenta: "#dddddd", cyan: "#cccccc" })

    // Derived UI tokens
    readonly property color bg: pal.bg
    readonly property color sidebar: pal.bg_alt
    readonly property color card: pal.surface
    readonly property color text: pal.fg
    readonly property color textDim: pal.fg_dim
    readonly property color textFaint: pal.fg_faint
    // Accent: the theme's, unless one is picked in Appearance (macOS accent colours).
    readonly property string accentOverride: Config.saved.accentColor ?? ""
    readonly property color accent: accentOverride || pal.accent
    readonly property color onAccent: accentOverride ? (accentOverride === "#ffd60a" ? "#1c1c1e" : "#ffffff") : pal.accent_fg
    readonly property color hairline: Qt.alpha(pal.fg, 0.08)
    readonly property color hover: Qt.alpha(pal.fg, 0.06)
    readonly property color control: Qt.alpha(pal.fg, 0.12)
    readonly property string font: Config.saved.widgetFont || "Adwaita Sans"     // macOS-style UI text
    readonly property string mono: "JetBrainsMono Nerd Font"                      // glyphs / code
    readonly property bool dark: pal.dark ?? true
    // macOS control tokens
    readonly property color knob: "#ffffff"
    readonly property color switchOff: Qt.alpha(pal.fg, dark ? 0.16 : 0.12)
    readonly property color button: dark ? Qt.alpha(pal.fg, 0.14) : "#ffffff"      // push / pop-up buttons
    readonly property color buttonBorder: dark ? "transparent" : Qt.alpha(pal.fg, 0.14)
    readonly property color focusRing: Qt.alpha(pal.accent, 0.45)
    readonly property color selection: Qt.alpha(pal.accent, 0.9)
    // Menu material: AppKit's look whatever the theme (graphite / frosted glass over Hyprland's
    // blur, system-blue selection unless an accent colour is picked in Appearance).
    readonly property color menuBg: dark ? Qt.rgba(0.165, 0.165, 0.175, 0.80) : Qt.rgba(0.955, 0.955, 0.955, 0.82)
    readonly property color menuEdge: dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color menuInner: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color menuText: dark ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(0, 0, 0, 0.86)
    readonly property color menuSel: accentOverride || (dark ? "#0a84ff" : "#007aff")
    readonly property color menuOnSel: accentOverride === "#ffd60a" ? "#1c1c1e" : "#ffffff"

    // Light/dark twins for Control Center's Dark Mode toggle ("" when a theme has none).
    readonly property var twins: ({ "catppuccin-mocha": "catppuccin-latte", "catppuccin-macchiato": "catppuccin-latte",
                                    "catppuccin-latte": "catppuccin-mocha", "monochrome": "monochrome-light", "monochrome-light": "monochrome",
                                    "macos": "macos-light", "macos-light": "macos" })
    function counterpart(id) { return id === "matugen" ? "matugen" : (twins[id] ?? ""); }
    function toggleDark() {
        if (current === "matugen") { Config.commit("matugenMode", dark ? "light" : "dark"); return; }
        const t = counterpart(current);
        if (t) apply(t);
    }

    function apply(id) {
        Quickshell.execDetached([Quickshell.shellDir + "/apply-theme.sh", id]);
    }

    function rescan() { scan.running = true; }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island/theme"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.current = text().trim(); root.rescan(); }   // also picks up a regenerated matugen.json
    }

    // One jq pass reads every palette.
    Process {
        id: scan
        running: true
        command: ["sh", "-c", 'for f in "$1"/themes/*.json; do jq -c --arg id "$(basename "$f" .json)" ". + {id: \\$id}" "$f"; done | jq -cs .', "sh", Quickshell.shellDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.themes = JSON.parse(text); } catch (e) { console.warn("island: bad theme json", e); }
            }
        }
    }
}
