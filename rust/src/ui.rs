use crate::theme::Theme;
use gtk::prelude::*;

pub fn install_css(theme: &Theme) {
    let provider = gtk::CssProvider::new();
    provider.load_from_data(&theme.css_common());
    if let Some(display) = gtk::gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_USER,
        );
    }
}

pub fn label(text: &str, class: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(0.0);
    label.add_css_class(class);
    label
}

pub fn glyph(text: &str, size: i32) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(0.5);
    label.set_yalign(0.5);
    label.set_width_chars(2);
    label.set_max_width_chars(2);
    label.add_css_class("spot-icon");
    label.set_markup(&format!(
        "<span font_family=\"JetBrainsMono Nerd Font\" size=\"{}\">{}</span>",
        size * 1024,
        glib_escape(text)
    ));
    label
}

pub fn glib_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

pub fn separator() -> gtk::Box {
    let line = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    line.add_css_class("row-sep");
    line.set_height_request(1);
    line
}

pub fn monitor_for(name: Option<&str>) -> Option<gtk::gdk::Monitor> {
    let display = gtk::gdk::Display::default()?;
    let monitors = display.monitors();
    let count = monitors.n_items();
    if let Some(name) = name {
        for i in 0..count {
            let Some(monitor) = monitors
                .item(i)
                .and_then(|o| o.downcast::<gtk::gdk::Monitor>().ok())
            else {
                continue;
            };
            if monitor
                .connector()
                .is_some_and(|connector| connector.as_str() == name)
            {
                return Some(monitor);
            }
        }
    }
    monitors
        .item(0)
        .and_then(|o| o.downcast::<gtk::gdk::Monitor>().ok())
}
