pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default output (Pipewire, event driven — no wpctl polling).
Singleton {
    id: root
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink?.ready ?? false
    readonly property real volume: sink?.audio?.volume ?? 0          // 0..1 (can exceed 1)
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property string name: sink?.nickname || sink?.description || sink?.name || "No output"
    readonly property string glyph: muted || volume <= 0 ? "" : volume < 0.5 ? "" : ""

    function setVolume(v) { if (sink?.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1.5, v)); } }
    function nudge(d) { setVolume(Math.round((volume + d) * 100) / 100); }
    function toggleMute() { if (sink?.audio) sink.audio.muted = !sink.audio.muted; }

    // Hardware outputs (not app streams), for the output pickers.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    function setDefault(n) { Pipewire.preferredDefaultAudioSink = n; }

    // Audio streams. Keep this filter independent of `properties`: unbound nodes have no
    // properties yet, and reading media.class here made the list empty, so the tracker below
    // never bound the streams and the Applications section never appeared.
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio)
    // Playback streams only, grouped per application (an app can own more than one stream).
    // `properties` is valid once `streams` above is tracked.
    readonly property var playbackStreams: streams.filter(n => {
        const p = n.properties ?? {};
        return String(p["media.class"] ?? "").startsWith("Stream/Output/");
    })
    readonly property var apps: {
        const byName = {};
        for (const n of playbackStreams) {
            const p = n.properties ?? {};
            const name = String(p["application.name"] || p["application.id"]
                                || p["application.process.binary"] || n.description || n.name
                                || "Other audio");
            let app = byName[name];
            if (!app) { app = { name, nodes: [] }; byName[name] = app; }
            app.nodes.push(n);
        }
        return Object.keys(byName).sort().map(k => byName[k]);
    }
    function appVolume(app) {
        const n = app?.nodes?.find(n => n.audio);
        return n?.audio?.volume ?? 0;
    }
    function appMuted(app) {
        const nodes = app?.nodes?.filter(n => n.audio) ?? [];
        return nodes.length > 0 && nodes.every(n => n.audio.muted);
    }
    function setAppVolume(app, v) {
        for (const n of app?.nodes ?? []) if (n.audio) {
            n.audio.muted = false;
            n.audio.volume = Math.max(0, Math.min(1.5, v));
        }
    }
    function toggleAppMute(app) {
        const mute = !appMuted(app);
        for (const n of app?.nodes ?? []) if (n.audio) n.audio.muted = mute;
    }

    // Default input (microphone)
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false
    function setMic(v) { if (source?.audio) { source.audio.muted = false; source.audio.volume = Math.max(0, Math.min(1.5, v)); } }
    function toggleMic() { if (source?.audio) source.audio.muted = !source.audio.muted; }

    PwObjectTracker { objects: [root.sink, root.source].concat(root.streams) }
}
