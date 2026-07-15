// Box records + small shared helpers (state dir resolution, shell quoting).
use serde::Deserialize;
use std::{fs, path::PathBuf};

/// One tracked sandbox, as written by the node side into a `<state>/boxes/*.json`.
#[derive(Deserialize, Default, Clone)]
pub(crate) struct Box {
    pub(crate) key: String,
    #[serde(default)]
    pub(crate) label: String,
    #[serde(default)]
    pub(crate) status: String,
    #[serde(default)]
    pub(crate) step: String,
    #[serde(default, rename = "sandboxId")]
    pub(crate) sandbox_id: String,
    #[serde(default)]
    pub(crate) files: u32,
    #[serde(default, rename = "worktreePath")]
    pub(crate) worktree_path: String,
}

/// Plugin state dir. Prefer herdr's own HERDR_PLUGIN_STATE_DIR (set for plugin
/// panes), then the plugin's HERDR_E2B_STATE_DIR override, then the XDG path the
/// node side writes to. Keep IN SYNC with src/store.js and bin/lib/paths.sh.
pub(crate) fn state_dir() -> PathBuf {
    if let Ok(d) = std::env::var("HERDR_PLUGIN_STATE_DIR") {
        return PathBuf::from(d);
    }
    if let Ok(d) = std::env::var("HERDR_E2B_STATE_DIR") {
        return PathBuf::from(d);
    }
    if let Ok(d) = std::env::var("XDG_STATE_HOME") {
        return PathBuf::from(d).join("herdr/plugins/herdr-e2b");
    }
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join(".local/state/herdr/plugins/herdr-e2b")
}

/// All box records in `dir`, sorted by display label.
pub(crate) fn load_boxes(dir: &PathBuf) -> Vec<Box> {
    let mut out: Vec<Box> = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) != Some("json") {
                continue;
            }
            if let Ok(txt) = fs::read_to_string(&p) {
                if let Ok(mut b) = serde_json::from_str::<Box>(&txt) {
                    if b.label.is_empty() {
                        b.label = b.key.clone();
                    }
                    out.push(b);
                }
            }
        }
    }
    out.sort_by(|a, b| a.label.cmp(&b.label));
    out
}

/// POSIX shell single-quote a value so it's a single safe token (paths with
/// spaces, $, backticks, quotes can't expand or break out of `bash -lc`).
pub(crate) fn sh(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
