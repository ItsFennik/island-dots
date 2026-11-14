pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// App index for the launcher: desktop entries (Quickshell parses them itself, and watches
// the directories), fuzzy search and launch counts. The counts are stored in
// ~/.local/state/island/launcher.json so the apps you use most rank first.
Singleton {
    id: root

    property var usage: ({})                      // desktop id -> launches
    readonly property var apps: {
        const seen = {};
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || seen[e.id]) continue;
            seen[e.id] = true;
            out.push(e);
        }
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }

    // ── Search ────────────────────────────────────────────────────────
    // Returns a score for `q` in `text` (both lower-case), 0 when it doesn't match.
    function match(text, q) {
        if (!text) return 0;
        if (text === q) return 1000;
        if (text.startsWith(q)) return 900 - text.length;
        const i = text.indexOf(q);
        if (i > 0) return (/[\s\-_.]/.test(text[i - 1]) ? 750 : 500) - i;
        // Fuzzy subsequence: reward consecutive runs and word starts, punish gaps.
        let score = 0, ti = 0, run = 0, last = -1;
        for (const c of q) {
            const j = text.indexOf(c, ti);
            if (j < 0) return 0;
            run = j === last + 1 ? run + 1 : 0;
            score += 10 + run * 15 + (j === 0 || /[\s\-_.]/.test(text[j - 1]) ? 25 : 0) - Math.min(j - ti, 10);
            last = j; ti = j + 1;
        }
        return Math.max(1, Math.min(400, score));
    }

    function score(e, q) {
        let s = match(e.name.toLowerCase(), q);
        s = Math.max(s, match((e.genericName ?? "").toLowerCase(), q) * 0.6);
        for (const k of (e.keywords ?? [])) s = Math.max(s, match(k.toLowerCase(), q) * 0.5);
        s = Math.max(s, match(e.id.toLowerCase(), q) * 0.4);
        return s > 0 ? s + Math.log2(1 + (usage[e.id] ?? 0)) * 30 : 0;
    }

    function search(query) {
        const q = query.trim().toLowerCase();
        if (q === "")
            return apps.slice().sort((a, b) => ((usage[b.id] ?? 0) - (usage[a.id] ?? 0)) || a.name.localeCompare(b.name));
        const hits = [];
        for (const e of apps) {
            const s = score(e, q);
            if (s > 0) hits.push({ e, s });
        }
        hits.sort((a, b) => (b.s - a.s) || a.e.name.localeCompare(b.e.name));
        return hits.map(h => h.e);
    }

    // Name with the matched characters wrapped for StyledText.
    function highlight(name, query, color) {
        const esc = c => c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "&" ? "&amp;" : c;
        const q = query.trim().toLowerCase();
        if (q === "") return name.split("").map(esc).join("");
        const lower = name.toLowerCase();
        const marks = new Array(name.length).fill(false);
        const i = lower.indexOf(q);
        if (i >= 0) for (let k = i; k < i + q.length; k++) marks[k] = true;
        else {
            let ti = 0;
            for (const c of q) { const j = lower.indexOf(c, ti); if (j < 0) return name.split("").map(esc).join(""); marks[j] = true; ti = j + 1; }
        }
        let out = "";
        for (let k = 0; k < name.length; k++)
            out += marks[k] ? `<font color="${color}"><b>${esc(name[k])}</b></font>` : esc(name[k]);
        return out;
    }

    // ── Launch ────────────────────────────────────────────────────────
    function launch(e) {
        const u = Object.assign({}, usage);
        u[e.id] = (u[e.id] ?? 0) + 1;
        usage = u;
        store.setText(JSON.stringify(u) + "\n");

        if (e.runInTerminal) {
            const term = Quickshell.env("TERMINAL") || "foot";
            Quickshell.execDetached({ command: [term, "-e", ...e.command], workingDirectory: e.workingDirectory || Quickshell.env("HOME") });
        } else {
            e.execute();
        }
    }

    function run(cmd) {
        Quickshell.execDetached({ command: ["sh", "-c", cmd], workingDirectory: Quickshell.env("HOME") });
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island/launcher.json"
        printErrors: false
        atomicWrites: true
        onLoaded: { try { root.usage = JSON.parse(text()) ?? {}; } catch (e) { root.usage = {}; } }
    }
}
