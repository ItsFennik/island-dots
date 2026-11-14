-- ─────────────────────────────────────────────────────────────────────
--  Island — Hyprland glue (Lua config), loaded from hyprland.lua.
--  The bar, launcher and every menu are one Quickshell process
--  (~/.config/quickshell/island). No waybar, no fuzzel.
-- ─────────────────────────────────────────────────────────────────────

local island = "~/.config/quickshell/island"

-- ── Autostart ───────────────────────────────────────────────────────
hl.on("hyprland.start", function()
  hl.exec_cmd(island .. "/scripts/wallpaper-set.sh --restore")
  hl.exec_cmd("qs -c island -n -d")   -- bar + launcher + menus + settings
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

-- ── Keybinds (all menus grow out of the bar) ────────────────────────
local function ipc(args) return hl.dsp.exec_cmd("qs -c island ipc call " .. args) end
hl.bind("SUPER + D",             ipc("launcher toggle"))
hl.bind("SUPER + C",             ipc("menu notifs"))
hl.bind("SUPER + V",             ipc("menu clipboard"))
hl.bind("SUPER + Escape",        ipc("menu power"))
hl.bind("SUPER + W",             ipc("picker wallpapers"))
hl.bind("SUPER + ALT + W",       ipc("picker themes"))
hl.bind("SUPER + I",             ipc("settings toggle"))
hl.bind("SUPER + N",             ipc("notifs toggle"))
hl.bind("SUPER + SHIFT + N",     ipc("notifs dnd"))
hl.bind("SUPER + M",             ipc("media toggle"))
hl.bind("SUPER + A",             ipc("launchpad toggle"))
hl.bind("SUPER + CTRL + Q",      ipc("lock lock"))
hl.bind("SUPER + SHIFT + W",     hl.dsp.exec_cmd(island .. "/scripts/wallpaper-set.sh --random"))
hl.bind("SUPER + CTRL + W",      hl.dsp.exec_cmd(island .. "/scripts/wallhaven.sh random"))

-- ── Glass: blur the island ──────────────────────────────────────────
-- ignore_alpha keeps the transparent part of the bar surface from being
-- blurred, so only the pill (and whatever popout it has grown into) is frosted.
hl.layer_rule({
  name = "island-bar-blur",
  match = { namespace = "island-bar" },
  blur = true,
  ignore_alpha = 0.3,
})

-- ── Glass: blur behind the desktop widgets ──────────────────────────
hl.layer_rule({
  name = "island-widgets-blur",
  match = { namespace = "island-widgets" },
  blur = true,
  ignore_alpha = 0.05,
})

-- ── Glass: blur behind the dock ─────────────────────────────────────
hl.layer_rule({
  name = "island-dock-blur",
  match = { namespace = "island-dock" },
  blur = true,
  ignore_alpha = 0.05,
})

-- ── Glass: Spotlight and Launchpad ──────────────────────────────────
hl.layer_rule({
  name = "island-spotlight-blur",
  match = { namespace = "island-spotlight" },
  blur = true,
  ignore_alpha = 0.05,
})
hl.layer_rule({
  name = "island-launchpad-blur",
  match = { namespace = "island-launchpad" },
  blur = true,
})
-- Hyprland animates Launchpad's open/close on the GPU (Island renders on the CPU, so a
-- full-screen fade/zoom there runs at ~20 fps).
hl.layer_rule({ name = "island-launchpad-anim", match = { namespace = "island-launchpad" }, animation = "popin 94%" })

-- ── No layer animation for the menu bar and dock (they resize when menus open) ──
hl.layer_rule({ name = "island-bar-noanim", match = { namespace = "island-bar" }, no_anim = true })
hl.layer_rule({ name = "island-dock-noanim", match = { namespace = "island-dock" }, no_anim = true })
