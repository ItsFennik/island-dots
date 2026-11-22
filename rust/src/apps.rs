use crate::paths;
use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Clone)]
pub struct AppEntry {
    pub info: gio::AppInfo,
    pub desktop: Option<gio_unix::DesktopAppInfo>,
    pub id: String,
    pub name: String,
    pub comment: String,
    pub generic_name: String,
    pub icon: Option<String>,
    pub keywords: Vec<String>,
    pub terminal: bool,
    pub working_dir: Option<PathBuf>,
    exec: Option<String>,
}

pub struct AppIndex {
    pub apps: Vec<AppEntry>,
    usage: BTreeMap<String, i64>,
    usage_path: PathBuf,
}

fn desktop_id(id: &str) -> &str {
    id.strip_suffix(".desktop").unwrap_or(id)
}

fn icon_name(info: &gio::AppInfo) -> Option<String> {
    let icon = info.icon()?;
    if let Ok(themed) = icon.clone().downcast::<gio::ThemedIcon>() {
        if let Some(name) = themed.names().first() {
            return Some(name.to_string());
        }
    }
    let text = icon.to_string()?;
    text.strip_prefix("GThemedIcon: ")
        .and_then(|s| s.split(',').next())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

impl AppIndex {
    pub fn load() -> Self {
        let mut apps = Vec::new();
        let mut seen = BTreeSet::new();
        for info in gio::AppInfo::all() {
            if !info.should_show() {
                continue;
            }
            let name = info.name().to_string();
            if name.trim().is_empty() {
                continue;
            }
            let raw_id = info.id().map_or_else(|| name.clone(), |id| id.to_string());
            let id = desktop_id(&raw_id).to_string();
            if !seen.insert(id.clone()) {
                continue;
            }
            let desktop = gio_unix::DesktopAppInfo::new(&raw_id)
                .or_else(|| gio_unix::DesktopAppInfo::new(&id))
                .or_else(|| gio_unix::DesktopAppInfo::new(&format!("{id}.desktop")));
            let comment = info
                .description()
                .map(|s| s.to_string())
                .unwrap_or_default();
            let generic_name = desktop
                .as_ref()
                .and_then(gio_unix::DesktopAppInfo::generic_name)
                .map(|s| s.to_string())
                .unwrap_or_default();
            let icon = icon_name(&info).or_else(|| {
                desktop
                    .as_ref()
                    .and_then(|desktop| desktop.string("Icon"))
                    .map(|s| s.to_string())
            });
            let keywords = desktop
                .as_ref()
                .map(|desktop| desktop.keywords().iter().map(ToString::to_string).collect())
                .unwrap_or_default();
            let terminal = desktop
                .as_ref()
                .is_some_and(|desktop| desktop.boolean("Terminal"));
            let working_dir = desktop
                .as_ref()
                .and_then(|desktop| desktop.string("Path"))
                .filter(|path| !path.is_empty())
                .map(PathBuf::from);
            let exec = desktop
                .as_ref()
                .and_then(|desktop| desktop.string("Exec"))
                .map(|s| s.to_string());
            apps.push(AppEntry {
                info,
                desktop,
                id,
                name,
                comment,
                generic_name,
                icon,
                keywords,
                terminal,
                working_dir,
                exec,
            });
        }
        apps.sort_by_key(|app| app.name.to_lowercase());
        let usage_path = paths::state_dir().join("island/launcher.json");
        let usage = fs::read_to_string(&usage_path)
            .ok()
            .and_then(|text| serde_json::from_str::<BTreeMap<String, i64>>(&text).ok())
            .unwrap_or_default();
        Self {
            apps,
            usage,
            usage_path,
        }
    }

    pub fn by_id(&self, id: &str) -> Option<&AppEntry> {
        let id = desktop_id(id);
        self.apps.iter().find(|app| app.id == id)
    }

    pub fn usage(&self) -> &BTreeMap<String, i64> {
        &self.usage
    }

    pub fn record_launch(&mut self, id: &str) {
        *self.usage.entry(id.to_string()).or_insert(0) += 1;
        let Ok(text) = serde_json::to_string(&self.usage) else {
            return;
        };
        if let Some(dir) = self.usage_path.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let tmp = self.usage_path.with_extension("json.tmp");
        if fs::write(&tmp, format!("{text}\n")).is_ok() {
            let _ = fs::rename(&tmp, &self.usage_path);
        }
    }

    pub fn ranked_all(&self) -> Vec<usize> {
        let mut indices: Vec<usize> = (0..self.apps.len()).collect();
        indices.sort_by(|&a, &b| {
            let count_a = self.usage.get(&self.apps[a].id).copied().unwrap_or(0);
            let count_b = self.usage.get(&self.apps[b].id).copied().unwrap_or(0);
            count_b
                .cmp(&count_a)
                .then_with(|| self.apps[a].name.cmp(&self.apps[b].name))
        });
        indices
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<usize> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return self.ranked_all().into_iter().take(limit).collect();
        }
        let mut hits: Vec<(f64, usize)> = self
            .apps
            .iter()
            .enumerate()
            .filter_map(|(index, app)| {
                let score = self.score(app, &q);
                (score > 0.0).then_some((score, index))
            })
            .collect();
        hits.sort_by(|(score_a, index_a), (score_b, index_b)| {
            score_b
                .total_cmp(score_a)
                .then_with(|| self.apps[*index_a].name.cmp(&self.apps[*index_b].name))
        });
        hits.into_iter()
            .take(limit)
            .map(|(_, index)| index)
            .collect()
    }

    #[allow(clippy::cast_precision_loss)]
    fn score(&self, app: &AppEntry, q: &str) -> f64 {
        let mut score = f64::from(match_score(&app.name.to_lowercase(), q));
        if !app.generic_name.is_empty() {
            score = score.max(f64::from(match_score(&app.generic_name.to_lowercase(), q)) * 0.6);
        }
        for keyword in &app.keywords {
            score = score.max(f64::from(match_score(&keyword.to_lowercase(), q)) * 0.5);
        }
        score = score.max(f64::from(match_score(&app.id.to_lowercase(), q)) * 0.4);
        if score > 0.0 {
            let count = self.usage.get(&app.id).copied().unwrap_or(0).max(0);
            score + (1.0 + count as f64).log2() * 30.0
        } else {
            0.0
        }
    }
}

fn is_word_boundary(c: char) -> bool {
    c.is_whitespace() || matches!(c, '-' | '_' | '.')
}

#[allow(clippy::cast_possible_truncation, clippy::cast_possible_wrap)]
pub fn match_score(text: &str, query: &str) -> i32 {
    if text.is_empty() || query.is_empty() {
        return 0;
    }
    if text == query {
        return 1000;
    }
    if let Some(rest) = text.strip_prefix(query) {
        return 900 - rest.encode_utf16().count() as i32 - query.encode_utf16().count() as i32;
    }
    if let Some(byte_index) = text.find(query) {
        let index = text[..byte_index].encode_utf16().count() as i32;
        if index > 0 {
            let before = text[..byte_index].chars().next_back();
            return (if before.is_some_and(is_word_boundary) {
                750
            } else {
                500
            }) - index;
        }
    }
    let units: Vec<u16> = text.encode_utf16().collect();
    let mut score = 0_i32;
    let mut from = 0_usize;
    let mut run = 0_i32;
    let mut last: Option<usize> = None;
    for wanted in query.chars() {
        let mut buffer = [0_u16; 2];
        let wanted = wanted.encode_utf16(&mut buffer);
        let Some(offset) = units[from..]
            .windows(wanted.len())
            .position(|window| window == wanted)
        else {
            return 0;
        };
        let index = from + offset;
        run = if last == Some(index.saturating_sub(1)) {
            run + 1
        } else {
            0
        };
        let boundary =
            index == 0 || char::from_u32(u32::from(units[index - 1])).is_some_and(is_word_boundary);
        score += 10 + run * 15 + if boundary { 25 } else { 0 }
            - i32::try_from(index.saturating_sub(from))
                .unwrap_or(10)
                .min(10);
        last = Some(index);
        from = index + wanted.len();
    }
    score.clamp(1, 400)
}

impl AppEntry {
    pub fn subtitle(&self) -> &str {
        if self.comment.is_empty() {
            &self.generic_name
        } else {
            &self.comment
        }
    }

    pub fn actions(&self) -> Vec<(String, String)> {
        let Some(desktop) = &self.desktop else {
            return Vec::new();
        };
        desktop
            .list_actions()
            .into_iter()
            .map(|action| {
                let name = desktop.action_name(&action).to_string();
                (action.to_string(), name)
            })
            .filter(|(_, name)| !name.is_empty())
            .collect()
    }

    pub fn launch_action(&self, action: &str) {
        if let Some(desktop) = &self.desktop {
            desktop.launch_action(action, None::<&gio::AppLaunchContext>);
        }
    }
}

fn expand_exec(arg: &str, app: &AppEntry) -> Vec<OsString> {
    match arg {
        "%f" | "%u" | "%F" | "%U" | "%d" | "%D" | "%n" | "%N" | "%v" | "%m" => return Vec::new(),
        "%i" => {
            return app
                .icon
                .as_ref()
                .map(|icon| vec![OsString::from("--icon"), OsString::from(icon)])
                .unwrap_or_default();
        }
        _ => {}
    }
    let mut out = String::new();
    let mut chars = arg.chars();
    while let Some(c) = chars.next() {
        if c != '%' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('%') => out.push('%'),
            Some('c') => out.push_str(&app.name),
            Some('k') => out.push_str(
                &app.desktop
                    .as_ref()
                    .and_then(gio_unix::DesktopAppInfo::filename)
                    .map(|path| path.to_string_lossy().to_string())
                    .unwrap_or_default(),
            ),
            Some('f' | 'u' | 'F' | 'U' | 'd' | 'D' | 'n' | 'N' | 'v' | 'm') | None => {}
            Some(other) => {
                out.push('%');
                out.push(other);
            }
        }
    }
    if out.is_empty() {
        Vec::new()
    } else {
        vec![OsString::from(out)]
    }
}

fn terminal_command(app: &AppEntry) -> Option<Vec<OsString>> {
    let exec = app.exec.as_deref()?;
    let args = glib::shell_parse_argv(exec).ok()?;
    let mut command = Vec::new();
    for arg in args {
        command.extend(expand_exec(&arg.to_string_lossy(), app));
    }
    Some(command)
}

/// Launches an app entry, adding a terminal when the desktop entry asks for one.
///
/// # Errors
/// Returns a message when the entry has no usable `Exec` line or spawning fails.
pub fn launch(app: &AppEntry) -> Result<(), String> {
    if app.terminal {
        let mut command = terminal_command(app)
            .filter(|command| !command.is_empty())
            .ok_or_else(|| format!("{} has no Exec line", app.id))?;
        let terminal = std::env::var("TERMINAL").unwrap_or_else(|_| "foot".to_string());
        command.insert(0, OsString::from("-e"));
        command.insert(0, OsString::from(terminal));
        let first = command.remove(0);
        let mut child = Command::new(first)
            .args(&command)
            .current_dir(app.working_dir.clone().unwrap_or_else(paths::home))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| format!("could not start terminal: {error}"))?;
        std::thread::spawn(move || {
            let _ = child.wait();
        });
        return Ok(());
    }
    let files: [gio::File; 0] = [];
    app.info
        .launch(&files, None::<&gio::AppLaunchContext>)
        .map_err(|error| format!("could not launch {}: {error}", app.name))
}
