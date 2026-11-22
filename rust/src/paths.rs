use serde_json::Value;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var)
        .map(PathBuf::from)
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| home().join(fallback))
}

pub fn config_dir() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config")
}

pub fn state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state")
}

pub fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
}

pub fn shell_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("ISLAND_SHELL_DIR") {
        let dir = PathBuf::from(dir);
        if dir.join("defaults.json").is_file() {
            return dir;
        }
    }
    let local = config_dir().join("quickshell/island");
    if local.join("defaults.json").is_file() {
        return local;
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent().and_then(Path::parent) {
            if dir.join("defaults.json").is_file() {
                return dir.to_path_buf();
            }
        }
    }
    local
}

pub fn settings_file() -> PathBuf {
    config_dir().join("island/settings.json")
}

pub fn defaults_file() -> PathBuf {
    shell_dir().join("defaults.json")
}

pub fn themes_dir() -> PathBuf {
    shell_dir().join("themes")
}

pub fn theme_state_file() -> PathBuf {
    state_dir().join("island/theme")
}

pub fn spotlight_state_file() -> PathBuf {
    state_dir().join("island/spotlight.json")
}

pub fn apply_settings_script() -> PathBuf {
    shell_dir().join("apply-settings.sh")
}

pub fn power_script() -> PathBuf {
    shell_dir().join("scripts/island-power")
}

pub fn theme_id() -> String {
    std::fs::read_to_string(theme_state_file())
        .map(|s| s.trim().to_string())
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "macos".into())
}

pub fn load_json(path: &Path) -> Option<Value> {
    let text = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

pub fn merged_settings() -> BTreeMap<String, Value> {
    let mut out = BTreeMap::new();
    if let Some(Value::Object(defaults)) = load_json(&defaults_file()) {
        out.extend(defaults);
    }
    if let Some(Value::Object(user)) = load_json(&settings_file()) {
        out.extend(user);
    }
    out
}

pub fn value(map: &BTreeMap<String, Value>, key: &str) -> Value {
    map.get(key).cloned().unwrap_or(Value::Null)
}

pub fn bool_value(map: &BTreeMap<String, Value>, key: &str, fallback: bool) -> bool {
    map.get(key).and_then(Value::as_bool).unwrap_or(fallback)
}

pub fn i64_value(map: &BTreeMap<String, Value>, key: &str, fallback: i64) -> i64 {
    map.get(key).and_then(Value::as_i64).unwrap_or(fallback)
}

pub fn f64_value(map: &BTreeMap<String, Value>, key: &str, fallback: f64) -> f64 {
    map.get(key).and_then(Value::as_f64).unwrap_or(fallback)
}

pub fn str_value<'a>(map: &'a BTreeMap<String, Value>, key: &str, fallback: &'a str) -> &'a str {
    map.get(key).and_then(Value::as_str).unwrap_or(fallback)
}
