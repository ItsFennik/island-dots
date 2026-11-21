pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather for the desktop widget, from wttr.in (no API key). Location comes from the
// weatherLocation setting; empty lets wttr.in guess from your IP. Refreshed every 30 min,
// and only fetched at all while the weather widget is on.
Singleton {
    id: root

    readonly property var s: Config.saved
    readonly property bool wanted: ((s.widgets ?? true) && (s.widgetWeather ?? true)) || (s.barWeather ?? true)
    readonly property bool fahrenheit: (s.weatherUnits ?? "c") === "f"
    readonly property string location: (s.weatherLocation ?? "").trim()

    property var data: null
    readonly property bool ok: data !== null
    property bool failed: false
    property bool loading: fetch?.running ?? false
    property string fetchedFor: ""          // location the current data belongs to
    property var updatedAt: null            // Date of the last good fetch
    readonly property bool badLocation: failed && location !== "" && fetchedFor !== location

    readonly property var cur: data?.current_condition?.[0] ?? null
    readonly property var today: data?.weather?.[0] ?? null
    readonly property int temp: cur ? Number(fahrenheit ? cur.temp_F : cur.temp_C) : 0
    readonly property int hi: today ? Number(fahrenheit ? today.maxtempF : today.maxtempC) : 0
    readonly property int lo: today ? Number(fahrenheit ? today.mintempF : today.mintempC) : 0
    readonly property int code: cur ? Number(cur.weatherCode) : 113
    readonly property string desc: cur?.weatherDesc?.[0]?.value ?? ""
    readonly property var area: data?.nearest_area?.[0] ?? null
    readonly property string place: fetchedFor ? fetchedFor.replace(/^~/, "").split(",")[0].trim()
                                             : (area?.areaName?.[0]?.value ?? "")
    // "Berlin, Germany" as wttr.in resolved it
    readonly property string resolved: area ? [area.areaName?.[0]?.value, area.region?.[0]?.value, area.country?.[0]?.value]
                                                  .filter((v, i, a) => v && a.indexOf(v) === i).join(", ") : ""
    readonly property int feels: cur ? Number(fahrenheit ? cur.FeelsLikeF : cur.FeelsLikeC) : 0
    readonly property int humidity: cur ? Number(cur.humidity) : 0
    readonly property string wind: cur ? (fahrenheit ? cur.windspeedMiles + " mph " : cur.windspeedKmph + " km/h ") + (cur.winddir16Point ?? "") : ""
    readonly property int uv: cur ? Number(cur.uvIndex) : 0
    readonly property string sunrise: today?.astronomy?.[0]?.sunrise ?? ""
    readonly property string sunset: today?.astronomy?.[0]?.sunset ?? ""
    readonly property int rainChance: {
        const h = today?.hourly ?? [];
        return h.length ? Math.max(...h.map(x => Number(x.chanceofrain ?? 0))) : 0;
    }
    // Settings subtitle for the location field
    readonly property string status: badLocation ? "Couldn't find \"" + location + "\". Try \"City, Country\""
                                   : loading && fetchedFor !== location ? "Looking up…"
                                   : resolved ? (location ? "Showing " : "Detected: ") + resolved
                                   : "Empty to use your approximate location"

    // Next few days: [{ label, hi, lo, code, rain }]
    readonly property var daily: (data?.weather ?? []).map((d, i) => {
        const at = new Date(d.date + "T12:00:00");
        const noon = (d.hourly ?? [])[4] ?? (d.hourly ?? [])[0];
        return {
            label: i === 0 ? "Today" : i === 1 ? "Tomorrow" : Qt.formatDate(at, "dddd"),
            hi: Number(fahrenheit ? d.maxtempF : d.maxtempC),
            lo: Number(fahrenheit ? d.mintempF : d.mintempC),
            code: Number(noon?.weatherCode ?? 113),
            rain: Math.max(0, ...(d.hourly ?? []).map(x => Number(x.chanceofrain ?? 0)))
        };
    })
    property bool isDay: true

    // Next five hours-ish (wttr.in gives 3-hourly slots): [{ label, temp, code, day }]
    readonly property var hourly: hours(5)
    function hours(n) {
        if (!data?.weather) return [];
        const now = new Date(), out = [];
        for (let d = 0; d < data.weather.length && out.length < n; d++) {
            for (const h of data.weather[d].hourly ?? []) {
                const hour = Number(h.time) / 100;
                const at = new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, hour);
                if (at.getTime() + 3 * 3600e3 <= now.getTime()) continue;     // slot already over
                out.push({
                    label: out.length === 0 ? "Now" : Qt.formatTime(at, (s.clock24h ?? true) ? "HH" : "h AP").replace(" ", ""),
                    temp: Number(fahrenheit ? h.tempF : h.tempC),
                    code: out.length === 0 ? root.code : Number(h.weatherCode),
                    day: out.length === 0 ? root.isDay : hour >= 6 && hour < 19,
                    rain: Number(h.chanceofrain ?? 0)
                });
                if (out.length >= n) break;
            }
        }
        return out;
    }

    // Nerd Font weather glyphs
    function glyph(c, day) {
        if (c === 113) return day ? "" : "";
        if (c === 116) return day ? "" : "";
        if ([119, 122].includes(c)) return "";
        if ([143, 248, 260].includes(c)) return "";
        if ([200, 386, 389, 392, 395].includes(c)) return "";
        if ([227, 230, 323, 326, 329, 332, 335, 338, 368, 371].includes(c)) return "";
        if ([179, 182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377].includes(c)) return "";
        if ([176, 263, 266, 293, 296, 353].includes(c)) return "";
        return "";
    }
    // Sky gradient, like Apple's weather widget: [top, bottom]
    function sky(c, day) {
        if ([200, 386, 389, 392, 395].includes(c)) return ["#3b3f58", "#1f2130"];
        if ([227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 179, 182, 185, 311, 314, 317, 320, 350, 362, 365, 374, 377].includes(c))
            return day ? ["#8ea4bd", "#5d7189"] : ["#33415a", "#1b2333"];
        if (c === 113 || c === 116) return day ? ["#3f8fe0", "#2463b8"] : ["#1a2a52", "#0b1430"];
        if ([119, 122, 143, 248, 260].includes(c)) return day ? ["#71849c", "#4b5c72"] : ["#2b3446", "#161c28"];
        return day ? ["#5a6d84", "#34445a"] : ["#26314a", "#121a2b"];
    }

    function parseClock(t) {      // "06:12 AM" → minutes since midnight
        const m = /(\d+):(\d+)\s*(AM|PM)/i.exec(t ?? "");
        if (!m) return -1;
        return (Number(m[1]) % 12 + (m[3].toUpperCase() === "PM" ? 12 : 0)) * 60 + Number(m[2]);
    }
    function updateDay() {
        const a = today?.astronomy?.[0];
        const rise = parseClock(a?.sunrise), set = parseClock(a?.sunset);
        const now = new Date(), m = now.getHours() * 60 + now.getMinutes();
        isDay = rise < 0 || set < 0 ? (m >= 360 && m < 1140) : (m >= rise && m < set);
    }

    function refresh() { if (wanted && !fetch.running) { fetch.target = location; fetch.running = true; } }
    // Wait for typing to settle before looking a new place up.
    onLocationChanged: relocate.restart()
    onWantedChanged: refresh()
    Timer { id: relocate; interval: 1200; onTriggered: fetch.running ? relocate.restart() : root.refresh() }

    Process {
        id: fetch
        property string target: ""
        command: ["curl", "-sf", "-m", "20", "https://wttr.in/" + encodeURIComponent(target) + "?format=j1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text), c = j.current_condition[0];
                    if (!j.weather?.length) throw "no forecast";
                    const a = j.nearest_area?.[0] ?? {};
                    const pick = (o, keys) => { const r = {}; for (const k of keys) r[k] = o?.[k]; return r; };
                    root.data = {
                        current_condition: [Object.assign(pick(c, ["temp_C", "temp_F", "FeelsLikeC", "FeelsLikeF", "humidity", "windspeedKmph",
                                                                  "windspeedMiles", "winddir16Point", "uvIndex", "weatherCode"]),
                                                          { weatherDesc: [{ value: (c.weatherDesc?.[0]?.value ?? "").trim() }] })],
                        nearest_area: [{ areaName: [{ value: a.areaName?.[0]?.value ?? "" }], region: [{ value: a.region?.[0]?.value ?? "" }],
                                         country: [{ value: a.country?.[0]?.value ?? "" }] }],
                        weather: j.weather.slice(0, 3).map(d => ({
                            date: d.date, maxtempC: d.maxtempC, maxtempF: d.maxtempF, mintempC: d.mintempC, mintempF: d.mintempF,
                            astronomy: [{ sunrise: d.astronomy?.[0]?.sunrise, sunset: d.astronomy?.[0]?.sunset }],
                            hourly: (d.hourly ?? []).map(h => pick(h, ["time", "tempC", "tempF", "weatherCode", "chanceofrain"]))
                        }))
                    };
                    root.fetchedFor = fetch.target; root.updatedAt = new Date();
                    root.failed = false; root.updateDay();
                }
                catch (e) { console.warn("island weather:", e); root.failed = true; }
            }
        }
        onExited: code => { if (code !== 0) root.failed = true; }
    }
    Timer { interval: 30 * 60 * 1000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Timer { interval: 60 * 1000; running: root.wanted && root.ok; repeat: true; onTriggered: root.updateDay() }
    // Retry sooner after a failure (offline at login, etc.).
    Timer { interval: 2 * 60 * 1000; running: root.wanted && root.failed; repeat: true; onTriggered: root.refresh() }
}
