pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Now playing (MPRIS). `player` is the one the bar button, the media popout and the media
// keys act on: whichever player last started playing (or was picked in the popout), falling
// back to anything playing, then to the first player.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property var chosen: null
    readonly property MprisPlayer player: (chosen && players.includes(chosen) ? chosen : null)
                                       ?? players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle || ""         // empty until the player sends metadata
    readonly property string label: title || player?.identity || ""   // title, else the app name ("Cider")
    readonly property string artist: player?.trackArtist || ""

    function pick(p) { chosen = p; }
    function playPause() { if (player?.canTogglePlaying) player.togglePlaying(); }
    function next() { if (player?.canGoNext) player.next(); }
    function previous() {
        if (!player) return;
        // Like most players: past the first few seconds, "previous" restarts the track.
        if (player.positionSupported && player.canSeek && player.position > 4) player.position = 0;
        else if (player.canGoPrevious) player.previous();
    }
    function stop() { if (player?.canControl) player.stop(); }

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0;
        sec = Math.floor(sec);
        const h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, s = sec % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(s).padStart(2, "0");
    }

    // Follow whichever player starts playing most recently.
    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData
            function onIsPlayingChanged() { if (modelData.isPlaying) root.chosen = modelData; }
        }
    }
}
