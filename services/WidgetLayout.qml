pragma Singleton
import QtQuick
import Quickshell

// Desktop widget positions and design. Until moved, widgets stack in the Settings corner; after a drag
// `widgetPos` holds { id: [x, y] } from the free area's top-left. `live` holds positions mid-edit.
Singleton {
    id: root

    readonly property var s: Config.saved
    readonly property bool tahoe: (s.widgetStyle ?? "tahoe") !== "classic"
    readonly property int unit: 164
    readonly property int gap: 14

    readonly property string corner: s.widgetsPosition ?? "top-left"
    readonly property bool onRight: corner.endsWith("right")
    readonly property bool onBottom: corner.startsWith("bottom")
    readonly property int margin: s.widgetsMargin ?? 24

    readonly property var on: ({
        clock: s.widgetClock ?? true,
        weather: s.widgetWeather ?? true,
        calendar: s.widgetCalendar ?? true,
        music: s.widgetMusic ?? true,
        system: s.widgetSystem ?? true,
        verse: s.widgetVerse ?? true
    })
    readonly property var ids: ["weather", "calendar", "clock", "music", "system", "verse"].filter(i => on[i])

    // A lone small tile in a row takes the full width, as on macOS.
    function wide(id) {
        if (id === "music" || id === "system" || id === "verse") return true;
        if (tahoe) {
            if (id === "weather") return !on.calendar;
            if (id === "calendar") return !on.weather;
            return false;
        }
        if (id === "weather") return !on.clock;
        return id === "calendar";
    }
    // Size per widget: "s" (1×1), "m" (2×1), "l" (2×2); right-click a widget to pick.
    // Not picked yet → the auto rule above (wide → medium).
    readonly property var sizes: s.widgetSize ?? ({})
    function size(id) { return sizes[id] ?? (wide(id) ? "m" : "s"); }
    function setSize(id, sz) {
        const m = Object.assign({}, sizes);
        m[id] = sz;
        Config.commit("widgetSize", m);
    }
    function width(id) { return size(id) === "s" ? unit : unit * 2 + gap; }
    function height(id) { return size(id) === "l" ? unit * 2 + gap : unit; }
    function remove(id) {
        const key = { clock: "widgetClock", weather: "widgetWeather", calendar: "widgetCalendar", music: "widgetMusic", system: "widgetSystem", verse: "widgetVerse" }[id];
        if (key) Config.commit(key, false);
    }

    // Auto layout rows. Tahoe: weather + month calendar, then the clock.
    // Classic: clock + weather, then the wide calendar.
    readonly property var rows: (tahoe ? [["weather", "calendar"], ["clock"], ["music"], ["system"], ["verse"]]
                                       : [["clock", "weather"], ["calendar"], ["music"], ["system"], ["verse"]])
                                .map(r => r.filter(i => on[i])).filter(r => r.length > 0)

    // Auto position: distance of the widget's near edges from the chosen corner.
    function autoOffset(id) {
        let y = margin;
        const ordered = onBottom ? rows.slice().reverse() : rows;
        for (const r of ordered) {
            const i = r.indexOf(id);
            if (i >= 0) {
                let x = margin;
                for (let k = 0; k < i; k++) x += width(r[k]) + gap;
                return [x, y];
            }
            y += Math.max(...r.map(height)) + gap;
        }
        return [margin, margin];
    }

    // Saved (or, while editing, live) top-left position, or null for auto layout.
    readonly property var saved: s.widgetPos ?? ({})
    readonly property bool custom: Object.keys(saved).length > 0
    property bool editing: false
    property string editScreen: ""
    property var live: ({})

    // Dragging straight on the desktop (no edit mode): which widget, on which monitor.
    property string dragId: ""
    property string dragScreen: ""
    readonly property bool moving: editing || dragId !== ""

    function pos(id) {
        const m = moving ? live : saved;
        return m[id] ?? null;
    }

    // Top-left of every visible widget in an area of size w × h (the editor's size).
    function resolved(w, h) {
        const out = {};
        for (const id of ids) {
            const p = pos(id);
            if (p) { out[id] = [p[0], p[1]]; continue; }
            const o = autoOffset(id);
            out[id] = [onRight ? w - o[0] - width(id) : o[0], onBottom ? h - o[1] - height(id) : o[1]];
        }
        return out;
    }

    // Snap one axis to the nearest candidate edge (our near or far edge), within 10 px.
    function snapAxis(v, size, cands) {
        let best = v, dist = 11;
        for (const c of cands) {
            for (const t of [c, c - size]) {
                const d = Math.abs(v - t);
                if (d < dist) { dist = d; best = t; }
            }
        }
        return best;
    }
    // Move `id`'s top-left to x,y in a w × h area, snapping to the margins and the other
    // widgets (`at` = resolved positions) unless `free`.
    function place(id, x, y, free, w, h, at) {
        const ww = width(id), hh = height(id);
        if (!free) {
            const xs = [margin, w - margin], ys = [margin, h - margin];
            for (const o of ids) {
                if (o === id || !at[o]) continue;
                const p = at[o], ow = width(o), oh = height(o);
                xs.push(p[0], p[0] + ow, p[0] - gap, p[0] + ow + gap);
                ys.push(p[1], p[1] + oh, p[1] - gap, p[1] + oh + gap);
            }
            x = snapAxis(x, ww, xs);
            y = snapAxis(y, hh, ys);
        }
        move(id, Math.max(0, Math.min(x, w - ww)), Math.max(0, Math.min(y, h - hh)));
    }

    function startDrag(id, screenName) {
        if (editing) return;
        live = Object.assign({}, saved);
        dragScreen = screenName ?? "";
        dragId = id;
    }
    // `all`: resolved positions in the dragged window's (full desktop) size.
    function endDrag(all) {
        if (dragId === "") return;
        const moved = live[dragId] !== undefined && JSON.stringify(live[dragId]) !== JSON.stringify(saved[dragId]);
        const out = Object.assign({}, all ?? {}, live);
        if (moved) Config.commit("widgetPos", out);   // saved first, so nothing jumps back
        dragId = "";
    }

    function edit(screenName) {
        if (!(s.widgets ?? true) || ids.length === 0) return;
        live = Object.assign({}, saved);
        editScreen = screenName ?? "";
        editing = true;
    }
    function move(id, x, y) {
        const l = Object.assign({}, live);
        l[id] = [Math.round(x), Math.round(y)];
        live = l;
    }
    function done(all) {
        // `all`: the editor's resolved map, so widgets nobody touched keep where they were.
        // Nothing moved since a reset (or ever) → stay on auto layout.
        const out = Object.keys(live).length ? Object.assign({}, all ?? {}, live) : ({});
        editing = false;
        Config.commit("widgetPos", out);
    }
    function reset() {
        live = {};
        if (!editing) Config.commit("widgetPos", ({}));
    }
}
