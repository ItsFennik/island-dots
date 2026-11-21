# Dock

`dock/Dock.qml` draws the application dock: magnification, launch bounce, drag to reorder, pinning, a right-click menu, trash and optional autohide.

- Config: `dock/Dock.qml`, `services/DockPins.qml`
- Surface namespace: `island-dock`
- Settings: Appearance > Dock
- IPC: `qs -c island ipc call dock <toggle|autohide>`

Pinned apps are the `dockPinned` setting. The same list is used by Launchpad and Spotlight's "Keep in Dock". The dock follows the main screen unless `dockAllScreens` is on.

If the dock is missing, check that `dock` is true in Settings and that the compositor reports the screen through Quickshell. The MangoWC example uses a `no_blur` rule for the dock layer.
