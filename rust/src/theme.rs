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
        .map_or_else(|| fallback.to_string(), str::to_string)
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

#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_lossless
)]
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
                fg_dim = rgba("#ffffff", 0.60);
                fg_faint = rgba("#ffffff", 0.35);
            }
            "black" => {
                fg = "#000000".into();
                fg_dim = rgba("#000000", 0.60);
                fg_faint = rgba("#000000", 0.35);
            }
            _ => {}
        }
        let accent_override = cfg.string("accentColor", "");
        let accent_fg = if accent_override == "#ffd60a" {
            "#1c1c1e".to_string()
        } else if accent_override.is_empty() {
            pick(&map, "accent_fg", if dark { "#0a0a0a" } else { "#ffffff" })
        } else {
            "#ffffff".to_string()
        };
        let accent = if accent_override.is_empty() {
            pick(&map, "accent", if dark { "#dddddd" } else { "#0a84ff" })
        } else {
            accent_override
        };
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
            font_weight: i32::try_from(cfg.i64("widgetFontWeight", 400)).unwrap_or(400),
            liquid: cfg.bool("liquidGlass", false),
        }
    }

    pub fn menu_bg(&self) -> String {
        if self.liquid {
            if self.dark {
                "rgba(28, 28, 33, 0.46)".into()
            } else {
                "rgba(255, 255, 255, 0.48)".into()
            }
        } else if self.dark {
            "rgba(42, 42, 45, 0.80)".into()
        } else {
            "rgba(244, 244, 244, 0.82)".into()
        }
    }

    pub fn menu_edge(&self) -> String {
        if self.liquid {
            if self.dark {
                "rgba(0, 0, 0, 0.30)".into()
            } else {
                "rgba(0, 0, 0, 0.10)".into()
            }
        } else if self.dark {
            "rgba(0, 0, 0, 0.55)".into()
        } else {
            "rgba(0, 0, 0, 0.14)".into()
        }
    }

    pub fn menu_inner(&self) -> String {
        if self.liquid {
            if self.dark {
                "rgba(255, 255, 255, 0.24)".into()
            } else {
                "rgba(255, 255, 255, 0.85)".into()
            }
        } else if self.dark {
            "rgba(255, 255, 255, 0.10)".into()
        } else {
            "rgba(255, 255, 255, 0.60)".into()
        }
    }

    pub fn capsule_fill(&self) -> String {
        if self.dark {
            "#000000".into()
        } else {
            self.bg.clone()
        }
    }

    pub fn card(&self) -> String {
        if self.dark {
            rgba(&self.fg, 0.055)
        } else {
            "rgba(255, 255, 255, 0.78)".into()
        }
    }

    #[allow(clippy::too_many_lines)]
    pub fn css(&self) -> String {
        let hairline = rgba(&self.fg, 0.08);
        let hover = rgba(&self.fg, 0.06);
        let card = self.card();
        let menu_bg = self.menu_bg();
        let menu_edge = self.menu_edge();
        let menu_inner = self.menu_inner();
        let capsule_fill = self.capsule_fill();
        let base_weight = self.font_weight.clamp(100, 900);
        let medium_weight = base_weight.max(500);
        let demibold_weight = base_weight.max(600);
        let selected_text = rgba(&self.accent_fg, 0.72);
        let selected_chip = rgba(&self.accent_fg, 0.70);
        let selected_badge = rgba(&self.accent_fg, 0.18);
        format!(
            r"
window {{
    background-color: transparent;
    background-image: none;
    box-shadow: none;
}}
.root {{
    background-color: transparent;
    background-image: none;
}}
.spot-scroller, .spot-scroller > viewport {{
    background-color: transparent;
    background-image: none;
    border: none;
    box-shadow: none;
    padding: 0;
}}
.spot-menu, .spot-menu.background, .spot-menu > contents {{
    background: {menu_bg};
    border: 1px solid {menu_edge};
    border-radius: 10px;
    padding: 5px;
    box-shadow: none;
}}
.spot-menu label {{ color: {fg}; }}
.spot-menu button {{
    background: transparent;
    border: none;
    box-shadow: none;
    padding: 4px 10px;
    border-radius: 6px;
    color: {fg};
    font-size: 12px;
}}
.spot-menu button:hover {{ background: {hover}; }}
.spot-menu .ctx-header {{ color: {fg_dim}; font-size: 11px; font-weight: {demibold_weight}; padding: 4px 10px; }}
.spot-menu .ctx-sep {{ background: {hairline}; min-height: 1px; margin: 4px 6px; }}
.settings-shell {{ background: {bg}; border-radius: 14px; border: 1px solid {hairline}; }}
.spot-card {{ background: {menu_bg}; border-radius: 14px; border: 1px solid {menu_edge}; box-shadow: inset 0 0 0 1px {menu_inner}; }}
.spot-card.morph {{ background: {capsule_fill}; border: none; border-radius: 15px; box-shadow: none; }}
.spot-card.morph.notch {{ border-radius: 0 0 18px 18px; }}
.spot-card.morph.grown {{ border-radius: 26px; }}
.spot-card.morph.notch.grown {{ border-radius: 0 0 18px 18px; }}
.traffic-close {{ background: {red}; color: rgba(0, 0, 0, 0.62); min-width: 13px; min-height: 13px; min-width: 13px; border-radius: 7px; padding: 0; font-size: 9px; }}
.traffic-close:hover {{ background: {red_hover}; }}
.sidebar {{ background: {sidebar}; border-right: 1px solid {hairline}; border-radius: 13px 0 0 13px; }}
.content {{ background: {bg}; border-radius: 0 13px 13px 0; }}
.toolbar {{ background: {bg}; border-bottom: 1px solid {hairline}; }}
.title {{ color: {fg}; font-size: 21px; font-weight: 700; }}
.pane-title {{ color: {fg}; font-size: 22px; font-weight: 700; }}
.row-title {{ color: {fg}; font-size: 13px; font-weight: {medium_weight}; }}
.row-title.calc {{ font-size: 17px; }}
.row-title.asking {{ color: {red}; }}
.glyph-badge.asking {{ background: {red_soft}; }}
.row-sub {{ color: {fg_dim}; font-size: 11px; }}
.muted {{ color: {fg_dim}; font-size: 12px; }}
.faint {{ color: {fg_faint}; font-size: 11px; }}
.section {{ color: {fg_dim}; font-size: 11px; font-weight: {demibold_weight}; }}
.sidebar-row {{ background: transparent; border-radius: 9px; padding: 6px 8px; }}
.sidebar-row:hover {{ background: {hover}; }}
.sidebar-row.active {{ background: {accent_soft}; }}
.sidebar-row.active label {{ color: {fg}; font-weight: 600; }}
.group-card {{ background: {card}; border: 1px solid {hairline}; border-radius: 12px; }}
.setting-row {{ padding: 11px 14px; }}
.row-sep {{ background: {hairline}; min-height: 1px; }}
.search {{ background: {search}; border-radius: 9px; border: 1px solid {hairline}; min-height: 30px; }}
.spot-entry {{ background: transparent; border: none; box-shadow: none; outline: none; padding: 0; min-height: 0; font-size: 17px; color: {fg}; caret-color: {fg}; }}
.spot-entry:focus {{ background: transparent; border: none; box-shadow: none; outline: none; }}
.spot-placeholder-main {{ color: {fg_faint}; font-size: 17px; }}
.spot-placeholder-hint {{ color: {fg_faint}; font-size: 13px; opacity: 0.7; }}
.spot-icon {{ color: {fg}; font-size: 15px; }}
.spot-list {{ background: transparent; }}
.spot-list row {{ background: transparent; padding: 0; margin: 0; border-radius: 0; min-height: 0; outline: none; }}
.spot-list row:hover {{ background: transparent; }}
.spot-list row:selected {{ background: transparent; }}
.spot-row {{ background: transparent; border-radius: 8px; }}
.spot-list row:selected .spot-row {{ background: {accent}; }}
.spot-list row:selected .row-title {{ color: {accent_fg}; }}
.spot-list row:selected .row-title.asking {{ color: {accent_fg}; }}
.spot-list row:selected .row-sub {{ color: {selected_text}; }}
.spot-list row:selected .glyph-badge {{ background: {selected_badge}; }}
.spot-list row:selected .glyph-badge.asking {{ background: {red_soft}; }}
.spot-list row:selected .dock-chip, .spot-list row:selected .pinned-chip {{ color: {selected_chip}; }}
.spot-list row.section-row {{ background: transparent; min-height: 26px; }}
.spot-list row.section-row label {{ color: {fg_dim}; font-size: 11px; font-weight: {demibold_weight}; }}
.glyph-badge {{ background: {glyph_bg}; border-radius: 14px; min-width: 28px; min-height: 28px; }}
.enter-chip {{ background: {chip}; border-radius: 5px; min-width: 26px; min-height: 20px; opacity: 0; }}
.enter-chip label {{ color: {fg_dim}; font-size: 12px; }}
.spot-list row:selected .enter-chip {{ background: {selected_badge}; opacity: 1; }}
.spot-list row:selected .enter-chip label {{ color: {accent_fg}; }}
.dock-chip, .pinned-chip {{ color: {fg_faint}; font-size: 10px; }}
.keycap {{ background: {chip}; color: {fg_dim}; border-radius: 4px; padding: 0 5px; min-height: 17px; font-size: 10px; }}
.keylabel {{ color: {fg_faint}; font-size: 11px; }}
.footer-status {{ color: {fg_dim}; font-size: 11px; font-weight: {demibold_weight}; }}
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
",
            bg = self.bg,
            sidebar = if self.dark {
                rgba(&self.fg, 0.035)
            } else {
                "rgba(255, 255, 255, 0.55)".into()
            },
            hairline = hairline,
            menu_bg = menu_bg,
            menu_edge = menu_edge,
            menu_inner = menu_inner,
            capsule_fill = capsule_fill,
            medium_weight = medium_weight,
            demibold_weight = demibold_weight,
            selected_text = selected_text,
            selected_chip = selected_chip,
            selected_badge = selected_badge,
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
            chip = rgba(&self.fg, 0.10),
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
