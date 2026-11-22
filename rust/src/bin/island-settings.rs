#![allow(
    clippy::cast_possible_truncation,
    clippy::too_many_arguments,
    clippy::too_many_lines
)]
use gtk::gdk;
use gtk::glib;
use gtk::prelude::*;
use island_rust::config::Config;
use island_rust::history::History;
use island_rust::paths;
use island_rust::singleton::Instance;
use island_rust::system;
use island_rust::theme::Theme;
use island_rust::ui;
use serde_json::{json, Value};
use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::{Rc, Weak};
use std::time::Duration;

#[derive(Clone, Copy)]
enum Btn {
    ClearHistory,
    HardwareSettings,
    QmlSettings,
    ThemePicker,
    WallpaperPicker,
}

#[derive(Clone, Copy)]
enum Spec {
    Toggle {
        key: &'static str,
        label: &'static str,
        sub: &'static str,
    },
    Slider {
        key: &'static str,
        label: &'static str,
        sub: &'static str,
        min: f64,
        max: f64,
        step: f64,
        decimals: usize,
        suffix: &'static str,
    },
    Choice {
        key: &'static str,
        label: &'static str,
        sub: &'static str,
        options: &'static [(&'static str, &'static str)],
        numeric: bool,
    },
    Text {
        key: &'static str,
        label: &'static str,
        sub: &'static str,
        placeholder: &'static str,
    },
    Themes,
    Accents,
    Button {
        label: &'static str,
        sub: &'static str,
        text: &'static str,
        action: Btn,
    },
}

struct Group {
    title: &'static str,
    footer: &'static str,
    rows: Vec<Spec>,
}

struct Page {
    id: &'static str,
    title: &'static str,
    glyph: &'static str,
    tint: &'static str,
    section: &'static str,
    about: &'static str,
    keywords: &'static str,
    groups: Vec<Group>,
}

struct Settings {
    cfg: Config,
    window: gtk::ApplicationWindow,
    search: gtk::Entry,
    title: gtk::Label,
    sidebar: gtk::Box,
    content: gtk::Box,
    pages: Vec<Page>,
    page: String,
    query: String,
    apply_gen: u64,
    weak: Weak<RefCell<Settings>>,
}

const ACCENTS: &[(&str, &str)] = &[
    ("", "Multicolour"),
    ("#0a84ff", "Blue"),
    ("#bf5af2", "Purple"),
    ("#ff375f", "Pink"),
    ("#ff453a", "Red"),
    ("#ff9f0a", "Orange"),
    ("#ffd60a", "Yellow"),
    ("#30d158", "Green"),
    ("#8e8e93", "Graphite"),
];

fn toggle(key: &'static str, label: &'static str, sub: &'static str) -> Spec {
    Spec::Toggle { key, label, sub }
}

fn slider(
    key: &'static str,
    label: &'static str,
    sub: &'static str,
    min: f64,
    max: f64,
    step: f64,
    decimals: usize,
    suffix: &'static str,
) -> Spec {
    Spec::Slider {
        key,
        label,
        sub,
        min,
        max,
        step,
        decimals,
        suffix,
    }
}

fn choice(
    key: &'static str,
    label: &'static str,
    sub: &'static str,
    options: &'static [(&'static str, &'static str)],
) -> Spec {
    Spec::Choice {
        key,
        label,
        sub,
        options,
        numeric: false,
    }
}

fn number_choice(
    key: &'static str,
    label: &'static str,
    sub: &'static str,
    options: &'static [(&'static str, &'static str)],
) -> Spec {
    Spec::Choice {
        key,
        label,
        sub,
        options,
        numeric: true,
    }
}

fn text(
    key: &'static str,
    label: &'static str,
    sub: &'static str,
    placeholder: &'static str,
) -> Spec {
    Spec::Text {
        key,
        label,
        sub,
        placeholder,
    }
}

fn button(label: &'static str, sub: &'static str, text: &'static str, action: Btn) -> Spec {
    Spec::Button {
        label,
        sub,
        text,
        action,
    }
}

fn pages() -> Vec<Page> {
    vec![
        Page {
            id: "appearance", title: "Appearance", glyph: "\u{f042}", tint: "#3a3a3c", section: "Personal",
            about: "Theme, colour and the shape of the shell.",
            keywords: "theme dark light accent text colour font layout skin liquid glass",
            groups: vec![
                Group { title: "Theme", footer: "Themes are read from the Island themes folder. Applying one recolours the whole desktop.", rows: vec![
                    Spec::Themes,
                    Spec::Accents,
                    choice("textColor", "Text colour", "Menu bar, menus, Dock, widgets and Settings", &[("auto", "Auto"), ("white", "White"), ("black", "Black")]),
                    text("widgetFont", "Interface font", "Menu bar, menus, Dock, Spotlight and Settings", "Adwaita Sans"),
                    choice("widgetFontWeight", "Weight", "Bold text stays at least this heavy", &[("300", "Light"), ("400", "Regular"), ("500", "Medium"), ("600", "Semibold"), ("700", "Bold")]),
                ]},
                Group { title: "Layout", footer: "The bottom bar replaces the menu bar and Dock; the compact bar is a content-sized pill.", rows: vec![
                    choice("shellLayout", "Layout", "", &[("menubar", "Menu bar + Dock"), ("taskbar", "Bottom bar"), ("compact", "Compact bar")]),
                    choice("barSkin", "Menu bar skin", "Island and Notch grow menus from the capsule", &[("classic", "Classic"), ("pills", "Pills"), ("island", "Dynamic Island"), ("notch", "Notch")]),
                    toggle("liquidGlass", "Liquid glass", "Clearer panels with a glass rim and sheen"),
                    choice("iconStyle", "Icon style", "Dock, Launchpad and Spotlight", &[("default", "Default"), ("clear", "Clear"), ("tinted", "Tinted")]),
                    slider("cursorSize", "Pointer size", "", 16.0, 64.0, 2.0, 0, " px"),
                ]},
            ],
        },
        Page {
            id: "spotlight", title: "Spotlight", glyph: "\u{f002}", tint: "#0a84ff", section: "Personal",
            about: "Search apps, files and actions, do maths, run a command, or search the web.",
            keywords: "spotlight search launcher apps files commands shell web duckduckgo history recent pin width results style",
            groups: vec![
                Group { title: "Window", footer: "Auto follows the bar: capsule bars grow from the capsule, menu bars drop down, bottom bars rise above them.", rows: vec![
                    choice("spotlightStyle", "Open as", "Auto fits the current bar", &[("auto", "Auto"), ("attached", "Attached"), ("floating", "Floating"), ("capsule", "Capsule")]),
                    toggle("spotlightFromCapsule", "Grow from the capsule", "Dynamic Island and Notch only, with Auto"),
                    slider("spotlightWidth", "Width", "", 520.0, 900.0, 20.0, 0, " px"),
                    slider("spotlightRows", "Visible results", "", 5.0, 12.0, 1.0, 0, ""),
                ]},
                Group { title: "Search", footer: "Files need three letters and stop after a second.", rows: vec![
                    toggle("spotlightFiles", "Search files in your home folder", "Names, four levels deep"),
                    toggle("spotlightCommands", "Run shell commands", "Type > or $ first"),
                    toggle("spotlightWeb", "Search the web", "DuckDuckGo, for anything that doesn't match"),
                ]},
                Group { title: "History", footer: "Stored in ~/.local/state/island/spotlight.json.", rows: vec![
                    button("History", "Recent and frequent items, launch counts and pinned rows", "Clear", Btn::ClearHistory),
                ]},
            ],
        },
        Page {
            id: "bar", title: "Menu Bar", glyph: "\u{f00b}", tint: "#8e8e93", section: "Shell",
            about: "Status items, workspaces and the clock across the top of the screen.",
            keywords: "menu bar height opacity blur font size workspaces clock time seconds weather",
            groups: vec![
                Group { title: "Menu Bar", footer: "", rows: vec![
                    slider("barHeight", "Height", "", 22.0, 44.0, 1.0, 0, " px"),
                    slider("barOpacity", "Background opacity", "", 0.0, 1.0, 0.01, 2, ""),
                    toggle("barBlur", "Blur behind the menu bar", ""),
                    slider("barFontSize", "Text size", "", 10.0, 18.0, 1.0, 0, " px"),
                    toggle("barWeather", "Weather", "Temperature next to the clock"),
                ]},
                Group { title: "Workspaces", footer: "", rows: vec![
                    toggle("barWorkspaces", "Show workspaces", "In the menu bar, bottom bar and compact bar"),
                    choice("barWorkspaceStyle", "Style", "", &[("numbers", "Numbers"), ("dots", "Dots"), ("pill", "Pill"), ("glide", "Glide"), ("line", "Line"), ("activity", "Activity"), ("kanji", "Kanji"), ("roman", "Roman")]),
                    slider("barWorkspaceCount", "Always show", "", 1.0, 10.0, 1.0, 0, ""),
                ]},
                Group { title: "Clock", footer: "", rows: vec![
                    choice("clockDate", "Date", "", &[("full", "Sat Nov 21"), ("weekday", "Sat"), ("none", "Time only")]),
                    toggle("clock24h", "Use a 24-hour clock", ""),
                    toggle("clockSeconds", "Display the time with seconds", ""),
                ]},
            ],
        },
        Page {
            id: "dock", title: "Dock", glyph: "\u{f009}", tint: "#1c1c1e", section: "Shell",
            about: "Your apps along the bottom of the screen.",
            keywords: "dock size magnification autohide minimise opacity margin pinned",
            groups: vec![
                Group { title: "", footer: "", rows: vec![toggle("dock", "Show the Dock", "")]},
                Group { title: "Size", footer: "", rows: vec![
                    slider("dockSize", "Size", "", 32.0, 96.0, 1.0, 0, " px"),
                    toggle("dockMagnify", "Magnification", "Icons grow under the pointer"),
                    slider("dockMagnifySize", "Magnified size", "", 1.1, 2.5, 0.05, 2, "×"),
                ]},
                Group { title: "Behaviour", footer: "", rows: vec![
                    toggle("dockAutohide", "Hide and show automatically", ""),
                    toggle("dockAllScreens", "Show on every display", ""),
                    slider("dockOpacity", "Background opacity", "", 0.0, 1.0, 0.01, 2, ""),
                    slider("dockMargin", "Distance from the edge", "", 0.0, 30.0, 1.0, 0, " px"),
                ]},
            ],
        },
        Page {
            id: "desktop", title: "Desktop & Widgets", glyph: "\u{f108}", tint: "#30d158", section: "Shell",
            about: "Widgets sit on the desktop under your windows. The lock screen and its wording live here too.",
            keywords: "widgets clock weather calendar music system verse lock screen password opacity colours position",
            groups: vec![
                Group { title: "Widgets", footer: "", rows: vec![
                    toggle("widgets", "Show widgets", ""),
                    choice("widgetStyle", "Style", "", &[("tahoe", "Tahoe"), ("classic", "Classic")]),
                    choice("widgetColors", "Colours", "Wallpaper picks accents from your wallpaper", &[("system", "System"), ("theme", "Theme"), ("wallpaper", "Wallpaper")]),
                    slider("widgetsOpacity", "Opacity", "", 0.0, 1.0, 0.01, 2, ""),
                    toggle("widgetClock", "Clock", ""),
                    toggle("widgetClockSeconds", "Clock second hand", ""),
                    toggle("widgetWeather", "Weather", ""),
                    toggle("widgetCalendar", "Calendar", ""),
                    toggle("widgetMusic", "Now Playing", ""),
                    toggle("widgetSystem", "System", "CPU, memory, temperature and disk"),
                    toggle("widgetVerse", "Verse of the Day", "ESV, from Bible Gateway"),
                ]},
                Group { title: "Arrangement", footer: "", rows: vec![
                    choice("widgetsPosition", "Corner", "Widgets you haven't moved stack here", &[("top-left", "Top Left"), ("top-right", "Top Right"), ("bottom-left", "Bottom Left"), ("bottom-right", "Bottom Right")]),
                    slider("widgetsMargin", "Distance from the edge", "", 0.0, 120.0, 1.0, 0, " px"),
                    toggle("widgetsAllScreens", "Show on every display", ""),
                ]},
                Group { title: "Lock Screen", footer: "", rows: vec![
                    choice("lockScreen", "Locker", "", &[("island", "Island"), ("hyprlock", "hyprlock")]),
                    toggle("lockTypingFx", "Typing animation", "Dots pop, the field glows and the screen fades while you type"),
                    choice("lockPasswordMask", "Password style", "", &[("circles", "Circles"), ("last", "Last letter"), ("letters", "Letters")]),
                    toggle("lockOnStart", "Lock when the session starts", "Pair with SDDM autologin"),
                    toggle("lockVerse", "Verse on the lock screen", ""),
                ]},
            ],
        },
        Page {
            id: "windows", title: "Windows", glyph: "\u{f2d0}", tint: "#30b0c7", section: "Shell",
            about: "Tiling, gaps, corners and the blur behind translucent windows.",
            keywords: "windows gaps borders rounding radius layout blur opacity dim inactive",
            groups: vec![
                Group { title: "Tiling", footer: "", rows: vec![
                    choice("layout", "Tiling layout", "", &[("dwindle", "Dwindle"), ("tile", "Master (left)"), ("right_tile", "Master (right)"), ("center_tile", "Master (centre)"), ("scroller", "Scrolling"), ("grid", "Grid"), ("deck", "Deck"), ("monocle", "Monocle")]),
                    slider("gapsIn", "Space between windows", "", 0.0, 30.0, 1.0, 0, " px"),
                    slider("gapsOut", "Space around the screen edge", "", 0.0, 40.0, 1.0, 0, " px"),
                ]},
                Group { title: "Look", footer: "", rows: vec![
                    slider("borderSize", "Border width", "", 0.0, 8.0, 1.0, 0, " px"),
                    slider("rounding", "Corner radius", "", 0.0, 24.0, 1.0, 0, " px"),
                    slider("activeOpacity", "Focused window opacity", "", 0.5, 1.0, 0.01, 2, ""),
                    slider("inactiveOpacity", "Other windows' opacity", "", 0.5, 1.0, 0.01, 2, ""),
                    toggle("dimInactive", "Dim windows in the background", ""),
                ]},
                Group { title: "Blur", footer: "Shows through translucent windows, the menu bar, Dock and Spotlight.", rows: vec![
                    toggle("blur", "Blur", ""),
                    slider("blurSize", "Strength", "", 1.0, 12.0, 1.0, 0, ""),
                    slider("blurPasses", "Passes", "", 1.0, 4.0, 1.0, 0, ""),
                ]},
            ],
        },
        Page {
            id: "animations", title: "Animations", glyph: "\u{f021}", tint: "#ff9f0a", section: "Shell",
            about: "How windows and workspaces move, and how quickly.",
            keywords: "animations motion speed curve windows workspaces popin slide genie",
            groups: vec![
                Group { title: "", footer: "", rows: vec![
                    toggle("animations", "Animate windows and workspaces", ""),
                    choice("animCurve", "Feel", "How motion eases in and out", &[("smooth", "Smooth"), ("spring", "Springy"), ("classic", "Classic")]),
                    slider("animSpeed", "Speed", "Higher is slower", 0.5, 10.0, 0.5, 1, ""),
                ]},
                Group { title: "Style", footer: "", rows: vec![
                    choice("windowAnim", "Windows", "", &[("popin", "Pop In"), ("slide", "Slide"), ("gnomed", "Genie")]),
                    choice("workspaceAnim", "Workspaces", "", &[("slide", "Slide"), ("slidevert", "Vertical"), ("fade", "Fade"), ("slidefade", "Slide & Fade")]),
                ]},
            ],
        },
        Page {
            id: "input", title: "Keyboard & Mouse", glyph: "\u{f11c}", tint: "#8e8e93", section: "System",
            about: "Key repeat, pointer speed, scrolling and focus.",
            keywords: "keyboard mouse pointer repeat delay speed acceleration scroll natural focus numlock",
            groups: vec![
                Group { title: "Keyboard", footer: "", rows: vec![
                    slider("repeatRate", "Key repeat rate", "", 10.0, 80.0, 1.0, 0, "/s"),
                    slider("repeatDelay", "Delay until repeat", "", 150.0, 1000.0, 25.0, 0, " ms"),
                    toggle("numlock", "Turn on Num Lock at login", ""),
                ]},
                Group { title: "Mouse", footer: "", rows: vec![
                    slider("sensitivity", "Tracking speed", "", -1.0, 1.0, 0.05, 2, ""),
                    toggle("naturalScroll", "Natural scrolling", "Content tracks finger movement"),
                    choice("accelProfile", "Pointer acceleration", "", &[("flat", "Off"), ("adaptive", "On")]),
                    number_choice("followMouse", "Focus follows pointer", "", &[("0", "Off"), ("1", "Always"), ("2", "Loosely")]),
                ]},
            ],
        },
        Page {
            id: "terminal", title: "Terminal", glyph: "\u{f120}", tint: "#1c1c1e", section: "System",
            about: "Settings for foot. They apply to new terminal windows.",
            keywords: "terminal foot font size opacity padding",
            groups: vec![Group { title: "", footer: "", rows: vec![
                text("termFont", "Font", "", "PPRightSerifMono Nerd Font Mono"),
                slider("termFontSize", "Font size", "", 8.0, 24.0, 1.0, 0, " pt"),
                slider("termOpacity", "Background opacity", "", 0.3, 1.0, 0.01, 2, ""),
                slider("termPadding", "Padding", "", 0.0, 40.0, 1.0, 0, " px"),
            ]}],
        },
        Page {
            id: "advanced", title: "Advanced", glyph: "\u{f0ad}", tint: "#636366", section: "System",
            about: "Hardware panes and the old Island Settings window are still available while they are ported.",
            keywords: "advanced wifi bluetooth network sound displays drives hardware qml theme wallpaper",
            groups: vec![
                Group { title: "Island", footer: "Wi-Fi, Bluetooth, network, sound, displays, drives and default apps are managed by Island's QML Settings.", rows: vec![
                    button("Hardware settings", "Wi-Fi, Bluetooth, sound, displays and drives", "Open…", Btn::HardwareSettings),
                    button("All Island settings", "The original QML Settings window", "Open…", Btn::QmlSettings),
                ]},
                Group { title: "Pickers", footer: "", rows: vec![
                    button("Theme picker", "Browse every palette", "Choose…", Btn::ThemePicker),
                    button("Wallpaper picker", "Pictures, videos and Wallhaven", "Choose…", Btn::WallpaperPicker),
                ]},
            ],
        },
    ]
}

impl Settings {
    fn new(app: &gtk::Application, initial_page: String) -> Rc<RefCell<Self>> {
        let cfg = Config::load();
        let theme = Theme::load(&cfg);
        ui::install_css(&theme);
        let pages = pages();
        let page = if pages.iter().any(|page| page.id == initial_page) {
            initial_page
        } else {
            "appearance".to_string()
        };

        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("Island Settings")
            .build();
        window.set_decorated(false);
        window.set_default_size(920, 700);
        window.set_resizable(true);

        let shell = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        shell.add_css_class("settings-shell");
        shell.set_size_request(920, 700);

        let sidebar_holder = gtk::Box::new(gtk::Orientation::Vertical, 0);
        sidebar_holder.add_css_class("sidebar");
        sidebar_holder.set_size_request(238, -1);

        let header = gtk::WindowHandle::new();
        let header_row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        header_row.set_margin_top(12);
        header_row.set_margin_bottom(8);
        header_row.set_margin_start(14);
        header_row.set_margin_end(14);
        let close = gtk::Button::with_label("×");
        close.add_css_class("traffic-close");
        close.set_tooltip_text(Some("Close"));
        close.connect_clicked({
            let window = window.clone();
            move |_| window.close()
        });
        header_row.append(&close);
        let header_title = ui::label("Settings", "title");
        header_title.set_margin_start(4);
        header_row.append(&header_title);
        header.set_child(Some(&header_row));
        sidebar_holder.append(&header);

        let search = gtk::Entry::new();
        search.set_placeholder_text(Some("Search"));
        search.add_css_class("search");
        search.set_margin_start(12);
        search.set_margin_end(12);
        search.set_margin_bottom(10);
        sidebar_holder.append(&search);

        let sidebar = gtk::Box::new(gtk::Orientation::Vertical, 1);
        sidebar.set_margin_start(8);
        sidebar.set_margin_end(8);
        sidebar.set_margin_bottom(10);
        let sidebar_scroll = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::Automatic)
            .vexpand(true)
            .build();
        sidebar_scroll.set_child(Some(&sidebar));
        sidebar_holder.append(&sidebar_scroll);
        shell.append(&sidebar_holder);

        let content_holder = gtk::Box::new(gtk::Orientation::Vertical, 0);
        content_holder.add_css_class("content");
        content_holder.set_hexpand(true);
        let toolbar = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        toolbar.add_css_class("toolbar");
        toolbar.set_size_request(-1, 54);
        let title = ui::label("Appearance", "title");
        title.set_margin_start(24);
        title.set_valign(gtk::Align::Center);
        toolbar.append(&title);
        content_holder.append(&toolbar);

        let content = gtk::Box::new(gtk::Orientation::Vertical, 18);
        content.set_margin_top(26);
        content.set_margin_bottom(32);
        content.set_margin_start(30);
        content.set_margin_end(30);
        let scroller = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::Automatic)
            .vexpand(true)
            .build();
        scroller.set_child(Some(&content));
        content_holder.append(&scroller);
        shell.append(&content_holder);

        window.set_child(Some(&shell));

        let spot: Rc<RefCell<Settings>> = Rc::new_cyclic(|weak: &Weak<RefCell<Settings>>| {
            let state = RefCell::new(Self {
                cfg,
                window: window.clone(),
                search: search.clone(),
                title: title.clone(),
                sidebar,
                content,
                pages,
                page,
                query: String::new(),
                apply_gen: 0,
                weak: weak.clone(),
            });
            search.connect_changed({
                let weak = weak.clone();
                move |entry| {
                    if let Some(spot) = weak.upgrade() {
                        spot.borrow_mut().query = entry.text().trim().to_lowercase();
                        spot.borrow_mut().rebuild_sidebar();
                        spot.borrow_mut().rebuild_content();
                    }
                }
            });
            let key = gtk::EventControllerKey::new();
            key.connect_key_pressed({
                let weak = weak.clone();
                move |_, keyval, _, modifiers| {
                    if keyval == gdk::Key::Escape {
                        if let Some(spot) = weak.upgrade() {
                            spot.borrow().window.close();
                        }
                        return glib::Propagation::Stop;
                    }
                    if modifiers.contains(gdk::ModifierType::CONTROL_MASK)
                        && keyval
                            .to_unicode()
                            .is_some_and(|c| c.eq_ignore_ascii_case(&'f'))
                    {
                        if let Some(spot) = weak.upgrade() {
                            spot.borrow().search.grab_focus();
                        }
                        return glib::Propagation::Stop;
                    }
                    glib::Propagation::Proceed
                }
            });
            window.add_controller(key);
            state
        });

        spot.borrow_mut().rebuild_sidebar();
        spot.borrow_mut().rebuild_content();
        window.present();
        search.grab_focus();
        spot
    }

    fn rebuild_sidebar(&mut self) {
        while let Some(child) = self.sidebar.first_child() {
            self.sidebar.remove(&child);
        }
        let mut section = "";
        for page in &self.pages {
            if !self.query.is_empty() && !page_matches(page, &self.query) {
                continue;
            }
            if self.query.is_empty() && page.section != section {
                section = page.section;
                let caption = ui::label(section, "section");
                caption.set_margin_start(11);
                caption.set_margin_top(12);
                caption.set_margin_bottom(2);
                self.sidebar.append(&caption);
            }
            let button = gtk::Button::new();
            button.add_css_class("sidebar-row");
            button.set_has_frame(false);
            if page.id == self.page {
                button.add_css_class("active");
            }
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
            let glyph = colored_glyph(page.glyph, page.tint, 14);
            let label = ui::label(page.title, "row-title");
            row.append(&glyph);
            row.append(&label);
            button.set_child(Some(&row));
            let weak = self.weak.clone();
            let id = page.id.to_string();
            button.connect_clicked(move |_| {
                if let Some(spot) = weak.upgrade() {
                    {
                        let mut state = spot.borrow_mut();
                        state.page.clone_from(&id);
                    }
                    let search = spot.borrow().search.clone();
                    if search.text().is_empty() {
                        spot.borrow_mut().rebuild_sidebar();
                        spot.borrow_mut().rebuild_content();
                    } else {
                        search.set_text("");
                    }
                }
            });
            self.sidebar.append(&button);
        }
    }

    fn rebuild_content(&mut self) {
        while let Some(child) = self.content.first_child() {
            self.content.remove(&child);
        }
        if !self.query.is_empty() {
            self.title.set_text("Search");
            self.build_search_results();
            return;
        }
        let Some(page) = self.pages.iter().find(|page| page.id == self.page) else {
            return;
        };
        self.title.set_text(page.title);
        let heading = ui::label(page.title, "pane-title");
        self.content.append(&heading);
        let about = ui::label(page.about, "muted");
        about.set_wrap(true);
        about.set_wrap_mode(gtk::pango::WrapMode::WordChar);
        about.set_max_width_chars(90);
        about.set_margin_top(-12);
        self.content.append(&about);

        for group in &page.groups {
            if !group.title.is_empty() {
                let caption = ui::label(group.title, "section");
                caption.set_margin_start(12);
                caption.set_margin_top(4);
                self.content.append(&caption);
            }
            let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
            card.add_css_class("group-card");
            for (index, spec) in group.rows.iter().enumerate() {
                let row = self.build_row(spec);
                card.append(&row);
                if index + 1 < group.rows.len() {
                    card.append(&ui::separator());
                }
            }
            self.content.append(&card);
            if !group.footer.is_empty() {
                let footer = ui::label(group.footer, "muted");
                footer.set_wrap(true);
                footer.set_wrap_mode(gtk::pango::WrapMode::WordChar);
                footer.set_margin_start(12);
                footer.set_margin_end(12);
                self.content.append(&footer);
            }
        }

        let keys = page_keys(page);
        if keys.iter().any(|key| !self.cfg.is_default(key)) {
            let restore = gtk::Button::with_label("Restore Defaults");
            restore.add_css_class("plain-button");
            restore.set_halign(gtk::Align::End);
            restore.set_margin_top(6);
            let weak = self.weak.clone();
            let keys: Vec<&'static str> = keys;
            restore.connect_clicked(move |_| {
                if let Some(spot) = weak.upgrade() {
                    {
                        let mut state = spot.borrow_mut();
                        let _ = state.cfg.reset(&keys);
                    }
                    schedule_apply(&spot);
                    schedule_rebuild(&spot);
                }
            });
            self.content.append(&restore);
        }
    }

    fn build_search_results(&mut self) {
        let mut results: Vec<(&Page, Option<&Spec>)> = Vec::new();
        for page in &self.pages {
            if !page_matches(page, &self.query) {
                continue;
            }
            let mut row_hit = false;
            for group in &page.groups {
                for spec in &group.rows {
                    if spec_matches(spec, &self.query) {
                        results.push((page, Some(spec)));
                        row_hit = true;
                    }
                }
            }
            if !row_hit {
                results.push((page, None));
            }
        }
        let heading = ui::label("Search results", "pane-title");
        self.content.append(&heading);
        let count = ui::label(
            &format!(
                "{} {}",
                results.len(),
                if results.len() == 1 {
                    "setting"
                } else {
                    "settings"
                }
            ),
            "muted",
        );
        count.set_margin_top(-12);
        self.content.append(&count);
        if results.is_empty() {
            let empty = gtk::Box::new(gtk::Orientation::Vertical, 4);
            empty.add_css_class("group-card");
            empty.set_margin_top(8);
            let title = ui::label("No matching settings", "row-title");
            title.set_margin_top(18);
            title.set_margin_start(18);
            let sub = ui::label(
                "Try a feature or a setting name, like Wi-Fi, Spotlight or theme.",
                "row-sub",
            );
            sub.set_margin_bottom(18);
            sub.set_margin_start(18);
            empty.append(&title);
            empty.append(&sub);
            self.content.append(&empty);
            return;
        }
        let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
        card.add_css_class("group-card");
        for (index, (page, spec)) in results.iter().enumerate() {
            let label = spec.map_or(page.title, spec_label);
            let sub = spec
                .map(|spec| spec_sub(spec).to_string())
                .filter(|sub| !sub.is_empty())
                .unwrap_or_else(|| format!("Open {}", page.title));
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
            row.add_css_class("setting-row");
            let glyph = colored_glyph(page.glyph, page.tint, 13);
            row.append(&glyph);
            let col = gtk::Box::new(gtk::Orientation::Vertical, 0);
            col.set_hexpand(true);
            col.append(&ui::label(label, "row-title"));
            let sub_label = ui::label(&sub, "row-sub");
            sub_label.set_ellipsize(gtk::pango::EllipsizeMode::End);
            col.append(&sub_label);
            row.append(&col);
            let chip = ui::label(page.title, "chip");
            chip.set_valign(gtk::Align::Center);
            row.append(&chip);
            let button = gtk::Button::new();
            button.set_has_frame(false);
            button.add_css_class("sidebar-row");
            button.set_child(Some(&row));
            let weak = self.weak.clone();
            let id = page.id.to_string();
            button.connect_clicked(move |_| {
                if let Some(spot) = weak.upgrade() {
                    {
                        let mut state = spot.borrow_mut();
                        state.page.clone_from(&id);
                    }
                    let search = spot.borrow().search.clone();
                    if search.text().is_empty() {
                        spot.borrow_mut().rebuild_sidebar();
                        spot.borrow_mut().rebuild_content();
                    } else {
                        search.set_text("");
                    }
                }
            });
            card.append(&button);
            if index + 1 < results.len() {
                card.append(&ui::separator());
            }
        }
        self.content.append(&card);
    }

    fn build_row(&self, spec: &Spec) -> gtk::Box {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 16);
        row.add_css_class("setting-row");
        let col = gtk::Box::new(gtk::Orientation::Vertical, 1);
        col.set_hexpand(true);
        col.set_valign(gtk::Align::Center);
        col.append(&ui::label(spec_label(spec), "row-title"));
        let sub = spec_sub(spec);
        if !sub.is_empty() {
            let label = ui::label(sub, "row-sub");
            label.set_wrap(true);
            label.set_wrap_mode(gtk::pango::WrapMode::WordChar);
            label.set_max_width_chars(60);
            col.append(&label);
        }
        row.append(&col);

        let weak = self.weak.clone();
        match spec {
            Spec::Toggle { key, .. } => {
                let switch = gtk::Switch::new();
                switch.set_active(self.cfg.bool(key, false));
                switch.set_valign(gtk::Align::Center);
                let key = *key;
                switch.connect_state_set(move |_, active| {
                    set_value(&weak, key, json!(active));
                    glib::Propagation::Proceed
                });
                row.append(&switch);
            }
            Spec::Slider {
                key,
                min,
                max,
                step,
                decimals,
                suffix,
                ..
            } => {
                let holder = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                holder.set_valign(gtk::Align::Center);
                let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, *min, *max, *step);
                scale.set_value(self.cfg.f64(key, *min));
                scale.set_draw_value(false);
                scale.set_size_request(190, -1);
                let value = ui::label(
                    &format_value(self.cfg.f64(key, *min), *decimals, suffix),
                    "row-sub",
                );
                value.set_size_request(56, -1);
                value.set_halign(gtk::Align::End);
                let key = *key;
                let step = *step;
                let decimals = *decimals;
                let suffix = *suffix;
                let value_label = value.clone();
                scale.connect_value_changed(move |scale| {
                    let raw = scale.value();
                    let snapped = if step > 0.0 {
                        (raw / step).round() * step
                    } else {
                        raw
                    };
                    value_label.set_text(&format_value(snapped, decimals, suffix));
                    let value = if decimals == 0 {
                        json!(snapped.round() as i64)
                    } else {
                        json!(snapped)
                    };
                    set_value(&weak, key, value);
                });
                holder.append(&scale);
                holder.append(&value);
                row.append(&holder);
            }
            Spec::Choice {
                key,
                options,
                numeric,
                ..
            } => {
                let labels: Vec<&str> = options.iter().map(|(_, label)| *label).collect();
                let dropdown = gtk::DropDown::from_strings(&labels);
                let current = if *numeric {
                    self.cfg.get(key).as_i64().map(|value| value.to_string())
                } else {
                    Some(
                        self.cfg
                            .string(key, options.first().map_or("", |(value, _)| *value)),
                    )
                };
                let index = options
                    .iter()
                    .position(|(value, _)| Some(*value) == current.as_deref())
                    .unwrap_or(0) as u32;
                dropdown.set_selected(index);
                dropdown.set_valign(gtk::Align::Center);
                let key = *key;
                let options = *options;
                let numeric = *numeric;
                dropdown.connect_selected_notify(move |dropdown| {
                    let Some((value, _)) = options.get(dropdown.selected() as usize) else {
                        return;
                    };
                    if numeric {
                        if let Ok(number) = value.parse::<i64>() {
                            set_value(&weak, key, json!(number));
                        }
                    } else {
                        set_value(&weak, key, json!(value));
                    }
                });
                row.append(&dropdown);
            }
            Spec::Text {
                key, placeholder, ..
            } => {
                let entry = gtk::Entry::new();
                entry.set_text(&self.cfg.string(key, ""));
                entry.set_placeholder_text(Some(placeholder));
                entry.set_width_chars(24);
                entry.set_valign(gtk::Align::Center);
                let key = *key;
                entry.connect_changed(move |entry| {
                    set_value(&weak, key, json!(entry.text().to_string()));
                });
                row.append(&entry);
            }
            Spec::Themes => {
                let (ids, labels) = theme_choices();
                let dropdown = gtk::DropDown::from_strings(
                    &labels.iter().map(String::as_str).collect::<Vec<_>>(),
                );
                let current = paths::theme_id();
                let index = ids.iter().position(|id| id == &current).unwrap_or(0) as u32;
                dropdown.set_selected(index);
                dropdown.set_valign(gtk::Align::Center);
                dropdown.connect_selected_notify(move |dropdown| {
                    let Some(id) = ids.get(dropdown.selected() as usize).cloned() else {
                        return;
                    };
                    apply_theme(&weak, &id);
                });
                row.append(&dropdown);
            }
            Spec::Accents => {
                let labels: Vec<&str> = ACCENTS.iter().map(|(_, label)| *label).collect();
                let dropdown = gtk::DropDown::from_strings(&labels);
                let current = self.cfg.string("accentColor", "");
                let index = ACCENTS
                    .iter()
                    .position(|(value, _)| *value == current)
                    .unwrap_or(0) as u32;
                dropdown.set_selected(index);
                dropdown.set_valign(gtk::Align::Center);
                dropdown.connect_selected_notify(move |dropdown| {
                    let Some((value, _)) = ACCENTS.get(dropdown.selected() as usize) else {
                        return;
                    };
                    set_value(&weak, "accentColor", json!(value));
                });
                row.append(&dropdown);
            }
            Spec::Button { text, action, .. } => {
                let button = gtk::Button::with_label(text);
                button.add_css_class("accent-button");
                button.set_valign(gtk::Align::Center);
                let action = *action;
                button.connect_clicked(move |_| button_action(&weak, action));
                row.append(&button);
            }
        }
        row
    }

    fn handle(&mut self, message: &str) {
        if message == "close" || message == "toggle" {
            self.window.close();
            return;
        }
        if message == "show" {
            self.window.present();
            return;
        }
        if let Some(page) = message
            .strip_prefix("show:")
            .or_else(|| message.strip_prefix("page:"))
        {
            if self.pages.iter().any(|item| item.id == page) {
                self.page = page.to_string();
                self.query.clear();
                self.rebuild_sidebar();
                self.rebuild_content();
            }
            self.window.present();
        }
    }
}

fn page_matches(page: &Page, query: &str) -> bool {
    page.title.to_lowercase().contains(query)
        || page.about.to_lowercase().contains(query)
        || page.keywords.to_lowercase().contains(query)
        || page
            .groups
            .iter()
            .any(|group| group.rows.iter().any(|spec| spec_matches(spec, query)))
}

fn spec_matches(spec: &Spec, query: &str) -> bool {
    format!("{} {} {}", spec_label(spec), spec_sub(spec), spec_key(spec))
        .to_lowercase()
        .contains(query)
}

fn spec_label(spec: &Spec) -> &'static str {
    match spec {
        Spec::Toggle { label, .. }
        | Spec::Slider { label, .. }
        | Spec::Choice { label, .. }
        | Spec::Text { label, .. }
        | Spec::Button { label, .. } => label,
        Spec::Themes => "Theme",
        Spec::Accents => "Accent colour",
    }
}

fn spec_sub(spec: &Spec) -> &'static str {
    match spec {
        Spec::Toggle { sub, .. }
        | Spec::Slider { sub, .. }
        | Spec::Choice { sub, .. }
        | Spec::Text { sub, .. }
        | Spec::Button { sub, .. } => sub,
        Spec::Themes => "The palette used across the desktop",
        Spec::Accents => "Selection, focus and progress",
    }
}

fn spec_key(spec: &Spec) -> &'static str {
    match spec {
        Spec::Toggle { key, .. }
        | Spec::Slider { key, .. }
        | Spec::Choice { key, .. }
        | Spec::Text { key, .. } => key,
        Spec::Themes => "theme",
        Spec::Accents => "accentColor",
        Spec::Button { .. } => "",
    }
}

fn page_keys(page: &Page) -> Vec<&'static str> {
    let mut out = Vec::new();
    for group in &page.groups {
        for spec in &group.rows {
            let key = match spec {
                Spec::Toggle { key, .. }
                | Spec::Slider { key, .. }
                | Spec::Choice { key, .. }
                | Spec::Text { key, .. } => *key,
                _ => "",
            };
            if !key.is_empty() && !out.contains(&key) {
                out.push(key);
            }
        }
    }
    out
}

fn format_value(value: f64, decimals: usize, suffix: &str) -> String {
    match decimals {
        0 => format!("{value:.0}{suffix}"),
        n => format!("{value:.n$}{suffix}"),
    }
}

fn colored_glyph(text: &str, color: &str, px: i32) -> gtk::Label {
    let label = gtk::Label::new(None);
    label.set_markup(&format!(
        "<span font_family=\"JetBrainsMono Nerd Font\" size=\"{}\" foreground=\"{}\">{}</span>",
        px * 1024,
        color,
        ui::glib_escape(text)
    ));
    label.set_valign(gtk::Align::Center);
    label.set_width_chars(2);
    label
}

fn theme_choices() -> (Vec<String>, Vec<String>) {
    let mut entries = Vec::new();
    if let Ok(dir) = std::fs::read_dir(paths::themes_dir()) {
        for entry in dir.flatten() {
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
                continue;
            }
            let Some(id) = path.file_stem().and_then(|stem| stem.to_str()) else {
                continue;
            };
            let name = std::fs::read_to_string(&path)
                .ok()
                .and_then(|text| serde_json::from_str::<Value>(&text).ok())
                .and_then(|value| {
                    value
                        .get("name")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
                .unwrap_or_else(|| id.to_string());
            entries.push((id.to_string(), name));
        }
    }
    entries.sort_by_key(|a| a.1.to_lowercase());
    entries.into_iter().unzip()
}

fn set_value(weak: &Weak<RefCell<Settings>>, key: &'static str, value: Value) {
    let Some(spot) = weak.upgrade() else {
        return;
    };
    {
        let mut state = spot.borrow_mut();
        if state.cfg.set(key, value).is_ok() {
            state.apply_gen = state.apply_gen.wrapping_add(1);
        }
    }
    schedule_apply(&spot);
    if matches!(key, "accentColor" | "textColor" | "liquidGlass") {
        schedule_rebuild(&spot);
    }
}

fn apply_theme(weak: &Weak<RefCell<Settings>>, id: &str) {
    let Some(spot) = weak.upgrade() else {
        return;
    };
    let state_file = paths::theme_state_file();
    if let Some(dir) = state_file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&state_file, format!("{id}\n"));
    let script = paths::shell_dir().join("apply-theme.sh");
    if script.is_file() {
        let _ = std::process::Command::new(script)
            .arg(id)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
    schedule_rebuild(&spot);
}

fn schedule_rebuild(spot: &Rc<RefCell<Settings>>) {
    let weak = Rc::downgrade(spot);
    glib::idle_add_local_once(move || {
        let Some(spot) = weak.upgrade() else {
            return;
        };
        let cfg = spot.borrow().cfg.clone();
        let theme = Theme::load(&cfg);
        ui::install_css(&theme);
        spot.borrow_mut().rebuild_sidebar();
        spot.borrow_mut().rebuild_content();
    });
}

fn schedule_apply(spot: &Rc<RefCell<Settings>>) {
    let generation = spot.borrow().apply_gen;
    let weak = Rc::downgrade(spot);
    glib::timeout_add_local_once(Duration::from_millis(500), move || {
        if let Some(spot) = weak.upgrade() {
            if spot.borrow().apply_gen == generation {
                system::apply_settings();
            }
        }
    });
}

fn button_action(weak: &Weak<RefCell<Settings>>, action: Btn) {
    match action {
        Btn::ClearHistory => {
            History::load().clear();
        }
        Btn::HardwareSettings => system::open_qml_settings(Some("wifi")),
        Btn::QmlSettings => system::open_qml_settings(None),
        Btn::ThemePicker => {
            let _ = system::spawn("qs", &["-c", "island", "ipc", "call", "picker", "themes"]);
        }
        Btn::WallpaperPicker => {
            let _ = system::spawn(
                "qs",
                &["-c", "island", "ipc", "call", "picker", "wallpapers"],
            );
        }
    }
    let _ = weak;
}

fn main() {
    let (shell_dir, page, command) = parse_args();
    if let Some(shell_dir) = shell_dir {
        std::env::set_var("ISLAND_SHELL_DIR", shell_dir);
    }
    let (tx, rx) = async_channel::unbounded();
    let Ok(Some(instance)) = Instance::claim("island-settings", &command, tx) else {
        return;
    };
    // `--close` with no running instance is a no-op, not a new window.
    if command == "close" {
        drop(instance);
        return;
    }
    let app = gtk::Application::builder()
        .application_id("org.island.SettingsRust")
        .build();
    let state: Rc<RefCell<Option<Rc<RefCell<Settings>>>>> = Rc::new(RefCell::new(None));
    {
        let state = state.clone();
        app.connect_activate(move |app| {
            let spot = Settings::new(app, page.clone());
            state.replace(Some(spot));
        });
    }
    glib::timeout_add_local(Duration::from_millis(60), {
        let state = state.clone();
        move || {
            while let Ok(message) = rx.try_recv() {
                if let Some(spot) = state.borrow().as_ref() {
                    let search = spot.borrow().search.clone();
                    let clear = message.starts_with("show:") || message.starts_with("page:");
                    spot.borrow_mut().handle(&message);
                    if clear && !search.text().is_empty() {
                        search.set_text("");
                    }
                }
            }
            glib::ControlFlow::Continue
        }
    });
    let _ = app.run_with_args(&["island-rust"]);
    drop(instance);
}

fn parse_args() -> (Option<PathBuf>, String, String) {
    let mut shell_dir = None;
    let mut page = String::new();
    let mut open = false;
    let mut close = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--shell-dir" => shell_dir = args.next().map(PathBuf::from),
            "--page" => page = args.next().unwrap_or_default(),
            "--open" => open = true,
            "--close" => close = true,
            _ => {}
        }
    }
    let command = if close {
        "close".to_string()
    } else if !page.is_empty() {
        format!("show:{page}")
    } else if open {
        "show".to_string()
    } else {
        "toggle".to_string()
    };
    (shell_dir, page, command)
}
