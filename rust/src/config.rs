use crate::paths;
use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

#[derive(Clone)]
pub struct Config {
    defaults: BTreeMap<String, Value>,
    user: BTreeMap<String, Value>,
    path: PathBuf,
}

impl Config {
    pub fn load() -> Self {
        let defaults = match paths::load_json(&paths::defaults_file()) {
            Some(Value::Object(map)) => map.into_iter().collect(),
            _ => BTreeMap::new(),
        };
        let user = match paths::load_json(&paths::settings_file()) {
            Some(Value::Object(map)) => map.into_iter().collect(),
            _ => BTreeMap::new(),
        };
        Self {
            defaults,
            user,
            path: paths::settings_file(),
        }
    }

    pub fn defaults(&self) -> &BTreeMap<String, Value> {
        &self.defaults
    }

    pub fn user(&self) -> &BTreeMap<String, Value> {
        &self.user
    }

    pub fn get(&self, key: &str) -> Value {
        self.user
            .get(key)
            .or_else(|| self.defaults.get(key))
            .cloned()
            .unwrap_or(Value::Null)
    }

    pub fn bool(&self, key: &str, fallback: bool) -> bool {
        self.get(key).as_bool().unwrap_or(fallback)
    }

    pub fn i64(&self, key: &str, fallback: i64) -> i64 {
        self.get(key).as_i64().unwrap_or(fallback)
    }

    pub fn f64(&self, key: &str, fallback: f64) -> f64 {
        self.get(key).as_f64().unwrap_or(fallback)
    }

    pub fn string(&self, key: &str, fallback: &str) -> String {
        self.get(key)
            .as_str()
            .map(str::to_string)
            .unwrap_or_else(|| fallback.to_string())
    }

    pub fn is_default(&self, key: &str) -> bool {
        self.user.get(key) == self.defaults.get(key)
    }

    pub fn set(&mut self, key: &str, value: Value) -> Result<()> {
        if self.defaults.get(key) == Some(&value) {
            self.user.remove(key);
        } else {
            self.user.insert(key.to_string(), value);
        }
        self.save()
    }

    pub fn reset(&mut self, keys: &[&str]) -> Result<()> {
        for key in keys {
            self.user.remove(*key);
        }
        self.save()
    }

    pub fn save(&self) -> Result<()> {
        let dir = self.path.parent().context("settings path has no parent")?;
        fs::create_dir_all(dir)?;
        let text = serde_json::to_string_pretty(&self.user)? + "\n";
        let tmp = self.path.with_extension("json.tmp");
        {
            let mut file = fs::File::create(&tmp)?;
            file.write_all(text.as_bytes())?;
            file.sync_all()?;
        }
        fs::rename(&tmp, &self.path)?;
        Ok(())
    }
}
