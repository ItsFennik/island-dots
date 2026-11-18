import QtQuick
import qs.components
import qs.services
import qs.bar

// One data-driven settings row. spec: { key, type, label, sub, ... }
//   switch                       on/off
//   slider   from to step decimals suffix minText maxText
//   choice   options: [[value, text], ...]   (segmented when ≤ 4, pop-up otherwise)
//   wsstyle  options: [[value, text], ...]   picture tiles with a live mini workspace indicator
//   list     options or source: "gtk" | "icons" | "cursors"   (pop-up button)
//   font                         searchable list of installed fonts (expands inline)
//   text     placeholder
//   secret   placeholder — the Wallhaven API key (masked; stored in its own file)
SettingRow {
    id: root
    required property var spec
    // spec.norm(v): how a stored value shows here (e.g. a tiling layout from another compositor)
    readonly property var value: spec.norm ? spec.norm(Config.values[spec.key]) : Config.values[spec.key]

    title: spec.label
    // spec.live: "weather" → the subtitle shows what the field currently resolves to
    subtitle: spec.live === "weather" ? Weather.status : spec.sub ?? ""
    readonly property bool isSecret: spec.type === "secret"
    enabled: spec.when ? Config.values[spec.when] === true : true

    readonly property var items: isFont ? [] : spec.source ? (Looks[spec.source] ?? []) : (spec.options ?? [])
    readonly property bool segmented: spec.type === "choice" && (spec.options ?? []).length <= 4

    Loader {
        sourceComponent: root.spec.type === "switch" ? sw
                       : root.spec.type === "slider" ? sl
                       : root.spec.type === "wsstyle" ? ws
                       : root.segmented ? seg
                       : root.spec.type === "choice" || root.spec.type === "list" ? pop
                       : root.spec.type === "font" ? fontBtn
                       : root.spec.type === "text" ? tx
                       : root.spec.type === "secret" ? sec : null
    }

    Component { id: sw; Switch { checked: root.value === true; onToggled: c => Config.set(root.spec.key, c) } }
    Component { id: sl; Slider {
        value: root.value ?? 0; from: root.spec.from; to: root.spec.to; stepSize: root.spec.step ?? 1
        decimals: root.spec.decimals ?? 0; suffix: root.spec.suffix ?? ""; wheelNeedsFocus: true
        minText: root.spec.minText ?? ""; maxText: root.spec.maxText ?? ""
        onMoved: v => Config.set(root.spec.key, v) } }
    Component { id: seg; Segmented {
        options: root.spec.options.map(o => ({ value: o[0], text: o[1] })); value: root.value
        onPicked: v => Config.set(root.spec.key, v) } }
    Component { id: ws; Row {
        spacing: 10
        Repeater {
            model: root.spec.options
            MouseArea {
                id: tileArea
                required property var modelData
                readonly property bool sel: root.value === modelData[0]
                width: 116; height: 58
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Config.set(root.spec.key, modelData[0])
                // sample of the menu bar with the indicator drawn exactly as it will be
                Rectangle {
                    id: sample
                    width: parent.width; height: 40
                    radius: 9
                    color: Qt.alpha(Theme.text, tileArea.containsMouse && !tileArea.sel ? 0.1 : 0.06)
                    border { width: tileArea.sel ? 2 : 1; color: tileArea.sel ? Theme.accent : Qt.alpha(Theme.text, 0.1) }
                    Workspaces {
                        anchors.centerIn: parent
                        screenName: ""
                        previewStyle: tileArea.modelData[0]
                        family: Theme.font
                        fontPx: 12
                        barH: 26
                    }
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    text: tileArea.modelData[1]
                    color: tileArea.sel ? Theme.text : Theme.textDim
                    font { family: Theme.font; pixelSize: 11; weight: tileArea.sel ? Font.DemiBold : Font.Normal }
                }
            }
        }
    } }
    Component { id: pop; PopupButton {
        options: root.items; value: root.value
        onPicked: v => Config.set(root.spec.key, v) } }
    Component { id: tx; TextField {
        text: root.value ?? ""; placeholder: root.spec.placeholder ?? ""
        // Save as you type (Config debounces the write) — not just on Enter, since closing
        // Settings or clicking elsewhere never takes focus away and the edit would be lost.
        onEdited: Config.set(root.spec.key, text)
        onAccepted: if (text !== root.value) Config.set(root.spec.key, text) } }
    Component { id: sec; TextField {
        text: Wallhaven.apiKey; placeholder: root.spec.placeholder ?? ""
        input.echoMode: input.activeFocus ? TextInput.Normal : TextInput.Password
        onAccepted: Wallhaven.setKey(text) } }
    Component { id: fontBtn; MouseArea {
        implicitWidth: Math.min(240, fontLabel.implicitWidth + 40); implicitHeight: 22
        onClicked: root.fontOpen = !root.fontOpen
        Rectangle { anchors.fill: parent; radius: 6; color: Theme.button; border { width: 1; color: Theme.buttonBorder } }
        Text { id: fontLabel; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
            width: Math.min(implicitWidth, 200); elide: Text.ElideRight
            text: root.value ?? ""; color: Theme.text; font { family: root.value || Theme.font; pixelSize: 13 } }
        Rectangle { anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
            width: 16; height: 16; radius: 4; color: Theme.accent
            Text { anchors.centerIn: parent; text: "⌃\n⌄"; lineHeight: 0.45; horizontalAlignment: Text.AlignHCenter
                color: Theme.onAccent; font { family: Theme.font; pixelSize: 9; weight: Font.Bold } } }
    } }

    property bool fontOpen: false
    readonly property bool isFont: spec.type === "font"
    below: Loader {
        width: parent.width
        height: item ? item.implicitHeight : 0
        active: root.fontOpen
        sourceComponent: Column {
            padding: 12; topPadding: 0
            spacing: 8
            readonly property var fonts: Qt.fontFamilies()
            TextField { id: q; width: parent.width - 24; placeholder: "Search fonts"
                Component.onCompleted: input.forceActiveFocus()
                onAccepted: if (input.activeFocus && list.count > 0) { Config.set(root.spec.key, list.model[0]); root.fontOpen = false; } }
            Text { visible: list.count === 0; text: "No matches"; color: Theme.textDim; font { family: Theme.font; pixelSize: 12 } leftPadding: 8 }
            ListView {
                id: list
                width: parent.width - 24; height: Math.min(200, contentHeight); clip: true
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                model: parent.fonts.filter(f => f.toLowerCase().includes(q.text.toLowerCase()))
                delegate: MouseArea {
                    required property var modelData
                    width: ListView.view.width; height: 24
                    hoverEnabled: true
                    onClicked: { Config.set(root.spec.key, modelData); root.fontOpen = false; }
                    Rectangle { anchors.fill: parent; radius: 5
                        color: parent.modelData === root.value || parent.containsMouse ? Theme.accent : "transparent" }
                    Text { anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        text: parent.modelData; color: parent.modelData === root.value || parent.containsMouse ? Theme.onAccent : Theme.text
                        font { family: parent.modelData; pixelSize: 13 } }
                }
            }
        }
    }
}
