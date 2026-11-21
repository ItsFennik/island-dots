import QtQuick
import qs.services
import qs.settings

// Keyboard Shortcuts group for the Keyboard pane (⌘ = Super).
Group {
    title: "Keyboard Shortcuts"
    footer: Compositor.hyprland ? "Shortcuts are defined in ~/.config/hypr/binds.lua and island.lua."
          : "Bind these in your compositor's config: each runs  qs -c island ipc call …  (see the top of shell.qml)."
    Repeater {
        model: [
            ["Spotlight", "⌘D"], ["Launchpad", "⌘A"], ["Notification Centre", "⌘C"], ["Control Centre · Music", "⌘M"],
            ["System Settings", "⌘I"], ["Clipboard history", "⌘V"], ["Wallpaper", "⌘W"], ["Random wallpaper", "⇧⌘W"],
            ["Themes", "⌥⌘W"], ["Power", "⌘Esc"], ["Screenshot of a selection", "Print"], ["Screenshot of a window", "⌥Print"],
            ["Screenshot of the screen", "⇧Print"], ["Screenshot toolbar", "⇧⌘S"], ["Terminal", "⌘T"], ["Files", "⌘E"], ["Browser", "⌘B"],
            ["Close window", "⌘Q"], ["Full screen", "⌘F"], ["Float window", "⇧⌘T"], ["Pin window", "⌘P"],
            ["Go to desktop 1–9", "⌘1 – ⌘9"], ["Move window to desktop", "⇧⌘1 – ⇧⌘9"],
            ["Scratch desktop", "⌘Space"], ["Send window to scratch", "⇧⌘Space"],
            ["Move focus", "⌘ arrows / H J K L"], ["Move window", "⇧⌘ arrows / H J K L"]
        ]
        delegate: SettingRow {
            required property var modelData
            title: modelData[0]
            Text { text: modelData[1]; color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 } }
        }
    }
}
