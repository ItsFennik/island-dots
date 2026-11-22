use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib::object::Cast;

#[derive(Clone)]
pub struct AppEntry {
    pub info: gio::AppInfo,
    pub desktop: Option<gio_unix::DesktopAppInfo>,
    pub id: String,
    pub name: String,
    pub description: String,
    pub icon: Option<String>,
}

pub struct AppIndex {
    pub apps: Vec<AppEntry>,
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
        for info in gio::AppInfo::all() {
            if !info.should_show() {
                continue;
            }
            let name = info.name().to_string();
            if name.trim().is_empty() {
                continue;
            }
            let id = info
                .id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| name.clone());
            let description = info
                .description()
                .map(|s| s.to_string())
                .unwrap_or_default();
            let icon = icon_name(&info);
            let desktop = gio_unix::DesktopAppInfo::new(&id)
                .or_else(|| gio_unix::DesktopAppInfo::new(&format!("{id}.desktop")));
            apps.push(AppEntry {
                info,
                desktop,
                id,
                name,
                description,
                icon,
            });
        }
        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Self { apps }
    }

    pub fn by_id(&self, id: &str) -> Option<&AppEntry> {
        self.apps.iter().find(|app| app.id == id)
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<AppEntry> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Vec::new();
        }
        let mut hits: Vec<(i32, &AppEntry)> = self
            .apps
            .iter()
            .filter_map(|app| score(app, &q).map(|score| (score, app)))
            .collect();
        hits.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.name.cmp(&b.1.name)));
        hits.into_iter()
            .take(limit)
            .map(|(_, app)| app.clone())
            .collect()
    }
}

fn score(app: &AppEntry, q: &str) -> Option<i32> {
    let name = app.name.to_lowercase();
    let mut score = 0;
    if name == q {
        score = 1000;
    } else if name.starts_with(q) {
        score = 850;
    } else if name
        .split(|c: char| c == ' ' || c == '-' || c == '_' || c == '.')
        .any(|word| word.starts_with(q))
    {
        score = 700;
    } else if name.contains(q) {
        score = 520;
    } else if app.description.to_lowercase().contains(q) {
        score = 260;
    }
    (score > 0).then_some(score)
}

impl AppEntry {
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

pub fn launch(app: &AppEntry) {
    let files: [gio::File; 0] = [];
    let _ = app.info.launch(&files, None::<&gio::AppLaunchContext>);
}
