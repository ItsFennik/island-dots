import QtQuick
import Quickshell
import qs.services
import qs.components
import qs.settings

// Appearance pane: Light / Dark thumbnails, accent colour dots, then every theme.
Column {
    id: root
    spacing: 20

    readonly property string twin: Theme.counterpart(Theme.current)
    readonly property var accents: [["", "Multicolour", "conic"], ["#0a84ff", "Blue"], ["#bf5af2", "Purple"], ["#ff375f", "Pink"],
                                    ["#ff453a", "Red"], ["#ff9f0a", "Orange"], ["#ffd60a", "Yellow"], ["#30d158", "Green"], ["#8e8e93", "Graphite"]]

    Group {
        SettingRow {
            title: "Appearance"
            subtitle: root.twin === "" ? "This theme has no light/dark twin. Pick one below" : ""
            Row {
                spacing: 14
                Repeater {
                    model: [[false, "Light"], [true, "Dark"]]
                    MouseArea {
                        id: mode
                        required property var modelData
                        readonly property bool on: Theme.dark === modelData[0]
                        width: 68; height: 64
                        enabled: on || root.twin !== ""
                        opacity: enabled ? 1 : 0.4
                        onClicked: if (!on) Theme.toggleDark()
                        Rectangle {
                            id: thumb
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 64; height: 42; radius: 7
                            color: mode.modelData[0] ? "#1c1c1e" : "#e5e5ea"
                            border { width: mode.on ? 3 : 1; color: mode.on ? Theme.accent : Qt.alpha(Theme.text, 0.15) }
                            Rectangle { x: 8; y: 8; width: 30; height: 22; radius: 3; color: mode.modelData[0] ? "#3a3a3c" : "#ffffff" }
                            Rectangle { x: 8; y: 8; width: 30; height: 5; radius: 2; color: Theme.accent }
                        }
                        Text { anchors { horizontalCenter: parent.horizontalCenter; top: thumb.bottom; topMargin: 5 }
                            text: mode.modelData[1]; color: Theme.text; font { family: Theme.font; pixelSize: 11; weight: Theme.w(mode.on ? Font.DemiBold : Font.Normal) } }
                    }
                }
            }
        }
        SettingRow {
            title: "Accent colour"
            subtitle: (root.accents.find(a => a[0] === (Config.values.accentColor ?? "")) ?? root.accents[0])[1]
            Row {
                spacing: 8
                Repeater {
                    model: root.accents
                    MouseArea {
                        id: dot
                        required property var modelData
                        readonly property bool on: (Config.values.accentColor ?? "") === modelData[0]
                        width: 18; height: 18
                        onClicked: Config.set("accentColor", modelData[0])
                        Rectangle {
                            anchors.fill: parent; radius: 9
                            gradient: dot.modelData[0] === "" ? multi : null
                            color: dot.modelData[0] || "transparent"
                            border { width: 1; color: Qt.rgba(0, 0, 0, 0.15) }
                        }
                        Rectangle { visible: dot.on; anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "white" }
                    }
                }
            }
            Gradient { id: multi; GradientStop { position: 0; color: "#ff453a" } GradientStop { position: 0.5; color: "#30d158" } GradientStop { position: 1; color: "#0a84ff" } }
        }
        SettingRow {
            title: "Icon style"
            subtitle: "App icons in the Dock, Launchpad and Spotlight"
            Segmented {
                options: [{ value: "default", text: "Default" }, { value: "clear", text: "Clear" }, { value: "tinted", text: "Tinted" }]
                value: Config.values.iconStyle ?? "default"
                onPicked: v => Config.set("iconStyle", v)
            }
        }
        SettingRow {
            visible: (Config.values.iconStyle ?? "default") === "tinted"
            title: "Icon tint"
            subtitle: (root.accents.find(a => a[0] === (Config.values.iconTint ?? "")) ?? [0, "Custom"])[1].replace("Multicolour", "Accent colour")
            Row {
                spacing: 8
                Repeater {
                    model: root.accents
                    MouseArea {
                        id: tdot
                        required property var modelData
                        readonly property bool on: (Config.values.iconTint ?? "") === modelData[0]
                        width: 18; height: 18
                        onClicked: Config.set("iconTint", modelData[0])
                        Rectangle {
                            anchors.fill: parent; radius: 9
                            color: tdot.modelData[0] || Theme.accent
                            border { width: 1; color: Qt.rgba(0, 0, 0, 0.15) }
                        }
                        Rectangle { visible: tdot.on; anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "white" }
                    }
                }
            }
        }
    }

    Group {
        title: "Layout"
        footer: "Bottom bar: one floating bar with your apps, now playing, status and the clock, in place of the menu bar and Dock. Compact bar: a smaller pill only as wide as its contents: start, search, apps, status, CPU/RAM and the clock. Desktop icons: Trash, mounted drives and (optionally) your Dock apps; double-click to open, right-click a USB drive to eject."
        Setting { spec: ({ key: "liquidGlass", type: "switch", label: "Liquid glass", sub: "Clearer panels with a glass rim and sheen. No extra GPU cost" }) }
        Setting { spec: ({ key: "shellLayout", type: "choice", label: "Layout", options: [["menubar", "Menu bar + Dock"], ["taskbar", "Bottom bar"], ["compact", "Compact bar"]] }) }
        Setting { spec: ({ key: "taskbarHeight", type: "slider", label: "Bottom bar height", from: 40, to: 72, suffix: " px" }); visible: ["taskbar", "compact"].includes(Config.values.shellLayout ?? "menubar") }
        Setting { spec: ({ key: "taskbarMagnify", type: "switch", label: "Magnification", sub: "Bottom bar icons grow under the pointer" }); visible: (Config.values.shellLayout ?? "menubar") === "taskbar" }
        Setting { spec: ({ key: "taskbarMagnifySize", type: "slider", label: "Magnified size", from: 1.1, to: 2.5, step: 0.05, decimals: 2, suffix: "×", minText: "Small", maxText: "Large", when: "taskbarMagnify" }); visible: (Config.values.shellLayout ?? "menubar") === "taskbar" }
        Setting { spec: ({ key: "taskbarBounce", type: "switch", label: "Animate opening applications", sub: "Bottom bar icons bounce while an app starts" }); visible: (Config.values.shellLayout ?? "menubar") === "taskbar" }
        Setting { spec: ({ key: "compactIconSize", type: "slider", label: "Icon size", from: 16, to: 44, suffix: " px", minText: "Small", maxText: "Large" }); visible: (Config.values.shellLayout ?? "menubar") === "compact" }
        Setting { spec: ({ key: "compactStats", type: "switch", label: "Show CPU and memory", sub: "In the compact bar, next to the clock" }); visible: (Config.values.shellLayout ?? "menubar") === "compact" }
        Setting { spec: ({ key: "desktopIcons", type: "switch", label: "Desktop icons", sub: "Trash and mounted drives" }) }
        Setting { spec: ({ key: "desktopIconsApps", type: "switch", label: "Show Dock apps on the desktop" }); visible: Config.values.desktopIcons === true }
        Setting { spec: ({ key: "desktopIconSize", type: "slider", label: "Desktop icon size", from: 40, to: 96, suffix: " px" }); visible: Config.values.desktopIcons === true }
    }

    Group {
        title: "Theme"
        footer: "Recolours GTK apps, window borders, the terminal and Island. Add your own by dropping a JSON file into ~/.config/quickshell/island/themes/."
        Item {
            width: parent.width
            height: grid.height + 24
            Grid {
                id: grid
                x: 12; y: 12
                readonly property int cols: Math.max(2, Math.floor((parent.width - 24 + 12) / 170))
                columns: cols
                spacing: 12
                Repeater {
                    model: Theme.themes
                    delegate: ThemeCard {
                        required property var modelData
                        theme: modelData
                        width: (grid.parent.width - 24 - (grid.cols - 1) * 12) / grid.cols
                    }
                }
            }
        }
    }
}
