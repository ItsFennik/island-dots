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
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Clone)]
enum Act {
    App(usize),
    File(PathBuf),
    Power(&'static str),
    Command(String),
    Copy(String),
    Url(String),
    Settings(Option<String>),
    Qml(Option<String>),
    Skin(String),
    Fill(String),
    None,
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
    focus_ready: bool,
    closing: bool,
    rows: Vec<Row>,
    row_widgets: Vec<gtk::ListBoxRow>,
    selected: usize,
    query: String,
    confirm_key: String,
    rows_limit: usize,
    files_enabled: bool,
    commands_enabled: bool,
    web_enabled: bool,
    files: Vec<PathBuf>,
    file_gen: u64,
    file_tx: mpsc::Sender<(u64, String, Vec<PathBuf>)>,
    weak: Weak<RefCell<Spotlight>>,
}

impl Spotlight {
    fn new(app: &gtk::Application, monitor_name: Option<String>) -> Rc<RefCell<Self>> {
        let cfg = Config::load();
        let theme = Theme::load(&cfg);
        ui::install_css(&theme);
        let apps = AppIndex::load();
        let history = History::load();
        let rows_limit = cfg.i64("spotlightRows", 9).clamp(5, 12) as usize;
        let width = cfg.i64("spotlightWidth", 700).clamp(460, 920) as i32;
        let files_enabled = cfg.bool("spotlightFiles", true);
        let commands_enabled = cfg.bool("spotlightCommands", true);
        let web_enabled = cfg.bool("spotlightWeb", true);
        let layout = cfg.string("shellLayout", "menubar");
        let skin = cfg.string("barSkin", "classic");
        let capsule = layout == "menubar" && (skin == "island" || skin == "notch");
        let morph = match cfg.string("spotlightStyle", "auto").as_str() {
            "floating" => false,
            "capsule" => capsule,
            // "attached" means the capsule on capsule bars, and the edge elsewhere.
            "attached" => capsule && cfg.bool("spotlightFromCapsule", true),
            _ => capsule && cfg.bool("spotlightFromCapsule", true),
        };
        let cap_w = if skin == "notch" { 190 } else { 104 };
        let cap_h = cfg.i64("barHeight", 30) as i32;
        let cap_y = if skin == "notch" { 0 } else { 6 };

        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("Spotlight")
            .build();
        window.set_decorated(false);
        window.init_layer_shell();
        window.set_namespace(Some(if morph {
            "island-capsule-spotlight"
        } else {
            "island-spotlight"
        }));
        window.set_layer(Layer::Overlay);
        window.set_keyboard_mode(KeyboardMode::Exclusive);
        window.set_exclusive_zone(-1);
        let monitor = ui::monitor_for(monitor_name.as_deref());
        if let Some(monitor) = &monitor {
            window.set_monitor(Some(monitor));
        }
        let screen_height = monitor
            .as_ref()
            .map(|monitor| monitor.geometry().height())
            .unwrap_or(1080);
        let (bottom, margin) = placement(&cfg, screen_height);
        let edge = if morph {
            Edge::Top
        } else if bottom {
            Edge::Bottom
        } else {
            Edge::Top
        };
        window.set_anchor(edge, true);
        window.set_margin(edge, if morph { 0 } else { margin });
        let max_height = 52 + 1 + rows_limit as i32 * 44 + 1 + 34;
        if morph {
            window.set_default_size(width + 40, max_height + 4 * 26 + cap_y + 40);
        } else {
            window.set_default_size(width + 40, max_height);
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
            card.set_margin_top(cap_y);
            card.set_size_request(cap_w, cap_h);
        } else {
            card.set_size_request(width, max_height);
        }
        card.set_halign(gtk::Align::Center);
        card.set_valign(if bottom && !morph {
            gtk::Align::End
        } else {
            gtk::Align::Start
        });
        card.set_overflow(gtk::Overflow::Hidden);
        root.append(&card);
        window.set_child(Some(&root));

        let search = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        search.set_size_request(-1, 52);
        search.set_margin_start(18);
        search.set_margin_end(18);
        let icon = ui::label(">_", "spot-prompt");
        let entry = gtk::Entry::new();
        entry.set_placeholder_text(Some("Search   ·   ? for help"));
        entry.set_has_frame(false);
        entry.set_hexpand(true);
        entry.set_valign(gtk::Align::Center);
        entry.add_css_class("spot-entry");
        search.append(&icon);
        search.append(&entry);
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
        footer.set_size_request(-1, 34);
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
                    move |entry| {
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
                                .row_widgets
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
                        if keyval == gdk::Key::Down || keyval == gdk::Key::Tab {
                            spot.borrow_mut().move_selection(1);
                            return glib::Propagation::Stop;
                        }
                        if keyval == gdk::Key::Up || keyval == gdk::Key::ISO_Left_Tab {
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
                glib::timeout_add_local_once(Duration::from_millis(450), move || armed2.set(true));

                RefCell::new(Self {
                    cfg,
                    apps,
                    history,
                    window: window.clone(),
                    card: card.clone(),
                    search: search.clone(),
                    entry: entry.clone(),
                    list,
                    footer: footer.clone(),
                    width,
                    morph,
                    cap_w,
                    cap_h,
                    final_h: max_height,
                    current_w: cap_w,
                    current_h: cap_h,
                    grown: !morph,
                    focus_ready: !morph,
                    closing: false,
                    rows: Vec::new(),
                    row_widgets: Vec::new(),
                    selected: 0,
                    query: String::new(),
                    confirm_key: String::new(),
                    rows_limit,
                    files_enabled,
                    commands_enabled,
                    web_enabled,
                    files: Vec::new(),
                    file_gen: 0,
                    file_tx: file_tx.clone(),
                    weak: weak.clone(),
                })
            });

        spot.borrow_mut().rebuild();
        window.present();
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
        self.files.clear();
        self.file_gen = self.file_gen.wrapping_add(1);
        self.rebuild();
        let q = self.query.trim();
        if self.files_enabled
            && q.len() >= 3
            && !q.starts_with('>')
            && !q.starts_with('$')
            && q != "?"
        {
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
        std::thread::spawn(move || {
            let files = search_files(&query);
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
                    .apps
                    .iter()
                    .enumerate()
                    .take(self.rows_limit)
                    .map(|(index, app)| app_row(index, app))
                    .collect();
                push_group(&mut out, self.rows_limit, "Applications", apps);
            }
            return out;
        }
        if q == "?" {
            let mut help = vec![Row::new(
                "",
                "Apps & actions",
                "Type a name: Firefox, Lock, Sleep, Restart…",
                "",
                Act::None,
            )];
            if self.commands_enabled {
                help.push(Row::new(
                    "",
                    "> command",
                    "Run a shell command ($ works too)",
                    "",
                    Act::Fill("> ".into()),
                ));
            }
            help.push(Row::new(
                "",
                "Math",
                "2*(3+4), 15% of 80. Enter copies the result",
                "󰃬",
                Act::Fill(String::new()),
            ));
            if self.files_enabled {
                help.push(Row::new(
                    "",
                    "Files",
                    "3+ letters also search your home folder",
                    "",
                    Act::Fill(String::new()),
                ));
            }
            if self.web_enabled {
                help.push(Row::new(
                    "",
                    "Web",
                    "Anything else: the last row searches DuckDuckGo",
                    "󰖟",
                    Act::Fill(String::new()),
                ));
            }
            help.push(Row::new(
                "",
                "Pinning",
                "Ctrl F pins the selected row; Shift Delete forgets it",
                "󰐃",
                Act::Fill(String::new()),
            ));
            push_group(&mut out, self.rows_limit, "Help", help);
            return out;
        }
        if q.starts_with('>') || q.starts_with('$') {
            if !self.commands_enabled {
                push_group(
                    &mut out,
                    self.rows_limit,
                    "Command",
                    vec![Row::new(
                        "sys:spotlight",
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
            push_group(
                &mut out,
                self.rows_limit,
                "Math",
                vec![Row::new(
                    "",
                    &result,
                    &format!("{} = · Enter copies", q),
                    "󰃬",
                    Act::Copy(result.clone()),
                )],
            );
        }

        let ql = q.to_lowercase();
        let mut actions = Vec::new();
        for row in system_actions() {
            let haystack = format!("{} {}", row.title, row.sub).to_lowercase();
            if haystack.contains(&ql) {
                actions.push(row);
            }
        }
        push_group(&mut out, self.rows_limit, "Actions", actions);

        let apps = self
            .apps
            .search(q, if out.len() < self.rows_limit { 6 } else { 0 });
        let app_rows: Vec<Row> = apps
            .iter()
            .filter_map(|app| {
                self.apps
                    .apps
                    .iter()
                    .position(|candidate| candidate.id == app.id)
                    .map(|index| app_row(index, app))
            })
            .collect();
        push_group(&mut out, self.rows_limit, "Applications", app_rows);

        if skin_query(&ql) {
            let current = self.cfg.string("barSkin", "classic");
            let mut skins = Vec::new();
            for (id, label, sub) in [
                ("classic", "Classic", "Full-width menu bar"),
                ("pills", "Pills", "Every item in its own floating pill"),
                ("island", "Dynamic Island", "Only a centre capsule"),
                ("notch", "Notch", "A MacBook-style notch"),
            ] {
                skins.push(Row::new(
                    "",
                    label,
                    &format!("{}{}", if current == id { "Current · " } else { "" }, sub),
                    "󰮺",
                    Act::Skin(id.into()),
                ));
            }
            push_group(&mut out, self.rows_limit, "Bar skins", skins);
        }

        if self.files_enabled && q.len() >= 3 && !self.files.is_empty() {
            let remaining = self
                .rows_limit
                .saturating_sub(out.len())
                .saturating_sub(usize::from(self.web_enabled));
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
        if out.is_empty() {
            push_group(
                &mut out,
                self.rows_limit,
                "",
                vec![Row::new(
                    "",
                    "No results",
                    "Try another name, or turn on web search in Spotlight Settings",
                    "󰍉",
                    Act::None,
                )],
            );
        }
        out
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
        let recent_keys: Vec<String> = self.history.recent().to_vec();
        let mut frequent = Vec::new();
        for key in self.history.frequent_ordered() {
            if frequent.len() + recent.len() >= self.rows_limit {
                break;
            }
            if recent_keys.contains(&key) && !pinned(&key) {
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
            let index = self.apps.apps.iter().position(|app| app.id == id)?;
            return Some(app_row(index, &self.apps.apps[index]));
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
        system_actions().into_iter().find(|row| row.key == key)
    }

    fn rebuild_list(&mut self) {
        while let Some(child) = self.list.first_child() {
            self.list.remove(&child);
        }
        self.row_widgets.clear();
        let mut last_section = String::new();
        let mut content_h = 0;
        for row in &self.rows {
            if !row.section.is_empty() && row.section != last_section {
                let header = gtk::ListBoxRow::new();
                header.set_selectable(false);
                header.set_activatable(false);
                header.add_css_class("section-row");
                header.set_size_request(-1, 26);
                let label = ui::label(&row.section.to_uppercase(), "section");
                label.set_margin_start(12);
                label.set_margin_bottom(4);
                label.set_valign(gtk::Align::End);
                header.set_child(Some(&label));
                self.list.append(&header);
                last_section = row.section.clone();
                content_h += 26;
            }
            let widget = self.row_widget(row);
            let list_row = gtk::ListBoxRow::new();
            list_row.set_child(Some(&widget));
            list_row.set_size_request(-1, 44);
            list_row.set_selectable(!matches!(row.act, Act::None));
            list_row.set_activatable(!matches!(row.act, Act::None));
            if !matches!(row.act, Act::None) {
                let motion = gtk::EventControllerMotion::new();
                let weak = self.weak.clone();
                let target = list_row.clone();
                let list = self.list.clone();
                motion.connect_enter(move |_, _, _| {
                    if let Some(spot) = weak.upgrade() {
                        let mut state = spot.borrow_mut();
                        if let Some(index) = state
                            .row_widgets
                            .iter()
                            .position(|widget| widget == &target)
                        {
                            state.selected = index;
                            list.select_row(Some(&target));
                            state.rebuild_footer();
                        }
                    }
                });
                list_row.add_controller(motion);
                self.row_widgets.push(list_row.clone());
            }
            self.list.append(&list_row);
            content_h += 44;
        }
        self.list.set_size_request(-1, content_h);
        self.list
            .set_visible(!self.rows.is_empty() && (!self.morph || self.grown));
        if let Some(first) = self.row_widgets.first() {
            self.selected = 0;
            self.list.select_row(Some(first));
        } else {
            self.selected = 0;
        }
        self.resize_card(content_h);
        self.rebuild_footer();
    }

    fn row_widget(&self, row: &Row) -> gtk::Widget {
        let line = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        line.add_css_class("spot-row");
        line.set_size_request(-1, 44);

        if let Some(name) = &row.icon {
            let image = gtk::Image::from_icon_name(name);
            image.set_pixel_size(28);
            image.set_margin_start(10);
            image.set_valign(gtk::Align::Center);
            line.append(&image);
        } else {
            let badge = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            badge.add_css_class("glyph-badge");
            if self.confirm_key == row.key && row.confirm {
                badge.add_css_class("asking");
            }
            badge.set_size_request(28, 28);
            badge.set_margin_start(10);
            badge.set_valign(gtk::Align::Center);
            let glyph = ui::glyph(row.glyph.as_deref().unwrap_or(""), 14);
            glyph.set_halign(gtk::Align::Center);
            glyph.set_valign(gtk::Align::Center);
            badge.append(&glyph);
            line.append(&badge);
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
        let height = 52
            + 1
            + (if self.rows.is_empty() {
                0
            } else {
                content_h + 12
            })
            + 1
            + 34;
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
            self.window.set_default_size(self.width + 40, height);
        }
    }

    fn start_open(&mut self) {
        if !self.morph {
            return;
        }
        self.closing = false;
        self.grown = false;
        self.search.set_visible(false);
        self.list.set_visible(false);
        self.footer.set_visible(false);
        self.focus_ready = false;
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
            let t = (start.elapsed().as_millis() as f64 / 420.0).clamp(0.0, 1.0);
            let eased = ease_out_back(t, 0.7);
            let width = state.cap_w as f64 + (state.width - state.cap_w) as f64 * eased;
            let height = state.cap_h as f64 + (state.final_h - state.cap_h) as f64 * eased;
            let width = (width.round() as i32).max(1);
            let height = (height.round() as i32).max(1);
            state.card.set_size_request(width, height);
            state.current_w = width;
            state.current_h = height;
            let reveal = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
            if reveal > 0.0 && !state.focus_ready {
                state.search.set_visible(true);
                state.footer.set_visible(true);
                state.entry.grab_focus();
                state.focus_ready = true;
            }
            state.search.set_opacity(reveal);
            state.footer.set_opacity(reveal);
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
        if !self.morph || !self.grown || self.closing {
            self.window.close();
            return;
        }
        self.closing = true;
        self.search.set_visible(false);
        self.list.set_visible(false);
        self.footer.set_visible(false);
        self.search.set_opacity(0.0);
        self.list.set_opacity(0.0);
        self.footer.set_opacity(0.0);
        let weak = self.weak.clone();
        let start = Instant::now();
        let from_w = self.current_w;
        let from_h = self.current_h;
        glib::timeout_add_local(Duration::from_millis(16), move || {
            let Some(spot) = weak.upgrade() else {
                return glib::ControlFlow::Break;
            };
            let state = spot.borrow_mut();
            let t = (start.elapsed().as_millis() as f64 / 320.0).clamp(0.0, 1.0);
            let eased = 1.0 - ease_in_out_cubic(t);
            let width = state.cap_w as f64 + (from_w - state.cap_w) as f64 * eased;
            let height = state.cap_h as f64 + (from_h - state.cap_h) as f64 * eased;
            state.card.set_size_request(
                (width.round() as i32).max(1),
                (height.round() as i32).max(1),
            );
            if t >= 1.0 {
                state.window.close();
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
        let status = if self.query.is_empty() {
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
        if self.query.is_empty() {
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
            serde_json::Value::Array(items) => {
                items.iter().filter_map(|value| value.as_str()).any(|pin| {
                    pin == id || pin == id.trim_end_matches(".desktop") || id.starts_with(pin)
                })
            }
            _ => false,
        }
    }

    fn move_selection(&mut self, delta: i64) {
        if self.row_widgets.is_empty() {
            return;
        }
        let len = self.row_widgets.len() as i64;
        let next = (self.selected as i64 + delta).rem_euclid(len) as usize;
        self.selected = next;
        self.list.select_row(Some(&self.row_widgets[next]));
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
    if let Act::Fill(text) = &act {
        let entry = spot.borrow().entry.clone();
        entry.set_text(text);
        entry.set_position(-1);
        return;
    }
    if matches!(act, Act::None) {
        return;
    }
    if !key.is_empty() && !matches!(act, Act::File(_)) {
        spot.borrow_mut().history.record(&key);
    }
    match act {
        Act::App(index) => {
            if let Some(app) = spot.borrow().apps.apps.get(index).cloned() {
                apps::launch(&app);
            }
        }
        Act::File(path) => system::open_path(&path),
        Act::Power(action) => system::power(action),
        Act::Command(command) => system::run_command(&command),
        Act::Copy(text) => system::copy_text(&text),
        Act::Url(url) => system::open_url(&url),
        Act::Settings(page) => system::open_settings(page.as_deref()),
        Act::Qml(page) => system::open_qml_settings(page.as_deref()),
        Act::Skin(id) => {
            let mut state = spot.borrow_mut();
            let _ = state.cfg.set("shellLayout", serde_json::json!("menubar"));
            let _ = state.cfg.set("barSkin", serde_json::json!(id));
            drop(state);
            system::apply_settings();
        }
        Act::Fill(_) | Act::None => {}
    }
    spot.borrow_mut().close();
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
    let mut state = spot.borrow_mut();
    let mut items: Vec<String> = match state.cfg.get("dockPinned") {
        serde_json::Value::Array(values) => values
            .into_iter()
            .filter_map(|value| value.as_str().map(str::to_string))
            .collect(),
        _ => Vec::new(),
    };
    let before = items.len();
    items.retain(|pin| !pin_matches(pin, &id));
    if items.len() == before {
        items.push(id);
    }
    if state
        .cfg
        .set("dockPinned", serde_json::json!(items))
        .is_ok()
    {
        state.rebuild();
    }
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

fn placement(cfg: &Config, screen_height: i32) -> (bool, i32) {
    let layout = cfg.string("shellLayout", "menubar");
    let skin = cfg.string("barSkin", "classic");
    let capsule = layout == "menubar" && (skin == "island" || skin == "notch");
    let bottom_layout = layout != "menubar";
    let style = cfg.string("spotlightStyle", "auto");
    let bottom = match style.as_str() {
        "floating" => false,
        "attached" => bottom_layout,
        "capsule" => {
            if capsule {
                false
            } else {
                bottom_layout
            }
        }
        _ => {
            if capsule && cfg.bool("spotlightFromCapsule", true) {
                false
            } else {
                bottom_layout
            }
        }
    };
    let bar = cfg.i64("barHeight", 30) + if skin == "pills" { 6 } else { 0 };
    let taskbar = cfg.i64("taskbarHeight", 54) + 8;
    let floating = style == "floating";
    let margin = if bottom {
        (taskbar + 8) as i32
    } else if floating {
        (screen_height * 20 / 100) + 8
    } else {
        (bar + 8) as i32
    };
    (bottom, margin)
}

fn system_actions() -> Vec<Row> {
    vec![
        Row::new(
            "sys:lock",
            "Lock",
            "Lock the screen",
            "",
            Act::Power("lock"),
        ),
        Row::new(
            "sys:sleep",
            "Sleep",
            "Suspend to RAM",
            "󰒲",
            Act::Power("suspend"),
        ),
        Row::new(
            "sys:logout",
            "Log Out",
            "End the session",
            "󰍃",
            Act::Power("logout"),
        ),
        Row::new(
            "sys:reboot",
            "Restart",
            "Reboot the computer",
            "",
            Act::Power("reboot"),
        ),
        Row::new(
            "sys:off",
            "Shut Down",
            "Power off the computer",
            "⏻",
            Act::Power("poweroff"),
        ),
        Row::new(
            "sys:settings",
            "System Settings",
            "Island settings",
            "",
            Act::Settings(None),
        ),
        Row::new(
            "sys:spotlight",
            "Spotlight Settings",
            "Window, results and search sources",
            "\u{f002}",
            Act::Settings(Some("spotlight".into())),
        ),
        Row::new(
            "sys:qml-settings",
            "Island Hardware Settings",
            "Wi-Fi, Bluetooth, sound, displays and drives",
            "",
            Act::Qml(None),
        ),
    ]
}

fn app_row(index: usize, app: &AppEntry) -> Row {
    let mut row = Row::new(
        &format!("app:{}", app.id),
        &app.name,
        &app.description,
        "",
        Act::App(index),
    );
    row.icon = app.icon.clone();
    row
}

fn file_row(path: &std::path::Path) -> Row {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string_lossy().to_string());
    let home = paths::home();
    let display = path
        .strip_prefix(&home)
        .map(|relative| format!("~/{}", relative.to_string_lossy()))
        .unwrap_or_else(|_| path.to_string_lossy().to_string());
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

fn skin_query(query: &str) -> bool {
    let words = [
        "skin", "skins", "bar", "bars", "menu bar", "bar skin", "notch", "island", "pills",
    ];
    words
        .iter()
        .any(|word| word.starts_with(query) || query.starts_with(&format!("{word} ")))
}

fn math_result(query: &str) -> Option<String> {
    let raw = query.trim().trim_start_matches('=');
    if raw.is_empty() || !raw.chars().any(|c| c.is_ascii_digit()) {
        return None;
    }
    let mut expression = raw.replace(',', ".");
    if let Some(pos) = expression.find("% of ") {
        let percent = expression[..pos].trim().to_string();
        let value = expression[pos + 5..].trim().to_string();
        expression = format!("({percent}/100)*{value}");
    }
    if !query.starts_with('=') && !expression.chars().any(|c| "+-*/%^()".contains(c)) {
        return None;
    }
    let value = meval::eval_str(&expression).ok()?;
    if !value.is_finite() {
        return None;
    }
    let rounded = (value * 1e10).round() / 1e10;
    Some(format!("{rounded}"))
}

fn search_files(query: &str) -> Vec<PathBuf> {
    let needle = query.to_lowercase();
    let home = paths::home();
    let mut out = Vec::new();
    for entry in walkdir::WalkDir::new(&home)
        .max_depth(4)
        .into_iter()
        .filter_entry(|entry| {
            entry
                .file_name()
                .to_str()
                .map(|name| name == "." || !name.starts_with('.'))
                .unwrap_or(true)
        })
        .flatten()
    {
        if entry.path() == home {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_lowercase();
        if name.contains(&needle) {
            out.push(entry.path().to_path_buf());
            if out.len() >= 6 {
                break;
            }
        }
    }
    out
}

fn ease_out_back(t: f64, overshoot: f64) -> f64 {
    let c3 = overshoot + 1.0;
    let u = t - 1.0;
    1.0 + c3 * u * u * u + overshoot * u * u
}

fn ease_in_out_cubic(t: f64) -> f64 {
    if t < 0.5 {
        4.0 * t * t * t
    } else {
        let u = -2.0 * t + 2.0;
        1.0 - u * u * u / 2.0
    }
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
    let mut out = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{byte:02X}")),
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
            let spot = Spotlight::new(app, monitor.clone());
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
    let mut page = None;
    let mut open = false;
    let mut close = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--shell-dir" => shell_dir = args.next(),
            "--monitor" => monitor = args.next(),
            "--page" => page = args.next(),
            "--open" => open = true,
            "--close" => close = true,
            _ => {}
        }
    }
    let command = if close {
        "close".to_string()
    } else if let Some(page) = page {
        format!("page:{page}")
    } else if open {
        "show".to_string()
    } else {
        "toggle".to_string()
    };
    (shell_dir, monitor, command)
}
