#![allow(
    clippy::cast_lossless,
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss,
    clippy::struct_excessive_bools,
    clippy::too_many_lines
)]
use gtk::gdk;
use gtk::glib;
use gtk::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use island_rust::apps::{self, AppEntry, AppIndex};
use island_rust::config::Config;
use island_rust::history::History;
use island_rust::paths;
use island_rust::singleton::Instance;
use island_rust::system;
use island_rust::theme::Theme;
use island_rust::ui;
use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::rc::{Rc, Weak};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

const FIELD_H: i32 = 52;
const ROW_H: i32 = 44;
const HEAD_H: i32 = 26;
const FOOT_H: i32 = 34;
const WINDOW_MARGIN: i32 = 20;
const MAX_HEADERS: i32 = 4;
const OPEN_MS: u64 = 180;
const CLOSE_MS: u64 = 420;
const OPEN_OVERSHOOT: f64 = 0.7;
const HOVER_GRACE_MS: u64 = 100;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Style {
    Capsule,
    Attached,
    Bottom,
    Floating,
}

impl Style {
    fn resolved(cfg: &Config) -> Self {
        let layout = cfg.string("shellLayout", "menubar");
        let skin = cfg.string("barSkin", "classic");
        let capsule = layout == "menubar" && (skin == "island" || skin == "notch");
        let bottom_layout = layout != "menubar";
        match cfg.string("spotlightStyle", "auto").as_str() {
            "floating" => Self::Floating,
            "capsule" => {
                if capsule {
                    Self::Capsule
                } else if bottom_layout {
                    Self::Bottom
                } else {
                    Self::Attached
                }
            }
            _ => {
                if capsule && cfg.bool("spotlightFromCapsule", true) {
                    Self::Capsule
                } else if bottom_layout {
                    Self::Bottom
                } else {
                    Self::Attached
                }
            }
        }
    }
}

fn uses_focus_grab() -> bool {
    std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
}

#[derive(Clone)]
enum Act {
    App(usize),
    File(PathBuf),
    Power(&'static str),
    Command(String),
    Copy(String),
    Url(String),
    Settings(Option<String>),
    Skin(String),
    Fill(String),
}

#[derive(Clone)]
enum MenuAct {
    Activate(usize),
    AppAction(usize, String),
    ToggleDock(String),
    TogglePin(String),
    Forget(String),
    OpenFolder(PathBuf),
    Copy(String),
    CloseCopy(String),
}

#[derive(Clone)]
struct Row {
    key: String,
    section: String,
    title: String,
    sub: String,
    icon: Option<String>,
    glyph: Option<String>,
    act: Act,
    confirm: bool,
}

impl Row {
    fn new(key: &str, title: &str, sub: &str, glyph: &str, act: Act) -> Self {
        Self {
            key: key.into(),
            section: String::new(),
            title: title.into(),
            sub: sub.into(),
            icon: None,
            glyph: (!glyph.is_empty()).then(|| glyph.to_string()),
            act,
            confirm: false,
        }
    }
}

struct Spotlight {
    cfg: Config,
    apps: AppIndex,
    history: History,
    window: gtk::ApplicationWindow,
    root: gtk::Box,
    card: gtk::Box,
    search: gtk::Box,
    entry: gtk::Entry,
    list: gtk::ListBox,
    footer: gtk::Box,
    width: i32,
    morph: bool,
    cap_w: i32,
    cap_h: i32,
    final_h: i32,
    current_w: i32,
    current_h: i32,
    grown: bool,
    closing: bool,
    rows: Vec<Row>,
    list_rows: Vec<gtk::ListBoxRow>,
    selected: usize,
    query: String,
    confirm_key: String,
    ctx_menu: Option<gtk::Popover>,
    rows_limit: usize,
    files_enabled: bool,
    commands_enabled: bool,
    web_enabled: bool,
    files: Vec<PathBuf>,
    file_gen: u64,
    file_cancel: Arc<AtomicBool>,
    file_tx: mpsc::Sender<(u64, String, Vec<PathBuf>)>,
    weak: Weak<RefCell<Spotlight>>,
}

impl Spotlight {
    fn new(app: &gtk::Application, monitor_name: Option<&str>) -> Rc<RefCell<Self>> {
        let cfg = Config::load();
        let theme = Theme::load(&cfg);
        ui::install_css(&theme);
        let apps = AppIndex::load();
        let mut history = History::load();
        history.merge_usage(apps.usage());
        let rows_limit = cfg.i64("spotlightRows", 9).clamp(5, 12) as usize;
        let width = cfg.i64("spotlightWidth", 700).clamp(460, 920) as i32;
        let files_enabled = cfg.bool("spotlightFiles", true);
        let commands_enabled = cfg.bool("spotlightCommands", true);
        let web_enabled = cfg.bool("spotlightWeb", true);
        let style = Style::resolved(&cfg);
        let morph = style == Style::Capsule;
        let skin = cfg.string("barSkin", "classic");
        let cap_w = if skin == "notch" { 190 } else { 104 };
        let cap_h = cfg.i64("barHeight", 30) as i32;
        let cap_y = if skin == "notch" { 0 } else { 6 };
        let fullscreen = !uses_focus_grab();

        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("Spotlight")
            .build();
        window.set_decorated(false);
        window.add_css_class("spotlight-window");
        window.init_layer_shell();
        window.set_namespace(Some(if morph {
            "island-capsule-spotlight"
        } else {
            "island-spotlight"
        }));
        window.set_layer(Layer::Overlay);
        window.set_keyboard_mode(KeyboardMode::Exclusive);
        window.set_exclusive_zone(-1);
        let monitor = ui::monitor_for(monitor_name);
        if let Some(monitor) = &monitor {
            window.set_monitor(Some(monitor));
        }
        let screen = monitor.as_ref().map(gtk::prelude::MonitorExt::geometry);
        let screen_width = screen.map_or(1920, |geometry| geometry.width());
        let screen_height = screen.map_or(1080, |geometry| geometry.height());

        let bar_height = cfg.i64("barHeight", 30) + i64::from(skin == "pills") * 6;
        let taskbar_height = cfg.i64("taskbarHeight", 54) + 8;
        let top_gap = (f64::from(screen_height) * 0.2).round() as i32;
        let (edge, margin, card_top) = match style {
            Style::Capsule => (Edge::Top, 0, cap_y),
            Style::Bottom => (Edge::Bottom, (taskbar_height + 8) as i32, 0),
            Style::Attached => (Edge::Top, (bar_height + 8) as i32, 0),
            Style::Floating => (Edge::Top, top_gap, 10),
        };
        if fullscreen {
            for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
                window.set_anchor(edge, true);
            }
            window.set_default_size(screen_width, screen_height);
        } else {
            window.set_anchor(edge, true);
            window.set_margin(edge, margin);
            let window_height = FIELD_H
                + rows_limit as i32 * ROW_H
                + MAX_HEADERS * HEAD_H
                + FOOT_H
                + WINDOW_MARGIN * 2;
            window.set_default_size(width + WINDOW_MARGIN * 2, window_height);
        }
        window.set_resizable(false);

        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("root");
        root.set_hexpand(true);
        root.set_vexpand(true);

        let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
        card.add_css_class("spot-card");
        if morph {
            card.add_css_class("morph");
            if skin == "notch" {
                card.add_css_class("notch");
            }
        }
        card.set_size_request(width, FIELD_H);
        card.set_halign(gtk::Align::Fill);
        card.set_valign(gtk::Align::Fill);
        card.set_overflow(gtk::Overflow::Hidden);
        let scroller = gtk::ScrolledWindow::new();
        scroller.add_css_class("spot-scroller");
        scroller.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Never);
        scroller.set_has_frame(false);
        scroller.set_halign(gtk::Align::Center);
        scroller.set_valign(match style {
            Style::Bottom => gtk::Align::End,
            _ => gtk::Align::Start,
        });
        scroller.set_margin_top(if fullscreen {
            match style {
                Style::Capsule => cap_y,
                Style::Bottom => 0,
                Style::Attached => (bar_height + 8) as i32,
                Style::Floating => top_gap + 10,
            }
        } else {
            card_top
        });
        scroller.set_margin_bottom(if fullscreen {
            match style {
                Style::Bottom => (taskbar_height + 8) as i32,
                _ => 0,
            }
        } else {
            0
        });
        scroller.set_child(Some(&card));
        root.append(&scroller);
        window.set_child(Some(&root));

        let search = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        search.set_size_request(-1, FIELD_H);
        search.set_margin_start(30);
        search.set_margin_end(18);
        let entry = gtk::Entry::new();
        entry.set_has_frame(false);
        entry.set_hexpand(true);
        entry.set_valign(gtk::Align::Center);
        entry.add_css_class("spot-entry");
        let field = gtk::Overlay::new();
        field.set_hexpand(true);
        field.set_child(Some(&entry));
        let placeholder = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        placeholder.add_css_class("spot-placeholder");
        placeholder.set_halign(gtk::Align::Start);
        placeholder.set_valign(gtk::Align::Center);
        placeholder.set_can_target(false);
        placeholder.append(&ui::label(
            "Search apps, files, actions",
            "spot-placeholder-main",
        ));
        placeholder.append(&ui::label("·  ? for help", "spot-placeholder-hint"));
        field.add_overlay(&placeholder);
        search.append(&field);
        if morph {
            search.set_visible(false);
            search.set_opacity(0.0);
        }
        card.append(&search);
        card.append(&ui::separator());

        let list = gtk::ListBox::new();
        list.set_selection_mode(gtk::SelectionMode::Single);
        list.set_activate_on_single_click(true);
        list.add_css_class("spot-list");
        list.set_margin_top(6);
        list.set_margin_bottom(6);
        list.set_margin_start(6);
        list.set_margin_end(6);
        list.set_visible(false);
        if morph {
            list.set_opacity(0.0);
        }
        card.append(&list);
        card.append(&ui::separator());

        let footer = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        footer.set_size_request(-1, FOOT_H);
        footer.set_margin_start(14);
        footer.set_margin_end(14);
        footer.set_valign(gtk::Align::Center);
        if morph {
            footer.set_visible(false);
            footer.set_opacity(0.0);
        }
        card.append(&footer);

        let (file_tx, file_rx) = mpsc::channel();

        let spot: Rc<RefCell<Spotlight>> =
            Rc::new_cyclic(|weak: &std::rc::Weak<RefCell<Spotlight>>| {
                entry.connect_changed({
                    let weak = weak.clone();
                    let placeholder = placeholder.clone();
                    move |entry| {
                        placeholder.set_visible(entry.text().is_empty());
                        if let Some(spot) = weak.upgrade() {
                            let query = entry.text().to_string();
                            spot.borrow_mut().set_query(query);
                        }
                    }
                });

                list.connect_row_activated({
                    let weak = weak.clone();
                    move |_, row| {
                        if let Some(spot) = weak.upgrade() {
                            let idx = spot
                                .borrow()
                                .list_rows
                                .iter()
                                .position(|widget| widget == row);
                            if let Some(idx) = idx {
                                activate(&spot, idx);
                            }
                        }
                    }
                });

                let key = gtk::EventControllerKey::new();
                key.connect_key_pressed({
                    let weak = weak.clone();
                    move |_, keyval, _, modifiers| {
                        let Some(spot) = weak.upgrade() else {
                            return glib::Propagation::Proceed;
                        };
                        let ctrl = modifiers.contains(gdk::ModifierType::CONTROL_MASK);
                        let shift = modifiers.contains(gdk::ModifierType::SHIFT_MASK);
                        let ch = keyval.to_unicode().map(|c| c.to_ascii_lowercase());
                        if keyval == gdk::Key::Escape {
                            let entry = spot.borrow().entry.clone();
                            if entry.text().is_empty() {
                                spot.borrow_mut().close();
                            } else {
                                entry.set_text("");
                            }
                            return glib::Propagation::Stop;
                        }
                        if keyval == gdk::Key::Down
                            || keyval == gdk::Key::Tab
                            || (ctrl && matches!(ch, Some('j' | 'n')))
                        {
                            spot.borrow_mut().move_selection(1);
                            return glib::Propagation::Stop;
                        }
                        if keyval == gdk::Key::Up
                            || keyval == gdk::Key::ISO_Left_Tab
                            || (ctrl && matches!(ch, Some('k' | 'p')))
                        {
                            spot.borrow_mut().move_selection(-1);
                            return glib::Propagation::Stop;
                        }
                        if ctrl {
                            if let Some(digit) = ch.and_then(|c| c.to_digit(10)) {
                                if (1..=9).contains(&digit) {
                                    activate(&spot, (digit - 1) as usize);
                                    return glib::Propagation::Stop;
                                }
                            }
                            if keyval == gdk::Key::Return || keyval == gdk::Key::KP_Enter {
                                toggle_dock_selected(&spot);
                                return glib::Propagation::Stop;
                            }
                        }
                        if keyval == gdk::Key::Return || keyval == gdk::Key::KP_Enter {
                            let idx = spot.borrow().selected;
                            activate(&spot, idx);
                            return glib::Propagation::Stop;
                        }
                        if keyval == gdk::Key::Menu || (shift && keyval == gdk::Key::F10) {
                            let index = spot.borrow().selected;
                            open_context_menu(&spot, index, None);
                            return glib::Propagation::Stop;
                        }
                        if ctrl && ch == Some('f') {
                            pin_selected(&spot);
                            return glib::Propagation::Stop;
                        }
                        if shift && keyval == gdk::Key::Delete {
                            forget_selected(&spot);
                            return glib::Propagation::Stop;
                        }
                        glib::Propagation::Proceed
                    }
                });
                entry.add_controller(key);

                if uses_focus_grab() {
                    let armed = Rc::new(Cell::new(false));
                    let focus = gtk::EventControllerFocus::new();
                    focus.connect_leave({
                        let weak = weak.clone();
                        let armed = armed.clone();
                        move |_| {
                            if !armed.get() {
                                return;
                            }
                            if let Some(spot) = weak.upgrade() {
                                spot.borrow_mut().close();
                            }
                        }
                    });
                    window.add_controller(focus);
                    let armed2 = armed.clone();
                    glib::timeout_add_local_once(Duration::from_millis(60), move || {
                        armed2.set(true);
                    });
                }

                let hover_entered = Rc::new(Cell::new(false));
                let hover_pending = Rc::new(Cell::new(false));
                let motion = gtk::EventControllerMotion::new();
                motion.set_propagation_phase(gtk::PropagationPhase::Capture);
                let pointer_inside = {
                    let card = card.clone();
                    let root = root.clone();
                    move |x: f64, y: f64| {
                        card.compute_bounds(&root).is_some_and(|bounds| {
                            x >= f64::from(bounds.x())
                                && y >= f64::from(bounds.y())
                                && x <= f64::from(bounds.x() + bounds.width())
                                && y <= f64::from(bounds.y() + bounds.height())
                        })
                    }
                };
                motion.connect_motion({
                    let weak = weak.clone();
                    let hover_entered = hover_entered.clone();
                    let hover_pending = hover_pending.clone();
                    let pointer_inside = pointer_inside.clone();
                    move |_, x, y| {
                        if pointer_inside(x, y) {
                            hover_entered.set(true);
                            hover_pending.set(false);
                        } else if hover_entered.get() {
                            schedule_hover_close(&weak, &hover_pending);
                        }
                    }
                });
                motion.connect_leave({
                    let weak = weak.clone();
                    let hover_entered = hover_entered.clone();
                    let hover_pending = hover_pending.clone();
                    move |_| {
                        if hover_entered.get() {
                            schedule_hover_close(&weak, &hover_pending);
                        }
                    }
                });
                root.add_controller(motion);

                let click = gtk::GestureClick::new();
                click.connect_pressed({
                    let weak = weak.clone();
                    let card = card.clone();
                    let root = root.clone();
                    move |_, _, x, y| {
                        let outside = card.compute_bounds(&root).is_none_or(|bounds| {
                            x < f64::from(bounds.x())
                                || y < f64::from(bounds.y())
                                || x > f64::from(bounds.x() + bounds.width())
                                || y > f64::from(bounds.y() + bounds.height())
                        });
                        if outside {
                            if let Some(spot) = weak.upgrade() {
                                spot.borrow_mut().close();
                            }
                        }
                    }
                });
                root.add_controller(click);

                RefCell::new(Self {
                    cfg,
                    apps,
                    history,
                    window: window.clone(),
                    root: root.clone(),
                    card: card.clone(),
                    search: search.clone(),
                    entry: entry.clone(),
                    list,
                    footer: footer.clone(),
                    width,
                    morph,
                    cap_w,
                    cap_h,
                    final_h: FIELD_H
                        + 1
                        + ROW_H * rows_limit as i32
                        + HEAD_H * MAX_HEADERS
                        + 1
                        + FOOT_H,
                    current_w: cap_w,
                    current_h: cap_h,
                    grown: !morph,
                    closing: false,
                    rows: Vec::new(),
                    list_rows: Vec::new(),
                    selected: 0,
                    query: String::new(),
                    confirm_key: String::new(),
                    ctx_menu: None,
                    rows_limit,
                    files_enabled,
                    commands_enabled,
                    web_enabled,
                    files: Vec::new(),
                    file_gen: 0,
                    file_cancel: Arc::new(AtomicBool::new(false)),
                    file_tx: file_tx.clone(),
                    weak: weak.clone(),
                })
            });

        spot.borrow_mut().rebuild();
        window.present_with_time(gdk::CURRENT_TIME);
        window.set_keyboard_mode(KeyboardMode::Exclusive);
        gtk::prelude::GtkWindowExt::set_focus(&window, Some(&entry));
        entry.grab_focus();
        spot.borrow_mut().start_open();

        glib::timeout_add_local(Duration::from_millis(80), {
            let weak = Rc::downgrade(&spot);
            move || {
                while let Ok((generation, query, files)) = file_rx.try_recv() {
                    let Some(spot) = weak.upgrade() else {
                        return glib::ControlFlow::Break;
                    };
                    let mut current = spot.borrow_mut();
                    if generation == current.file_gen && query == current.query {
                        current.files = files;
                        current.rebuild();
                    }
                }
                glib::ControlFlow::Continue
            }
        });

        spot
    }
    fn set_query(&mut self, query: String) {
        self.query = query;
        self.confirm_key.clear();
        self.selected = 0;
        self.files.clear();
        self.file_gen = self.file_gen.wrapping_add(1);
        self.file_cancel.store(true, Ordering::Relaxed);
        self.rebuild();
        let q = self.query.trim();
        let files_wanted = self.files_enabled
            && q.encode_utf16().count() >= 3
            && !q.starts_with('>')
            && !q.starts_with('$')
            && q != "?"
            && math_result(q).is_none();
        if files_wanted {
            let weak = self.weak.clone();
            let generation = self.file_gen;
            let wanted = self.query.clone();
            glib::timeout_add_local_once(Duration::from_millis(220), move || {
                let Some(spot) = weak.upgrade() else {
                    return;
                };
                let mut state = spot.borrow_mut();
                if state.file_gen == generation && state.query == wanted && state.files.is_empty() {
                    state.start_file_search();
                }
            });
        }
    }

    fn start_file_search(&mut self) {
        let generation = self.file_gen;
        let query = self.query.clone();
        let tx = self.file_tx.clone();
        let cancel = Arc::new(AtomicBool::new(false));
        self.file_cancel = cancel.clone();
        std::thread::spawn(move || {
            let files = search_files(&query, &cancel);
            let _ = tx.send((generation, query, files));
        });
    }

    fn handle(&mut self, message: &str) {
        match message {
            "show" => {
                self.window.present();
                self.entry.grab_focus();
            }
            "close" | "toggle" => self.close(),
            _ => {}
        }
    }

    fn rebuild(&mut self) {
        self.rows = self.build_rows();
        if !self
            .rows
            .iter()
            .any(|row| row.confirm && row.key == self.confirm_key)
        {
            self.confirm_key.clear();
        }
        self.rebuild_list();
    }

    fn build_rows(&self) -> Vec<Row> {
        let q = self.query.trim();
        let mut out = Vec::new();
        if q.is_empty() {
            self.add_history(&mut out);
            if out.is_empty() {
                let apps: Vec<Row> = self
                    .apps
                    .ranked_all()
                    .into_iter()
                    .take(8)
                    .map(|index| app_row(index, &self.apps.apps[index]))
                    .collect();
                push_group(&mut out, self.rows_limit, "Applications", apps);
            }
            return out;
        }
        if q == "?" {
            push_group(
                &mut out,
                self.rows_limit,
                "Help",
                help_rows(self.commands_enabled, self.files_enabled, self.web_enabled),
            );
            return out;
        }
        if q.starts_with('>') || q.starts_with('$') {
            if !self.commands_enabled {
                push_group(
                    &mut out,
                    self.rows_limit,
                    "Command",
                    vec![Row::new(
                        "",
                        "Shell commands are off",
                        "Turn them on in Spotlight Settings",
                        "\u{f002}",
                        Act::Settings(Some("spotlight".into())),
                    )],
                );
                return out;
            }
            let command = q[1..].trim().to_string();
            push_group(
                &mut out,
                self.rows_limit,
                "Command",
                vec![Row::new(
                    &format!("cmd:{command}"),
                    if command.is_empty() {
                        "Type a shell command"
                    } else {
                        &command
                    },
                    "Run in a shell",
                    "",
                    Act::Command(command.clone()),
                )],
            );
            return out;
        }

        if let Some(result) = math_result(q) {
            let expression = q.strip_prefix('=').unwrap_or(q);
            push_group(
                &mut out,
                self.rows_limit,
                "Math",
                vec![Row::new(
                    "",
                    &result,
                    &format!("{expression} =  ·  Enter copies"),
                    "󰃬",
                    Act::Copy(result.clone()),
                )],
            );
        }

        let ql = q.to_lowercase();
        let sys = Self::ranked_system_actions(&ql);
        let skins = self.ranked_skins(&ql);
        let skin_prefix = ql.starts_with("skin") || ql.starts_with("bar") || ql.starts_with("menu");
        if skin_prefix {
            push_group(&mut out, self.rows_limit, "Bar skins", skins.clone());
        }
        let apps_limit = if sys.is_empty() { 5 } else { 4 };
        let apps: Vec<Row> = self
            .apps
            .search(q, apps_limit)
            .into_iter()
            .map(|index| app_row(index, &self.apps.apps[index]))
            .collect();
        let apps_first = sys.is_empty()
            || (!apps.is_empty()
                && island_rust::apps::match_score(&apps[0].title.to_lowercase(), &ql)
                    >= island_rust::apps::match_score(&sys[0].title.to_lowercase(), &ql));
        if apps_first {
            push_group(&mut out, self.rows_limit, "Applications", apps);
            push_group(
                &mut out,
                self.rows_limit,
                "Actions",
                sys.into_iter().take(2).collect(),
            );
        } else {
            push_group(
                &mut out,
                self.rows_limit,
                "Actions",
                sys.into_iter().take(2).collect(),
            );
            push_group(&mut out, self.rows_limit, "Applications", apps);
        }
        if !skin_prefix {
            push_group(&mut out, self.rows_limit, "Bar skins", skins);
        }

        if self.files_enabled && !self.files.is_empty() {
            let remaining = self.rows_limit.saturating_sub(1).saturating_sub(out.len());
            let rows: Vec<Row> = self
                .files
                .iter()
                .take(remaining)
                .map(|path| file_row(path))
                .collect();
            push_group(&mut out, self.rows_limit, "Files", rows);
        }

        if self.web_enabled {
            push_group(
                &mut out,
                self.rows_limit,
                "Web",
                vec![Row::new(
                    "",
                    &format!("Search the web for “{q}”"),
                    "DuckDuckGo",
                    "󰖟",
                    Act::Url(format!("https://duckduckgo.com/?q={}", url_escape(q))),
                )],
            );
        }
        out
    }

    fn ranked_system_actions(query: &str) -> Vec<Row> {
        let mut ranked: Vec<(f64, Row)> = system_actions()
            .into_iter()
            .filter_map(|(row, words)| {
                let title = island_rust::apps::match_score(&row.title.to_lowercase(), query) as f64;
                let words = words
                    .split_whitespace()
                    .map(|word| island_rust::apps::match_score(word, query) as f64 * 0.7)
                    .fold(0.0_f64, f64::max);
                let score = title.max(words);
                (score >= 300.0).then_some((score, row))
            })
            .collect();
        ranked.sort_by(|(left, _), (right, _)| right.total_cmp(left));
        ranked.into_iter().map(|(_, row)| row).collect()
    }

    fn ranked_skins(&self, query: &str) -> Vec<Row> {
        let words = [
            "skin", "skins", "bar", "bars", "menu bar", "bar skin", "notch", "island", "pills",
        ];
        let skin_word = query.chars().count() >= 2
            && words
                .iter()
                .any(|word| word.starts_with(query) || query.starts_with(&format!("{word} ")));
        let current_layout = self.cfg.string("shellLayout", "menubar");
        let current_skin = self.cfg.string("barSkin", "classic");
        let mut skins = Vec::new();
        for (id, label, sub, glyph) in [
            ("classic", "Classic", "Full-width menu bar", "󰍜"),
            ("pills", "Pills", "Every item in its own floating pill", "󰮺"),
            (
                "island",
                "Dynamic Island",
                "Only a centre capsule: the time, growing for music, volume, notifications and menus",
                "󰐾",
            ),
            (
                "notch",
                "Notch",
                "Only a MacBook-style notch: the time, growing for music, volume, notifications and menus",
                "󰟀",
            ),
        ] {
            let matches = skin_word
                || (query.chars().count() >= 4
                    && island_rust::apps::match_score(&label.to_lowercase(), query) >= 300);
            if !matches {
                continue;
            }
            let current = current_layout == "menubar" && current_skin == id;
            skins.push(Row::new(
                "",
                label,
                &format!("{}{}", if current { "Current · " } else { "" }, sub),
                glyph,
                Act::Skin(id.into()),
            ));
        }
        skins
    }

    fn add_history(&self, out: &mut Vec<Row>) {
        let pinned = |key: &str| self.history.is_pinned(key);
        let mut recent = Vec::new();
        for key in self.history.recent() {
            if pinned(key) || recent.len() >= 3 {
                continue;
            }
            if let Some(row) = self.row_for_key(key) {
                recent.push(row);
            }
        }
        let seen: Vec<String> = recent.iter().map(|row| row.key.clone()).collect();
        let mut frequent = Vec::new();
        for key in self.history.frequent_ordered() {
            if frequent.len() + recent.len() >= 8 {
                break;
            }
            if seen.contains(&key) {
                continue;
            }
            if let Some(row) = self.row_for_key(&key) {
                frequent.push(row);
            }
        }
        push_group(out, self.rows_limit, "Recently used", recent);
        push_group(out, self.rows_limit, "Frequently used", frequent);
    }

    fn row_for_key(&self, key: &str) -> Option<Row> {
        if let Some(id) = key.strip_prefix("app:") {
            let app = self.apps.by_id(id)?;
            let index = self
                .apps
                .apps
                .iter()
                .position(|candidate| candidate.id == app.id)?;
            return Some(app_row(index, app));
        }
        if let Some(id) = key.strip_prefix("cmd:") {
            return Some(Row::new(
                key,
                id,
                "Shell command",
                "",
                Act::Command(id.to_string()),
            ));
        }
        system_actions()
            .into_iter()
            .find(|(row, _)| row.key == key)
            .map(|(row, _)| row)
    }

    fn rebuild_list(&mut self) {
        while let Some(child) = self.list.first_child() {
            self.list.remove(&child);
        }
        self.list_rows.clear();
        let mut last_section = String::new();
        let mut content_h = 0;
        for (index, row) in self.rows.iter().enumerate() {
            if !row.section.is_empty() && row.section != last_section {
                let header = gtk::ListBoxRow::new();
                header.set_selectable(false);
                header.set_activatable(false);
                header.add_css_class("section-row");
                header.set_size_request(-1, HEAD_H);
                let label = ui::label(&row.section, "section");
                label.set_margin_start(12);
                label.set_margin_bottom(4);
                label.set_valign(gtk::Align::End);
                header.set_child(Some(&label));
                self.list.append(&header);
                last_section.clone_from(&row.section);
                content_h += HEAD_H;
            }
            let widget = self.row_widget(row);
            let secondary = gtk::GestureClick::new();
            secondary.set_button(gdk::BUTTON_SECONDARY);
            secondary.set_propagation_phase(gtk::PropagationPhase::Capture);
            secondary.connect_pressed({
                let weak = self.weak.clone();
                let target = widget.clone();
                move |gesture, _, x, y| {
                    gesture.set_state(gtk::EventSequenceState::Claimed);
                    let Some(spot) = weak.upgrade() else {
                        return;
                    };
                    let root = spot.borrow().root.clone();
                    if let Some(bounds) = target.compute_bounds(&root) {
                        let rect = gdk::Rectangle::new(
                            (bounds.x() + x as f32) as i32,
                            (bounds.y() + y as f32) as i32,
                            1,
                            1,
                        );
                        open_context_menu(&spot, index, Some(rect));
                    }
                }
            });
            widget.add_controller(secondary);
            let list_row = gtk::ListBoxRow::new();
            list_row.set_child(Some(&widget));
            list_row.set_size_request(-1, ROW_H);
            list_row.set_activatable(true);
            let motion = gtk::EventControllerMotion::new();
            let weak = self.weak.clone();
            let target = list_row.clone();
            let list = self.list.clone();
            motion.connect_enter(move |_, _, _| {
                if let Some(spot) = weak.upgrade() {
                    let mut state = spot.borrow_mut();
                    if let Some(index) = state.list_rows.iter().position(|widget| widget == &target)
                    {
                        state.selected = index;
                        list.select_row(Some(&target));
                        state.rebuild_footer();
                    }
                }
            });
            list_row.add_controller(motion);
            self.list_rows.push(list_row.clone());
            self.list.append(&list_row);
            content_h += ROW_H;
        }
        self.list.set_size_request(-1, content_h);
        self.list
            .set_visible(!self.rows.is_empty() && (!self.morph || self.grown));
        self.selected = self.selected.min(self.rows.len().saturating_sub(1));
        if let Some(row) = self.list_rows.get(self.selected) {
            self.list.select_row(Some(row));
        }
        self.resize_card(content_h);
        self.rebuild_footer();
    }

    fn row_widget(&self, row: &Row) -> gtk::Widget {
        let line = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        line.add_css_class("spot-row");
        line.set_size_request(-1, ROW_H);

        if let Some(glyph_text) = &row.glyph {
            let badge = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            badge.add_css_class("glyph-badge");
            if self.confirm_key == row.key && row.confirm {
                badge.add_css_class("asking");
            }
            badge.set_size_request(28, 28);
            badge.set_margin_start(10);
            badge.set_valign(gtk::Align::Center);
            let glyph = ui::glyph(glyph_text, 14);
            glyph.set_halign(gtk::Align::Center);
            glyph.set_valign(gtk::Align::Center);
            badge.append(&glyph);
            line.append(&badge);
        } else {
            let name = row.icon.as_deref().unwrap_or("application-x-executable");
            let image = icon_image(name, "application-x-executable");
            image.set_pixel_size(28);
            image.set_margin_start(10);
            image.set_valign(gtk::Align::Center);
            line.append(&image);
        }

        let text = gtk::Box::new(gtk::Orientation::Vertical, 0);
        text.set_hexpand(true);
        text.set_halign(gtk::Align::Fill);
        let asking = row.confirm && self.confirm_key == row.key;
        let title_text = if asking {
            format!("Press ↵ again to {}", row.title.to_lowercase())
        } else {
            row.title.clone()
        };
        let title = ui::label(&title_text, "row-title");
        if matches!(row.act, Act::Copy(_)) {
            title.add_css_class("calc");
        }
        if asking {
            title.add_css_class("asking");
        }
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        title.set_hexpand(true);
        text.append(&title);
        if !row.sub.is_empty() {
            let sub = ui::label(&row.sub, "row-sub");
            if asking {
                sub.add_css_class("asking");
            }
            sub.set_ellipsize(if matches!(row.act, Act::File(_)) {
                gtk::pango::EllipsizeMode::Middle
            } else {
                gtk::pango::EllipsizeMode::End
            });
            sub.set_hexpand(true);
            text.append(&sub);
        }
        line.append(&text);

        let tail = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        tail.set_margin_end(10);
        tail.set_valign(gtk::Align::Center);
        if !row.key.is_empty() && self.history.is_pinned(&row.key) {
            tail.append(&ui::label("Pinned", "pinned-chip"));
        }
        if self.in_dock(row) {
            tail.append(&ui::label("In Dock", "dock-chip"));
        }
        let enter = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        enter.add_css_class("enter-chip");
        enter.set_size_request(26, 20);
        enter.set_valign(gtk::Align::Center);
        let glyph = ui::label("↵", "faint");
        glyph.set_halign(gtk::Align::Center);
        glyph.set_valign(gtk::Align::Center);
        enter.append(&glyph);
        tail.append(&enter);
        line.append(&tail);
        line.upcast()
    }

    fn resize_card(&mut self, content_h: i32) {
        if self.closing {
            return;
        }
        let height = FIELD_H
            + 1
            + (if self.rows.is_empty() {
                0
            } else {
                content_h + 12
            })
            + 1
            + FOOT_H;
        self.final_h = height;
        if self.morph {
            if self.grown {
                self.current_w = self.width;
                self.current_h = height;
                self.card.set_size_request(self.width, height);
            } else {
                self.current_w = self.cap_w;
                self.current_h = self.cap_h;
                self.card.set_size_request(self.cap_w, self.cap_h);
            }
        } else {
            self.current_w = self.width;
            self.current_h = height;
            self.card.set_size_request(self.width, height);
        }
    }

    fn start_open(&mut self) {
        self.closing = false;
        if !self.morph {
            self.card.set_opacity(0.0);
            let weak = self.weak.clone();
            let start = Instant::now();
            glib::timeout_add_local(Duration::from_millis(16), move || {
                let Some(spot) = weak.upgrade() else {
                    return glib::ControlFlow::Break;
                };
                let state = spot.borrow_mut();
                let t = (start.elapsed().as_millis() as f64 / 120.0).clamp(0.0, 1.0);
                state.card.set_opacity(t);
                if t >= 1.0 {
                    return glib::ControlFlow::Break;
                }
                glib::ControlFlow::Continue
            });
            return;
        }
        self.grown = false;
        self.search.set_visible(false);
        self.list.set_visible(false);
        self.footer.set_visible(false);
        self.search.set_opacity(0.0);
        self.list.set_opacity(0.0);
        self.footer.set_opacity(0.0);
        self.card.set_size_request(self.cap_w, self.cap_h);
        self.current_w = self.cap_w;
        self.current_h = self.cap_h;
        let weak = self.weak.clone();
        let start = Instant::now();
        glib::timeout_add_local(Duration::from_millis(16), move || {
            let Some(spot) = weak.upgrade() else {
                return glib::ControlFlow::Break;
            };
            let mut state = spot.borrow_mut();
            let t = (start.elapsed().as_millis() as f64 / OPEN_MS as f64).clamp(0.0, 1.0);
            let eased = ease_out_back(t, OPEN_OVERSHOOT);
            let width = state.cap_w as f64 + (state.width - state.cap_w) as f64 * eased;
            let height = state.cap_h as f64 + (state.final_h - state.cap_h) as f64 * eased;
            let width = (width.round() as i32).max(1);
            let height = (height.round() as i32).max(1);
            state.card.set_size_request(width, height);
            state.current_w = width;
            state.current_h = height;
            if t >= 0.45 && !state.search.is_visible() {
                state.search.set_visible(true);
                state.footer.set_visible(true);
            }
            if t >= 0.8 {
                state.list.set_visible(!state.rows.is_empty());
            }
            if t >= 1.0 {
                state.grown = true;
                state.card.add_css_class("grown");
                state.card.set_size_request(state.width, state.final_h);
                state.current_w = state.width;
                state.current_h = state.final_h;
                state.search.set_visible(true);
                state.entry.grab_focus();
                state.search.set_opacity(1.0);
                state.list.set_visible(!state.rows.is_empty());
                state.list.set_opacity(1.0);
                state.footer.set_visible(true);
                state.footer.set_opacity(1.0);
                return glib::ControlFlow::Break;
            }
            glib::ControlFlow::Continue
        });
    }

    fn close(&mut self) {
        if self.closing {
            return;
        }
        if !self.morph || !self.grown {
            close_window_later(&self.window);
            return;
        }
        self.closing = true;
        self.search.set_visible(false);
        self.list.set_visible(false);
        self.footer.set_visible(false);
        let weak = self.weak.clone();
        let start = Instant::now();
        let from_w = self.current_w;
        let from_h = self.current_h;
        glib::timeout_add_local(Duration::from_millis(16), move || {
            let Some(spot) = weak.upgrade() else {
                return glib::ControlFlow::Break;
            };
            let state = spot.borrow_mut();
            let t = (start.elapsed().as_millis() as f64 / CLOSE_MS as f64).clamp(0.0, 1.0);
            let eased = ease_out_back(t, OPEN_OVERSHOOT);
            let width = from_w as f64 + (state.cap_w - from_w) as f64 * eased;
            let height = from_h as f64 + (state.cap_h - from_h) as f64 * eased;
            state.card.set_size_request(
                (width.round() as i32).max(1),
                (height.round() as i32).max(1),
            );
            if t >= 1.0 {
                close_window_later(&state.window);
                return glib::ControlFlow::Break;
            }
            glib::ControlFlow::Continue
        });
    }

    fn rebuild_footer(&mut self) {
        while let Some(child) = self.footer.first_child() {
            self.footer.remove(&child);
        }
        let left = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        left.set_valign(gtk::Align::Center);
        let status = if self.query.trim().is_empty() {
            "History"
        } else if self.query.trim() == "?" {
            "Help"
        } else {
            "Results"
        };
        left.append(&ui::label(status, "footer-status"));
        left.append(&key_chip("↑↓", "Navigate"));
        left.append(&key_chip("↵", "Open"));
        left.append(&key_chip("Ctrl 1-9", "Jump"));
        if let Some(row) = self.rows.get(self.selected) {
            if self.history.has(&row.key) {
                left.append(&key_chip("⇧ Del", "Remove"));
            }
            if !row.key.is_empty() {
                left.append(&key_chip(
                    "Ctrl F",
                    if self.history.is_pinned(&row.key) {
                        "Unpin"
                    } else {
                        "Pin"
                    },
                ));
            }
            if matches!(row.act, Act::App(_)) && !self.history.has(&row.key) {
                left.append(&key_chip(
                    "Ctrl ↵",
                    if self.in_dock(row) {
                        "Remove from Dock"
                    } else {
                        "Keep in Dock"
                    },
                ));
            }
        }
        let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        spacer.set_hexpand(true);
        let right = gtk::Box::new(gtk::Orientation::Horizontal, 14);
        right.set_valign(gtk::Align::Center);
        if self.query.trim().is_empty() {
            right.append(&key_chip("?", "Help"));
        }
        right.append(&key_chip("Esc", "Close"));
        self.footer.append(&left);
        self.footer.append(&spacer);
        self.footer.append(&right);
    }

    fn in_dock(&self, row: &Row) -> bool {
        let Act::App(index) = row.act else {
            return false;
        };
        let Some(app) = self.apps.apps.get(index) else {
            return false;
        };
        let id = app.id.as_str();
        match self.cfg.get("dockPinned") {
            serde_json::Value::Array(items) => items
                .iter()
                .filter_map(|value| value.as_str())
                .any(|pin| pin_matches(pin, id)),
            _ => false,
        }
    }

    fn move_selection(&mut self, delta: i64) {
        if self.list_rows.is_empty() {
            return;
        }
        let len = self.list_rows.len() as i64;
        let next = (self.selected as i64 + delta).rem_euclid(len) as usize;
        self.selected = next;
        self.list.select_row(Some(&self.list_rows[next]));
        self.rebuild_footer();
    }
}

fn activate(spot: &Rc<RefCell<Spotlight>>, index: usize) {
    let (act, key, confirm) = {
        let state = spot.borrow();
        let Some(row) = state.rows.get(index) else {
            return;
        };
        (row.act.clone(), row.key.clone(), row.confirm)
    };
    if confirm {
        let already = spot.borrow().confirm_key == key;
        if !already && !key.is_empty() {
            spot.borrow_mut().confirm_key = key;
            spot.borrow_mut().rebuild();
            return;
        }
        spot.borrow_mut().confirm_key.clear();
    }
    match &act {
        Act::Fill(text) => {
            let entry = spot.borrow().entry.clone();
            entry.set_text(text);
            entry.set_position(-1);
            return;
        }
        Act::Command(command) if command.trim().is_empty() => return,
        _ => {}
    }
    if let Act::App(index) = act {
        let app = spot.borrow().apps.apps.get(index).cloned();
        spot.borrow_mut().close();
        if let Some(app) = app {
            let mut state = spot.borrow_mut();
            state.history.record(&format!("app:{}", app.id));
            state.apps.record_launch(&app.id);
            drop(state);
            if let Err(error) = apps::launch(&app) {
                eprintln!("island-spotlight: {error}");
            }
        }
        return;
    }
    if !key.is_empty() && !matches!(act, Act::File(_)) {
        spot.borrow_mut().history.record(&key);
    }
    spot.borrow_mut().close();
    match act {
        Act::File(path) => system::open_path(&path),
        Act::Power(action) => system::power(action),
        Act::Command(command) => system::run_command(&command),
        Act::Copy(text) => system::copy_text(&text),
        Act::Url(url) => system::open_url(&url),
        Act::Settings(page) => system::open_settings(page.as_deref()),
        Act::Skin(id) => {
            let mut state = spot.borrow_mut();
            let _ = state.cfg.set("shellLayout", serde_json::json!("menubar"));
            let _ = state.cfg.set("barSkin", serde_json::json!(id));
            drop(state);
            system::apply_settings();
        }
        Act::App(_) | Act::Fill(_) => {}
    }
}

fn menu_separator() -> gtk::Box {
    let sep = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    sep.add_css_class("ctx-sep");
    sep.set_height_request(1);
    sep
}

fn open_context_menu(
    spot: &Rc<RefCell<Spotlight>>,
    index: usize,
    position: Option<gdk::Rectangle>,
) {
    let (row, root, card, query, docked) = {
        let mut state = spot.borrow_mut();
        let Some(row) = state.rows.get(index).cloned() else {
            return;
        };
        let root = state.root.clone();
        let card = state.card.clone();
        if let Some(menu) = state.ctx_menu.take() {
            menu.popdown();
        }
        let docked = state.in_dock(&row);
        (row, root, card, state.query.clone(), docked)
    };
    if matches!(row.act, Act::Fill(_)) {
        return;
    }
    let rect = position.or_else(|| {
        card.compute_bounds(&root).map(|bounds| {
            gdk::Rectangle::new(
                (bounds.x() + 60.0) as i32,
                (bounds.y() + FIELD_H as f32 + 30.0) as i32,
                1,
                1,
            )
        })
    });
    let Some(rect) = rect else {
        return;
    };
    let popover = gtk::Popover::new();
    popover.add_css_class("spot-menu");
    popover.set_has_arrow(false);
    popover.set_parent(&root);
    let menu = gtk::Box::new(gtk::Orientation::Vertical, 0);
    menu.set_margin_start(2);
    menu.set_margin_end(2);
    let add_header = |text: &str| {
        let label = ui::label(text, "ctx-header");
        menu.append(&label);
    };
    let add_action = |label: &str, action: MenuAct| {
        let button = gtk::Button::with_label(label);
        button.add_css_class("flat");
        let popover = popover.clone();
        let weak = Rc::downgrade(spot);
        button.connect_clicked(move |_| {
            popover.popdown();
            if let Some(spot) = weak.upgrade() {
                run_menu_action(&spot, &action);
            }
        });
        menu.append(&button);
    };
    let history_items = |key: &str| {
        if key.is_empty() {
            return;
        }
        menu.append(&menu_separator());
        let pinned = spot.borrow().history.is_pinned(key);
        add_action(
            if pinned {
                "Unpin from Top"
            } else {
                "Pin to Top"
            },
            MenuAct::TogglePin(key.to_string()),
        );
        if spot.borrow().history.has(key) {
            add_action("Remove from Recents", MenuAct::Forget(key.to_string()));
        }
    };
    match row.act {
        Act::App(app_index) => {
            add_header(&row.title);
            add_action("Open", MenuAct::Activate(index));
            let actions = spot
                .borrow()
                .apps
                .apps
                .get(app_index)
                .map(AppEntry::actions)
                .unwrap_or_default();
            if !actions.is_empty() {
                menu.append(&menu_separator());
                for (id, name) in actions {
                    add_action(&name, MenuAct::AppAction(app_index, id));
                }
            }
            menu.append(&menu_separator());
            add_action(
                if docked {
                    "Unpin from Taskbar"
                } else {
                    "Pin to Taskbar"
                },
                MenuAct::ToggleDock(row.key.trim_start_matches("app:").to_string()),
            );
            history_items(&row.key);
        }
        Act::File(ref path) => {
            add_header(&row.title);
            add_action("Open", MenuAct::Activate(index));
            add_action(
                "Open Containing Folder",
                MenuAct::OpenFolder(
                    path.parent()
                        .map_or_else(paths::home, std::path::Path::to_path_buf),
                ),
            );
            menu.append(&menu_separator());
            add_action(
                "Copy Path",
                MenuAct::Copy(path.to_string_lossy().to_string()),
            );
            add_action("Copy Name", MenuAct::Copy(row.title.clone()));
        }
        Act::Command(ref command) if !command.trim().is_empty() => {
            add_action("Run", MenuAct::Activate(index));
            add_action("Copy Command", MenuAct::Copy(command.clone()));
            history_items(&row.key);
        }
        Act::Copy(ref result) => {
            add_action("Copy Result", MenuAct::CloseCopy(result.clone()));
            add_action(
                "Copy Expression",
                MenuAct::Copy(query.trim().trim_start_matches('=').to_string()),
            );
        }
        Act::Url(_) => {
            add_action("Search the Web", MenuAct::Activate(index));
            add_action("Copy Search Text", MenuAct::Copy(query.trim().to_string()));
        }
        Act::Power(_) | Act::Settings(_) | Act::Skin(_) => {
            add_header(&row.title);
            let label = if row.confirm {
                format!("{}…", row.title)
            } else {
                row.title.clone()
            };
            add_action(&label, MenuAct::Activate(index));
            history_items(&row.key);
        }
        Act::Command(_) | Act::Fill(_) => {}
    }
    if menu.first_child().is_none() {
        return;
    }
    popover.set_child(Some(&menu));
    let menu_width = menu.measure(gtk::Orientation::Horizontal, -1).1;
    let rect = gdk::Rectangle::new(rect.x() + menu_width / 2, rect.y(), 1, 1);
    popover.set_pointing_to(Some(&rect));
    popover.connect_closed({
        let weak = Rc::downgrade(spot);
        move |_| {
            if let Some(spot) = weak.upgrade() {
                spot.borrow_mut().ctx_menu = None;
            }
        }
    });
    popover.popup();
    spot.borrow_mut().ctx_menu = Some(popover);
}

fn run_menu_action(spot: &Rc<RefCell<Spotlight>>, action: &MenuAct) {
    match action {
        MenuAct::Activate(index) => activate(spot, *index),
        MenuAct::AppAction(app_index, action) => {
            let app = spot.borrow().apps.apps.get(*app_index).cloned();
            spot.borrow_mut().close();
            if let Some(app) = app {
                app.launch_action(action);
            }
        }
        MenuAct::ToggleDock(id) => toggle_dock_id(spot, id),
        MenuAct::TogglePin(key) => {
            let mut state = spot.borrow_mut();
            state.history.toggle_pin(key);
            state.rebuild();
        }
        MenuAct::Forget(key) => {
            let mut state = spot.borrow_mut();
            state.history.forget(key);
            state.rebuild();
        }
        MenuAct::OpenFolder(path) => {
            spot.borrow_mut().close();
            system::open_path(path);
        }
        MenuAct::Copy(text) => system::copy_text(text),
        MenuAct::CloseCopy(text) => {
            spot.borrow_mut().close();
            system::copy_text(text);
        }
    }
}

fn toggle_dock_id(spot: &Rc<RefCell<Spotlight>>, id: &str) {
    let mut state = spot.borrow_mut();
    let mut items: Vec<String> = match state.cfg.get("dockPinned") {
        serde_json::Value::Array(values) => values
            .into_iter()
            .filter_map(|value| value.as_str().map(str::to_string))
            .collect(),
        _ => Vec::new(),
    };
    let before = items.len();
    items.retain(|pin| !pin_matches(pin, id));
    if items.len() == before {
        items.push(id.to_string());
    }
    if state
        .cfg
        .set("dockPinned", serde_json::json!(items))
        .is_ok()
    {
        state.rebuild();
    }
}

fn pin_matches(pin: &str, id: &str) -> bool {
    pin == id || pin == id.trim_end_matches(".desktop") || id.starts_with(pin)
}

fn toggle_dock_selected(spot: &Rc<RefCell<Spotlight>>) {
    let id = {
        let state = spot.borrow();
        let Some(row) = state.rows.get(state.selected) else {
            return;
        };
        let Act::App(index) = row.act else {
            return;
        };
        let Some(app) = state.apps.apps.get(index) else {
            return;
        };
        app.id.clone()
    };
    toggle_dock_id(spot, &id);
}

fn pin_selected(spot: &Rc<RefCell<Spotlight>>) {
    let key = {
        let state = spot.borrow();
        state
            .rows
            .get(state.selected)
            .map(|row| row.key.clone())
            .filter(|key| !key.is_empty())
    };
    if let Some(key) = key {
        let mut state = spot.borrow_mut();
        state.history.toggle_pin(&key);
        state.rebuild();
    }
}

fn forget_selected(spot: &Rc<RefCell<Spotlight>>) {
    let key = {
        let state = spot.borrow();
        let Some(key) = state.rows.get(state.selected).map(|row| row.key.clone()) else {
            return;
        };
        if !state.history.has(&key) {
            return;
        }
        key
    };
    {
        let mut state = spot.borrow_mut();
        state.history.forget(&key);
        state.rebuild();
    }
}

fn system_actions() -> Vec<(Row, &'static str)> {
    vec![
        (
            Row::new(
                "sys:lock",
                "Lock",
                "Lock the screen",
                "",
                Act::Power("lock"),
            ),
            "lock screen",
        ),
        (
            Row::new(
                "sys:sleep",
                "Sleep",
                "Suspend to RAM",
                "󰒲",
                Act::Power("suspend"),
            ),
            "sleep suspend",
        ),
        (
            Row::new(
                "sys:logout",
                "Log Out",
                "End the session",
                "󰍃",
                Act::Power("logout"),
            ),
            "log out logout exit quit session",
        ),
        (
            Row::new(
                "sys:reboot",
                "Restart",
                "Reboot the computer",
                "",
                Act::Power("reboot"),
            ),
            "restart reboot",
        ),
        (
            Row::new(
                "sys:off",
                "Shut Down",
                "Power off the computer",
                "⏻",
                Act::Power("poweroff"),
            ),
            "shut down shutdown power off poweroff",
        ),
        (
            Row::new(
                "sys:settings",
                "System Settings",
                "Island settings",
                "",
                Act::Settings(None),
            ),
            "settings preferences island",
        ),
        (
            Row::new(
                "sys:spotlight",
                "Spotlight Settings",
                "Window, results and search sources",
                "\u{f002}",
                Act::Settings(Some("spotlight".into())),
            ),
            "spotlight search launcher settings",
        ),
    ]
}

fn help_rows(commands: bool, files: bool, web: bool) -> Vec<Row> {
    let mut rows = vec![Row::new(
        "",
        "Apps & actions",
        "Type a name: Firefox, Lock, Sleep, Restart…",
        "",
        Act::Fill(String::new()),
    )];
    if commands {
        rows.push(Row::new(
            "",
            "> command",
            "Run a shell command ($ works too)",
            "",
            Act::Fill("> ".into()),
        ));
    }
    rows.push(Row::new(
        "",
        "Math",
        "2*(3+4), 15% of 80 → type it, Enter copies the result",
        "󰃬",
        Act::Fill(String::new()),
    ));
    if files {
        rows.push(Row::new(
            "",
            "Files",
            "3+ letters also search your home folder",
            "",
            Act::Fill(String::new()),
        ));
    }
    if web {
        rows.push(Row::new(
            "",
            "Web",
            "Anything else: last row searches DuckDuckGo",
            "󰖟",
            Act::Fill(String::new()),
        ));
    }
    rows.push(Row::new(
        "",
        "Frequently used",
        "Ctrl+F pins the selected row so it stays at the top",
        "󰐃",
        Act::Fill(String::new()),
    ));
    rows
}
fn app_row(index: usize, app: &AppEntry) -> Row {
    let mut row = Row::new(
        &format!("app:{}", app.id),
        &app.name,
        app.subtitle(),
        "",
        Act::App(index),
    );
    row.icon = Some(
        app.icon
            .clone()
            .unwrap_or_else(|| "application-x-executable".to_string()),
    );
    row
}

fn file_row(path: &std::path::Path) -> Row {
    let name = path.file_name().map_or_else(
        || path.to_string_lossy().to_string(),
        |name| name.to_string_lossy().to_string(),
    );
    let home = paths::home();
    let display = path.strip_prefix(&home).map_or_else(
        |_| path.to_string_lossy().to_string(),
        |relative| format!("~/{}", relative.to_string_lossy()),
    );
    let ext = path
        .extension()
        .map(|ext| ext.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    let icon = match ext.as_str() {
        "png" | "jpg" | "jpeg" | "webp" | "gif" | "svg" => "image-x-generic",
        "mp4" | "mkv" | "webm" | "mov" => "video-x-generic",
        "mp3" | "flac" | "ogg" | "wav" | "opus" => "audio-x-generic",
        "pdf" => "application-pdf",
        "" => "folder",
        _ => "text-x-generic",
    };
    let mut row = Row::new("", &name, &display, "", Act::File(path.to_path_buf()));
    row.icon = Some(icon.into());
    row
}

fn push_group(out: &mut Vec<Row>, limit: usize, section: &str, rows: Vec<Row>) {
    for (index, mut row) in rows.into_iter().enumerate() {
        if out.len() >= limit {
            break;
        }
        if index == 0 {
            row.section = section.to_string();
        }
        out.push(row);
    }
}

fn math_result(query: &str) -> Option<String> {
    let trimmed = query.trim();
    let forced = trimmed.starts_with('=');
    let stripped = trimmed.strip_prefix('=').unwrap_or(trimmed);
    if stripped.is_empty() || !stripped.chars().any(|c| c.is_ascii_digit()) {
        return None;
    }
    let expression = expand_percent_of(stripped);
    if !expression
        .chars()
        .all(|c| c.is_ascii_digit() || c.is_whitespace() || "+-*/%().,^".contains(c))
    {
        return None;
    }
    if !forced && !expression.chars().any(|c| "+-*/%^".contains(c)) {
        return None;
    }
    let expression = expression.replace(',', ".");
    let value = meval::eval_str(&expression).ok()?;
    if !value.is_finite() {
        return None;
    }
    let rounded = js_round(value * 1e10) / 1e10;
    if rounded == 0.0 {
        Some("0".to_string())
    } else {
        Some(format!("{rounded}"))
    }
}

fn expand_percent_of(input: &str) -> String {
    let mut out = input.to_string();
    let mut search_from = 0;
    while let Some(offset) = out[search_from..].find('%') {
        let percent = search_from + offset;
        let mut number_end = percent;
        while number_end > 0 && out.as_bytes()[number_end - 1].is_ascii_whitespace() {
            number_end -= 1;
        }
        let mut number_start = number_end;
        while number_start > 0 && out.as_bytes()[number_start - 1].is_ascii_digit() {
            number_start -= 1;
        }
        if number_start < number_end
            && number_start > 0
            && matches!(out.as_bytes()[number_start - 1], b'.' | b',')
        {
            let dot = number_start - 1;
            let mut start = dot;
            while start > 0 && out.as_bytes()[start - 1].is_ascii_digit() {
                start -= 1;
            }
            if start < dot {
                number_start = start;
            }
        }
        if number_start == number_end {
            search_from = percent + 1;
            continue;
        }
        let mut end = percent + 1;
        while end < out.len() && out.as_bytes()[end].is_ascii_whitespace() {
            end += 1;
        }
        if !out
            .get(end..end + 2)
            .is_some_and(|word| word.eq_ignore_ascii_case("of"))
        {
            search_from = percent + 1;
            continue;
        }
        end += 2;
        while end < out.len() && out.as_bytes()[end].is_ascii_whitespace() {
            end += 1;
        }
        let number = out[number_start..number_end].replace(',', ".");
        let replacement = format!("({number}/100)*");
        out.replace_range(number_start..end, &replacement);
        search_from = number_start + replacement.len();
    }
    out
}

fn js_round(value: f64) -> f64 {
    (value + 0.5).floor()
}

fn search_files(query: &str, cancel: &AtomicBool) -> Vec<PathBuf> {
    let needle = query.to_lowercase();
    let home = paths::home();
    let deadline = Instant::now() + Duration::from_secs(1);
    let mut out = Vec::new();
    for entry in walkdir::WalkDir::new(&home)
        .max_depth(4)
        .into_iter()
        .filter_entry(|entry| {
            entry
                .file_name()
                .to_str()
                .is_none_or(|name| name == "." || !name.starts_with('.'))
        })
        .flatten()
    {
        if cancel.load(Ordering::Relaxed) || Instant::now() >= deadline {
            break;
        }
        if entry.path() == home {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_lowercase();
        if name.contains(&needle) {
            out.push(entry.path().to_path_buf());
            if out.len() >= 4 {
                break;
            }
        }
    }
    out
}

fn icon_image(name: &str, fallback: &str) -> gtk::Image {
    if name.contains('/') {
        return gtk::Image::from_file(name);
    }
    let icon = gtk::gdk::Display::default().map_or(name, |display| {
        let theme = gtk::IconTheme::for_display(&display);
        if theme.has_icon(name) {
            name
        } else {
            fallback
        }
    });
    gtk::Image::from_icon_name(icon)
}

fn schedule_hover_close(weak: &Weak<RefCell<Spotlight>>, pending: &Rc<Cell<bool>>) {
    let Some(spot) = weak.upgrade() else {
        return;
    };
    {
        let state = spot.borrow();
        if !state.grown || state.ctx_menu.is_some() {
            return;
        }
    }
    pending.set(true);
    let weak = weak.clone();
    let pending = pending.clone();
    glib::timeout_add_local_once(Duration::from_millis(HOVER_GRACE_MS), move || {
        if !pending.get() {
            return;
        }
        if let Some(spot) = weak.upgrade() {
            let mut state = spot.borrow_mut();
            if state.grown && !state.closing && state.ctx_menu.is_none() {
                state.close();
            }
        }
    });
}

fn close_window_later(window: &gtk::ApplicationWindow) {
    let window = window.clone();
    glib::idle_add_local_once(move || window.close());
}

fn ease_out_back(t: f64, overshoot: f64) -> f64 {
    let c3 = overshoot + 1.0;
    let u = t - 1.0;
    1.0 + c3 * u * u * u + overshoot * u * u
}

fn key_chip(keys: &str, label: &str) -> gtk::Box {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    row.set_valign(gtk::Align::Center);
    let cap = ui::label(keys, "keycap");
    cap.set_halign(gtk::Align::Center);
    cap.set_valign(gtk::Align::Center);
    row.append(&cap);
    row.append(&ui::label(label, "keylabel"));
    row
}

fn url_escape(value: &str) -> String {
    use std::fmt::Write as _;

    let mut out = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'_'
            | b'.'
            | b'!'
            | b'~'
            | b'*'
            | b'\''
            | b'('
            | b')' => out.push(byte as char),
            b' ' => out.push('+'),
            _ => {
                let _ = write!(out, "%{byte:02X}");
            }
        }
    }
    out
}

fn main() {
    let (shell_dir, monitor, command) = parse_args();
    if let Some(shell_dir) = shell_dir {
        std::env::set_var("ISLAND_SHELL_DIR", shell_dir);
    }
    let (tx, rx) = async_channel::unbounded();
    let Ok(Some(instance)) = Instance::claim("island-spotlight", &command, tx) else {
        return;
    };
    // `--close` with no running instance is a no-op, not a new window.
    if command == "close" {
        drop(instance);
        return;
    }
    let app = gtk::Application::builder()
        .application_id("org.island.SpotlightRust")
        .build();
    let state: Rc<RefCell<Option<Rc<RefCell<Spotlight>>>>> = Rc::new(RefCell::new(None));
    {
        let state = state.clone();
        let monitor = monitor.clone();
        app.connect_activate(move |app| {
            let spot = Spotlight::new(app, monitor.as_deref());
            state.replace(Some(spot));
        });
    }
    glib::timeout_add_local(Duration::from_millis(60), {
        let state = state.clone();
        move || {
            while let Ok(message) = rx.try_recv() {
                if let Some(spot) = state.borrow().as_ref() {
                    spot.borrow_mut().handle(&message);
                }
            }
            glib::ControlFlow::Continue
        }
    });
    let _ = app.run_with_args(&["island-rust"]);
    drop(instance);
}

fn parse_args() -> (Option<String>, Option<String>, String) {
    let mut shell_dir = None;
    let mut monitor = None;
    let mut open = false;
    let mut close = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--shell-dir" => shell_dir = args.next(),
            "--monitor" => monitor = args.next(),
            "--open" => open = true,
            "--close" => close = true,
            _ => {}
        }
    }
    let command = if close {
        "close".to_string()
    } else if open {
        "show".to_string()
    } else {
        "toggle".to_string()
    };
    (shell_dir, monitor, command)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn math_basics() {
        assert_eq!(math_result("2+2").as_deref(), Some("4"));
        assert_eq!(math_result("15% of 80").as_deref(), Some("12"));
        assert_eq!(math_result("=1/3").as_deref(), Some("0.3333333333"));
        assert_eq!(math_result("2^3").as_deref(), Some("8"));
        assert_eq!(math_result("hello"), None);
        assert_eq!(math_result("100%"), None);
    }

    #[test]
    fn percent_of_is_case_insensitive() {
        assert_eq!(math_result("15 % OF 80").as_deref(), Some("12"));
    }

    #[test]
    fn unicode_is_not_math() {
        assert_eq!(math_result("λ+2"), None);
    }

    #[test]
    fn fuzzy_match_rewards_prefixes() {
        assert!(
            island_rust::apps::match_score("firefox", "fire")
                > island_rust::apps::match_score("librewolf", "fire")
        );
        assert_eq!(island_rust::apps::match_score("firefox", "firefox"), 1000);
    }
}
