use crate::paths;
use anyhow::{Context, Result};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::thread;

pub struct Instance {
    path: PathBuf,
}

impl Instance {
    pub fn claim(
        name: &str,
        message: &str,
        tx: async_channel::Sender<String>,
    ) -> Result<Option<Self>> {
        let dir = paths::runtime_dir();
        let _ = fs::create_dir_all(&dir);
        let path = dir.join(format!("{name}.sock"));
        if let Ok(mut stream) = UnixStream::connect(&path) {
            let _ = stream.write_all(format!("{message}\n").as_bytes());
            let _ = stream.flush();
            return Ok(None);
        }
        let _ = fs::remove_file(&path);
        let listener =
            UnixListener::bind(&path).with_context(|| format!("bind {}", path.display()))?;
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let reader = BufReader::new(stream);
                for line in reader.lines().map_while(Result::ok) {
                    let line = line.trim().to_string();
                    if !line.is_empty() {
                        let _ = tx.send_blocking(line);
                    }
                }
            }
        });
        Ok(Some(Self { path }))
    }
}

impl Drop for Instance {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}
