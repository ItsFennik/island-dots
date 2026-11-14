pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Connection summary from NetworkManager over D-Bus (no nmcli polling).
Singleton {
    id: root
    readonly property var devices: Networking.devices.values
    readonly property var device: devices.find(d => d.connected && d.type === DeviceType.Wired)
                               ?? devices.find(d => d.connected) ?? null
    readonly property bool online: device !== null
    readonly property bool wired: device?.type === DeviceType.Wired
    readonly property var wifi: !wired && device ? (device.networks.values.find(n => n.connected) ?? null) : null
    readonly property int strength: {
        const s = wifi?.signalStrength ?? 0;
        return Math.round(s <= 1 ? s * 100 : s);
    }
    readonly property string glyph: !online ? "" : wired ? "" : ""
    readonly property string label: !online ? "Disconnected"
        : wired ? "Wired · " + device.name
        : (wifi?.name ?? device.name) + " · " + strength + "%"
}
