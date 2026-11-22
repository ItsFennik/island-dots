pragma Singleton
import QtQuick
import Quickshell

// Which menu-bar items show, in which zone (left / center / right) and in what order.
// Setting barItems = { left: [ids], center: [ids], right: [ids] }; an id in no zone is hidden.
// Until it's edited, the layout follows the older per-item switches (barAppMenus, barWorkspaces…).
Singleton {
    id: root

    readonly property var s: Config.saved

    // Every item the bar can show, in its natural order.
    readonly property var catalogue: [
        { id: "logo",       label: "Logo menu",       glyph: "\uf17c" },
        { id: "appmenus",   label: "App menus",       glyph: "󰍜", sub: "App name, Go, Window, Help" },
        { id: "workspaces", label: "Workspaces",      glyph: "󰕰" },
        { id: "media",      label: "Now playing",     glyph: "󰝚", sub: "Song and artist; opens the player" },
        { id: "tray",       label: "Tray icons",      glyph: "󱊔" },
        { id: "battery",    label: "Battery",         glyph: "󰁹", sub: "Laptops only" },
        { id: "sound",      label: "Sound",           glyph: "󰕾" },
        { id: "network",    label: "Network",         glyph: "󰖩" },
        { id: "spotlight",  label: "Spotlight",       glyph: "\uf002", sub: "Super+D opens it either way" },
        { id: "weather",    label: "Weather",         glyph: "󰖐" },
        { id: "controls",   label: "Control Centre",  glyph: "󰒓" },
        { id: "clock",      label: "Clock",           glyph: "󰥔", sub: "Opens notifications" },
        { id: "power",      label: "Power",           glyph: "\uf011" },
    ]
    readonly property var zones: ["left", "center", "right"]

    // Menu bar skins (setting barSkin; only the "Menu bar + Dock" layout has skins).
    // Listed by Spotlight ("skin", "bar"), Settings → Appearance and `ipc call bar skin <id>`.
    readonly property var skins: [
        { id: "classic", label: "Classic",        glyph: "󰍜", sub: "Full-width menu bar" },
        { id: "pills",   label: "Pills",          glyph: "󰮺", sub: "Every item in its own floating pill" },
        { id: "island",  label: "Dynamic Island", glyph: "󰐾", sub: "Only a centre capsule: the time, growing for music, volume, notifications and menus" },
        { id: "notch",   label: "Notch",          glyph: "󰟀", sub: "Only a MacBook-style notch: the time, growing for music, volume, notifications and menus" },
    ]
    readonly property string skin: skins.some(k => k.id === s.barSkin) ? s.barSkin : "classic"
    readonly property bool capsule: (s.shellLayout ?? "menubar") === "menubar" && (skin === "island" || skin === "notch")
    readonly property bool bottomLayout: (s.shellLayout ?? "menubar") !== "menubar"
    // Black like the hardware it imitates; light themes keep their bg so menu text stays readable.
    readonly property color capsuleFill: Theme.dark ? "#000000" : Theme.bg
    // Island / notch: Spotlight grows out of the capsule too (setting spotlightFromCapsule).
    property int capsuleIdleW: 110      // the idle capsule's real width (set by the bar), where Spotlight starts
    readonly property bool spotlightFromCapsule: capsule && (s.spotlightFromCapsule ?? true)
    // Resolved Spotlight placement for the current bar: auto follows the bar, the other
    // choices are explicit overrides. Shared with Popouts so the close hold matches the morph.
    readonly property string spotlightStyle: {
        const st = s.spotlightStyle ?? "auto";
        if (st === "floating") return "floating";
        if (st === "capsule") return capsule ? "capsule" : bottomLayout ? "bottom" : "attached";
        if (st === "attached") return capsule && spotlightFromCapsule ? "capsule" : bottomLayout ? "bottom" : "attached";
        if (capsule && spotlightFromCapsule) return "capsule";
        return bottomLayout ? "bottom" : "attached";
    }
    readonly property bool spotlightMorph: spotlightStyle === "capsule"
    function setSkin(id) {
        if (!skins.some(k => k.id === id)) { console.warn("island: unknown bar skin " + id); return; }
        if ((s.shellLayout ?? "menubar") !== "menubar") Config.commit("shellLayout", "menubar");
        Config.commit("barSkin", id);
    }
    function cycleSkin(d) {
        const i = skins.findIndex(k => k.id === skin);
        setSkin(skins[(i + (d ?? 1) + skins.length) % skins.length].id);
    }
    function info(id) { return catalogue.find(c => c.id === id) ?? { id: id, label: id, glyph: "" }; }

    // The layout as the older switches describe it.
    readonly property var legacy: ({
        left: ["logo"].concat((s.barAppMenus ?? true) ? ["appmenus"] : []),
        center: (s.barWorkspaces ?? true) ? ["workspaces"] : [],
        right: ["tray", "battery", "sound", "network"]
            .concat((s.barSearch ?? true) ? ["spotlight"] : [])
            .concat((s.barWeather ?? true) ? ["weather"] : [])
            .concat(["controls", "clock", "power"])
    })
    readonly property var layout: {
        const b = s.barItems;
        if (!b || typeof b !== "object") return legacy;
        const known = catalogue.map(c => c.id);
        const clean = z => (Array.isArray(b[z]) ? b[z] : []).filter(id => known.includes(id));
        const l = { left: clean("left"), center: clean("center"), right: clean("right") };
        // "Show workspaces" (also used by the bottom bars) still hides them here.
        if (s.barWorkspaces === false) for (const z of zones) l[z] = l[z].filter(id => id !== "workspaces");
        return l;
    }

    function zoneOf(id) { return zones.find(z => layout[z].includes(id)) ?? ""; }
    function shown(id) { return zoneOf(id) !== ""; }

    // Editing (Settings → Menu Bar)
    function copy() { return { left: layout.left.slice(), center: layout.center.slice(), right: layout.right.slice() }; }
    function write(l) { Config.commit("barItems", l); }

    function setShown(id, on) {
        if (id === "workspaces" && on && s.barWorkspaces === false) Config.commit("barWorkspaces", true);
        const l = copy();
        for (const z of zones) l[z] = l[z].filter(x => x !== id);
        if (on) {
            // Back where it naturally belongs: same zone as its legacy home, at the end.
            const home = zones.find(z => legacy[z].includes(id)) ?? "right";
            l[home].push(id);
        }
        write(l);
    }
    function moveTo(id, zone) {
        const l = copy();
        for (const z of zones) l[z] = l[z].filter(x => x !== id);
        l[zone].push(id);
        write(l);
    }
    function shift(id, delta) {
        const l = copy(), z = zoneOf(id);
        if (!z) return;
        const a = l[z], i = a.indexOf(id), j = i + delta;
        if (j < 0 || j >= a.length) return;
        a.splice(i, 1); a.splice(j, 0, id);
        write(l);
    }
    readonly property var defaultLayout: ({ left: ["logo", "appmenus"], center: ["workspaces"],
        right: ["tray", "battery", "sound", "network", "spotlight", "weather", "controls", "clock", "power"] })
    function reset() { write(defaultLayout); }
}
