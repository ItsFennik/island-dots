import QtQuick
import Quickshell
import qs.services

// Analog clock, Apple style: numerals, a weekday under the 12. Tahoe: white monochrome;
// Classic: theme colours with an orange second hand.
// Small: the face. Medium: face + digital time and date. Large: a big face.
Card {
    id: root
    readonly property bool seconds: Config.saved.widgetClockSeconds ?? true

    SystemClock { id: clk; precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes }

    Canvas {
        id: face
        width: root.large ? parent.width - 40 : parent.height - 16
        height: width
        x: root.size === "m" ? 8 : (parent.width - width) / 2
        y: (parent.height - height) / 2
        onWidthChanged: requestPaint()
        property date t: clk.date
        onTChanged: requestPaint()
        Connections { target: Theme; function onPalChanged() { face.requestPaint(); } }
        Connections { target: root; function onFontChanged() { face.requestPaint(); } function onGlassChanged() { face.requestPaint(); } function onFgChanged() { face.requestPaint(); } function onTahoeChanged() { face.requestPaint(); } }

        onPaint: {
            const ctx = getContext("2d");
            const w = width, r = w / 2, k = r / 74;      // k: scale from the small face
            ctx.reset();
            ctx.translate(r, r);

            // Face
            ctx.beginPath(); ctx.arc(0, 0, r, 0, 2 * Math.PI);
            ctx.fillStyle = root.tahoe ? Qt.rgba(1, 1, 1, 0.07) : Qt.alpha(Theme.card, Math.min(1, root.glass + 0.3)); ctx.fill();

            // Minute ticks
            for (let i = 0; i < 60; i++) {
                if (i % 5 === 0) continue;
                const a = i * Math.PI / 30;
                ctx.beginPath();
                ctx.moveTo(Math.sin(a) * (r - 5 * k), -Math.cos(a) * (r - 5 * k));
                ctx.lineTo(Math.sin(a) * (r - 8 * k), -Math.cos(a) * (r - 8 * k));
                ctx.strokeStyle = root.fgFaint; ctx.lineWidth = Math.max(1, k * 0.8); ctx.stroke();
            }

            // Numerals
            ctx.fillStyle = root.fg;
            ctx.textAlign = "center"; ctx.textBaseline = "middle";
            ctx.font = "600 " + Math.round(r * 0.22) + "px '" + root.font + "'";
            for (let h = 1; h <= 12; h++) {
                const a = h * Math.PI / 6;
                ctx.fillText(String(h), Math.sin(a) * r * 0.74, -Math.cos(a) * r * 0.74 + 1);
            }

            // Weekday
            ctx.fillStyle = root.fgDim;
            ctx.font = "700 " + Math.round(r * 0.13) + "px '" + root.font + "'";
            ctx.fillText(Qt.formatDate(t, "ddd").toUpperCase(), 0, -r * 0.38);

            const hand = (angle, len, width, color, tail) => {
                ctx.save();
                ctx.rotate(angle);
                ctx.beginPath(); ctx.moveTo(0, tail); ctx.lineTo(0, -len);
                ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineCap = "round"; ctx.stroke();
                ctx.restore();
            };
            const s = t.getSeconds(), m = t.getMinutes() + (root.seconds ? s / 60 : 0), h = t.getHours() % 12 + m / 60;
            hand(h * Math.PI / 6, r * 0.5, 4.5 * k, root.fg, 0);
            hand(m * Math.PI / 30, r * 0.78, 3.5 * k, root.fg, 0);
            ctx.beginPath(); ctx.arc(0, 0, 4 * k, 0, 2 * Math.PI); ctx.fillStyle = root.fg; ctx.fill();
            if (root.seconds) {
                const sc = root.tahoe ? root.fgDim : "#ff9f0a";
                hand(s * Math.PI / 30, r * 0.86, 1.5 * k, sc, r * 0.16);
                ctx.beginPath(); ctx.arc(0, 0, 2.5 * k, 0, 2 * Math.PI); ctx.fillStyle = sc; ctx.fill();
            }
        }
    }

    // Medium: digital time and date beside the face
    Column {
        visible: root.size === "m"
        anchors { left: face.right; leftMargin: 18; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: -2
        Text { text: Qt.formatDate(clk.date, "dddd").toUpperCase(); color: root.tahoe ? root.fgDim : "#ff9f0a"
            font { family: root.font; pixelSize: 12; weight: Font.Bold; letterSpacing: 0.4 } }
        Text {
            readonly property bool h24: Config.saved.clock24h ?? true
            text: Qt.formatTime(clk.date, h24 ? "HH:mm" : "h:mm")
            color: root.fg
            font { family: root.font; pixelSize: 46; weight: Font.Light }
        }
        Text { text: Qt.formatDate(clk.date, "d MMMM"); color: root.fgDim
            font { family: root.font; pixelSize: 13; weight: Font.DemiBold } }
    }
}
