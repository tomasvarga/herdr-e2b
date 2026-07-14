// POC: Ratatui (Rust) live dashboard for herdr-e2b boxes.
// Reads the box JSON records, renders an auto-refreshing table, and runs
// e2b-box actions AGAINST EACH BOX'S OWN worktreePath (shown in the UI), with a
// confirm gate on the ones that overwrite or destroy. Single static binary.
//
// Theming: defaults to the TERMINAL's own palette (so it inherits whatever
// theme your terminal / herdr uses). Cycle live with `T`, or pick a start theme
// with E2B_DASH_THEME (or "auto" = terminal):
//   terminal (default) | solarized-light | tokyo-night | dracula | nord | gruvbox
//
//   cargo run --release -- [boxes_dir]
use std::{
    fs,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

use crossterm::event::{self, Event, KeyCode};
use ratatui::{
    layout::{Constraint, Layout},
    style::{Color, Modifier, Style, Stylize},
    text::Line,
    widgets::{Block, Borders, Cell, Paragraph, Row, Table, TableState},
    Frame,
};
use serde::Deserialize;

// ---------------- theme ----------------

struct Theme {
    accent: Color,
    dim: Color,
    border: Color,
    ready: Color,
    paused: Color,
    prov: Color,
    failed: Color,
    sel: Style,     // selected-row style
    confirm: Style, // confirm bar style
}

fn rgb(hex: u32) -> Color {
    Color::Rgb((hex >> 16) as u8, (hex >> 8) as u8, hex as u8)
}

/// POSIX shell single-quote a value so it's a single safe token (paths with
/// spaces, $, backticks, quotes can't expand or break out of `bash -lc`).
fn sh(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

// Cycle order for the `T` key. "terminal" (== auto) is first so it's the default.
const THEMES: [&str; 6] = ["terminal", "solarized-light", "tokyo-night", "dracula", "nord", "gruvbox"];

fn theme_from(name: &str) -> Theme {
    match name {
        // Solarized Light — tuned for a LIGHT terminal background.
        "solarized-light" => Theme {
            accent: rgb(0x268bd2),
            dim: rgb(0x586e75),
            border: rgb(0x93a1a1),
            ready: rgb(0x859900),
            paused: rgb(0xb58900),
            prov: rgb(0x268bd2),
            failed: rgb(0xdc322f),
            sel: Style::default().bg(rgb(0xeee8d5)).fg(rgb(0x002b36)).add_modifier(Modifier::BOLD),
            confirm: Style::default().bg(rgb(0xb58900)).fg(rgb(0xfdf6e3)).add_modifier(Modifier::BOLD),
        },
        "tokyo-night" => Theme {
            accent: rgb(0x7aa2f7),
            dim: rgb(0x565f89),
            border: rgb(0x3b4261),
            ready: rgb(0x9ece6a),
            paused: rgb(0xe0af68),
            prov: rgb(0x7dcfff),
            failed: rgb(0xf7768e),
            sel: Style::default().bg(rgb(0x283457)).fg(rgb(0xc0caf5)).add_modifier(Modifier::BOLD),
            confirm: Style::default().bg(rgb(0xe0af68)).fg(rgb(0x1a1b26)).add_modifier(Modifier::BOLD),
        },
        "dracula" => Theme {
            accent: rgb(0xbd93f9),
            dim: rgb(0x6272a4),
            border: rgb(0x44475a),
            ready: rgb(0x50fa7b),
            paused: rgb(0xf1fa8c),
            prov: rgb(0x8be9fd),
            failed: rgb(0xff5555),
            sel: Style::default().bg(rgb(0x44475a)).fg(rgb(0xf8f8f2)).add_modifier(Modifier::BOLD),
            confirm: Style::default().bg(rgb(0xf1fa8c)).fg(rgb(0x282a36)).add_modifier(Modifier::BOLD),
        },
        "nord" => Theme {
            accent: rgb(0x88c0d0),
            dim: rgb(0x4c566a),
            border: rgb(0x434c5e),
            ready: rgb(0xa3be8c),
            paused: rgb(0xebcb8b),
            prov: rgb(0x81a1c1),
            failed: rgb(0xbf616a),
            sel: Style::default().bg(rgb(0x3b4252)).fg(rgb(0xeceff4)).add_modifier(Modifier::BOLD),
            confirm: Style::default().bg(rgb(0xebcb8b)).fg(rgb(0x2e3440)).add_modifier(Modifier::BOLD),
        },
        "gruvbox" => Theme {
            accent: rgb(0x83a598),
            dim: rgb(0x928374),
            border: rgb(0x504945),
            ready: rgb(0xb8bb26),
            paused: rgb(0xfabd2f),
            prov: rgb(0x83a598),
            failed: rgb(0xfb4934),
            sel: Style::default().bg(rgb(0x3c3836)).fg(rgb(0xebdbb2)).add_modifier(Modifier::BOLD),
            confirm: Style::default().bg(rgb(0xfabd2f)).fg(rgb(0x282828)).add_modifier(Modifier::BOLD),
        },
        // "terminal" (default): use the terminal's OWN 16-color palette via named
        // ANSI colors, and a REVERSED selection — so it blends with any terminal
        // theme (tokyo-night in herdr, someone else's solarized, etc.).
        _ => Theme {
            accent: Color::Cyan,
            dim: Color::DarkGray,
            border: Color::Blue,
            ready: Color::Green,
            paused: Color::Yellow,
            prov: Color::Cyan,
            failed: Color::Red,
            sel: Style::default().add_modifier(Modifier::REVERSED | Modifier::BOLD),
            confirm: Style::default().fg(Color::Black).bg(Color::Yellow).add_modifier(Modifier::BOLD),
        },
    }
}

// Plugin state dir. Prefer herdr's own HERDR_PLUGIN_STATE_DIR (set for plugin
// panes), then the plugin's HERDR_E2B_STATE_DIR override, then the XDG path the
// node side writes to. Independent of the boxes-dir arg (which may be samples).
fn state_dir() -> PathBuf {
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
fn theme_file() -> PathBuf {
    state_dir().join("dashboard-theme")
}

fn save_theme(name: &str) {
    let p = theme_file();
    if let Some(dir) = p.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let _ = fs::write(p, name);
}

// Starting theme: a saved `T` choice wins (so it persists), else the
// E2B_DASH_THEME seed ("auto" -> terminal), else default (terminal).
fn initial_theme_idx() -> usize {
    if let Ok(s) = fs::read_to_string(theme_file()) {
        if let Some(i) = THEMES.iter().position(|&t| t == s.trim()) {
            return i;
        }
    }
    let mut want = std::env::var("E2B_DASH_THEME").unwrap_or_default();
    if want == "auto" {
        want = "terminal".into();
    }
    THEMES.iter().position(|&t| t == want).unwrap_or(0)
}

// ---------------- data ----------------

#[derive(Deserialize, Default, Clone)]
struct Box {
    key: String,
    #[serde(default)]
    label: String,
    #[serde(default)]
    status: String,
    #[serde(default)]
    step: String,
    #[serde(default, rename = "sandboxId")]
    sandbox_id: String,
    #[serde(default)]
    files: u32,
    #[serde(default, rename = "worktreePath")]
    worktree_path: String,
}

#[derive(Clone, Copy)]
enum Verb {
    Sync,
    Pull,
    Kill,
}

impl Verb {
    fn cmd(self) -> &'static str {
        match self {
            Verb::Sync => "sync",
            Verb::Pull => "pull",
            Verb::Kill => "kill",
        }
    }
    fn confirm(self, label: &str, wt: &str) -> String {
        match self {
            Verb::Sync => format!("SYNC  local → sandbox   overwrites the SANDBOX from {wt}   [y/N]"),
            Verb::Pull => format!("PULL  sandbox → local   overwrites {wt} from the sandbox   [y/N]"),
            Verb::Kill => format!("KILL  '{label}'   destroys the sandbox   [y/N]"),
        }
    }
}

fn load_boxes(dir: &PathBuf) -> Vec<Box> {
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

fn status_glyph_color(theme: &Theme, s: &str) -> (&'static str, Color) {
    match s {
        "ready" => ("●", theme.ready),
        "paused" => ("●", theme.paused),
        "provisioning" => ("◐", theme.prov),
        "failed" => ("●", theme.failed),
        _ => ("○", theme.dim),
    }
}

struct App {
    dir: PathBuf,
    theme: Theme,
    theme_idx: usize,
    boxes: Vec<Box>,
    state: TableState,
    msg: String,
    pending: Option<Verb>,
    run: Option<(String, String, &'static str, String)>, // (label, key, verb, worktree)
    post_open: Option<(String, String, String)>,         // after a shell exits: (label, key, worktree)
}

impl App {
    fn reload(&mut self) {
        self.boxes = load_boxes(&self.dir);
        if self.boxes.is_empty() {
            self.state.select(None);
        } else {
            let sel = self.state.selected().unwrap_or(0);
            self.state.select(Some(sel.min(self.boxes.len() - 1)));
        }
    }
    fn move_by(&mut self, d: isize) {
        if self.boxes.is_empty() {
            return;
        }
        let n = self.boxes.len() as isize;
        let cur = self.state.selected().unwrap_or(0) as isize;
        self.state.select(Some(((cur + d).rem_euclid(n)) as usize));
    }
    fn sel(&self) -> Option<&Box> {
        self.state.selected().and_then(|i| self.boxes.get(i))
    }
    fn arm(&mut self, v: Verb) {
        if self.sel().map_or(false, |b| !b.worktree_path.is_empty() || matches!(v, Verb::Kill)) {
            self.pending = Some(v);
        }
    }
}

fn draw(f: &mut Frame, app: &mut App) {
    let t = &app.theme;
    let chunks = Layout::vertical([
        Constraint::Length(1),
        Constraint::Min(3),
        Constraint::Length(3),
    ])
    .split(f.area());

    let head = Line::from(format!("  herdr-e2b · {} sandboxes · theme: {}", app.boxes.len(), THEMES[app.theme_idx]))
        .style(Style::default().fg(t.accent).add_modifier(Modifier::BOLD));
    f.render_widget(Paragraph::new(head), chunks[0]);

    let header = Row::new(["NAME", "STATUS", "SANDBOX", "FILES", "STEP"])
        .style(Style::default().fg(t.accent).add_modifier(Modifier::BOLD))
        .bottom_margin(1);

    let rows: Vec<Row> = app
        .boxes
        .iter()
        .map(|b| {
            let (dot, col) = status_glyph_color(t, &b.status);
            let status = Line::from(vec![format!("{dot} ").fg(col), b.status.clone().into()]);
            let sid: String = b.sandbox_id.chars().take(12).collect();
            let files = if b.files > 0 { b.files.to_string() } else { "—".into() };
            Row::new(vec![
                Cell::from(b.label.clone()),
                Cell::from(status),
                Cell::from(sid),
                Cell::from(files),
                Cell::from(b.step.clone()),
            ])
        })
        .collect();

    let widths = [
        Constraint::Length(18),
        Constraint::Length(16),
        Constraint::Length(13),
        Constraint::Length(6),
        Constraint::Min(20),
    ];
    let table = Table::new(rows, widths)
        .header(header)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(t.border)))
        .row_highlight_style(t.sel)
        .highlight_symbol("▸ ");
    f.render_stateful_widget(table, chunks[1], &mut app.state);

    let target = app
        .sel()
        .map(|b| {
            let wt = if b.worktree_path.is_empty() { "—".into() } else { b.worktree_path.clone() };
            format!("  target: {wt}")
        })
        .unwrap_or_default();
    let target_line = Line::from(target).style(Style::default().fg(t.dim));

    let mid = if let Some((label, _, _)) = &app.post_open {
        Line::from(format!("  left '{label}' — [p]ull changes down · [k]ill it · [L]eave running")).style(t.confirm)
    } else if let Some(v) = app.pending {
        let b = app.sel();
        let label = b.map(|b| b.label.as_str()).unwrap_or("");
        let wt = b.map(|b| b.worktree_path.as_str()).unwrap_or("");
        Line::from(format!("  {}", v.confirm(label, wt))).style(t.confirm)
    } else {
        Line::from("  ↑/↓ move · o open · s sync · p pull · x kill · r refresh · T theme · q quit")
            .style(Style::default().fg(t.dim))
    };
    let msg = Line::from(format!("  {}", app.msg)).style(Style::default().fg(t.paused));
    f.render_widget(Paragraph::new(vec![target_line, mid, msg]), chunks[2]);
}

fn main() -> std::io::Result<()> {
    let dir = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| state_dir().join("boxes"));

    let idx = initial_theme_idx();
    let mut app = App {
        dir,
        theme: theme_from(THEMES[idx]),
        theme_idx: idx,
        boxes: vec![],
        state: TableState::default(),
        msg: String::new(),
        pending: None,
        run: None,
        post_open: None,
    };
    app.reload();
    if !app.boxes.is_empty() {
        app.state.select(Some(0));
    }

    let mut terminal = ratatui::init();
    let mut last = Instant::now();
    let res = loop {
        if let Err(e) = terminal.draw(|f| draw(f, &mut app)) {
            break Err(e);
        }

        if let Some((label, key, verb, wt)) = app.run.take() {
            // kill/status target the box by KEY (no worktree needed). Everything
            // else operates ON the worktree, so it MUST exist — never fall back
            // to the current dir (that would provision/sync the wrong folder).
            let key_only = verb == "kill" || verb == "status";
            if !key_only && (wt.is_empty() || !std::path::Path::new(&wt).is_dir()) {
                app.msg = format!("skipped {verb}: worktree not found ({wt})");
                continue; // stay in the TUI, run nothing
            }

            // `open` is the interactive one: run INLINE (hand this pane's terminal
            // to the box shell), quiet e2b-box with E2B_DASH=1, and offer
            // pull/kill/leave when the shell exits. `unset HERDR_PLUGIN_CONTEXT_JSON`
            // stops e2b-box cd-ing to the dashboard pane's context; KEY pins the
            // box; sh() single-quotes every value so odd paths can't break out.
            if verb == "open" {
                ratatui::restore();
                let script = format!(
                    "unset HERDR_PLUGIN_CONTEXT_JSON; cd {} && KEY={} E2B_DASH=1 e2b-box open",
                    sh(&wt),
                    sh(&key),
                );
                let _ = Command::new("bash")
                    .arg("-lc")
                    .arg(&script)
                    .env_remove("HERDR_PLUGIN_CONTEXT_JSON")
                    .status();
                terminal = ratatui::init();
                app.post_open = Some((label, key, wt));
                app.reload();
                continue;
            }

            // sync/pull run in the worktree; kill/status target by KEY only.
            let header = sh(&format!("── e2b-box {verb} ({label}) ──"));
            let cd = if key_only { String::new() } else { format!("cd {} && ", sh(&wt)) };
            let inner = format!(
                "unset HERDR_PLUGIN_CONTEXT_JSON; echo {header}; {cd}KEY={} e2b-box {verb}; echo; read -rp '↵ close this pane '",
                sh(&key),
            );
            let cwd = if wt.is_empty() {
                std::env::var("HOME").unwrap_or_else(|_| ".".into())
            } else {
                wt.clone()
            };

            // Inside a herdr session (socket present) run the action in its OWN
            // split pane — visible, keeps the dashboard up. HERDR_BIN_PATH is set
            // for plugin commands; fall back to `herdr` on PATH otherwise.
            let in_herdr = std::env::var("HERDR_SOCKET_PATH").map_or(false, |s| !s.is_empty());
            if in_herdr {
                let herdr = std::env::var("HERDR_BIN_PATH")
                    .ok()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| "herdr".into());
                let ok = Command::new(&herdr)
                    .args([
                        "agent", "start", &format!("e2b-{verb}"),
                        "--cwd", &cwd, "--split", "down", "--focus",
                        "--", "bash", "-lc", &inner,
                    ])
                    .env_remove("HERDR_PLUGIN_CONTEXT_JSON")
                    .status()
                    .map_or(false, |s| s.success());
                app.msg = if ok {
                    format!("{verb} · opened a pane for {label}")
                } else {
                    format!("{verb}: couldn't open a pane for {label}")
                };
            } else {
                // Standalone terminal: suspend the TUI, run inline, then resume.
                ratatui::restore();
                let _ = Command::new("bash")
                    .arg("-lc")
                    .arg(&inner)
                    .env_remove("HERDR_PLUGIN_CONTEXT_JSON")
                    .status();
                terminal = ratatui::init();
                app.msg = format!("{verb} done · {label}");
            }
            app.reload();
            continue;
        }

        if event::poll(Duration::from_millis(250))? {
            if let Event::Key(k) = event::read()? {
                // Post-open: after the box shell exits, offer pull / kill / leave.
                if let Some((label, key, wt)) = app.post_open.take() {
                    match k.code {
                        KeyCode::Char('p') | KeyCode::Char('P') => {
                            app.run = Some((label, key, "pull", wt));
                        }
                        KeyCode::Char('k') | KeyCode::Char('K') => {
                            app.run = Some((label, key, "kill", wt));
                        }
                        _ => app.msg = format!("left '{label}' running"),
                    }
                    continue;
                }
                if let Some(v) = app.pending {
                    match k.code {
                        KeyCode::Char('y') | KeyCode::Char('Y') => {
                            if let Some(b) = app.sel() {
                                app.run = Some((b.label.clone(), b.key.clone(), v.cmd(), b.worktree_path.clone()));
                            }
                            app.pending = None;
                        }
                        _ => {
                            app.pending = None;
                            app.msg = "cancelled".into();
                        }
                    }
                    continue;
                }
                match k.code {
                    KeyCode::Char('q') | KeyCode::Esc => break Ok(()),
                    KeyCode::Char('r') => {
                        app.reload();
                        app.msg = "refreshed".into();
                    }
                    KeyCode::Char('t') | KeyCode::Char('T') => {
                        app.theme_idx = (app.theme_idx + 1) % THEMES.len();
                        app.theme = theme_from(THEMES[app.theme_idx]);
                        save_theme(THEMES[app.theme_idx]); // remember across runs
                        app.msg = format!("theme: {} (saved)", THEMES[app.theme_idx]);
                    }
                    KeyCode::Down | KeyCode::Char('j') => app.move_by(1),
                    KeyCode::Up | KeyCode::Char('k') => app.move_by(-1),
                    KeyCode::Char('s') => app.arm(Verb::Sync),
                    KeyCode::Char('p') => app.arm(Verb::Pull),
                    KeyCode::Char('x') => app.arm(Verb::Kill),
                    KeyCode::Char('o') => {
                        if let Some(b) = app.sel() {
                            app.run = Some((b.label.clone(), b.key.clone(), "open", b.worktree_path.clone()));
                        }
                    }
                    _ => {}
                }
            }
        }
        if last.elapsed() >= Duration::from_secs(2) {
            app.reload();
            last = Instant::now();
        }
    };
    ratatui::restore();
    res
}
