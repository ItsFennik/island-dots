use crate::paths;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;

#[derive(Default, Serialize, Deserialize)]
pub struct HistoryFile {
    #[serde(default)]
    recent: Vec<String>,
    #[serde(default)]
    count: BTreeMap<String, i64>,
    #[serde(default)]
    pinned: Vec<String>,
}

pub struct History {
    path: std::path::PathBuf,
    data: HistoryFile,
}

impl History {
    pub fn load() -> Self {
        let path = paths::spotlight_state_file();
        let data = fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        Self { path, data }
    }

    pub fn record(&mut self, key: &str) {
        if key.is_empty() {
            return;
        }
        *self.data.count.entry(key.to_string()).or_insert(0) += 1;
        self.data.recent.retain(|existing| existing != key);
        self.data.recent.insert(0, key.to_string());
        self.data.recent.truncate(30);
        self.save();
    }

    pub fn forget(&mut self, key: &str) {
        self.data.recent.retain(|existing| existing != key);
        self.data.pinned.retain(|existing| existing != key);
        self.data.count.remove(key);
        self.save();
    }

    pub fn toggle_pin(&mut self, key: &str) {
        if key.is_empty() {
            return;
        }
        if self.is_pinned(key) {
            self.data.pinned.retain(|existing| existing != key);
        } else {
            self.data.pinned.insert(0, key.to_string());
        }
        self.save();
    }

    pub fn is_pinned(&self, key: &str) -> bool {
        self.data.pinned.iter().any(|existing| existing == key)
    }

    pub fn has(&self, key: &str) -> bool {
        self.data.count.contains_key(key)
            || self.data.recent.iter().any(|existing| existing == key)
            || self.is_pinned(key)
    }

    pub fn recent(&self) -> &[String] {
        &self.data.recent
    }

    pub fn frequent_ordered(&self) -> Vec<String> {
        let recency = |key: &str| {
            self.data
                .recent
                .iter()
                .position(|existing| existing == key)
                .unwrap_or(999)
        };
        let mut rest: Vec<_> = self
            .data
            .count
            .iter()
            .filter(|(_, count)| **count > 0)
            .map(|(key, _)| key.clone())
            .collect();
        rest.sort_by(|a, b| {
            let ca = self.data.count.get(a).copied().unwrap_or(0);
            let cb = self.data.count.get(b).copied().unwrap_or(0);
            cb.cmp(&ca).then_with(|| recency(a).cmp(&recency(b)))
        });
        let mut out = self.data.pinned.clone();
        for key in rest {
            if !out.iter().any(|existing| existing == &key) {
                out.push(key);
            }
        }
        out
    }

    pub fn clear(&mut self) {
        self.data = HistoryFile::default();
        self.save();
    }

    fn save(&self) {
        if let Some(dir) = self.path.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let Ok(text) = serde_json::to_string_pretty(&self.data) else {
            return;
        };
        let tmp = self.path.with_extension("json.tmp");
        if let Ok(mut file) = fs::File::create(&tmp) {
            if file.write_all((text + "\n").as_bytes()).is_ok() {
                let _ = fs::rename(&tmp, &self.path);
            }
        }
    }
}
