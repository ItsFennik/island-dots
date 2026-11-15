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

    // Default input (microphone)
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false
    function setMic(v) { if (source?.audio) { source.audio.muted = false; source.audio.volume = Math.max(0, Math.min(1.5, v)); } }
    function toggleMic() { if (source?.audio) source.audio.muted = !source.audio.muted; }

    PwObjectTracker { objects: [root.sink, root.source] }
}
