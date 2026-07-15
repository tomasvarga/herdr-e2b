// Per-sandbox actions: the confirm-gated verbs, and Enter's "go to the worktree".
use std::process::Command;

use crate::state::sh;

#[derive(Clone, Copy)]
pub(crate) enum Verb {
    Sync,
    Pull,
    Kill,
}

impl Verb {
    pub(crate) fn cmd(self) -> &'static str {
        match self {
            Verb::Sync => "sync",
            Verb::Pull => "pull",
            Verb::Kill => "kill",
        }
    }
    pub(crate) fn confirm(self, label: &str, wt: &str) -> String {
        match self {
            Verb::Sync => format!("SYNC  local → sandbox   uploads {wt} into the sandbox (additive)   [y/N]"),
            Verb::Pull => format!("PULL  sandbox → local   overwrites {wt} from the sandbox   [y/N]"),
            Verb::Kill => format!("KILL  '{label}'   destroys the sandbox   [y/N]"),
        }
    }
}

/// Enter: go to a sandbox's local worktree. Focus an already-open herdr workspace
/// for that path (or a subdir), else open it fresh. Only meaningful inside herdr.
/// Returns a status message for the footer.
pub(crate) fn goto_worktree(label: &str, wt: &str) -> String {
    if wt.is_empty() {
        return format!("{label}: no worktree path");
    }
    if std::env::var("HERDR_SOCKET_PATH").map_or(true, |s| s.is_empty()) {
        return "↵ needs herdr (press o to open the sandbox instead)".into();
    }
    let herdr = std::env::var("HERDR_BIN_PATH")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "herdr".into());
    // Match an open pane by cwd (or a subdir), then:
    //  - different workspace → workspace focus (+ tab focus)
    //  - same workspace, other tab → tab focus
    //  - same workspace + tab → unzoom the dashboard's own pane (you're already
    //    in this worktree; the board is zoomed over it)
    //  - not open anywhere → open it fresh (--focus)
    let sel = "'.result.panes[] | select(.cwd==$wt or (.cwd|startswith($wt+\"/\")) or .foreground_cwd==$wt or (.foreground_cwd|startswith($wt+\"/\"))) | \"\\(.workspace_id) \\(.tab_id)\"'";
    let script = format!(
        "wt={wt}; sel=$({h} pane list 2>/dev/null | jq -r --arg wt \"$wt\" {sel} | head -1); \
ws=$(echo \"$sel\" | cut -d' ' -f1); tab=$(echo \"$sel\" | cut -d' ' -f2); \
if [ -z \"$ws\" ]; then \
  if [ -d \"$wt\" ]; then {h} workspace create --cwd \"$wt\" --focus >/dev/null 2>&1 && echo opened || echo missing; else echo missing; fi; \
elif [ \"$ws\" != \"$HERDR_WORKSPACE_ID\" ]; then \
  {h} workspace focus \"$ws\" >/dev/null 2>&1; {h} tab focus \"$tab\" >/dev/null 2>&1; echo switched; \
elif [ \"$tab\" != \"$HERDR_TAB_ID\" ]; then \
  {h} tab focus \"$tab\" >/dev/null 2>&1; echo switched; \
else \
  {h} pane zoom --pane \"$HERDR_PANE_ID\" --off >/dev/null 2>&1 || {h} pane zoom --current --off >/dev/null 2>&1; echo unzoomed; \
fi",
        wt = sh(wt),
        h = sh(&herdr),
        sel = sel,
    );
    let word = Command::new("bash")
        .arg("-lc")
        .arg(&script)
        .env_remove("HERDR_PLUGIN_CONTEXT_JSON")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    match word.as_str() {
        "switched" => format!("→ switched to {label}'s worktree"),
        "opened" => format!("→ opened {label}'s worktree"),
        "unzoomed" => format!("→ {label} is here — unzoomed the board"),
        "missing" => format!("{label}: worktree not open & not found locally"),
        _ => format!("{label}: couldn't switch"),
    }
}
