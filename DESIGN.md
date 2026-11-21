# Island design direction

Status: draft written from the shell as it is on 2026-11-21. The owner hasn't signed it off yet.
Change anything here that doesn't match how you want Island to look.

Dial: ENERGY 1 / RHYTHM 1 / MOTION 2

## Identity

A macOS-feeling desktop on Linux that takes on whatever colour theme is active. The shell is
furniture: it should stay out of the way of the apps and the wallpaper. Every app it can reach
(GTK, Qt, terminals, browsers, Discord, Cider, Steam, VSCodium) gets the same palette, so the whole
desktop reads as one surface rather than a shell sitting on top of mismatched apps.

Personality: quiet, flat, tidy. Closer to a well-set-up Mac than to a riced screenshot.

## Palette

Colours always come from the active theme (`themes/<id>.json`), never hard-coded. Roles:

| Role | Use |
|---|---|
| `bg` | windows, bars, the main surface everywhere |
| `bg_alt` | browser frame, sidebars that need to step back |
| `surface` | raised things: menus, search fields, cards |
| `overlay` | hairlines, separators, slider tracks |
| `fg` / `fg_dim` / `fg_faint` | text, secondary text, disabled and scrollbars |
| `accent` + `accent_fg` | the one highlight: selection, focus, the active workspace, progress |
| red … cyan | status only (errors, battery, terminal colours), never decoration |

One accent, used where the user's attention belongs. Album-art or app-supplied colours get
overridden with the palette (Cider's Immersive view, Brave's new-tab page).

## Typography

- UI text: Adwaita Sans (setting `widgetFont`). It matches GTK 4 / libadwaita apps, so the shell
  and the apps share one typeface.
- Glyphs: JetBrainsMono Nerd Font, for icons only, never for running text.
- Sentence case everywhere. No wide-tracked uppercase labels.

## Shape and surface

- Flat. Borders off (`borderSize` 0), gaps 16 px, window rounding 12 px.
- Menus follow macOS metrics: 22 px rows, 5 px selection inset, 4 px selection corners.
- Hairlines separate; shadows are rare (Classic widgets only).
- Blur and glass are compositor-side and optional ("Liquid glass"), not the default character.

## Motion

- Purpose only: the Dock magnifies and bounces on launch, menus and overlays fade.
- Full-screen fades and scales belong to the compositor (layer rules), not Qt. Island runs on the
  software renderer to save ~180 MB of RAM, so Qt-side animation of big surfaces is off the table.
- Nothing loops forever. The video wallpaper pauses on any monitor that has a visible window.

## Constraints

- Memory first: popouts only exist while open.
- Must keep working on Hyprland, niri, Sway and Mango.
- More choice beats replacement: when the owner asks for a "revamp" of a feature, add options and
  keep the old ones.
