// herdr-e2b dashboard — a live Ratatui board of every tracked E2B sandbox.
// Reads the sandbox JSON records, renders an auto-refreshing table, and runs
// e2b-box actions against EACH SANDBOX'S OWN worktreePath (shown in the UI), with
// a confirm gate on the ones that overwrite or destroy. Single static binary.
//
// Theming: defaults to the TERMINAL's own palette (so it inherits whatever theme
// your terminal / herdr uses). Cycle live with `T`, or seed a start theme with
// E2B_DASH_THEME (or "auto" = terminal):
//   terminal (default) | solarized-light | tokyo-night | dracula | nord | gruvbox
//
//   cargo run --release -- [boxes_dir]
mod actions;
mod state;
mod theme;

use std::{
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

use crossterm::event::{self, Event, KeyCode};
use ratatui::{
    layout::{Constraint, Layout},
    style::{Modifier, Style, Stylize},
    text::Line,
    widgets::{Block, Borders, Cell, Paragraph, Row, Table, TableState},
    Frame,
};

use actions::{goto_worktree, Verb};
use state::{load_boxes, sh, state_dir, Box};
use theme::{initial_theme_idx, save_theme, status_glyph_color, theme_from, Theme, THEMES};

struct App {
    dir: PathBuf,
    theme: Theme,
    theme_idx: usize,
    boxes: Vec<Box>,
    state: TableState,
    msg: String,
    pending: Option<Verb>,
    run: Option<(String, String, &'static str, String)>, // (label, key, verb, worktree)
    post_open: Option<(String, String, String)>,          // after a shell exits: (label, key, worktree)
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
        Line::from("  ↑/↓ move · ↵ worktree · o open · s sync · p pull · x kill · r refresh · T theme · q quit")
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
                    KeyCode::Enter => {
                        if let Some(b) = app.sel() {
                            let (label, wt) = (b.label.clone(), b.worktree_path.clone());
                            app.msg = goto_worktree(&label, &wt);
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
