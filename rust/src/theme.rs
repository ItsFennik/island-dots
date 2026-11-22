use crate::config::Config;
use crate::paths;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Clone, Debug)]
pub struct Theme {
    pub id: String,
    pub dark: bool,
    pub bg: String,
    pub bg_alt: String,
    pub surface: String,
    pub overlay: String,
    pub fg: String,
    pub fg_dim: String,
    pub fg_faint: String,
    pub accent: String,
    pub accent_fg: String,
    pub red: String,
    pub green: String,
    pub yellow: String,
    pub blue: String,
    pub magenta: String,
    pub cyan: String,
    pub font: String,
    pub font_weight: i32,
    pub liquid: bool,
}

fn pick(map: &BTreeMap<String, Value>, key: &str, fallback: &str) -> String {
    map.get(key)
        .and_then(Value::as_str)
        .filter(|s| s.starts_with('#') && (s.len() == 7 || s.len() == 9))
        .map(str::to_string)
        .unwrap_or_else(|| fallback.to_string())
}

fn rgb(hex: &str) -> Option<(u8, u8, u8)> {
    let hex = hex.trim_start_matches('#');
    if hex.len() < 6 {
        return None;
    }
    let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
    let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
    let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
    Some((r, g, b))
}

pub fn rgba(hex: &str, alpha: f64) -> String {
    match rgb(hex) {
        Some((r, g, b)) => format!("rgba({}, {}, {}, {:.3})", r, g, b, alpha.clamp(0.0, 1.0)),
        None => format!("rgba(128, 128, 128, {:.3})", alpha.clamp(0.0, 1.0)),
    }
}

pub fn mix(a: &str, b: &str, t: f64) -> String {
    let (Some(a), Some(b)) = (rgb(a), rgb(b)) else {
        return a.to_string();
    };
    let t = t.clamp(0.0, 1.0);
    let c = |x: u8, y: u8| (x as f64 * (1.0 - t) + y as f64 * t).round() as u8;
    format!("#{:02x}{:02x}{:02x}", c(a.0, b.0), c(a.1, b.1), c(a.2, b.2))
}

impl Theme {
    pub fn load(cfg: &Config) -> Self {
        let id = paths::theme_id();
        let map = match paths::load_json(&paths::themes_dir().join(format!("{id}.json"))) {
            Some(Value::Object(map)) => map.into_iter().collect::<BTreeMap<_, _>>(),
            _ => BTreeMap::new(),
        };
        let dark = map.get("dark").and_then(Value::as_bool).unwrap_or(true);
        let mut fg = pick(&map, "fg", if dark { "#f2f2f2" } else { "#1c1c1e" });
        let mut fg_dim = pick(&map, "fg_dim", if dark { "#8a8a8a" } else { "#6e6e73" });
        let mut fg_faint = pick(&map, "fg_faint", if dark { "#4a4a4a" } else { "#b0b0b5" });
        match cfg.string("textColor", "auto").as_str() {
            "white" => {
                fg = "#ffffff".into();
                fg_dim = rgba("#ffffff", 0.62);
                fg_faint = rgba("#ffffff", 0.36);
            }
            "black" => {
                fg = "#000000".into();
                fg_dim = rgba("#000000", 0.62);
                fg_faint = rgba("#000000", 0.36);
            }
            _ => {}
        }
        let accent_override = cfg.string("accentColor", "");
        let accent = if accent_override.is_empty() {
            pick(&map, "accent", if dark { "#dddddd" } else { "#0a84ff" })
        } else {
            accent_override
        };
        let accent_fg = pick(&map, "accent_fg", if dark { "#0a0a0a" } else { "#ffffff" });
        Self {
            id,
            dark,
            bg: pick(&map, "bg", if dark { "#0a0a0a" } else { "#f5f5f7" }),
            bg_alt: pick(&map, "bg_alt", if dark { "#050505" } else { "#ececef" }),
            surface: pick(&map, "surface", if dark { "#161616" } else { "#ffffff" }),
            overlay: pick(&map, "overlay", if dark { "#2a2a2a" } else { "#d1d1d6" }),
            fg,
            fg_dim,
            fg_faint,
            accent,
            accent_fg,
            red: pick(&map, "red", "#ff453a"),
            green: pick(&map, "green", "#30d158"),
            yellow: pick(&map, "yellow", "#ffd60a"),
            blue: pick(&map, "blue", "#0a84ff"),
            magenta: pick(&map, "magenta", "#bf5af2"),
            cyan: pick(&map, "cyan", "#64d2ff"),
            font: cfg.string("widgetFont", "Adwaita Sans"),
            font_weight: cfg.i64("widgetFontWeight", 400) as i32,
            liquid: cfg.bool("liquidGlass", false),
        }
    }

    pub fn menu_bg(&self) -> String {
        if self.liquid {
            if self.dark {
                "rgba(28, 28, 31, 0.46)".into()
            } else {
                "rgba(250, 250, 252, 0.48)".into()
            }
        } else if self.dark {
            "rgba(42, 42, 45, 0.94)".into()
        } else {
            "rgba(244, 244, 246, 0.96)".into()
        }
    }

    pub fn card(&self) -> String {
        if self.dark {
            rgba(&self.fg, 0.055)
        } else {
            "rgba(255, 255, 255, 0.78)".into()
        }
    }

    pub fn css(&self) -> String {
        let hairline = rgba(&self.fg, 0.09);
        let hover = rgba(&self.fg, 0.07);
        let card = self.card();
        let spot_bg = rgba(&self.bg, if self.liquid { 0.55 } else { 0.86 });
        let spot_rim = if self.liquid {
            rgba("#ffffff", if self.dark { 0.26 } else { 0.7 })
        } else {
            rgba(&self.fg, 0.14)
        };
        let row_selected = rgba(&self.fg, 0.10);
        let capsule_fill = if self.dark {
            "#000000".to_string()
        } else {
            self.bg.clone()
        };
        format!(
            r#"
window {{ background: transparent; }}
.root {{ background: transparent; }}
.settings-shell {{ background: {bg}; border-radius: 14px; border: 1px solid {hairline}; }}
.spot-card {{ background: {spot_bg}; border-radius: 14px; border: 1px solid {spot_rim}; }}
.spot-card.morph {{ background: {capsule_fill}; border: none; border-radius: 15px; }}
.spot-card.morph.notch {{ border-radius: 0 0 18px 18px; }}
.spot-card.morph.grown {{ border-radius: 26px; }}
.spot-card.morph.notch.grown {{ border-radius: 0 0 26px 26px; }}
.traffic-close {{ background: {red}; color: rgba(0, 0, 0, 0.62); min-width: 13px; min-height: 13px; min-width: 13px; border-radius: 7px; padding: 0; font-size: 9px; }}
.traffic-close:hover {{ background: {red_hover}; }}
.sidebar {{ background: {sidebar}; border-right: 1px solid {hairline}; border-radius: 13px 0 0 13px; }}
.content {{ background: {bg}; border-radius: 0 13px 13px 0; }}
.toolbar {{ background: {bg}; border-bottom: 1px solid {hairline}; }}
.title {{ color: {fg}; font-size: 21px; font-weight: 700; }}
.pane-title {{ color: {fg}; font-size: 22px; font-weight: 700; }}
.row-title {{ color: {fg}; font-size: 13px; font-weight: 500; }}
.row-title.calc {{ font-size: 17px; }}
.row-title.asking {{ color: {red}; }}
.row-sub.asking {{ color: {red_dim}; }}
.glyph-badge.asking {{ background: {red_soft}; }}
.row-sub {{ color: {fg_dim}; font-size: 11px; }}
.muted {{ color: {fg_dim}; font-size: 12px; }}
.faint {{ color: {fg_faint}; font-size: 11px; }}
.section {{ color: {fg_dim}; font-size: 11px; font-weight: 600; }}
.sidebar-row {{ background: transparent; border-radius: 9px; padding: 6px 8px; }}
.sidebar-row:hover {{ background: {hover}; }}
.sidebar-row.active {{ background: {accent_soft}; }}
.sidebar-row.active label {{ color: {fg}; font-weight: 600; }}
.group-card {{ background: {card}; border: 1px solid {hairline}; border-radius: 12px; }}
.setting-row {{ padding: 11px 14px; }}
.row-sep {{ background: {hairline}; min-height: 1px; }}
.search {{ background: {search}; border-radius: 9px; border: 1px solid {hairline}; min-height: 30px; }}
.spot-entry {{ background: transparent; border: none; box-shadow: none; padding: 0; min-height: 0; font-size: 17px; color: {fg}; caret-color: {fg}; }}
.spot-entry:focus {{ box-shadow: none; }}
.spot-prompt {{ color: {fg_dim}; font-size: 16px; }}
.spot-icon {{ color: {fg}; font-size: 15px; }}
.spot-list {{ background: transparent; }}
.spot-list row {{ background: transparent; padding: 0; margin: 0; border-radius: 0; min-height: 0; outline: none; }}
.spot-list row:hover {{ background: transparent; }}
.spot-list row:selected {{ background: transparent; }}
.spot-row {{ background: transparent; border-radius: 8px; }}
.spot-list row:selected .spot-row {{ background: {row_selected}; }}
.spot-list row.section-row {{ background: transparent; min-height: 26px; }}
.spot-list row.section-row label {{ color: {fg_faint}; font-size: 10px; font-weight: 600; }}
.glyph-badge {{ background: {glyph_bg}; border-radius: 14px; min-width: 28px; min-height: 28px; }}
.enter-chip {{ background: {chip}; border-radius: 5px; min-width: 26px; min-height: 20px; opacity: 0; }}
.enter-chip label {{ color: {fg_dim}; font-size: 12px; }}
.spot-list row:selected .enter-chip {{ opacity: 1; }}
.dock-chip, .pinned-chip {{ color: {fg_faint}; font-size: 10px; }}
.keycap {{ background: {chip}; color: {fg_dim}; border-radius: 4px; padding: 0 5px; min-height: 17px; font-size: 10px; }}
.keylabel {{ color: {fg_faint}; font-size: 11px; }}
.footer-status {{ color: {fg_dim}; font-size: 11px; font-weight: 600; }}
.chip {{ background: {chip}; border-radius: 5px; padding: 1px 6px; font-size: 10px; color: {fg_dim}; }}
.accent-button {{ background: {accent}; color: {accent_fg}; border-radius: 7px; padding: 5px 12px; }}
.accent-button:hover {{ background: {accent_hover}; }}
.plain-button {{ background: {button}; color: {fg}; border-radius: 7px; padding: 5px 12px; border: 1px solid {hairline}; }}
.plain-button:hover {{ background: {hover}; }}
entry {{ background: {search}; color: {fg}; border-radius: 7px; border: 1px solid {hairline}; }}
entry:focus {{ border-color: {accent}; }}
switch {{ background: {overlay}; border-radius: 99px; }}
switch:checked {{ background: {accent}; }}
switch slider {{ background: white; }}
scale trough {{ background: {overlay}; border-radius: 99px; min-height: 5px; }}
scale highlight {{ background: {accent}; border-radius: 99px; }}
scale slider {{ background: white; border-radius: 99px; min-width: 16px; min-height: 16px; }}
dropdown button {{ background: {button}; color: {fg}; border-radius: 7px; border: 1px solid {hairline}; padding: 4px 10px; }}
dropdown popover {{ background: {sidebar}; color: {fg}; }}
"#,
            bg = self.bg,
            sidebar = if self.dark {
                rgba(&self.fg, 0.035)
            } else {
                "rgba(255, 255, 255, 0.55)".into()
            },
            hairline = hairline,
            spot_bg = spot_bg,
            spot_rim = spot_rim,
            row_selected = row_selected,
            capsule_fill = capsule_fill,
            red_dim = rgba(&self.red, 0.78),
            red_soft = rgba(&self.red, 0.18),
            glyph_bg = rgba(&self.fg, 0.12),
            fg = self.fg,
            fg_dim = self.fg_dim,
            fg_faint = self.fg_faint,
            accent = self.accent,
            accent_fg = self.accent_fg,
            accent_soft = rgba(&self.accent, if self.dark { 0.20 } else { 0.14 }),
            accent_hover = mix(&self.accent, &self.accent_fg, 0.10),
            hover = hover,
            card = card,
            search = if self.dark {
                rgba(&self.fg, 0.055)
            } else {
                rgba("#000000", 0.045)
            },
            chip = rgba(&self.fg, 0.085),
            button = if self.dark {
                rgba(&self.fg, 0.12)
            } else {
                rgba("#000000", 0.04)
            },
            overlay = rgba(&self.fg, 0.18),
            red = self.red,
            red_hover = mix(&self.red, "#ffffff", 0.12),
        )
    }

    pub fn css_common(&self) -> String {
        let font = self.font.replace('"', "");
        let weight = self.font_weight;
        format!(
            "* {{ font-family: \"{font}\"; font-weight: {weight}; }}\n{}",
            self.css()
        )
    }
}
