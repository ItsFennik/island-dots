use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

/// Typed view of Island's settings.json. Unknown keys are kept in `extra`.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub gaps_in: i64,
    pub gaps_out: i64,
    pub border_size: i64,
    pub rounding: i64,
    pub layout: String,
    pub active_opacity: f64,
    pub inactive_opacity: f64,
    pub dim_inactive: bool,
    pub blur: bool,
    pub blur_size: i64,
    pub blur_passes: i64,
    pub animations: bool,
    pub anim_speed: f64,
    pub anim_curve: String,
    pub window_anim: String,
    pub workspace_anim: String,
    pub follow_mouse: i64,
    pub sensitivity: f64,
    pub accel_profile: String,
    pub natural_scroll: bool,
    pub repeat_rate: i64,
    pub repeat_delay: i64,
    pub numlock: bool,
    pub bar_height: i64,
    pub bar_opacity: f64,
    pub bar_font_size: i64,
    pub bar_blur: bool,
    pub clock24h: bool,
    pub clock_seconds: bool,
    pub clock_date: String,
    pub bar_app_menus: bool,
    pub bar_search: bool,
    pub bar_items: Value,
    pub widget_font_weight: String,
    pub term_font: String,
    pub term_font_size: i64,
    pub term_opacity: f64,
    pub term_padding: i64,
    pub gtk_theme: String,
    pub icon_theme: String,
    pub icon_style: String,
    pub icon_tint: String,
    pub shell_layout: String,
    pub taskbar_height: i64,
    pub taskbar_magnify: bool,
    pub taskbar_magnify_size: f64,
    pub taskbar_bounce: bool,
    pub compact_stats: bool,
    pub compact_icon_size: i64,
    pub automount: bool,
    pub automount_open: bool,
    pub automount_notify: bool,
    pub mount_at_login: Vec<String>,
    pub desktop_icons: bool,
    pub desktop_icons_apps: bool,
    pub desktop_icon_size: i64,
    pub cursor_theme: String,
    pub cursor_size: i64,
    pub matugen: bool,
    pub matugen_scheme: String,
    pub matugen_mode: String,
    pub matugen_prefer: String,
    pub wall_dir: String,
    pub video_dir: String,
    pub video_mpv_options: String,
    pub wall_transition: String,
    pub wall_duration: f64,
    pub wallhaven_query: String,
    pub wallhaven_sorting: String,
    pub wallhaven_top_range: String,
    pub wallhaven_general: bool,
    pub wallhaven_anime: bool,
    pub wallhaven_people: bool,
    pub wallhaven_sketchy: bool,
    pub wallhaven_nsfw: bool,
    pub wallhaven_atleast: String,
    pub wallhaven_ratios: String,
    pub notif_timeout: i64,
    pub notif_dnd: bool,
    pub widgets: bool,
    pub widget_style: String,
    pub widget_colors: String,
    pub text_color: String,
    pub widget_pos: Value,
    pub widget_size: Value,
    pub widgets_position: String,
    pub widgets_all_screens: bool,
    pub widgets_margin: i64,
    pub widgets_opacity: f64,
    pub widget_font: String,
    pub widget_clock: bool,
    pub widget_clock_seconds: bool,
    pub widget_weather: bool,
    pub weather_location: String,
    pub weather_units: String,
    pub bar_weather: bool,
    pub bar_skin: String,
    pub spotlight_from_capsule: bool,
    pub spotlight_style: String,
    pub spotlight_width: i64,
    pub spotlight_rows: i64,
    pub spotlight_files: bool,
    pub spotlight_commands: bool,
    pub spotlight_web: bool,
    pub bar_workspaces: bool,
    pub bar_workspace_style: String,
    pub bar_workspace_count: i64,
    pub widget_calendar: bool,
    pub widget_music: bool,
    pub widget_system: bool,
    pub widget_verse: bool,
    pub lock_verse: bool,
    pub lock_screen: String,
    pub lock_typing_fx: bool,
    pub lock_password_mask: String,
    pub lock_on_start: bool,
    pub overview_workspaces: i64,
    pub dock: bool,
    pub dock_autohide: bool,
    pub dock_all_screens: bool,
    pub main_screen: String,
    pub dock_size: i64,
    pub dock_magnify: bool,
    pub dock_magnify_size: f64,
    pub dock_opacity: f64,
    pub dock_margin: i64,
    pub dock_pinned: Vec<String>,
    pub accent_color: String,
    pub screenshot_dest: String,
    pub screenshot_copy: bool,
    pub screenshot_thumb: bool,
    pub screenshot_pointer: bool,
    pub screenshot_sound: bool,
    pub liquid_glass: bool,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            gaps_in: 5,
            gaps_out: 5,
            border_size: 3,
            rounding: 0,
            layout: "dwindle".to_string(),
            active_opacity: 1.0,
            inactive_opacity: 1.0,
            dim_inactive: false,
            blur: true,
            blur_size: 3,
            blur_passes: 1,
            animations: true,
            anim_speed: 2.0,
            anim_curve: "smooth".to_string(),
            window_anim: "popin".to_string(),
            workspace_anim: "slide".to_string(),
            follow_mouse: 1,
            sensitivity: 0.0,
            accel_profile: "flat".to_string(),
            natural_scroll: false,
            repeat_rate: 25,
            repeat_delay: 600,
            numlock: true,
            bar_height: 30,
            bar_opacity: 0.55,
            bar_font_size: 13,
            bar_blur: true,
            clock24h: true,
            clock_seconds: false,
            clock_date: "full".to_string(),
            bar_app_menus: true,
            bar_search: true,
            bar_items: Value::Null,
            widget_font_weight: "400".to_string(),
            term_font: "PPRightSerifMono Nerd Font Mono".to_string(),
            term_font_size: 12,
            term_opacity: 0.8,
            term_padding: 10,
            gtk_theme: "auto".to_string(),
            icon_theme: "WhiteSur-dark".to_string(),
            icon_style: "default".to_string(),
            icon_tint: "".to_string(),
            shell_layout: "menubar".to_string(),
            taskbar_height: 54,
            taskbar_magnify: true,
            taskbar_magnify_size: 1.7,
            taskbar_bounce: true,
            compact_stats: true,
            compact_icon_size: 28,
            automount: false,
            automount_open: false,
            automount_notify: true,
            mount_at_login: vec![],
            desktop_icons: false,
            desktop_icons_apps: true,
            desktop_icon_size: 56,
            cursor_theme: "macOS27-GoldenGate".to_string(),
            cursor_size: 28,
            matugen: false,
            matugen_scheme: "tonal-spot".to_string(),
            matugen_mode: "dark".to_string(),
            matugen_prefer: "saturation".to_string(),
            wall_dir: "~/Pictures/Wallpapers".to_string(),
            video_dir: "~/Videos/Wallpapers".to_string(),
            video_mpv_options: "no-audio loop hwdec=auto panscan=1.0".to_string(),
            wall_transition: "fade".to_string(),
            wall_duration: 0.8,
            wallhaven_query: "".to_string(),
            wallhaven_sorting: "toplist".to_string(),
            wallhaven_top_range: "1M".to_string(),
            wallhaven_general: true,
            wallhaven_anime: true,
            wallhaven_people: false,
            wallhaven_sketchy: false,
            wallhaven_nsfw: false,
            wallhaven_atleast: "1920x1080".to_string(),
            wallhaven_ratios: "".to_string(),
            notif_timeout: 5,
            notif_dnd: false,
            widgets: true,
            widget_style: "tahoe".to_string(),
            widget_colors: "system".to_string(),
            text_color: "auto".to_string(),
            widget_pos: serde_json::Value::Object(serde_json::Map::new()),
            widget_size: serde_json::Value::Object(serde_json::Map::new()),
            widgets_position: "top-left".to_string(),
            widgets_all_screens: false,
            widgets_margin: 24,
            widgets_opacity: 0.55,
            widget_font: "Adwaita Sans".to_string(),
            widget_clock: true,
            widget_clock_seconds: true,
            widget_weather: true,
            weather_location: "".to_string(),
            weather_units: "c".to_string(),
            bar_weather: true,
            bar_skin: "classic".to_string(),
            spotlight_from_capsule: true,
            spotlight_style: "auto".to_string(),
            spotlight_width: 700,
            spotlight_rows: 9,
            spotlight_files: true,
            spotlight_commands: true,
            spotlight_web: true,
            bar_workspaces: true,
            bar_workspace_style: "numbers".to_string(),
            bar_workspace_count: 5,
            widget_calendar: true,
            widget_music: true,
            widget_system: true,
            widget_verse: true,
            lock_verse: true,
            lock_screen: "island".to_string(),
            lock_typing_fx: true,
            lock_password_mask: "last".to_string(),
            lock_on_start: false,
            overview_workspaces: 10,
            dock: true,
            dock_autohide: false,
            dock_all_screens: false,
            main_screen: "".to_string(),
            dock_size: 52,
            dock_magnify: true,
            dock_magnify_size: 1.7,
            dock_opacity: 0.45,
            dock_margin: 6,
            dock_pinned: vec![
                "org.gnome.Nautilus".to_string(),
                "librewolf".to_string(),
                "foot".to_string(),
                "vesktop".to_string(),
                "Cider".to_string(),
                "steam".to_string(),
                "net.lutris.Lutris".to_string(),
                "com.moonlight_stream.Moonlight".to_string(),
            ],
            accent_color: "".to_string(),
            screenshot_dest: "~/Pictures/Screenshots".to_string(),
            screenshot_copy: true,
            screenshot_thumb: true,
            screenshot_pointer: false,
            screenshot_sound: true,
            liquid_glass: false,
            extra: BTreeMap::new(),
        }
    }
}

#[derive(Clone)]
pub struct Store {
    path: PathBuf,
    defaults: Settings,
    current: Settings,
}

impl Store {
    pub fn load() -> Self {
        let defaults = match crate::paths::load_json(&crate::paths::defaults_file()) {
            Some(value) => serde_json::from_value(value).unwrap_or_default(),
            None => Settings::default(),
        };
        let user = crate::paths::load_json(&crate::paths::settings_file())
            .unwrap_or(Value::Object(Default::default()));
        let mut merged =
            serde_json::to_value(&defaults).unwrap_or(Value::Object(Default::default()));
        merge(&mut merged, &user);
        let current = serde_json::from_value(merged).unwrap_or_else(|_| defaults.clone());
        Self {
            path: crate::paths::settings_file(),
            defaults,
            current,
        }
    }

    pub fn get(&self, key: &str) -> Value {
        serde_json::to_value(&self.current)
            .ok()
            .and_then(|value| value.get(key).cloned())
            .unwrap_or(Value::Null)
    }

    pub fn bool(&self, key: &str, fallback: bool) -> bool {
        self.get(key).as_bool().unwrap_or(fallback)
    }

    pub fn i64(&self, key: &str, fallback: i64) -> i64 {
        let value = self.get(key);
        value
            .as_i64()
            .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
            .unwrap_or(fallback)
    }

    pub fn f64(&self, key: &str, fallback: f64) -> f64 {
        self.get(key).as_f64().unwrap_or(fallback)
    }

    pub fn set_default(&self, key: &str) -> bool {
        self.is_default(key)
    }

    pub fn string(&self, key: &str, fallback: &str) -> String {
        self.get(key)
            .as_str()
            .map_or_else(|| fallback.to_string(), str::to_string)
    }

    pub fn is_default(&self, key: &str) -> bool {
        self.get(key) == self.defaults_value(key)
    }

    fn defaults_value(&self, key: &str) -> Value {
        serde_json::to_value(&self.defaults)
            .ok()
            .and_then(|value| value.get(key).cloned())
            .unwrap_or(Value::Null)
    }

    /// Changes a field and returns true when it was accepted. No disk write happens here.
    pub fn set(&mut self, key: &str, value: Value) -> bool {
        let mut map = match serde_json::to_value(&self.current) {
            Ok(Value::Object(map)) => map,
            _ => return false,
        };
        map.insert(key.to_string(), value);
        match serde_json::from_value(Value::Object(map)) {
            Ok(next) => {
                self.current = next;
                true
            }
            Err(error) => {
                eprintln!("island-settings: rejected {key}: {error}");
                false
            }
        }
    }

    pub fn default_keys(&self) -> Vec<String> {
        serde_json::to_value(&self.defaults)
            .ok()
            .and_then(|value| value.as_object().map(|map| map.keys().cloned().collect()))
            .unwrap_or_default()
    }

    pub fn reset(&mut self, keys: &[&str]) {
        for key in keys {
            let value = self.defaults_value(key);
            let _ = self.set(key, value);
        }
    }

    /// Writes the user file atomically, keeping unknown keys from the file on disk.
    pub fn save(&self) -> std::io::Result<()> {
        let defaults =
            serde_json::to_value(&self.defaults).unwrap_or(Value::Object(Default::default()));
        let current =
            serde_json::to_value(&self.current).unwrap_or(Value::Object(Default::default()));
        let mut user = match crate::paths::load_json(&self.path) {
            Some(Value::Object(map)) => map,
            _ => serde_json::Map::new(),
        };
        let current = match current {
            Value::Object(map) => map,
            _ => serde_json::Map::new(),
        };
        let defaults = match defaults {
            Value::Object(map) => map,
            _ => serde_json::Map::new(),
        };
        for (key, value) in current {
            if defaults.get(&key) != Some(&value) {
                user.insert(key, value);
            } else {
                user.remove(&key);
            }
        }
        let dir = self.path.parent().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::Other, "settings path has no parent")
        })?;
        fs::create_dir_all(dir)?;
        let text = serde_json::to_string_pretty(&Value::Object(user))
            .map_err(std::io::Error::other)?
            + "\n";
        let tmp = self
            .path
            .with_extension(format!("json.tmp.{}", std::process::id()));
        {
            let mut file = fs::File::create(&tmp)?;
            file.write_all(text.as_bytes())?;
            file.sync_all()?;
        }
        fs::rename(&tmp, &self.path)
    }

    /// The exact merged object currently in memory, for watcher comparison.
    pub fn snapshot(&self) -> Value {
        serde_json::to_value(&self.current).unwrap_or(Value::Null)
    }

    pub fn replace_from_disk(&mut self) -> bool {
        let defaults =
            serde_json::to_value(&self.defaults).unwrap_or(Value::Object(Default::default()));
        let user = crate::paths::load_json(&self.path).unwrap_or(Value::Object(Default::default()));
        let mut merged = defaults;
        merge(&mut merged, &user);
        match serde_json::from_value(merged) {
            Ok(next) => {
                if serde_json::to_value(&next).ok() == serde_json::to_value(&self.current).ok() {
                    return false;
                }
                self.current = next;
                true
            }
            Err(_) => false,
        }
    }
}

fn merge(base: &mut Value, overlay: &Value) {
    match (base, overlay) {
        (Value::Object(base), Value::Object(overlay)) => {
            for (key, value) in overlay {
                match base.get_mut(key) {
                    Some(existing) => merge(existing, value),
                    None => {
                        base.insert(key.clone(), value.clone());
                    }
                }
            }
        }
        (base, overlay) => *base = overlay.clone(),
    }
}

impl crate::config::SettingsRead for Store {
    fn bool(&self, key: &str, fallback: bool) -> bool {
        Self::bool(self, key, fallback)
    }

    fn i64(&self, key: &str, fallback: i64) -> i64 {
        Self::i64(self, key, fallback)
    }

    fn string(&self, key: &str, fallback: &str) -> String {
        Self::string(self, key, fallback)
    }
}
