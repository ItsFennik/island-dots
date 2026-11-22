use crate::paths;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn spawn(program: impl AsRef<std::ffi::OsStr>, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_ok()
}

pub fn power(action: &str) {
    let script = paths::power_script();
    if script.is_file() {
        let _ = Command::new(script)
            .arg(action)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}

pub fn apply_settings() {
    let script = paths::apply_settings_script();
    if script.is_file() {
        let _ = Command::new(script)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}

pub fn open_url(url: &str) {
    spawn("xdg-open", &[url]);
}

pub fn open_path(path: &Path) {
    if let Some(path) = path.to_str() {
        spawn("xdg-open", &[path]);
    }
}

pub fn run_command(command: &str) {
    let home = paths::home();
    let _ = Command::new("sh")
        .arg("-c")
        .arg(command)
        .current_dir(home)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

pub fn copy_text(text: &str) {
    let _ = Command::new("wl-copy")
        .arg(text)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

pub fn settings_binary() -> PathBuf {
    if let Some(path) = std::env::var_os("ISLAND_SETTINGS_BIN") {
        return PathBuf::from(path);
    }
    let local = paths::home().join(".local/bin/island-settings");
    if local.is_file() {
        return local;
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let sibling = dir.join("island-settings");
            if sibling.is_file() {
                return sibling;
            }
        }
    }
    local
}

pub fn open_settings(page: Option<&str>) {
    let binary = settings_binary();
    let shell = paths::shell_dir();
    let mut command = Command::new(binary);
    command.arg("--open");
    if let Some(page) = page.filter(|p| !p.is_empty()) {
        command.arg("--page").arg(page);
    }
    command.arg("--shell-dir").arg(shell);
    let _ = command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

pub fn open_qml_settings(page: Option<&str>) {
    let target = match page.filter(|p| !p.is_empty()) {
        Some(page) => vec!["-c", "island", "ipc", "call", "settings", "qmlPage", page],
        None => vec!["-c", "island", "ipc", "call", "settings", "qml"],
    };
    spawn("qs", &target);
}
