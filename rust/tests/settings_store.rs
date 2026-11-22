use island_rust::settings_store::Store;
use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("island-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn round_trip_keeps_unknown_keys_and_only_writes_changes() {
    let root = temp_dir("settings-store");
    let config = root.join("config");
    let state = root.join("state");
    let home = root.join("home");
    fs::create_dir_all(config.join("island")).unwrap();
    fs::create_dir_all(&state).unwrap();
    fs::create_dir_all(&home).unwrap();
    std::env::set_var("XDG_CONFIG_HOME", &config);
    std::env::set_var("XDG_STATE_HOME", &state);
    std::env::set_var("HOME", &home);
    let shell = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf();
    std::env::set_var("ISLAND_SHELL_DIR", &shell);
    let defaults: Value =
        serde_json::from_str(&fs::read_to_string(shell.join("defaults.json")).unwrap()).unwrap();
    let default_gaps = defaults.get("gapsIn").and_then(Value::as_i64).unwrap_or(5);

    let path = config.join("island/settings.json");
    fs::write(
        &path,
        r##"{"gapsIn": 99, "unknownThing": {"keep": true}, "accentColor": "#123456"}"##,
    )
    .unwrap();

    let mut store = Store::load();
    assert_eq!(store.i64("gapsIn", 0), 99);
    assert!(store.get("unknownThing").is_object());

    assert!(store.set("gapsIn", json!(default_gaps)));
    store.save().unwrap();
    let saved: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
    assert!(
        saved.get("gapsIn").is_none(),
        "default key should be removed"
    );
    assert_eq!(saved.get("unknownThing"), Some(&json!({"keep": true})));
    assert_eq!(saved.get("accentColor"), Some(&json!("#123456")));

    assert!(store.set("gapsIn", json!(11)));
    store.save().unwrap();
    let saved: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
    assert_eq!(saved.get("gapsIn"), Some(&json!(11)));
    assert_eq!(saved.get("unknownThing"), Some(&json!({"keep": true})));
    assert!(
        fs::read_dir(config.join("island"))
            .unwrap()
            .flatten()
            .all(|entry| !entry.file_name().to_string_lossy().contains(".tmp")),
        "atomic save should leave no temporary file"
    );

    fs::write(
        &path,
        r##"{"gapsIn": 13, "unknownThing": {"keep": true}, "accentColor": "#123456"}"##,
    )
    .unwrap();
    assert!(store.replace_from_disk());
    assert_eq!(store.i64("gapsIn", 0), 13);

    let _ = fs::remove_dir_all(&root);
}
