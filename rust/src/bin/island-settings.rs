#![allow(
    clippy::cast_possible_truncation,
    clippy::match_same_arms,
    clippy::needless_pass_by_value,
    clippy::similar_names,
    clippy::too_many_arguments,
    clippy::too_many_lines,
    clippy::unused_self,
    clippy::useless_vec
)]
use gtk::gdk;
use gtk::glib;
use gtk::prelude::*;
use island_rust::history::History;
use island_rust::paths;
use island_rust::settings_store::Store as Config;
use island_rust::singleton::Instance;
use island_rust::system;
use island_rust::theme::Theme;
use island_rust::ui;
use serde_json::{json, Value};
use std::cell::RefCell;
use std::path::PathBuf;
use std::process::Command;
use std::rc::{Rc, Weak};
use std::time::Duration;

#[derive(Clone, Copy)]
enum Btn {
    ClearHistory,
    ResetAll,
    ScreenshotToolbar,
    WallpaperPicker,
}

#[derive(Clone)]
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
    Options {
        key: &'static str,
        label: &'static str,
        sub: &'static str,
        options: Vec<(String, String)>,
    },
    Text {
        key: &'static str,
        label: &'static str,
        sub: &'static str,
        placeholder: &'static str,
    },
    Secret {
        label: &'static str,
        sub: &'static str,
        placeholder: &'static str,
    },
    Info {
        label: &'static str,
        value: &'static str,
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

#[derive(Clone)]
struct Group {
    title: &'static str,
    footer: &'static str,
    rows: Vec<Spec>,
}

#[derive(Clone)]
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
    toolbar: gtk::Box,
    sidebar: gtk::Box,
    content: gtk::Box,
    scroller: gtk::ScrolledWindow,
    pages: Vec<Page>,
    page: String,
    back: Vec<String>,
    forward: Vec<String>,
    query: String,
    apply_gen: u64,
    save_gen: u64,
    monitor: Option<gtk::gio::FileMonitor>,
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

fn list(
    key: &'static str,
    label: &'static str,
    sub: &'static str,
    options: Vec<(String, String)>,
) -> Spec {
    Spec::Options {
        key,
        label,
        sub,
        options,
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

fn info(label: &'static str, value: &'static str) -> Spec {
    Spec::Info { label, value }
}

fn button(label: &'static str, sub: &'static str, text: &'static str, action: Btn) -> Spec {
    Spec::Button {
        label,
        sub,
        text,
        action,
    }
}

const HYPR_LAYOUTS: &[(&str, &str)] = &[
    ("dwindle", "Dwindle"),
    ("master", "Master"),
    ("scrolling", "Scrolling"),
    ("monocle", "Monocle"),
];
const MANGO_LAYOUTS: &[(&str, &str)] = &[
    ("dwindle", "Dwindle"),
    ("tile", "Master (left)"),
    ("right_tile", "Master (right)"),
    ("center_tile", "Master (centre)"),
    ("vertical_tile", "Master (top)"),
    ("scroller", "Scrolling"),
    ("vertical_scroller", "Scrolling (vertical)"),
    ("grid", "Grid"),
    ("vertical_grid", "Grid (vertical)"),
    ("fair", "Fair"),
    ("vertical_fair", "Fair (vertical)"),
    ("deck", "Deck"),
    ("vertical_deck", "Deck (vertical)"),
    ("monocle", "Monocle"),
];
const I3_LAYOUTS: &[(&str, &str)] = &[
    ("default", "Split"),
    ("tabbed", "Tabbed"),
    ("stacking", "Stacked"),
];
const NIRI_LAYOUTS: &[(&str, &str)] = &[("scrolling", "Scrolling")];
const WALL_TRANSITIONS: &[(&str, &str)] = &[
    ("fade", "Fade"),
    ("wipe", "Wipe"),
    ("wave", "Wave"),
    ("grow", "Grow"),
    ("cursor", "Grow from Cursor"),
    ("any", "Grow from Random Spot"),
    ("outer", "Outer"),
    ("simple", "Cut"),
    ("random", "Random"),
];

const BAR_ITEMS: &[(&str, &str, &str)] = &[
    ("logo", "Logo menu", ""),
    ("appmenus", "App menus", "App name, Go, Window, Help"),
    ("workspaces", "Workspaces", ""),
    ("media", "Now playing", "Song and artist; opens the player"),
    ("tray", "Tray icons", ""),
    ("battery", "Battery", "Laptops only"),
    ("sound", "Sound", ""),
    ("network", "Network", ""),
    ("spotlight", "Spotlight", "Super+D opens it either way"),
    ("weather", "Weather", ""),
    ("controls", "Control Centre", ""),
    ("clock", "Clock", "Opens notifications"),
    ("power", "Power", ""),
];

struct DefaultKind {
    label: &'static str,
    probe: &'static str,
    mimes: &'static [&'static str],
}

const DEFAULT_KINDS: &[DefaultKind] = &[
    DefaultKind {
        label: "Web browser",
        probe: "x-scheme-handler/https",
        mimes: &[
            "x-scheme-handler/http",
            "x-scheme-handler/https",
            "x-scheme-handler/about",
            "x-scheme-handler/unknown",
            "text/html",
            "application/xhtml+xml",
            "application/x-extension-htm",
            "application/x-extension-html",
            "application/x-extension-shtml",
            "application/x-extension-xhtml",
            "application/x-extension-xht",
        ],
    },
    DefaultKind {
        label: "Email",
        probe: "x-scheme-handler/mailto",
        mimes: &["x-scheme-handler/mailto"],
    },
    DefaultKind {
        label: "File manager",
        probe: "inode/directory",
        mimes: &["inode/directory"],
    },
    DefaultKind {
        label: "Text editor",
        probe: "text/plain",
        mimes: &[
            "text/plain",
            "text/markdown",
            "text/x-markdown",
            "text/x-shellscript",
            "application/x-shellscript",
            "text/x-python",
            "text/x-csrc",
            "text/x-chdr",
            "text/x-c++src",
            "application/json",
            "application/xml",
            "text/x-log",
            "application/toml",
            "application/x-yaml",
            "text/css",
        ],
    },
    DefaultKind {
        label: "Images",
        probe: "image/png",
        mimes: &[
            "image/png",
            "image/jpeg",
            "image/gif",
            "image/webp",
            "image/bmp",
            "image/svg+xml",
            "image/avif",
            "image/tiff",
            "image/heic",
            "image/jxl",
            "image/x-icon",
        ],
    },
    DefaultKind {
        label: "Videos",
        probe: "video/mp4",
        mimes: &[
            "video/mp4",
            "video/x-matroska",
            "video/webm",
            "video/quicktime",
            "video/x-msvideo",
            "video/mpeg",
            "video/ogg",
            "video/x-flv",
            "video/3gpp",
            "video/x-ms-wmv",
        ],
    },
    DefaultKind {
        label: "Music",
        probe: "audio/mpeg",
        mimes: &[
            "audio/mpeg",
            "audio/flac",
            "audio/x-flac",
            "audio/ogg",
            "audio/x-vorbis+ogg",
            "audio/opus",
            "audio/mp4",
            "audio/x-m4a",
            "audio/aac",
            "audio/wav",
            "audio/x-wav",
            "audio/webm",
        ],
    },
    DefaultKind {
        label: "PDF documents",
        probe: "application/pdf",
        mimes: &["application/pdf"],
    },
    DefaultKind {
        label: "Archives",
        probe: "application/zip",
        mimes: &[
            "application/zip",
            "application/x-tar",
            "application/gzip",
            "application/x-compressed-tar",
            "application/x-7z-compressed",
            "application/vnd.rar",
            "application/x-rar",
            "application/x-xz",
            "application/x-xz-compressed-tar",
            "application/x-bzip2",
            "application/x-bzip2-compressed-tar",
            "application/zstd",
            "application/x-zstd-compressed-tar",
        ],
    },
];

fn first_percent(text: &str) -> f64 {
    let Some(index) = text.find('%') else {
        return 0.0;
    };
    let digits: String = text[..index]
        .chars()
        .rev()
        .take_while(char::is_ascii_digit)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    digits.parse().unwrap_or(0.0)
}

fn flatten_blockdevices(value: &Value, out: &mut Vec<Value>) {
    let Some(devices) = value.get("blockdevices").and_then(Value::as_array) else {
        return;
    };
    for device in devices {
        out.push(device.clone());
        if let Some(children) = device.get("children").and_then(Value::as_array) {
            for child in children {
                out.push(child.clone());
            }
        }
    }
}

fn pactl_descriptions(section: &str) -> std::collections::BTreeMap<String, String> {
    let text = capture("pactl", &["list", section]);
    let mut map = std::collections::BTreeMap::new();
    let mut name: Option<String> = None;
    for line in text.lines() {
        let line = line.trim();
        if let Some(value) = line.strip_prefix("Name: ") {
            name = Some(value.to_string());
        } else if let Some(value) = line.strip_prefix("Description: ") {
            if let Some(name) = name.take() {
                map.insert(name, value.to_string());
            }
        }
    }
    map
}

fn prompt_wifi_password(
    window: &gtk::ApplicationWindow,
    weak: &Weak<RefCell<Settings>>,
    ssid: &str,
) {
    let dialog = gtk::Dialog::builder()
        .title("Join network")
        .transient_for(window)
        .modal(true)
        .build();
    dialog.add_button("Cancel", gtk::ResponseType::Cancel);
    dialog.add_button("Join", gtk::ResponseType::Ok);
    let entry = gtk::Entry::new();
    entry.set_placeholder_text(Some("Password"));
    entry.set_visibility(false);
    entry.set_activates_default(true);
    entry.set_margin_top(12);
    entry.set_margin_bottom(12);
    entry.set_margin_start(12);
    entry.set_margin_end(12);
    dialog.content_area().append(&entry);
    dialog.set_default_response(gtk::ResponseType::Ok);
    let ssid = ssid.to_string();
    let weak = weak.clone();
    dialog.connect_response(move |dialog, response| {
        if response == gtk::ResponseType::Ok {
            let password = entry.text().to_string();
            let mut command = Command::new("nmcli");
            command.args(["dev", "wifi", "connect", &ssid]);
            if !password.is_empty() {
                command.args(["password", &password]);
            }
            let _ = command.output();
            if let Some(spot) = weak.upgrade() {
                schedule_rebuild(&spot);
            }
        }
        dialog.close();
    });
    dialog.present();
}

const PAGE_ORDER: &[&str] = &[
    "wifi",
    "bluetooth",
    "network",
    "notifications",
    "sound",
    "focus",
    "general",
    "appearance",
    "bar",
    "spotlight",
    "dock",
    "desktop",
    "windows",
    "animations",
    "defaultapps",
    "drives",
    "displays",
    "wallpaper",
    "keyboard",
    "screenshots",
    "mouse",
    "terminal",
];

fn page_rank(id: &str) -> usize {
    PAGE_ORDER
        .iter()
        .position(|item| *item == id)
        .unwrap_or(999)
}

fn custom_page(id: &str) -> bool {
    matches!(
        id,
        "general"
            | "wifi"
            | "bluetooth"
            | "network"
            | "sound"
            | "defaultapps"
            | "drives"
            | "displays"
    )
}

fn capture(program: &str, args: &[&str]) -> String {
    match Command::new(program).args(args).output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if stdout.is_empty() {
                String::from_utf8_lossy(&output.stderr).trim().to_string()
            } else {
                stdout
            }
        }
        Err(error) => format!("{program}: {error}"),
    }
}

fn nmcli_split(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut escaped = false;
    for ch in line.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
        } else if ch == '\\' {
            escaped = true;
        } else if ch == ':' {
            fields.push(current.clone());
            current.clear();
        } else {
            current.push(ch);
        }
    }
    fields.push(current);
    fields
}

fn layout_options() -> &'static [(&'static str, &'static str)] {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
        HYPR_LAYOUTS
    } else if std::env::var_os("NIRI_SOCKET").is_some() {
        NIRI_LAYOUTS
    } else if std::env::var_os("SWAYSOCK").is_some() || std::env::var_os("I3SOCK").is_some() {
        I3_LAYOUTS
    } else if std::env::var_os("MANGO_INSTANCE_SIGNATURE").is_some() {
        MANGO_LAYOUTS
    } else {
        HYPR_LAYOUTS
    }
}

fn monitor_options() -> Vec<(String, String)> {
    let mut options = vec![
        ("auto".to_string(), "Auto (pointer)".to_string()),
        ("focused".to_string(), "Focused".to_string()),
        ("main".to_string(), "Main display".to_string()),
    ];
    if let Some(display) = gdk::Display::default() {
        let monitors = display.monitors();
        for i in 0..monitors.n_items() {
            let Some(monitor) = monitors
                .item(i)
                .and_then(|item| item.downcast::<gdk::Monitor>().ok())
            else {
                continue;
            };
            if let Some(name) = monitor.connector() {
                let name = name.to_string();
                options.push((name.clone(), name));
            }
        }
    }
    options
}

fn pages() -> Vec<Page> {
    vec![
        Page {
            id: "notifications", title: "Notifications", glyph: "\u{f0f3}", tint: "#ff3b30", section: "Alerts & Sound",
            about: "Banners slide in at the top right of the screen. Click the clock in the menu bar to open Notification Centre.",
            keywords: "notification daemon toast banner popup alerts timeout",
            groups: vec![Group { title: "Notification Centre", footer: "Critical notifications stay until dismissed and still show while Do Not Disturb is on.", rows: vec![
                slider("notifTimeout", "Banner duration", "Unless the app asks for its own", 2.0, 20.0, 1.0, 0, " s"),
            ]}],
        },
        Page {
            id: "focus", title: "Focus", glyph: "\u{f186}", tint: "#5e5ce6", section: "Alerts & Sound",
            about: "Focus silences notification banners. They still collect in Notification Centre.",
            keywords: "do not disturb dnd quiet silence",
            groups: vec![Group { title: "", footer: "", rows: vec![toggle("notifDnd", "Do Not Disturb", "Also in Control Centre")] }],
        },
        Page {
            id: "general", title: "General", glyph: "\u{f013}", tint: "#8e8e93", section: "Desktop",
            about: "About this computer, transfer and reset.",
            keywords: "about computer system info os kernel memory cpu storage reset",
            groups: vec![
                Group { title: "Transfer or Reset", footer: "Your settings are in ~/.config/island/settings.json; everything not listed there comes from defaults.json.", rows: vec![
                    button("Reset all settings", "Every setting returns to its default; themes are kept", "Reset…", Btn::ResetAll),
                ]},
            ],
        },
        Page {
            id: "appearance", title: "Appearance", glyph: "\u{f042}", tint: "#3a3a3c", section: "Desktop",
            about: "Theme, accent and text colour, the layout of the desktop, and how apps, icons and the pointer look.",
            keywords: "theme dark light accent text colour color black white gtk icons cursor pointer matugen wallpaper material font catppuccin nord gruvbox",
            groups: vec![
                Group { title: "Theme", footer: "Themes are read from the Island themes folder. Applying one recolours the whole desktop.", rows: vec![
                    Spec::Themes,
                    Spec::Accents,
                    choice("iconStyle", "Icon style", "Dock, Launchpad and Spotlight", &[("default", "Default"), ("clear", "Clear"), ("tinted", "Tinted")]),
                    choice("iconTint", "Icon tint", "Visible when icons are tinted", ACCENTS),
                    choice("textColor", "Text colour", "Menu bar, menus, Dock, widgets and Settings", &[("auto", "Auto"), ("white", "White"), ("black", "Black")]),
                    text("widgetFont", "Interface font", "Menu bar, menus, Dock, Spotlight and Settings", "Adwaita Sans"),
                    choice("widgetFontWeight", "Weight", "Bold text stays at least this heavy", &[("300", "Light"), ("400", "Regular"), ("500", "Medium"), ("600", "Semibold"), ("700", "Bold"), ("800", "Heavy"), ("900", "Black")]),
                ]},
                Group { title: "Layout", footer: "Bottom bar: one floating bar with your apps, now playing, status and the clock, in place of the menu bar and Dock. Compact bar: a smaller pill only as wide as its contents: start, search, apps, status, CPU/RAM and the clock. Desktop icons: Trash, mounted drives and (optionally) your Dock apps; double-click to open, right-click a USB drive to eject.", rows: vec![
                    toggle("liquidGlass", "Liquid glass", "Clearer panels with a glass rim and sheen. No extra GPU cost"),
                    choice("shellLayout", "Layout", "", &[("menubar", "Menu bar + Dock"), ("taskbar", "Bottom bar"), ("compact", "Compact bar")]),
                    choice("barSkin", "Menu bar skin", "", &[("classic", "Classic"), ("pills", "Pills"), ("island", "Dynamic Island"), ("notch", "Notch")]),
                    slider("taskbarHeight", "Bottom bar height", "", 40.0, 72.0, 1.0, 0, " px"),
                    toggle("taskbarMagnify", "Magnification", "Bottom bar icons grow under the pointer"),
                    slider("taskbarMagnifySize", "Magnified size", "", 1.1, 2.5, 0.05, 2, "×"),
                    toggle("taskbarBounce", "Animate opening applications", "Bottom bar icons bounce while an app starts"),
                    slider("compactIconSize", "Icon size", "", 16.0, 44.0, 1.0, 0, " px"),
                    toggle("compactStats", "Show CPU and memory", "In the compact bar, next to the clock"),
                    toggle("desktopIcons", "Desktop icons", "Trash and mounted drives"),
                    toggle("desktopIconsApps", "Show Dock apps on the desktop", ""),
                    slider("desktopIconSize", "Desktop icon size", "", 40.0, 96.0, 1.0, 0, " px"),
                ]},
                Group { title: "Colours from wallpaper", footer: "Builds a theme from the current wallpaper with matugen, and rebuilds it whenever the wallpaper changes. Choosing a theme above turns this off.", rows: vec![
                    toggle("matugen", "Match the wallpaper", ""),
                    choice("matugenScheme", "Scheme", "", &[("tonal-spot", "Tonal Spot"), ("content", "Content"), ("expressive", "Expressive"), ("fidelity", "Fidelity"), ("fruit-salad", "Fruit Salad"), ("rainbow", "Rainbow"), ("neutral", "Neutral"), ("monochrome", "Monochrome")]),
                    choice("matugenMode", "Mode", "", &[("light", "Light"), ("dark", "Dark")]),
                    choice("matugenPrefer", "Pick colour by", "", &[("saturation", "Most saturated"), ("less-saturation", "Least saturated"), ("value", "Brightest"), ("darkness", "Darkest"), ("lightness", "Lightest")]),
                ]},
                Group { title: "Look & feel", footer: "GTK apps pick these up live (GTK 4 apps may need a restart).", rows: vec![
                    list("gtkTheme", "Application theme", "adw-gtk3 is recoloured to match", gtk_theme_options()),
                    list("iconTheme", "Icons", "", icon_theme_options()),
                    list("cursorTheme", "Pointer", "", cursor_theme_options()),
                    slider("cursorSize", "Pointer size", "", 16.0, 64.0, 2.0, 0, " px"),
                ]},
            ],
        },
        Page {
            id: "bar", title: "Menu Bar", glyph: "\u{f00b}", tint: "#8e8e93", section: "Desktop",
            about: "Status items, workspaces and the clock across the top of the screen.",
            keywords: "menu bar height opacity blur font size workspaces clock time seconds weather",
            groups: vec![
                Group { title: "Menu Bar", footer: "", rows: vec![
                    slider("barHeight", "Height", "", 22.0, 44.0, 1.0, 0, " px"),
                    slider("barOpacity", "Background opacity", "", 0.0, 1.0, 0.01, 2, ""),
                    toggle("barBlur", "Blur behind the menu bar", ""),
                    slider("barFontSize", "Text size", "", 10.0, 18.0, 1.0, 0, " px"),
                ]},
                Group { title: "Workspaces", footer: "Click to switch, scroll to step through, right-click for the Overview.", rows: vec![
                    toggle("barWorkspaces", "Show workspaces", "In the menu bar, bottom bar and compact bar"),
                    choice("barWorkspaceStyle", "Style", "", &[("numbers", "Numbers"), ("dots", "Dots"), ("pill", "Pill"), ("glide", "Glide"), ("line", "Line"), ("activity", "Activity"), ("kanji", "Kanji"), ("roman", "Roman")]),
                    slider("barWorkspaceCount", "Always show", "", 1.0, 10.0, 1.0, 0, ""),
                ]},
                Group { title: "Clock", footer: "", rows: vec![
                    choice("clockDate", "Date", "Click the clock for the full date", &[("full", "Sat Nov 21"), ("weekday", "Sat"), ("none", "Time only")]),
                    toggle("clock24h", "Use a 24-hour clock", ""),
                    toggle("clockSeconds", "Display the time with seconds", ""),
                ]},
            ],
        },
        Page {
            id: "spotlight", title: "Spotlight", glyph: "\u{f002}", tint: "#0a84ff", section: "Desktop",
            about: "Search apps, files and actions, do maths, run a command, or search the web.",
            keywords: "spotlight search launcher apps files commands shell web duckduckgo history recent pin width results style monitor display screen",
            groups: vec![
                Group { title: "Window", footer: "Auto opens the macOS card at the top. Capsule grows out of the Dynamic Island or Notch; Attached drops from the bar.", rows: vec![
                    choice("spotlightStyle", "Open as", "macOS card at the top by default", &[("auto", "Auto"), ("attached", "Attached"), ("floating", "Floating"), ("capsule", "Capsule")]),
                    list("spotlightMonitor", "Monitor", "Auto opens under the pointer", monitor_options()),
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
            id: "dock", title: "Dock", glyph: "\u{f108}", tint: "#1c1c1e", section: "Desktop",
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
                    toggle("dockAutohide", "Automatically hide and show the Dock", ""),
                    toggle("dockAllScreens", "Show on every display", ""),
                    slider("dockOpacity", "Background opacity", "", 0.0, 1.0, 0.01, 2, ""),
                    slider("dockMargin", "Distance from the edge", "", 0.0, 30.0, 1.0, 0, " px"),
                ]},
            ],
        },
        Page {
            id: "desktop", title: "Desktop & Widgets", glyph: "\u{f108}", tint: "#30d158", section: "Desktop",
            about: "Widgets sit on the desktop under your windows. The lock screen and its wording live here too.",
            keywords: "widgets clock weather calendar music system verse lock screen password opacity colours position",
            groups: vec![
                Group { title: "", footer: "", rows: vec![
                    toggle("widgets", "Show widgets", ""),
                    choice("widgetStyle", "Style", "", &[("tahoe", "Tahoe"), ("classic", "Classic")]),
                    choice("widgetColors", "Colours", "Wallpaper picks accents from your wallpaper", &[("system", "System"), ("theme", "Theme"), ("wallpaper", "Wallpaper")]),
                    slider("widgetsOpacity", "Widget opacity", "", 0.0, 1.0, 0.01, 2, ""),
                ]},
                Group { title: "Widgets", footer: "", rows: vec![
                    toggle("widgetClock", "Clock", ""),
                    toggle("widgetClockSeconds", "Second hand", ""),
                    toggle("widgetWeather", "Weather", ""),
                    toggle("widgetCalendar", "Calendar", ""),
                    toggle("widgetMusic", "Now Playing", ""),
                    toggle("widgetSystem", "System", "CPU, memory, temperature and disk"),
                    toggle("widgetVerse", "Verse of the Day", "ESV, from Bible Gateway"),
                ]},
                Group { title: "Lock Screen", footer: "hyprlock reads ~/.config/hypr/hyprlock.conf, which apply-theme.sh keeps in the current palette.", rows: vec![
                    choice("lockScreen", "Locker", "", &[("island", "Island"), ("hyprlock", "hyprlock")]),
                    toggle("lockTypingFx", "Typing animation", "Password dots pop, the field glows and the screen fades back while you type"),
                    choice("lockPasswordMask", "Password style", "", &[("circles", "Circles"), ("last", "Last letter"), ("letters", "Letters")]),
                    toggle("lockOnStart", "Lock when the session starts", "Use with SDDM autologin: log in automatically, then unlock Island"),
                    toggle("lockVerse", "Verse on the lock screen", "Island's lock screen only; it sits above the picture"),
                ]},
                Group { title: "Arrangement", footer: "Widgets you haven't moved stack in the chosen corner. Drag them on the desktop or use the QML editor.", rows: vec![
                    choice("widgetsPosition", "Corner", "", &[("top-left", "Top Left"), ("top-right", "Top Right"), ("bottom-left", "Bottom Left"), ("bottom-right", "Bottom Right")]),
                    slider("widgetsMargin", "Distance from the edge", "", 0.0, 120.0, 1.0, 0, " px"),
                    toggle("widgetsAllScreens", "Show on every display", ""),
                ]},
                Group { title: "Weather", footer: "Used by the weather widget, the menu bar and the forecast.", rows: vec![
                    text("weatherLocation", "Location", "Empty to use your approximate location", "City, Country, or empty for automatic"),
                    choice("weatherUnits", "Units", "Temperature and wind speed", &[("c", "Celsius · km/h"), ("f", "Fahrenheit · mph")]),
                ]},
            ],
        },
        Page {
            id: "windows", title: "Windows", glyph: "\u{f2d0}", tint: "#30b0c7", section: "Desktop",
            about: "Tiling, gaps, corners and the blur behind translucent windows.",
            keywords: "windows gaps borders rounding radius layout blur opacity dim inactive",
            groups: vec![
                Group { title: "Tiling", footer: "", rows: vec![
                    choice("layout", "Tiling layout", "Options for the running compositor, detected automatically", layout_options()),
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
                Group { title: "Blur", footer: "Blur shows through translucent windows, the menu bar, Dock and Spotlight. Higher values use more GPU.", rows: vec![
                    toggle("blur", "Blur", ""),
                    slider("blurSize", "Strength", "", 1.0, 12.0, 1.0, 0, ""),
                    slider("blurPasses", "Passes", "", 1.0, 4.0, 1.0, 0, ""),
                ]},
            ],
        },
        Page {
            id: "animations", title: "Animations", glyph: "\u{f021}", tint: "#ff9f0a", section: "Desktop",
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
            id: "wallpaper", title: "Wallpaper", glyph: "\u{f03e}", tint: "#32ade6", section: "Desktop",
            about: "Pick a picture or a video from your wallpaper folders. Super+W opens the picker.",
            keywords: "background picture folder transition video live animated mpvpaper wallhaven download api key",
            groups: vec![
                Group { title: "", footer: "", rows: vec![
                    button("Wallpaper picker", "Pictures, videos and Wallhaven", "Choose…", Btn::WallpaperPicker),
                    text("wallDir", "Pictures folder", "", "~/Pictures/Wallpapers"),
                    text("videoDir", "Videos folder", "Played with mpvpaper", "~/Videos/Wallpapers"),
                    text("videoMpvOptions", "mpv options", "", "no-audio loop hwdec=auto panscan=1.0"),
                    choice("wallTransition", "Transition", "", WALL_TRANSITIONS),
                    slider("wallDuration", "Transition length", "", 0.0, 3.0, 0.1, 1, " s"),
                ]},
                Group { title: "Wallhaven", footer: "The API key is only needed for NSFW results or your account's blacklist. It's kept in ~/.config/island/wallhaven-api-key, readable only by you.", rows: vec![
                    Spec::Secret { label: "API key", sub: "Press Return to save", placeholder: "Optional" },
                    text("wallhavenQuery", "Default search", "", "Anything"),
                    choice("wallhavenSorting", "Sort by", "", &[("toplist", "Toplist"), ("date_added", "Newest"), ("random", "Random"), ("views", "Most Viewed"), ("favorites", "Most Favourited"), ("relevance", "Relevance"), ("hot", "Hot")]),
                    choice("wallhavenTopRange", "Toplist range", "", &[("1d", "Day"), ("1w", "Week"), ("1M", "Month"), ("3M", "3 Months"), ("1y", "Year")]),
                    toggle("wallhavenGeneral", "General", ""),
                    toggle("wallhavenAnime", "Anime", ""),
                    toggle("wallhavenPeople", "People", ""),
                    toggle("wallhavenSketchy", "Include sketchy", ""),
                    toggle("wallhavenNsfw", "Include NSFW", "Needs an API key"),
                    text("wallhavenAtleast", "Minimum resolution", "", "1920x1080"),
                    text("wallhavenRatios", "Aspect ratios", "e.g. 16x9,21x9", "Any"),
                ]},
            ],
        },
        Page {
            id: "keyboard", title: "Keyboard", glyph: "\u{f11c}", tint: "#8e8e93", section: "Input & Capture",
            about: "Key repeat, Num Lock and Island's keyboard shortcuts.",
            keywords: "keyboard repeat delay numlock shortcuts keybinds",
            groups: vec![
                Group { title: "", footer: "", rows: vec![
                    slider("repeatRate", "Key repeat rate", "", 10.0, 80.0, 1.0, 0, "/s"),
                    slider("repeatDelay", "Delay until repeat", "", 150.0, 1000.0, 25.0, 0, " ms"),
                    toggle("numlock", "Turn on Num Lock at login", ""),
                ]},
                Group { title: "Keyboard Shortcuts", footer: "Shortcuts are defined by your compositor. ⌘ = Super.", rows: vec![
                    info("Spotlight", "⌘D"), info("Launchpad", "⌘A"), info("Notification Centre", "⌘C"),
                    info("Control Centre · Music", "⌘M"), info("System Settings", "⌘I"),
                    info("Clipboard history", "⌘V"), info("Wallpaper", "⌘W"),
                    info("Random wallpaper", "⇧⌘W"), info("Themes", "⌥⌘W"),
                    info("Power", "⌘Esc"), info("Terminal", "⌘T"), info("Files", "⌘E"),
                    info("Browser", "⌘B"), info("Close window", "⌘Q"),
                    info("Full screen", "⌘F"), info("Float window", "⇧⌘T"),
                    info("Pin window", "⌘P"), info("Go to desktop 1–9", "⌘1 – ⌘9"),
                    info("Move window to desktop", "⇧⌘1 – ⇧⌘9"),
                    info("Move focus", "⌘ arrows / H J K L"),
                ]},
            ],
        },
        Page {
            id: "screenshots", title: "Screenshots", glyph: "\u{f030}", tint: "#636366", section: "Input & Capture",
            about: "Print captures a selection, Alt+Print a window, Shift+Print the whole screen. Super+Shift+S opens the screenshot toolbar.",
            keywords: "screenshot screen capture print grim slurp snip region window clipboard thumbnail",
            groups: vec![Group { title: "", footer: "", rows: vec![
                button("Screenshot toolbar", "Screen, window or selection, with a timer", "Open…", Btn::ScreenshotToolbar),
                choice("screenshotDest", "Save to", "", &[("~/Pictures/Screenshots", "Screenshots folder"), ("~/Pictures", "Pictures"), ("~/Desktop", "Desktop"), ("clipboard", "Clipboard only")]),
                toggle("screenshotCopy", "Also copy to the clipboard", ""),
                toggle("screenshotThumb", "Show floating thumbnail", "Click it to open the screenshot"),
                toggle("screenshotPointer", "Show the mouse pointer", ""),
                toggle("screenshotSound", "Play sound", ""),
            ]}],
        },
        Page {
            id: "mouse", title: "Mouse", glyph: "\u{f245}", tint: "#8e8e93", section: "Input & Capture",
            about: "Pointer speed, acceleration, scrolling and focus.",
            keywords: "pointer tracking speed sensitivity acceleration scroll natural focus follows",
            groups: vec![Group { title: "", footer: "", rows: vec![
                slider("sensitivity", "Tracking speed", "", -1.0, 1.0, 0.05, 2, ""),
                toggle("naturalScroll", "Natural scrolling", "Content tracks finger movement"),
                choice("accelProfile", "Pointer acceleration", "", &[("flat", "Off"), ("adaptive", "On")]),
                number_choice("followMouse", "Focus follows pointer", "", &[("0", "Off"), ("1", "Always"), ("2", "Loosely")]),
            ]}],
        },
        Page {
            id: "terminal", title: "Terminal", glyph: "\u{f120}", tint: "#1c1c1e", section: "Apps",
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
            id: "wifi", title: "Wi-Fi", glyph: "\u{f1eb}", tint: "#0a84ff", section: "Network",
            about: "Join wireless networks. Networks you've used before connect on their own.",
            keywords: "wireless network wlan ssid password join",
            groups: vec![],
        },
        Page {
            id: "bluetooth", title: "Bluetooth", glyph: "\u{f293}", tint: "#0a84ff", section: "Network",
            about: "Pair and connect headphones, mice, keyboards and other devices.",
            keywords: "devices pair headphones mouse keyboard",
            groups: vec![],
        },
        Page {
            id: "network", title: "Network", glyph: "\u{f0ac}", tint: "#0a84ff", section: "Network",
            about: "Wired connections, IP details and VPNs.",
            keywords: "ethernet wired lan ip address internet vpn wireguard openvpn tunnel",
            groups: vec![],
        },
        Page {
            id: "sound", title: "Sound", glyph: "\u{f028}", tint: "#ff2d55", section: "Alerts & Sound",
            about: "Choose where sound plays and which microphone listens.",
            keywords: "volume output speakers headphones mute audio",
            groups: vec![],
        },
        Page {
            id: "defaultapps", title: "Default Apps", glyph: "\u{f00a}", tint: "#5856d6", section: "Desktop",
            about: "The apps that open links, mail, folders and files.",
            keywords: "default browser web mail email file manager folder text editor image viewer video player music pdf archive open with xdg mime handler",
            groups: vec![],
        },
        Page {
            id: "drives", title: "Drives", glyph: "\u{f02ca}", tint: "#636366", section: "Desktop",
            about: "Mount drives automatically when they're plugged in or when you log in, and mount, unmount or eject them here.",
            keywords: "automount mount unmount eject usb stick disk drive external sd card storage udisks login partition",
            groups: vec![],
        },
        Page {
            id: "displays", title: "Displays", glyph: "\u{f26c}", tint: "#0a84ff", section: "Desktop",
            about: "Resolution, refresh rate, scale and rotation.",
            keywords: "monitor resolution refresh rate hz scale rotation rotate screen vrr adaptive sync",
            groups: vec![],
        },
    ]
}
impl Settings {
    fn new(app: &gtk::Application, initial_page: String) -> Rc<RefCell<Self>> {
        let cfg = Config::load();
        let theme = Theme::load(&cfg);
        ui::install_css(&theme);
        let pages = pages();
        let initial_page = match initial_page.as_str() {
            "input" => "keyboard".to_string(),
            "menubar" => "bar".to_string(),
            other => other.to_string(),
        };
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
        window.set_default_size(880, 660);
        window.set_size_request(700, 460);
        window.set_resizable(true);

        let shell = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        shell.add_css_class("settings-shell");
        shell.set_size_request(880, 660);

        let sidebar_holder = gtk::Box::new(gtk::Orientation::Vertical, 0);
        sidebar_holder.add_css_class("sidebar");
        sidebar_holder.set_size_request(232, -1);

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
        let minimize = gtk::Button::with_label("−");
        minimize.add_css_class("traffic-min");
        minimize.set_tooltip_text(Some("Minimise"));
        minimize.connect_clicked({
            let window = window.clone();
            move |_| window.minimize()
        });
        header_row.append(&minimize);
        let zoom = gtk::Button::with_label("+");
        zoom.add_css_class("traffic-max");
        zoom.set_tooltip_text(Some("Zoom"));
        zoom.connect_clicked({
            let window = window.clone();
            move |_| {
                if window.is_maximized() {
                    window.unmaximize();
                } else {
                    window.maximize();
                }
            }
        });
        header_row.append(&zoom);
        let header_title = ui::label("Settings", "title");
        header_title.set_margin_start(4);
        header_row.append(&header_title);
        header.set_child(Some(&header_row));
        sidebar_holder.append(&header);

        let user = capture(
            "sh",
            &[
                "-c",
                "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); echo \"${n:-$USER}\"",
            ],
        );
        let user = if user.trim().is_empty() {
            std::env::var("USER").unwrap_or_else(|_| "Local Account".to_string())
        } else {
            user.trim().to_string()
        };
        let initials: String = user
            .split_whitespace()
            .filter_map(|word| word.chars().next())
            .take(2)
            .collect::<String>()
            .to_uppercase();
        let account = gtk::Button::new();
        account.add_css_class("account-card");
        account.set_has_frame(false);
        let account_row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        let avatar = ui::label(
            if initials.is_empty() { "?" } else { &initials },
            "account-avatar",
        );
        avatar.set_xalign(0.5);
        avatar.set_yalign(0.5);
        avatar.set_size_request(34, 34);
        avatar.set_valign(gtk::Align::Center);
        account_row.append(&avatar);
        let names = gtk::Box::new(gtk::Orientation::Vertical, 1);
        names.set_valign(gtk::Align::Center);
        names.append(&ui::label(&user, "row-title"));
        names.append(&ui::label("Local Account", "row-sub"));
        account_row.append(&names);
        account.set_child(Some(&account_row));
        account.set_margin_start(10);
        account.set_margin_end(10);
        account.set_margin_bottom(8);
        let account_wire = account.clone();
        sidebar_holder.append(&account);

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
        toolbar.set_size_request(-1, 56);
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
                toolbar: toolbar.clone(),
                sidebar,
                content,
                scroller: scroller.clone(),
                pages,
                page,
                back: Vec::new(),
                forward: Vec::new(),
                query: String::new(),
                apply_gen: 0,
                save_gen: 0,
                monitor: None,
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
                    let ctrl = modifiers.contains(gdk::ModifierType::CONTROL_MASK);
                    let alt = modifiers.contains(gdk::ModifierType::ALT_MASK);
                    if keyval == gdk::Key::Escape {
                        if let Some(spot) = weak.upgrade() {
                            let search = spot.borrow().search.clone();
                            if !search.text().is_empty() {
                                search.set_text("");
                                search.grab_focus();
                            }
                        }
                        return glib::Propagation::Stop;
                    }
                    if ctrl
                        && keyval
                            .to_unicode()
                            .is_some_and(|c| c.eq_ignore_ascii_case(&'f'))
                    {
                        if let Some(spot) = weak.upgrade() {
                            let search = spot.borrow().search.clone();
                            search.grab_focus();
                            search.select_region(0, -1);
                        }
                        return glib::Propagation::Stop;
                    }
                    if ctrl && keyval.to_unicode().is_some_and(|c| matches!(c, 'w' | 'q')) {
                        if let Some(spot) = weak.upgrade() {
                            spot.borrow().window.close();
                        }
                        return glib::Propagation::Stop;
                    }
                    if (alt && keyval == gdk::Key::Left)
                        || (ctrl && keyval == gdk::Key::bracketleft)
                    {
                        if let Some(spot) = weak.upgrade() {
                            spot.borrow_mut().go_back();
                        }
                        return glib::Propagation::Stop;
                    }
                    if (alt && keyval == gdk::Key::Right)
                        || (ctrl && keyval == gdk::Key::bracketright)
                    {
                        if let Some(spot) = weak.upgrade() {
                            spot.borrow_mut().go_forward();
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
        spot.borrow_mut().build_toolbar();
        spot.borrow_mut().wire_account(&account_wire);
        install_settings_watch(&spot);
        window.present();
        search.grab_focus();
        spot
    }

    fn set_page(&mut self, id: String) {
        if id == self.page {
            return;
        }
        self.back.push(self.page.clone());
        if self.back.len() > 30 {
            self.back.remove(0);
        }
        self.forward.clear();
        self.page = id;
    }

    fn go_back(&mut self) {
        let Some(page) = self.back.pop() else {
            return;
        };
        self.forward.insert(0, self.page.clone());
        self.page = page;
        self.rebuild_sidebar();
        self.rebuild_content();
    }

    fn go_forward(&mut self) {
        let Some(page) = self.forward.first().cloned() else {
            return;
        };
        self.forward.remove(0);
        self.back.push(self.page.clone());
        self.page = page;
        self.rebuild_sidebar();
        self.rebuild_content();
    }

    fn rebuild_sidebar(&mut self) {
        while let Some(child) = self.sidebar.first_child() {
            self.sidebar.remove(&child);
        }
        let mut section = "";
        let mut pages: Vec<&Page> = self
            .pages
            .iter()
            .filter(|page| self.query.is_empty() || page_matches(page, &self.query))
            .collect();
        pages.sort_by_key(|page| page_rank(page.id));
        for page in pages {
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
                        state.set_page(id.clone());
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
        if !self.query.is_empty() && self.sidebar.first_child().is_none() {
            let empty = ui::label("No Results", "muted");
            empty.set_margin_start(8);
            empty.set_margin_top(6);
            self.sidebar.append(&empty);
        }
    }

    fn rebuild_content(&mut self) {
        self.scroller.vadjustment().set_value(0.0);
        while let Some(child) = self.content.first_child() {
            self.content.remove(&child);
        }
        if !self.query.is_empty() {
            self.title.set_text("Search");
            self.build_search_results();
            return;
        }
        let Some(page) = self.pages.iter().find(|page| page.id == self.page).cloned() else {
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

        if custom_page(page.id) {
            self.build_custom(page.id);
        }

        for group in &page.groups {
            let rows: Vec<&Spec> = group
                .rows
                .iter()
                .filter(|spec| spec_visible(spec_key(spec), &self.cfg))
                .collect();
            if !group.title.is_empty() {
                let caption = ui::label(group.title, "section");
                caption.set_margin_start(12);
                caption.set_margin_top(4);
                self.content.append(&caption);
            }
            let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
            card.add_css_class("group-card");
            for (index, spec) in rows.iter().enumerate() {
                let row = self.build_row(spec);
                card.append(&row);
                if index + 1 < rows.len() {
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

        if page.id == "bar" {
            self.build_bar_items();
        }
        if page.id == "desktop" {
            self.build_widget_arranging();
        }
        if page.id == "appearance" {
            self.build_theme_cards();
        }

        let keys = page_keys(&page);
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
                        state.cfg.reset(&keys);
                        state.apply_gen = state.apply_gen.wrapping_add(1);
                        state.save_gen = state.save_gen.wrapping_add(1);
                    }
                    schedule_save(&spot);
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
                    if spec_visible(spec_key(spec), &self.cfg) && spec_matches(spec, &self.query) {
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
        let mut panes = std::collections::BTreeSet::new();
        for (page, _) in &results {
            panes.insert(page.id);
        }
        let count = ui::label(
            &format!(
                "{} {} in {} {}",
                results.len(),
                if results.len() == 1 {
                    "setting"
                } else {
                    "settings"
                },
                panes.len(),
                if panes.len() == 1 { "pane" } else { "panes" }
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
                        state.set_page(id.clone());
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
            Spec::Options { key, options, .. } => {
                let current = self
                    .cfg
                    .string(key, options.first().map_or("", |(value, _)| value));
                let mut options = options.clone();
                if !options.iter().any(|(value, _)| value == &current) && !current.is_empty() {
                    options.insert(0, (current.clone(), current.clone()));
                }
                let labels: Vec<&str> = options.iter().map(|(_, label)| label.as_str()).collect();
                let dropdown = gtk::DropDown::from_strings(&labels);
                let index = options
                    .iter()
                    .position(|(value, _)| value == &current)
                    .unwrap_or(0) as u32;
                dropdown.set_selected(index);
                dropdown.set_valign(gtk::Align::Center);
                let key = *key;
                dropdown.connect_selected_notify(move |dropdown| {
                    let Some((value, _)) = options.get(dropdown.selected() as usize) else {
                        return;
                    };
                    set_value(&weak, key, json!(value));
                });
                row.append(&dropdown);
            }
            Spec::Secret { placeholder, .. } => {
                let entry = gtk::Entry::new();
                entry.set_text(&read_wallhaven_key());
                entry.set_placeholder_text(Some(placeholder));
                entry.set_visibility(false);
                entry.set_width_chars(24);
                entry.set_valign(gtk::Align::Center);
                entry.connect_activate(move |entry| {
                    save_wallhaven_key(entry.text().as_str());
                });
                row.append(&entry);
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
            Spec::Info { value, .. } => {
                let label = ui::label(value, "row-sub");
                label.set_valign(gtk::Align::Center);
                row.append(&label);
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

    fn wire_account(&self, account: &gtk::Button) {
        let weak = self.weak.clone();
        account.connect_clicked(move |_| {
            if let Some(spot) = weak.upgrade() {
                {
                    let mut state = spot.borrow_mut();
                    state.set_page("general".to_string());
                    state.query.clear();
                }
                spot.borrow_mut().rebuild_sidebar();
                spot.borrow_mut().rebuild_content();
            }
        });
    }

    fn build_toolbar(&mut self) {
        let weak = self.weak.clone();
        let back = self.custom_button("\u{2039}", "toolbar-button", move || {
            if let Some(spot) = weak.upgrade() {
                spot.borrow_mut().go_back();
            }
        });
        let weak = self.weak.clone();
        let forward = self.custom_button("\u{203a}", "toolbar-button", move || {
            if let Some(spot) = weak.upgrade() {
                spot.borrow_mut().go_forward();
            }
        });
        self.toolbar.prepend(&forward);
        self.toolbar.prepend(&back);
    }

    fn add_group(&mut self, title: &str, footer: &str, rows: Vec<gtk::Widget>) {
        if rows.is_empty() {
            return;
        }
        if !title.is_empty() {
            let caption = ui::label(title, "section");
            caption.set_margin_start(12);
            caption.set_margin_top(4);
            self.content.append(&caption);
        }
        let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
        card.add_css_class("group-card");
        let count = rows.len();
        for (index, row) in rows.into_iter().enumerate() {
            card.append(&row);
            if index + 1 < count {
                card.append(&ui::separator());
            }
        }
        self.content.append(&card);
        if !footer.is_empty() {
            let footer = ui::label(footer, "muted");
            footer.set_wrap(true);
            footer.set_wrap_mode(gtk::pango::WrapMode::WordChar);
            footer.set_margin_start(12);
            footer.set_margin_end(12);
            self.content.append(&footer);
        }
    }

    fn custom_row(&self, title: &str, sub: &str, control: Option<gtk::Widget>) -> gtk::Widget {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 16);
        row.add_css_class("setting-row");
        let col = gtk::Box::new(gtk::Orientation::Vertical, 1);
        col.set_hexpand(true);
        col.set_valign(gtk::Align::Center);
        col.append(&ui::label(title, "row-title"));
        if !sub.is_empty() {
            let label = ui::label(sub, "row-sub");
            label.set_wrap(true);
            label.set_wrap_mode(gtk::pango::WrapMode::WordChar);
            label.set_max_width_chars(60);
            col.append(&label);
        }
        row.append(&col);
        if let Some(control) = control {
            control.set_valign(gtk::Align::Center);
            row.append(&control);
        }
        row.upcast()
    }

    fn control_row(&self, title: &str, sub: &str, controls: Vec<gtk::Widget>) -> gtk::Widget {
        let holder = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        holder.set_valign(gtk::Align::Center);
        for control in controls {
            holder.append(&control);
        }
        self.custom_row(title, sub, Some(holder.upcast()))
    }

    fn custom_button(&self, text: &str, class: &str, action: impl Fn() + 'static) -> gtk::Widget {
        let button = gtk::Button::with_label(text);
        button.add_css_class(class);
        button.set_valign(gtk::Align::Center);
        button.connect_clicked(move |_| action());
        button.upcast()
    }

    fn refresh_button(&self) -> gtk::Widget {
        let weak = self.weak.clone();
        self.custom_button("Refresh", "plain-button", move || {
            if let Some(spot) = weak.upgrade() {
                schedule_rebuild(&spot);
            }
        })
    }

    fn build_custom(&mut self, id: &str) {
        match id {
            "general" => self.build_general_about(),
            "sound" => self.build_sound(),
            "defaultapps" => self.build_default_apps(),
            "wifi" => self.build_wifi(),
            "bluetooth" => self.build_bluetooth(),
            "network" => self.build_network(),
            "drives" => self.build_drives(),
            "displays" => self.build_displays(),
            _ => {}
        }
    }

    fn build_general_about(&mut self) {
        let script = r#"
            . /etc/os-release 2>/dev/null
            echo "os=${PRETTY_NAME:-Linux}"
            echo "id=${ID:-linux}"
            echo "host=$(cat /etc/hostname 2>/dev/null || hostname)"
            echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//; s/ *$//')"
            echo "cores=$(nproc)"
            echo "mem=$(awk '/MemTotal/ {printf "%.0f GB", $2/1048576}' /proc/meminfo)"
            echo "gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d' | head -1 | sed 's/.*: //; s/ (rev .*//')"
            echo "kernel=$(uname -r)"
            echo "up=$(uptime -p 2>/dev/null | sed 's/^up //')"
            echo "disk=$(df -h --output=avail,size / | tail -1 | awk '{print $1 " available of " $2}')"
        "#;
        let output = capture("sh", &["-c", script]);
        let mut info = std::collections::BTreeMap::new();
        for line in output.lines() {
            if let Some((key, value)) = line.split_once('=') {
                info.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
        let host = info.get("host").cloned().unwrap_or_default();
        let os = info.get("os").cloned().unwrap_or_default();
        let logo = match info.get("id").map(String::as_str) {
            Some("fedora") => "\u{f30a}",
            Some("arch" | "cachyos" | "endeavouros" | "manjaro") => "\u{f303}",
            Some("debian") => "\u{f306}",
            Some("ubuntu") => "\u{f31b}",
            Some("nixos") => "\u{f313}",
            Some("opensuse" | "opensuse-tumbleweed") => "\u{f314}",
            Some("gentoo") => "\u{f30d}",
            Some("void") => "\u{f32e}",
            _ => "\u{f17c}",
        };
        let hero = gtk::Box::new(gtk::Orientation::Horizontal, 18);
        hero.add_css_class("about-hero");
        let badge = colored_glyph(logo, "#0a84ff", 34);
        badge.set_size_request(58, 58);
        badge.set_halign(gtk::Align::Center);
        badge.set_valign(gtk::Align::Center);
        let badge_holder = gtk::Box::new(gtk::Orientation::Vertical, 0);
        badge_holder.add_css_class("about-badge");
        badge_holder.set_size_request(58, 58);
        badge_holder.append(&badge);
        hero.append(&badge_holder);
        let names = gtk::Box::new(gtk::Orientation::Vertical, 2);
        names.set_valign(gtk::Align::Center);
        let name = ui::label(
            if host.is_empty() {
                "This computer"
            } else {
                &host
            },
            "pane-title",
        );
        let system = ui::label(&os, "muted");
        names.append(&name);
        names.append(&system);
        hero.append(&names);
        self.content.append(&hero);

        let mut rows = Vec::new();
        let fields = [
            ("Name", host.clone()),
            (
                "Processor",
                info.get("cpu").map_or_else(String::new, |cpu| {
                    let cores = info.get("cores").map_or("", String::as_str);
                    format!("{cpu} ({cores} threads)")
                }),
            ),
            ("Graphics", info.get("gpu").cloned().unwrap_or_default()),
            ("Memory", info.get("mem").cloned().unwrap_or_default()),
            ("Storage", info.get("disk").cloned().unwrap_or_default()),
            ("Operating system", os.clone()),
            ("Kernel", info.get("kernel").cloned().unwrap_or_default()),
            ("Uptime", info.get("up").cloned().unwrap_or_default()),
        ];
        for (label, value) in fields {
            if value.is_empty() {
                continue;
            }
            let text = ui::label(&value, "row-sub");
            text.set_ellipsize(gtk::pango::EllipsizeMode::End);
            text.set_max_width_chars(48);
            rows.push(self.custom_row(label, "", Some(text.upcast())));
        }
        self.add_group("About", "", rows);
    }

    fn build_sound(&mut self) {
        let info = capture("pactl", &["info"]);
        if info.starts_with("pactl:") {
            self.add_group(
                "Sound",
                "",
                vec![self.custom_row("PipeWire / PulseAudio", &info, None)],
            );
            return;
        }
        let default_sink = info
            .lines()
            .find_map(|line| line.strip_prefix("Default Sink: ").map(str::to_string))
            .unwrap_or_default();
        let default_source = info
            .lines()
            .find_map(|line| line.strip_prefix("Default Source: ").map(str::to_string))
            .unwrap_or_default();
        let volume = first_percent(&capture("pactl", &["get-sink-volume", "@DEFAULT_SINK@"]));
        let muted = capture("pactl", &["get-sink-mute", "@DEFAULT_SINK@"]).contains("yes");
        let input_volume = first_percent(&capture(
            "pactl",
            &["get-source-volume", "@DEFAULT_SOURCE@"],
        ));
        let input_muted =
            capture("pactl", &["get-source-mute", "@DEFAULT_SOURCE@"]).contains("yes");

        let mut output_rows = Vec::new();
        let value = ui::label(&format!("{volume:.0}%"), "row-sub");
        value.set_size_request(46, -1);
        value.set_halign(gtk::Align::End);
        let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 100.0, 1.0);
        scale.set_value(volume);
        scale.set_draw_value(false);
        scale.set_size_request(190, -1);
        let value_label = value.clone();
        scale.connect_value_changed(move |scale| {
            let volume = scale.value().round();
            value_label.set_text(&format!("{volume:.0}%"));
            let _ = Command::new("pactl")
                .args([
                    "set-sink-volume",
                    "@DEFAULT_SINK@",
                    &format!("{volume:.0}%"),
                ])
                .output();
        });
        output_rows.push(self.control_row(
            "Output volume",
            "",
            vec![scale.upcast(), value.upcast()],
        ));
        let mute = gtk::Switch::new();
        mute.set_active(muted);
        mute.set_valign(gtk::Align::Center);
        let weak = self.weak.clone();
        mute.connect_state_set(move |_, _| {
            let _ = Command::new("pactl")
                .args(["set-sink-mute", "@DEFAULT_SINK@", "toggle"])
                .output();
            if let Some(spot) = weak.upgrade() {
                schedule_rebuild(&spot);
            }
            glib::Propagation::Proceed
        });
        output_rows.push(self.custom_row("Mute", "", Some(mute.upcast())));
        let sink_names = pactl_descriptions("sinks");
        for line in capture("pactl", &["list", "short", "sinks"]).lines() {
            let fields: Vec<&str> = line.split_whitespace().collect();
            let Some(name) = fields.get(1) else {
                continue;
            };
            let active = *name == default_sink;
            let sub = if active { "Current output" } else { "" };
            let label = sink_names.get(*name).map_or(*name, String::as_str);
            let control = if active {
                ui::label("\u{2713}", "accent-check").upcast::<gtk::Widget>()
            } else {
                let name = name.to_string();
                let weak = self.weak.clone();
                self.custom_button("Use", "plain-button", move || {
                    let _ = Command::new("pactl")
                        .args(["set-default-sink", &name])
                        .output();
                    if let Some(spot) = weak.upgrade() {
                        schedule_rebuild(&spot);
                    }
                })
            };
            output_rows.push(self.custom_row(label, sub, Some(control)));
        }
        self.add_group("Output", "", output_rows);

        let mut input_rows = Vec::new();
        let value = ui::label(&format!("{input_volume:.0}%"), "row-sub");
        value.set_size_request(46, -1);
        value.set_halign(gtk::Align::End);
        let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 100.0, 1.0);
        scale.set_value(input_volume);
        scale.set_draw_value(false);
        scale.set_size_request(190, -1);
        let value_label = value.clone();
        scale.connect_value_changed(move |scale| {
            let volume = scale.value().round();
            value_label.set_text(&format!("{volume:.0}%"));
            let _ = Command::new("pactl")
                .args([
                    "set-source-volume",
                    "@DEFAULT_SOURCE@",
                    &format!("{volume:.0}%"),
                ])
                .output();
        });
        input_rows.push(self.control_row("Input volume", "", vec![scale.upcast(), value.upcast()]));
        let mute = gtk::Switch::new();
        mute.set_active(input_muted);
        mute.set_valign(gtk::Align::Center);
        let weak = self.weak.clone();
        mute.connect_state_set(move |_, _| {
            let _ = Command::new("pactl")
                .args(["set-source-mute", "@DEFAULT_SOURCE@", "toggle"])
                .output();
            if let Some(spot) = weak.upgrade() {
                schedule_rebuild(&spot);
            }
            glib::Propagation::Proceed
        });
        input_rows.push(self.custom_row("Mute", "", Some(mute.upcast())));
        let source_names = pactl_descriptions("sources");
        for line in capture("pactl", &["list", "short", "sources"]).lines() {
            let fields: Vec<&str> = line.split_whitespace().collect();
            let Some(name) = fields.get(1) else {
                continue;
            };
            if name.ends_with(".monitor") {
                continue;
            }
            let active = *name == default_source;
            let sub = if active { "Current input" } else { "" };
            let label = source_names.get(*name).map_or(*name, String::as_str);
            let control = if active {
                ui::label("\u{2713}", "accent-check").upcast::<gtk::Widget>()
            } else {
                let name = name.to_string();
                let weak = self.weak.clone();
                self.custom_button("Use", "plain-button", move || {
                    let _ = Command::new("pactl")
                        .args(["set-default-source", &name])
                        .output();
                    if let Some(spot) = weak.upgrade() {
                        schedule_rebuild(&spot);
                    }
                })
            };
            input_rows.push(self.custom_row(label, sub, Some(control)));
        }
        self.add_group("Input", "", input_rows);
        self.add_group(
            "Applications",
            "Per-app levels stay in Control Centre for now.",
            vec![self.custom_row(
                "Application volume",
                "Open Control Centre to adjust a single app",
                None,
            )],
        );
    }

    fn build_default_apps(&mut self) {
        let script = paths::shell_dir().join("scripts/default-apps.sh");
        if !script.is_file() {
            self.add_group(
                "Default apps",
                "",
                vec![self.custom_row(
                    "Helper missing",
                    "scripts/default-apps.sh was not found",
                    None,
                )],
            );
            return;
        }
        let probes: Vec<&str> = DEFAULT_KINDS.iter().map(|kind| kind.probe).collect();
        let mut args = vec!["query".to_string()];
        args.extend(probes.iter().map(|probe| (*probe).to_string()));
        let args: Vec<&str> = args.iter().map(String::as_str).collect();
        let output = capture(script.to_string_lossy().as_ref(), &args);
        let mut state: std::collections::BTreeMap<String, (String, Vec<String>)> =
            std::collections::BTreeMap::new();
        for line in output.lines() {
            let fields: Vec<&str> = line.split('\t').collect();
            if fields.len() < 3 {
                continue;
            }
            state.insert(
                fields[0].to_string(),
                (
                    fields[1].to_string(),
                    fields[2]
                        .split(';')
                        .filter(|item| !item.is_empty())
                        .map(str::to_string)
                        .collect(),
                ),
            );
        }
        let mut rows = Vec::new();
        for kind in DEFAULT_KINDS {
            let (current, candidates) = state
                .get(kind.probe)
                .cloned()
                .unwrap_or_else(|| (String::new(), Vec::new()));
            if candidates.is_empty() && current.is_empty() {
                rows.push(self.custom_row(kind.label, "No installed app handles this", None));
                continue;
            }
            let mut options = candidates.clone();
            if !current.is_empty() && !options.iter().any(|item| item == &current) {
                options.insert(0, current.clone());
            }
            let labels: Vec<String> = options
                .iter()
                .map(|id| id.trim_end_matches(".desktop").to_string())
                .collect();
            let dropdown =
                gtk::DropDown::from_strings(&labels.iter().map(String::as_str).collect::<Vec<_>>());
            let index = options
                .iter()
                .position(|item| item == &current)
                .unwrap_or(0) as u32;
            dropdown.set_selected(index);
            dropdown.set_valign(gtk::Align::Center);
            let script = script.clone();
            let mimes: Vec<String> = kind.mimes.iter().map(|mime| (*mime).to_string()).collect();
            let weak = self.weak.clone();
            dropdown.connect_selected_notify(move |dropdown| {
                let Some(app) = options.get(dropdown.selected() as usize).cloned() else {
                    return;
                };
                let mut command = Command::new(&script);
                command.arg("set").arg(&app);
                for mime in &mimes {
                    command.arg(mime);
                }
                let _ = command.output();
                if let Some(spot) = weak.upgrade() {
                    schedule_rebuild(&spot);
                }
            });
            rows.push(self.custom_row(kind.label, "", Some(dropdown.upcast())));
        }
        self.add_group(
            "Default apps",
            "Used whenever an app opens a link or file (xdg-open).",
            rows,
        );
    }

    fn build_wifi(&mut self) {
        let radio = capture("nmcli", &["radio", "wifi"]);
        let enabled = radio.trim() == "enabled";
        let mut rows = Vec::new();
        let switch = gtk::Switch::new();
        switch.set_active(enabled);
        switch.set_valign(gtk::Align::Center);
        let weak = self.weak.clone();
        switch.connect_state_set(move |_, active| {
            let _ = Command::new("nmcli")
                .args(["radio", "wifi", if active { "on" } else { "off" }])
                .output();
            if let Some(spot) = weak.upgrade() {
                schedule_rebuild(&spot);
            }
            glib::Propagation::Proceed
        });
        rows.push(self.custom_row(
            "Wi-Fi",
            if enabled { "On" } else { "Off" },
            Some(switch.upcast()),
        ));
        if enabled {
            let list = capture(
                "nmcli",
                &[
                    "-t",
                    "-f",
                    "IN-USE,SSID,SIGNAL,SECURITY",
                    "dev",
                    "wifi",
                    "list",
                ],
            );
            let mut seen = Vec::new();
            for line in list.lines() {
                let fields = nmcli_split(line);
                if fields.len() < 4 {
                    continue;
                }
                let in_use = fields[0].trim() == "*";
                let ssid = fields[1].trim().to_string();
                if ssid.is_empty() || seen.iter().any(|item| item == &ssid) {
                    continue;
                }
                seen.push(ssid.clone());
                let signal = fields[2].trim();
                let security = fields[3].trim();
                let sub = if in_use {
                    format!("Connected · {signal}%")
                } else if security.is_empty() || security == "--" {
                    format!("Open · {signal}%")
                } else {
                    format!("{security} · {signal}%")
                };
                let control = if in_use {
                    ui::label("\u{2713}", "accent-check").upcast::<gtk::Widget>()
                } else if security.is_empty() || security == "--" {
                    let weak = self.weak.clone();
                    let ssid = ssid.clone();
                    self.custom_button("Join", "plain-button", move || {
                        let _ = Command::new("nmcli")
                            .args(["dev", "wifi", "connect", &ssid])
                            .output();
                        if let Some(spot) = weak.upgrade() {
                            schedule_rebuild(&spot);
                        }
                    })
                } else {
                    let weak = self.weak.clone();
                    let window = self.window.clone();
                    let ssid = ssid.clone();
                    self.custom_button("Join…", "plain-button", move || {
                        prompt_wifi_password(&window, &weak, &ssid);
                    })
                };
                rows.push(self.custom_row(&ssid, &sub, Some(control)));
            }
            rows.push(self.control_row(
                "Networks",
                "Scan again if a network is missing",
                vec![self.refresh_button()],
            ));
        }
        self.add_group(
            "Wi-Fi",
            if enabled {
                "Networks come from NetworkManager. A password is only needed the first time."
            } else {
                "Turn Wi-Fi on to see networks."
            },
            rows,
        );
    }

    fn build_bluetooth(&mut self) {
        let show = capture("bluetoothctl", &["show"]);
        if show.starts_with("bluetoothctl:") || show.is_empty() {
            self.add_group(
                "Bluetooth",
                "",
                vec![self.custom_row("No Bluetooth adapter found", "", None)],
            );
            return;
        }
        let powered = show.lines().any(|line| line.trim() == "Powered: yes");
        let adapter = show
            .lines()
            .find_map(|line| line.strip_prefix("Name: ").map(str::to_string))
            .unwrap_or_default();
        let mut rows = Vec::new();
        let switch = gtk::Switch::new();
        switch.set_active(powered);
        switch.set_valign(gtk::Align::Center);
        let weak = self.weak.clone();
        switch.connect_state_set(move |_, active| {
            let _ = Command::new("bluetoothctl")
                .args(["power", if active { "on" } else { "off" }])
                .output();
            if let Some(spot) = weak.upgrade() {
                schedule_rebuild(&spot);
            }
            glib::Propagation::Proceed
        });
        rows.push(
            self.custom_row(
                "Bluetooth",
                if adapter.is_empty() {
                    String::new()
                } else {
                    format!("This computer is discoverable as “{adapter}” while this pane is open")
                }
                .as_str(),
                Some(switch.upcast()),
            ),
        );
        if powered {
            let devices = capture("bluetoothctl", &["devices"]);
            let mut count = 0;
            for line in devices.lines() {
                let fields: Vec<&str> = line.splitn(3, ' ').collect();
                if fields.len() < 3 || fields[0] != "Device" {
                    continue;
                }
                let mac = fields[1];
                let name = fields[2];
                let info = capture("bluetoothctl", &["info", mac]);
                let connected = info.lines().any(|line| line.trim() == "Connected: yes");
                let paired = info.lines().any(|line| line.trim() == "Paired: yes");
                let sub = if connected {
                    "Connected"
                } else if paired {
                    "Paired · Not connected"
                } else {
                    "Not paired"
                };
                let mut controls = Vec::new();
                let weak = self.weak.clone();
                let mac_string = mac.to_string();
                controls.push(self.custom_button(
                    if connected { "Disconnect" } else { "Connect" },
                    "plain-button",
                    move || {
                        let _ = Command::new("bluetoothctl")
                            .args([
                                if connected { "disconnect" } else { "connect" },
                                &mac_string,
                            ])
                            .output();
                        if let Some(spot) = weak.upgrade() {
                            schedule_rebuild(&spot);
                        }
                    },
                ));
                if !paired {
                    let weak = self.weak.clone();
                    let mac_string = mac.to_string();
                    controls.push(self.custom_button("Pair", "plain-button", move || {
                        let _ = Command::new("bluetoothctl")
                            .args(["pair", &mac_string])
                            .output();
                        if let Some(spot) = weak.upgrade() {
                            schedule_rebuild(&spot);
                        }
                    }));
                }
                rows.push(self.control_row(name, sub, controls));
                count += 1;
                if count >= 24 {
                    break;
                }
            }
            if count == 0 {
                rows.push(self.custom_row("No devices", "Put a device in pairing mode", None));
            }
            rows.push(self.control_row(
                "Devices",
                "Scan again after pairing mode is on",
                vec![self.refresh_button()],
            ));
        }
        self.add_group(
            "Bluetooth",
            "Pairing uses the system Bluetooth agent. Some devices need a PIN or confirmation.",
            rows,
        );
    }

    fn build_network(&mut self) {
        let mut rows = Vec::new();
        let status = capture(
            "nmcli",
            &[
                "-t",
                "-f",
                "DEVICE,TYPE,STATE,CONNECTION",
                "device",
                "status",
            ],
        );
        for line in status.lines() {
            let fields = nmcli_split(line);
            if fields.len() < 4 {
                continue;
            }
            let device = fields[0].trim();
            let kind = fields[1].trim();
            let state = fields[2].trim();
            let connection = fields[3].trim();
            if device == "lo" {
                continue;
            }
            let title = match kind {
                "ethernet" => "Ethernet",
                "wifi" => "Wi-Fi",
                _ => device,
            };
            let sub = if connection.is_empty() {
                format!("{device} · {state}")
            } else {
                format!("{device} · {connection} · {state}")
            };
            let glyph = if state == "connected" {
                ui::label("\u{25cf}", "accent-check").upcast::<gtk::Widget>()
            } else {
                ui::label("\u{25cb}", "row-sub").upcast::<gtk::Widget>()
            };
            rows.push(self.custom_row(title, &sub, Some(glyph)));
        }
        let connectivity = capture("nmcli", &["networking", "connectivity"]);
        self.add_group(
            "Network",
            match connectivity.trim() {
                "full" => "Connected to the internet.",
                "portal" => "A sign-in page is blocking the internet.",
                "limited" => "Connected, with limited internet access.",
                _ => "",
            },
            rows,
        );

        let mut vpn_rows = Vec::new();
        let connections = capture(
            "nmcli",
            &["-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"],
        );
        for line in connections.lines() {
            let fields = nmcli_split(line);
            if fields.len() < 4 {
                continue;
            }
            let name = fields[0].trim();
            let uuid = fields[1].trim();
            let kind = fields[2].trim();
            if kind != "vpn" && kind != "wireguard" {
                continue;
            }
            let active = fields[3].trim() == "yes";
            let sub = if active {
                "Connected"
            } else if kind == "wireguard" {
                "WireGuard"
            } else {
                "VPN"
            };
            let switch = gtk::Switch::new();
            switch.set_active(active);
            switch.set_valign(gtk::Align::Center);
            let weak = self.weak.clone();
            let uuid = uuid.to_string();
            switch.connect_state_set(move |_, active| {
                let _ = Command::new("nmcli")
                    .args([
                        "connection",
                        if active { "up" } else { "down" },
                        "uuid",
                        &uuid,
                    ])
                    .output();
                if let Some(spot) = weak.upgrade() {
                    schedule_rebuild(&spot);
                }
                glib::Propagation::Proceed
            });
            vpn_rows.push(self.custom_row(name, sub, Some(switch.upcast())));
        }
        if vpn_rows.is_empty() {
            vpn_rows.push(self.custom_row(
                "VPN",
                "Add WireGuard or OpenVPN profiles with nmcli",
                None,
            ));
        }
        vpn_rows.push(self.control_row(
            "VPNs",
            "Import a profile with nmcli connection import",
            vec![self.refresh_button()],
        ));
        self.add_group("VPN", "", vpn_rows);
    }

    fn build_drives(&mut self) {
        let rows = vec![
            self.build_row(&Spec::Toggle {
                key: "automount",
                label: "Mount drives when plugged in",
                sub: "",
            })
            .upcast::<gtk::Widget>(),
            self.build_row(&Spec::Toggle {
                key: "automountOpen",
                label: "Open in the file manager",
                sub: "",
            })
            .upcast::<gtk::Widget>(),
            self.build_row(&Spec::Toggle {
                key: "automountNotify",
                label: "Show a notification",
                sub: "",
            })
            .upcast::<gtk::Widget>(),
        ];
        self.add_group(
            "Automount",
            "Drives you plug in are mounted under /run/media.",
            rows,
        );

        let json = capture(
            "lsblk",
            &["-J", "-o", "NAME,LABEL,SIZE,FSTYPE,MOUNTPOINT,RM,UUID"],
        );
        let value: Value = serde_json::from_str(&json).unwrap_or(Value::Null);
        let mut devices = Vec::new();
        flatten_blockdevices(&value, &mut devices);
        let mut rows = Vec::new();
        for device in devices {
            let name = device.get("name").and_then(Value::as_str).unwrap_or("");
            let fstype = device.get("fstype").and_then(Value::as_str).unwrap_or("");
            let mount = device
                .get("mountpoint")
                .and_then(Value::as_str)
                .unwrap_or("");
            if name.is_empty()
                || fstype.is_empty()
                || fstype == "swap"
                || name.starts_with("zram")
                || name.starts_with("loop")
                || mount == "/"
            {
                continue;
            }
            let label = device
                .get("label")
                .and_then(Value::as_str)
                .filter(|label| !label.is_empty())
                .unwrap_or(name);
            let size = device.get("size").and_then(Value::as_str).unwrap_or("");
            let removable = device.get("rm").and_then(Value::as_bool).unwrap_or(false);
            let uuid = device.get("uuid").and_then(Value::as_str).unwrap_or("");
            let sub = if mount.is_empty() {
                format!("{size} · {fstype} · Not mounted")
            } else {
                format!("{size} · {fstype} · {mount}")
            };
            let mut controls = Vec::new();
            let mut login = None;
            if !uuid.is_empty() {
                let switch = gtk::Switch::new();
                let mounted_at_login = self
                    .cfg
                    .get("mountAtLogin")
                    .as_array()
                    .is_some_and(|items| items.iter().any(|item| item.as_str() == Some(uuid)));
                switch.set_active(mounted_at_login);
                switch.set_valign(gtk::Align::Center);
                let weak = self.weak.clone();
                let uuid = uuid.to_string();
                switch.connect_state_set(move |_, active| {
                    if let Some(spot) = weak.upgrade() {
                        let mut state = spot.borrow_mut();
                        let mut items = state
                            .cfg
                            .get("mountAtLogin")
                            .as_array()
                            .cloned()
                            .unwrap_or_default();
                        items.retain(|item| item.as_str() != Some(uuid.as_str()));
                        if active {
                            items.push(Value::String(uuid.clone()));
                        }
                        state.cfg.set("mountAtLogin", Value::Array(items));
                        state.apply_gen = state.apply_gen.wrapping_add(1);
                        state.save_gen = state.save_gen.wrapping_add(1);
                        drop(state);
                        schedule_save(&spot);
                        schedule_rebuild(&spot);
                    }
                    glib::Propagation::Proceed
                });
                login = Some(switch.upcast::<gtk::Widget>());
            }
            if let Some(login) = login {
                controls.push(login);
            }
            let weak = self.weak.clone();
            let name_string = name.to_string();
            let mounted = !mount.is_empty();
            controls.push(self.custom_button(
                if mounted { "Unmount" } else { "Mount" },
                "plain-button",
                move || {
                    let _ = Command::new("udisksctl")
                        .args([
                            if mounted { "unmount" } else { "mount" },
                            "-b",
                            &format!("/dev/{name_string}"),
                        ])
                        .output();
                    if let Some(spot) = weak.upgrade() {
                        schedule_rebuild(&spot);
                    }
                },
            ));
            if removable {
                let weak = self.weak.clone();
                let name_string = name.to_string();
                controls.push(self.custom_button("Eject", "plain-button", move || {
                    let _ = Command::new("udisksctl")
                        .args(["power-off", "-b", &format!("/dev/{name_string}")])
                        .output();
                    if let Some(spot) = weak.upgrade() {
                        schedule_rebuild(&spot);
                    }
                }));
            }
            rows.push(self.control_row(label, &sub, controls));
        }
        if rows.is_empty() {
            rows.push(self.custom_row(
                "No other drives",
                "Your system drive isn't listed here",
                None,
            ));
        }
        rows.push(self.control_row(
            "Drives",
            "Mounting an internal drive may ask for your password",
            vec![self.refresh_button()],
        ));
        self.add_group("Drives", "", rows);
    }

    fn build_displays(&mut self) {
        let json = capture("wlr-randr", &["--json"]);
        let value: Value = serde_json::from_str(&json).unwrap_or(Value::Null);
        let Some(outputs) = value.as_array() else {
            self.add_group(
                "Displays",
                "",
                vec![self.custom_row("wlr-randr", &json, None)],
            );
            return;
        };
        let mut rows = Vec::new();
        for output in outputs {
            let name = output.get("name").and_then(Value::as_str).unwrap_or("");
            if name.is_empty()
                || !output
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(true)
            {
                continue;
            }
            let make = output.get("make").and_then(Value::as_str).unwrap_or("");
            let model = output.get("model").and_then(Value::as_str).unwrap_or("");
            let title = if model.is_empty() { name } else { model };
            let sub = if make.is_empty() {
                name.to_string()
            } else {
                format!("{make} · {name}")
            };
            rows.push(self.custom_row(title, &sub, None));
            let modes = output
                .get("modes")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let mut labels = Vec::new();
            let mut current = 0_u32;
            for (index, mode) in modes.iter().enumerate() {
                let width = mode.get("width").and_then(Value::as_i64).unwrap_or(0);
                let height = mode.get("height").and_then(Value::as_i64).unwrap_or(0);
                let refresh = mode.get("refresh").and_then(Value::as_f64).unwrap_or(0.0);
                labels.push(format!("{width} × {height} · {refresh:.0} Hz"));
                if mode
                    .get("current")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    current = index as u32;
                }
            }
            if !labels.is_empty() {
                let dropdown = gtk::DropDown::from_strings(
                    &labels.iter().map(String::as_str).collect::<Vec<_>>(),
                );
                dropdown.set_selected(current);
                dropdown.set_valign(gtk::Align::Center);
                let name = name.to_string();
                let modes = modes.clone();
                let weak = self.weak.clone();
                dropdown.connect_selected_notify(move |dropdown| {
                    let Some(mode) = modes.get(dropdown.selected() as usize) else {
                        return;
                    };
                    let width = mode.get("width").and_then(Value::as_i64).unwrap_or(0);
                    let height = mode.get("height").and_then(Value::as_i64).unwrap_or(0);
                    let refresh = mode.get("refresh").and_then(Value::as_f64).unwrap_or(0.0);
                    let _ = Command::new("wlr-randr")
                        .args([
                            "--output",
                            &name,
                            "--mode",
                            &format!("{width}x{height}@{refresh:.3}Hz"),
                        ])
                        .output();
                    if let Some(spot) = weak.upgrade() {
                        schedule_rebuild(&spot);
                    }
                });
                rows.push(self.custom_row("Resolution", "", Some(dropdown.upcast())));
            }
            let scale = output.get("scale").and_then(Value::as_f64).unwrap_or(1.0);
            let scales = [1.0, 1.25, 1.5, 1.75, 2.0];
            let labels: Vec<String> = scales
                .iter()
                .map(|scale| format!("{:.0}%", scale * 100.0))
                .collect();
            let dropdown =
                gtk::DropDown::from_strings(&labels.iter().map(String::as_str).collect::<Vec<_>>());
            let index = scales
                .iter()
                .position(|item| (item - scale).abs() < 0.01)
                .unwrap_or(0) as u32;
            dropdown.set_selected(index);
            dropdown.set_valign(gtk::Align::Center);
            let name = name.to_string();
            let weak = self.weak.clone();
            dropdown.connect_selected_notify(move |dropdown| {
                let Some(scale) = scales.get(dropdown.selected() as usize) else {
                    return;
                };
                let _ = Command::new("wlr-randr")
                    .args(["--output", &name, "--scale", &format!("{scale}")])
                    .output();
                if let Some(spot) = weak.upgrade() {
                    schedule_rebuild(&spot);
                }
            });
            rows.push(self.custom_row("Scale", "", Some(dropdown.upcast())));
        }
        rows.push(self.control_row(
            "Displays",
            "Changes apply immediately",
            vec![self.refresh_button()],
        ));
        self.add_group(
            "Displays",
            "Unlike the QML pane, changes are not reverted automatically after 15 seconds.",
            rows,
        );
    }

    fn bar_layout(&self) -> std::collections::BTreeMap<String, Vec<String>> {
        let mut layout: std::collections::BTreeMap<String, Vec<String>> =
            std::collections::BTreeMap::new();
        let known: Vec<&str> = BAR_ITEMS.iter().map(|(id, _, _)| *id).collect();
        let value = self.cfg.get("barItems");
        if let Some(object) = value.as_object() {
            for zone in ["left", "center", "right"] {
                let items = object
                    .get(zone)
                    .and_then(Value::as_array)
                    .map(|items| {
                        items
                            .iter()
                            .filter_map(Value::as_str)
                            .filter(|id| known.contains(id))
                            .map(str::to_string)
                            .collect()
                    })
                    .unwrap_or_default();
                layout.insert(zone.to_string(), items);
            }
            return layout;
        }
        let mut left = vec!["logo".to_string()];
        if self.cfg.bool("barAppMenus", true) {
            left.push("appmenus".to_string());
        }
        let center = if self.cfg.bool("barWorkspaces", true) {
            vec!["workspaces".to_string()]
        } else {
            Vec::new()
        };
        let mut right = ["tray", "battery", "sound", "network"]
            .iter()
            .map(|id| (*id).to_string())
            .collect::<Vec<_>>();
        if self.cfg.bool("barSearch", true) {
            right.push("spotlight".to_string());
        }
        if self.cfg.bool("barWeather", true) {
            right.push("weather".to_string());
        }
        right.push("controls".to_string());
        right.push("clock".to_string());
        right.push("power".to_string());
        layout.insert("left".to_string(), left);
        layout.insert("center".to_string(), center);
        layout.insert("right".to_string(), right);
        layout
    }

    fn write_bar_layout(
        weak: &Weak<RefCell<Settings>>,
        layout: &std::collections::BTreeMap<String, Vec<String>>,
    ) {
        let Some(spot) = weak.upgrade() else {
            return;
        };
        {
            let mut state = spot.borrow_mut();
            let value = serde_json::json!({
                "left": layout.get("left").cloned().unwrap_or_default(),
                "center": layout.get("center").cloned().unwrap_or_default(),
                "right": layout.get("right").cloned().unwrap_or_default(),
            });
            state.cfg.set("barItems", value);
            state.apply_gen = state.apply_gen.wrapping_add(1);
            state.save_gen = state.save_gen.wrapping_add(1);
        }
        schedule_save(&spot);
        schedule_rebuild(&spot);
    }

    fn build_bar_items(&mut self) {
        let layout = self.bar_layout();
        let mut order: Vec<(String, String, usize)> = Vec::new();
        for zone in ["left", "center", "right"] {
            if let Some(items) = layout.get(zone) {
                for (index, id) in items.iter().enumerate() {
                    order.push((id.clone(), zone.to_string(), index));
                }
            }
        }
        for (id, _, _) in BAR_ITEMS {
            if !order.iter().any(|(item, _, _)| item == id) {
                order.push(((*id).to_string(), String::new(), 0));
            }
        }
        let mut rows = Vec::new();
        for (id, zone, index) in order {
            let Some((_, label, sub)) = BAR_ITEMS.iter().find(|(item, _, _)| *item == id) else {
                continue;
            };
            let zone_label = match zone.as_str() {
                "left" => "Left",
                "center" => "Centre",
                "right" => "Right",
                _ => "Hidden",
            };
            let subtitle = if zone.is_empty() {
                if sub.is_empty() {
                    "Hidden".to_string()
                } else {
                    format!("Hidden · {sub}")
                }
            } else if sub.is_empty() {
                zone_label.to_string()
            } else {
                format!("{zone_label} · {sub}")
            };
            let mut controls = Vec::new();
            if !zone.is_empty() {
                let weak = self.weak.clone();
                let id_up = id.clone();
                let layout_up = layout.clone();
                let zone_up = zone.clone();
                let up = self.custom_button("\u{2191}", "plain-button", move || {
                    let mut next = layout_up.clone();
                    let Some(items) = next.get_mut(&zone_up) else {
                        return;
                    };
                    if index > 0 {
                        items.swap(index, index - 1);
                    }
                    Self::write_bar_layout(&weak, &next);
                });
                if index == 0 {
                    up.set_sensitive(false);
                }
                controls.push(up);
                let weak = self.weak.clone();
                let layout_down = layout.clone();
                let zone_down = zone.clone();
                let count = layout.get(&zone).map_or(0, Vec::len);
                let down = self.custom_button("\u{2193}", "plain-button", move || {
                    let mut next = layout_down.clone();
                    let Some(items) = next.get_mut(&zone_down) else {
                        return;
                    };
                    if index + 1 < items.len() {
                        items.swap(index, index + 1);
                    }
                    Self::write_bar_layout(&weak, &next);
                });
                if index + 1 >= count {
                    down.set_sensitive(false);
                }
                controls.push(down);
                let _ = id_up;
            }
            let zones = ["Left", "Centre", "Right", "Hidden"];
            let dropdown = gtk::DropDown::from_strings(&zones);
            dropdown.set_selected(match zone.as_str() {
                "left" => 0,
                "center" => 1,
                "right" => 2,
                _ => 3,
            });
            dropdown.set_valign(gtk::Align::Center);
            let weak = self.weak.clone();
            let layout_choice = layout.clone();
            let id_choice = id.clone();
            let current_zone = zone.clone();
            dropdown.connect_selected_notify(move |dropdown| {
                let target = match dropdown.selected() {
                    0 => "left",
                    1 => "center",
                    2 => "right",
                    _ => "",
                };
                if target == current_zone {
                    return;
                }
                let mut next = layout_choice.clone();
                for zone in ["left", "center", "right"] {
                    if let Some(items) = next.get_mut(zone) {
                        items.retain(|item| item != &id_choice);
                    }
                }
                if !target.is_empty() {
                    next.entry(target.to_string())
                        .or_default()
                        .push(id_choice.clone());
                }
                Self::write_bar_layout(&weak, &next);
            });
            controls.push(dropdown.upcast());
            rows.push(self.control_row(label, &subtitle, controls));
        }
        let weak = self.weak.clone();
        let reset = self.custom_button("Reset", "plain-button", move || {
            let mut layout = std::collections::BTreeMap::new();
            layout.insert(
                "left".to_string(),
                vec!["logo".to_string(), "appmenus".to_string()],
            );
            layout.insert("center".to_string(), vec!["workspaces".to_string()]);
            layout.insert(
                "right".to_string(),
                vec![
                    "tray",
                    "battery",
                    "sound",
                    "network",
                    "spotlight",
                    "weather",
                    "controls",
                    "clock",
                    "power",
                ]
                .iter()
                .map(|id| (*id).to_string())
                .collect(),
            );
            Self::write_bar_layout(&weak, &layout);
        });
        rows.push(self.control_row(
            "Default layout",
            "Logo and app menus on the left, workspaces in the centre, everything else on the right",
            vec![reset],
        ));
        self.add_group(
            "Menu Bar Items",
            "Switch items on or off, choose Left, Centre or Right, and use the arrows to reorder them within their zone. Hidden items stay reachable with Spotlight and the keyboard shortcuts.",
            rows,
        );
    }

    fn build_widget_arranging(&mut self) {
        let edit = self.custom_button("Edit Widgets…", "accent-button", || {
            let _ = system::spawn("qs", &["-c", "island", "ipc", "call", "widgets", "edit"]);
        });
        let reset = self.custom_button("Reset", "plain-button", || {
            let _ = system::spawn("qs", &["-c", "island", "ipc", "call", "widgets", "reset"]);
        });
        self.add_group(
            "Arrangement",
            "Or just drag a widget on the desktop. Widgets you haven't moved stack in the chosen corner.",
            vec![
                self.control_row(
                    "Arrange widgets",
                    "Open the desktop editor",
                    vec![edit],
                ),
                self.control_row("Widget positions", "Stack them in the corner again", vec![reset]),
            ],
        );
    }

    fn build_theme_cards(&mut self) {
        let (ids, labels) = theme_choices();
        if ids.is_empty() {
            return;
        }
        let caption = ui::label("Themes", "section");
        caption.set_margin_start(12);
        caption.set_margin_top(8);
        self.content.append(&caption);
        let flow = gtk::FlowBox::new();
        flow.set_selection_mode(gtk::SelectionMode::None);
        flow.set_column_spacing(12);
        flow.set_row_spacing(12);
        flow.set_margin_start(4);
        flow.set_margin_end(4);
        flow.set_margin_top(2);
        flow.set_margin_bottom(4);
        flow.set_max_children_per_line(4);
        flow.set_min_children_per_line(2);
        flow.set_homogeneous(true);
        let current = paths::theme_id();
        for (index, (id, label)) in ids.iter().zip(labels.iter()).enumerate() {
            let path = paths::themes_dir().join(format!("{id}.json"));
            let theme = std::fs::read_to_string(&path)
                .ok()
                .and_then(|text| serde_json::from_str::<Value>(&text).ok())
                .unwrap_or(Value::Null);
            let bg = theme.get("bg").and_then(Value::as_str).unwrap_or("#1c1c1e");
            let fg = theme.get("fg").and_then(Value::as_str).unwrap_or("#ffffff");
            let surface = theme
                .get("surface")
                .and_then(Value::as_str)
                .unwrap_or("#2c2c2e");
            let overlay = theme
                .get("overlay")
                .and_then(Value::as_str)
                .unwrap_or("#3a3a3c");
            let accent = theme
                .get("accent")
                .and_then(Value::as_str)
                .unwrap_or("#0a84ff");
            let button = gtk::Button::new();
            let class = format!("theme-card-{index}");
            button.add_css_class("theme-card");
            button.add_css_class(&class);
            button.set_size_request(150, 96);
            let provider = gtk::CssProvider::new();
            provider.load_from_data(&format!(
                ".{class} {{ background: {bg}; color: {fg}; border: 1px solid {overlay}; border-radius: 10px; padding: 8px; }} .{class}:hover {{ border-color: {accent}; }}"
            ));
            if let Some(display) = gdk::Display::default() {
                gtk::style_context_add_provider_for_display(
                    &display,
                    &provider,
                    gtk::STYLE_PROVIDER_PRIORITY_USER,
                );
            }
            let col = gtk::Box::new(gtk::Orientation::Vertical, 6);
            let mini = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            mini.add_css_class("theme-mini");
            mini.set_size_request(-1, 42);
            let mini_provider = gtk::CssProvider::new();
            let mini_class = format!("theme-mini-{index}");
            mini.add_css_class(&mini_class);
            mini_provider.load_from_data(&format!(
                ".{mini_class} {{ background: {surface}; border: 1px solid {overlay}; border-radius: 6px; }}"
            ));
            if let Some(display) = gdk::Display::default() {
                gtk::style_context_add_provider_for_display(
                    &display,
                    &mini_provider,
                    gtk::STYLE_PROVIDER_PRIORITY_USER,
                );
            }
            let bar = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            bar.set_size_request(-1, 8);
            let bar_provider = gtk::CssProvider::new();
            let bar_class = format!("theme-bar-{index}");
            bar.add_css_class(&bar_class);
            bar_provider.load_from_data(&format!(
                ".{bar_class} {{ background: {accent}; border-radius: 4px; }}"
            ));
            if let Some(display) = gdk::Display::default() {
                gtk::style_context_add_provider_for_display(
                    &display,
                    &bar_provider,
                    gtk::STYLE_PROVIDER_PRIORITY_USER,
                );
            }
            let bar_holder = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            bar_holder.set_margin_top(6);
            bar_holder.set_margin_start(8);
            bar_holder.set_margin_end(8);
            bar_holder.append(&bar);
            mini.append(&bar_holder);
            col.append(&mini);
            let name = ui::label(label, "row-title");
            name.set_ellipsize(gtk::pango::EllipsizeMode::End);
            col.append(&name);
            button.set_child(Some(&col));
            if id == &current {
                button.add_css_class("theme-card-active");
            }
            let weak = self.weak.clone();
            let id = id.clone();
            button.connect_clicked(move |_| {
                apply_theme(&weak, &id);
            });
            flow.insert(&button, -1);
        }
        self.content.append(&flow);
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
                self.set_page(page.to_string());
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

fn spec_visible(key: &str, cfg: &impl island_rust::config::SettingsRead) -> bool {
    let layout = cfg.string("shellLayout", "menubar");
    let skin = cfg.string("barSkin", "classic");
    match key {
        "barSkin" => layout == "menubar",
        "taskbarHeight" => layout != "menubar",
        "taskbarMagnify" | "taskbarBounce" => layout == "taskbar",
        "taskbarMagnifySize" => layout == "taskbar" && cfg.bool("taskbarMagnify", true),
        "compactIconSize" | "compactStats" => layout == "compact",
        "desktopIconsApps" | "desktopIconSize" => cfg.bool("desktopIcons", false),
        "iconTint" => cfg.string("iconStyle", "default") == "tinted",
        "spotlightFromCapsule" => {
            layout == "menubar"
                && (skin == "island" || skin == "notch")
                && cfg.string("spotlightStyle", "auto") == "auto"
        }
        "barWorkspaceStyle" | "barWorkspaceCount" => cfg.bool("barWorkspaces", true),
        "blurSize" | "blurPasses" => cfg.bool("blur", true),
        "animCurve" | "animSpeed" | "windowAnim" | "workspaceAnim" => cfg.bool("animations", true),
        "dockSize" | "dockMagnify" | "dockAutohide" | "dockAllScreens" | "dockOpacity"
        | "dockMargin" => cfg.bool("dock", true),
        "dockMagnifySize" => cfg.bool("dock", true) && cfg.bool("dockMagnify", true),
        "widgetStyle" | "widgetColors" | "widgetsOpacity" | "widgetClock" | "widgetWeather"
        | "widgetCalendar" | "widgetMusic" | "widgetSystem" | "widgetVerse" | "widgetsPosition"
        | "widgetsMargin" | "widgetsAllScreens" => cfg.bool("widgets", true),
        "widgetClockSeconds" => cfg.bool("widgets", true) && cfg.bool("widgetClock", true),
        _ => true,
    }
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
        | Spec::Options { label, .. }
        | Spec::Text { label, .. }
        | Spec::Button { label, .. } => label,
        Spec::Secret { label, .. } => label,
        Spec::Info { label, .. } => label,
        Spec::Themes => "Theme",
        Spec::Accents => "Accent colour",
    }
}

fn spec_sub(spec: &Spec) -> &'static str {
    match spec {
        Spec::Toggle { sub, .. }
        | Spec::Slider { sub, .. }
        | Spec::Choice { sub, .. }
        | Spec::Options { sub, .. }
        | Spec::Text { sub, .. }
        | Spec::Button { sub, .. } => sub,
        Spec::Secret { sub, .. } => sub,
        Spec::Info { .. } => "",
        Spec::Themes => "The palette used across the desktop",
        Spec::Accents => "Selection, focus and progress",
    }
}

fn spec_key(spec: &Spec) -> &'static str {
    match spec {
        Spec::Toggle { key, .. }
        | Spec::Slider { key, .. }
        | Spec::Choice { key, .. }
        | Spec::Options { key, .. }
        | Spec::Text { key, .. } => key,
        Spec::Themes => "theme",
        Spec::Accents => "accentColor",
        Spec::Secret { .. } | Spec::Info { .. } | Spec::Button { .. } => "",
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
                | Spec::Options { key, .. }
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

fn theme_dirs() -> Vec<PathBuf> {
    let home = paths::home();
    vec![
        home.join(".themes"),
        home.join(".local/share/themes"),
        PathBuf::from("/usr/share/themes"),
    ]
}

fn theme_names(kind: &str) -> Vec<(String, String)> {
    let skip = [
        "hicolor",
        "locolor",
        "default",
        "Default",
        "Emacs",
        "Island",
        "Island-dark",
    ];
    let mut out = Vec::new();
    for dir in theme_dirs() {
        let Ok(entries) = std::fs::read_dir(dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            if skip.contains(&name) || out.iter().any(|(value, _)| value == name) {
                continue;
            }
            let ok = match kind {
                "gtk" => path.join("gtk-3.0").is_dir(),
                "cursor" => path.join("cursors").is_dir(),
                "icon" => std::fs::read_to_string(path.join("index.theme")).is_ok_and(|text| {
                    text.lines()
                        .any(|line| line.starts_with("Directories=") && line.len() > 13)
                }),
                _ => false,
            };
            if ok {
                out.push((name.to_string(), name.to_string()));
            }
        }
    }
    out.sort_by_key(|(_, label)| label.to_lowercase());
    out
}

fn gtk_theme_options() -> Vec<(String, String)> {
    let mut out = vec![(
        "auto".to_string(),
        "Island (adw-gtk3, follows theme)".to_string(),
    )];
    out.extend(theme_names("gtk"));
    out
}

fn icon_theme_options() -> Vec<(String, String)> {
    theme_names("icon")
}

fn cursor_theme_options() -> Vec<(String, String)> {
    theme_names("cursor")
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
        if state.cfg.set(key, value) {
            state.apply_gen = state.apply_gen.wrapping_add(1);
            state.save_gen = state.save_gen.wrapping_add(1);
        }
    }
    schedule_save(&spot);
    if matches!(
        key,
        "accentColor"
            | "textColor"
            | "liquidGlass"
            | "shellLayout"
            | "barSkin"
            | "spotlightStyle"
            | "iconStyle"
            | "dock"
            | "dockMagnify"
            | "widgets"
            | "widgetClock"
            | "blur"
            | "animations"
            | "barWorkspaces"
            | "desktopIcons"
            | "taskbarMagnify"
    ) {
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

fn install_settings_watch(spot: &Rc<RefCell<Settings>>) {
    let path = paths::settings_file();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let file = gtk::gio::File::for_path(&path);
    let Ok(monitor) = file.monitor_file(
        gtk::gio::FileMonitorFlags::empty(),
        None::<&gtk::gio::Cancellable>,
    ) else {
        return;
    };
    let weak = Rc::downgrade(spot);
    monitor.connect_changed(move |_, _, _, _| {
        schedule_reload(&weak);
    });
    spot.borrow_mut().monitor = Some(monitor);
}

fn schedule_reload(weak: &Weak<RefCell<Settings>>) {
    let weak = weak.clone();
    glib::timeout_add_local_once(Duration::from_millis(150), move || {
        let Some(spot) = weak.upgrade() else {
            return;
        };
        let changed = spot.borrow_mut().cfg.replace_from_disk();
        if changed {
            schedule_rebuild(&spot);
        }
    });
}

fn schedule_save(spot: &Rc<RefCell<Settings>>) {
    let generation = spot.borrow().save_gen;
    let weak = Rc::downgrade(spot);
    glib::timeout_add_local_once(Duration::from_millis(450), move || {
        let Some(spot) = weak.upgrade() else {
            return;
        };
        if spot.borrow().save_gen != generation {
            return;
        }
        let ok = spot.borrow().cfg.save().is_ok();
        if ok {
            system::apply_settings();
        }
    });
}

fn button_action(weak: &Weak<RefCell<Settings>>, action: Btn) {
    match action {
        Btn::ClearHistory => {
            History::load().clear();
        }
        Btn::ScreenshotToolbar => {
            let _ = system::spawn(
                "qs",
                &["-c", "island", "ipc", "call", "screenshot", "toolbar"],
            );
        }
        Btn::ResetAll => {
            if let Some(spot) = weak.upgrade() {
                let keys = spot.borrow().cfg.default_keys();
                let refs: Vec<&str> = keys.iter().map(String::as_str).collect();
                {
                    let mut state = spot.borrow_mut();
                    state.cfg.reset(&refs);
                    state.apply_gen = state.apply_gen.wrapping_add(1);
                    state.save_gen = state.save_gen.wrapping_add(1);
                }
                schedule_save(&spot);
                schedule_rebuild(&spot);
            }
        }
        Btn::WallpaperPicker => {
            let _ = system::spawn(
                "qs",
                &["-c", "island", "ipc", "call", "picker", "wallpapers"],
            );
        }
    }
}

fn wallhaven_key_path() -> PathBuf {
    paths::config_dir().join("island/wallhaven-api-key")
}

fn read_wallhaven_key() -> String {
    std::fs::read_to_string(wallhaven_key_path())
        .map(|text| {
            text.lines()
                .filter(|line| !line.trim_start().starts_with('#'))
                .collect::<String>()
                .trim()
                .to_string()
        })
        .unwrap_or_default()
}

fn save_wallhaven_key(key: &str) {
    use std::os::unix::fs::OpenOptionsExt;

    let path = wallhaven_key_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    let result = std::fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&tmp)
        .and_then(|mut file| {
            use std::io::Write as _;
            file.write_all(format!("{}\n", key.trim()).as_bytes())?;
            file.sync_all()
        })
        .and_then(|()| std::fs::rename(&tmp, &path));
    if let Err(error) = result {
        eprintln!("island-settings: could not save Wallhaven key: {error}");
    }
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
