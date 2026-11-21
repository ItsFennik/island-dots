import QtQuick
import qs.services
import qs.components
import qs.settings

// Menu Bar pane: pick which items the bar shows, in which zone and in what order (BarLayout).
Group {
    id: root
    title: "Menu Bar Items"
    footer: "Switch items on or off, choose Left, Centre or Right, and use the arrows to reorder them within their zone. Hidden items are still reachable: Spotlight with Super+D, notifications with Super+N, Control Centre and power with their shortcuts."

    // Shown items zone by zone in bar order, then the hidden ones in catalogue order.
    readonly property var rows: {
        const l = BarLayout.layout, out = [];
        for (const z of BarLayout.zones) l[z].forEach((id, i) => out.push({ id: id, zone: z, i: i, n: l[z].length }));
        for (const c of BarLayout.catalogue) if (!BarLayout.shown(c.id)) out.push({ id: c.id, zone: "", i: 0, n: 0 });
        return out;
    }
    readonly property var zoneNames: ({ left: "Left", center: "Centre", right: "Right" })

    component Arrow: MouseArea {
        property string label
        width: 22; height: 22
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        opacity: enabled ? 1 : 0.25
        Rectangle { anchors.fill: parent; radius: 6; color: parent.containsMouse && parent.enabled ? Theme.hover : "transparent" }
        Text { anchors.centerIn: parent; text: parent.label; color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 } }
    }

    Repeater {
        model: root.rows
        delegate: SettingRow {
            id: row
            required property var modelData
            readonly property var c: BarLayout.info(modelData.id)
            readonly property bool on: modelData.zone !== ""
            title: c.label
            subtitle: on ? root.zoneNames[modelData.zone] + (c.sub ? " · " + c.sub : "") : "Hidden" + (c.sub ? " · " + c.sub : "")
            glyph: c.glyph
            glyphTint: on ? Theme.accent : "#8e8e93"

            Row {
                spacing: 8
                Arrow { label: "↑"; visible: row.on; enabled: row.modelData.i > 0; anchors.verticalCenter: parent.verticalCenter
                        onClicked: BarLayout.shift(row.modelData.id, -1) }
                Arrow { label: "↓"; visible: row.on; enabled: row.modelData.i < row.modelData.n - 1; anchors.verticalCenter: parent.verticalCenter
                        onClicked: BarLayout.shift(row.modelData.id, 1) }
                Segmented {
                    visible: row.on
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ value: "left", text: "Left" }, { value: "center", text: "Centre" }, { value: "right", text: "Right" }]
                    value: row.modelData.zone
                    onPicked: v => { if (v !== row.modelData.zone) BarLayout.moveTo(row.modelData.id, v); }
                }
                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: row.on
                    onToggled: v => BarLayout.setShown(row.modelData.id, v)
                }
            }
        }
    }
    SettingRow {
        title: "Default layout"
        subtitle: "Logo and app menus on the left, workspaces in the centre, everything else on the right"
        PushButton { text: "Reset"; onClicked: BarLayout.reset() }
    }
}
