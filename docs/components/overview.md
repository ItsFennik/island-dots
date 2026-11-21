# Overview

`overlays/Overview.qml` shows every workspace with live window previews. Drag a window onto another workspace to move it. Right-click a workspace indicator in the bar to open it.

- Config: `overlays/Overview.qml`
- Settings: `overviewWorkspaces`
- IPC: `qs -c island ipc call overview <toggle|open|close>`

The preview uses foreign-toplevel where available, with compositor-specific focus and move actions in `services/Compositor.qml`. Workspace switching closes open popouts and Settings.
