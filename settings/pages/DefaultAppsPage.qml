import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
import qs.settings

// Default Apps pane: which app opens links, mail, folders, text, pictures… (xdg-mime,
// stored in ~/.config/mimeapps.list). Read once when the pane opens; written on pick.
Column {
    id: root
    spacing: 20

    // probe: the MIME whose handler we show; mimes: everything set together when picked.
    readonly property var kinds: [
        { id: "browser", label: "Web browser", glyph: "", tint: "#0a84ff", probe: "x-scheme-handler/https",
          mimes: ["x-scheme-handler/http", "x-scheme-handler/https", "x-scheme-handler/about", "x-scheme-handler/unknown",
                  "text/html", "application/xhtml+xml", "application/x-extension-htm", "application/x-extension-html",
                  "application/x-extension-shtml", "application/x-extension-xhtml", "application/x-extension-xht"] },
        { id: "mail", label: "Email", glyph: "", tint: "#0a84ff", probe: "x-scheme-handler/mailto", mimes: ["x-scheme-handler/mailto"] },
        { id: "files", label: "File manager", glyph: "", tint: "#1e88e5", probe: "inode/directory", mimes: ["inode/directory"] },
        { id: "text", label: "Text editor", glyph: "", tint: "#8e8e93", probe: "text/plain",
          mimes: ["text/plain", "text/markdown", "text/x-markdown", "text/x-shellscript", "application/x-shellscript",
                  "text/x-python", "text/x-csrc", "text/x-chdr", "text/x-c++src", "application/json", "application/xml",
                  "text/x-log", "application/toml", "application/x-yaml", "text/css"] },
        { id: "images", label: "Images", glyph: "", tint: "#ff9500", probe: "image/png",
          mimes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/avif",
                  "image/tiff", "image/heic", "image/jxl", "image/x-icon"] },
        { id: "video", label: "Videos", glyph: "", tint: "#ff3b30", probe: "video/mp4",
          mimes: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg",
                  "video/ogg", "video/x-flv", "video/3gpp", "video/x-ms-wmv"] },
        { id: "music", label: "Music", glyph: "", tint: "#ff2d55", probe: "audio/mpeg",
          mimes: ["audio/mpeg", "audio/flac", "audio/x-flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus", "audio/mp4",
                  "audio/x-m4a", "audio/aac", "audio/wav", "audio/x-wav", "audio/webm"] },
        { id: "pdf", label: "PDF documents", glyph: "", tint: "#ff3b30", probe: "application/pdf", mimes: ["application/pdf"] },
        { id: "archives", label: "Archives", glyph: "", tint: "#a2845e", probe: "application/zip",
          mimes: ["application/zip", "application/x-tar", "application/gzip", "application/x-compressed-tar",
                  "application/x-7z-compressed", "application/vnd.rar", "application/x-rar", "application/x-xz",
                  "application/x-xz-compressed-tar", "application/x-bzip2", "application/x-bzip2-compressed-tar",
                  "application/zstd", "application/x-zstd-compressed-tar"] }
    ]

    property var state: ({})          // probe → { def, cands: [ids] }
    property bool loading: true
    readonly property string script: Quickshell.shellDir + "/scripts/default-apps.sh"

    function refresh() { query.running = false; query.running = true; }
    Process {
        id: query
        running: true
        command: [root.script, "query"].concat(root.kinds.map(k => k.probe))
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {};
                for (const l of text.split("\n")) {
                    const p = l.split("\t");
                    if (p.length < 3) continue;
                    s[p[0]] = { def: p[1], cands: p[2].split(";").filter(x => x) };
                }
                root.state = s;
                root.loading = false;
            }
        }
    }
    Process {
        id: setter
        onExited: root.refresh()
    }
    function pick(kind, app) {
        // Show the choice at once; the re-query confirms it.
        const s = Object.assign({}, state);
        s[kind.probe] = Object.assign({}, s[kind.probe] ?? { cands: [] }, { def: app });
        state = s;
        setter.command = [script, "set", app].concat(kind.mimes);
        setter.running = true;
    }

    function appName(id) {
        if (!id) return "None";
        const e = DesktopEntries.byId(id.replace(/\.desktop$/, ""));
        return e?.name || id.replace(/\.desktop$/, "");
    }
    function appIcon(id) {
        const e = id ? DesktopEntries.byId(id.replace(/\.desktop$/, "")) : null;
        return e?.icon ? Quickshell.iconPath(e.icon, true) : "";
    }

    Group {
        title: "Default apps"
        footer: "Used whenever an app opens a link or file (xdg-open). Super+B and Super+E are Hyprland shortcuts and still start LibreWolf and Thunar."
        Repeater {
            model: root.kinds
            delegate: SettingRow {
                id: row
                required property var modelData
                readonly property var st: root.state[modelData.probe] ?? { def: "", cands: [] }
                readonly property var ids: {
                    const l = st.cands.slice();
                    if (st.def && !l.includes(st.def)) l.unshift(st.def);
                    return l;
                }
                title: modelData.label
                glyph: modelData.glyph; glyphTint: modelData.tint
                subtitle: !root.loading && ids.length === 0 ? "No installed app handles this" : ""
                Row {
                    spacing: 8
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        sourceSize: Qt.size(36, 36)
                        source: root.appIcon(row.st.def)
                        visible: source != ""
                        asynchronous: true
                    }
                    PopupButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.ids.length > 0 || root.loading
                        enabled: !root.loading
                        options: root.loading ? [["", "…"]] : (row.st.def ? [] : [["", "None"]]).concat(row.ids.map(id => [id, root.appName(id)]))
                        value: root.loading ? "" : row.st.def
                        onPicked: v => { if (v) root.pick(row.modelData, v); }
                    }
                }
            }
        }
    }
}
