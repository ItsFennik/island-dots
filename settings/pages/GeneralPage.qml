import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
import qs.settings

// General pane: About this computer (read once when opened), then Transfer or Reset.
Column {
    id: root
    spacing: 20

    property var info: ({})
    Process {
        running: true
        command: ["sh", "-c", `
            . /etc/os-release 2>/dev/null
            echo "os=\${PRETTY_NAME:-Linux}"
            echo "id=\${ID:-linux}"
            echo "host=$(cat /etc/hostname 2>/dev/null || hostname)"
            echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//; s/ *$//')"
            echo "cores=$(nproc)"
            echo "mem=$(awk '/MemTotal/ {printf "%.0f GB", $2/1048576}' /proc/meminfo)"
            echo "gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d' | head -1 | sed 's/.*: //; s/ (rev .*//')"
            echo "kernel=$(uname -r)"
            echo "up=$(uptime -p 2>/dev/null | sed 's/^up //')"
            echo "disk=$(df -h --output=avail,size / | tail -1 | awk '{print $1 " available of " $2}')"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
                root.info = o;
            }
        }
    }
    readonly property string logo: ({ fedora: "", arch: "", cachyos: "", endeavouros: "", manjaro: "",
        debian: "", ubuntu: "", nixos: "", opensuse: "", gentoo: "", void: "" })[info.id ?? ""] ?? ""

    // Hero, like the About pane
    Column {
        width: parent.width
        spacing: 6
        topPadding: 6
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96; radius: 22
            gradient: Gradient { GradientStop { position: 0; color: "#5ac8fa" } GradientStop { position: 1; color: "#0a84ff" } }
            Text { anchors.centerIn: parent; text: root.logo; color: "white"; font { family: Theme.mono; pixelSize: 52 } }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; topPadding: 6; text: root.info.host ?? ""; color: Theme.text
            font { family: Theme.font; pixelSize: 22; weight: Font.Bold } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.info.os ?? ""; color: Theme.textDim
            font { family: Theme.font; pixelSize: 12 } }
    }

    Group {
        title: "About"
        Repeater {
            model: [["Name", root.info.host], ["Processor", root.info.cpu ? root.info.cpu + " (" + root.info.cores + " threads)" : ""],
                    ["Graphics", root.info.gpu], ["Memory", root.info.mem], ["Storage", root.info.disk],
                    ["Operating system", root.info.os], ["Kernel", root.info.kernel], ["Uptime", root.info.up]]
            delegate: SettingRow {
                required property var modelData
                visible: !!modelData[1]
                title: modelData[0]
                Text { text: modelData[1] ?? ""; color: Theme.textDim; width: Math.min(implicitWidth, 340); elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 13 } }
            }
        }
    }

    Group {
        title: "Transfer or Reset"
        footer: "Your settings are in ~/.config/island/settings.json; everything not listed there comes from defaults.json."
        SettingRow {
            id: resetRow
            title: "Reset all settings"
            subtitle: armed ? "Click again to reset every setting to its default (themes are kept)" : ""
            property bool armed: false
            PushButton { text: resetRow.armed ? "Reset" : "Reset…"; destructive: true
                onClicked: { if (resetRow.armed) { Config.reset(Object.keys(Config.defaults)); resetRow.armed = false; } else resetRow.armed = true; } }
        }
    }
}
