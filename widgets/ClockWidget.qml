import QtQuick
import Quickshell
import qs.services

// Analog clock, Apple style: numerals, a weekday under the 12, orange second hand.
Card {
    id: root
    readonly property bool seconds: Config.saved.widgetClockSeconds ?? true

    SystemClock { id: clk; precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes }

    Canvas {
        id: face
        anchors.fill: parent
        anchors.margins: 8
        property date t: clk.date
        onTChanged: requestPaint()
        Connections { target: Theme; function onPalChanged() { face.requestPaint(); } }
        Connections { target: root; function onFontChanged() { face.requestPaint(); } function onGlassChanged() { face.requestPaint(); } }

        onPaint: {
            const ctx = getContext("2d");
            const w = width, r = w / 2;
            ctx.reset();
            ctx.translate(r, r);

            // Face
            ctx.beginPath(); ctx.arc(0, 0, r, 0, 2 * Math.PI);
            ctx.fillStyle = Qt.alpha(Theme.card, Math.min(1, root.glass + 0.3)); ctx.fill();

            // Minute ticks
            for (let i = 0; i < 60; i++) {
                if (i % 5 === 0) continue;
                const a = i * Math.PI / 30;
                ctx.beginPath();
                ctx.moveTo(Math.sin(a) * (r - 5), -Math.cos(a) * (r - 5));
                ctx.lineTo(Math.sin(a) * (r - 8), -Math.cos(a) * (r - 8));
                ctx.strokeStyle = Theme.textFaint; ctx.lineWidth = 1; ctx.stroke();
            }

            // Numerals
            ctx.fillStyle = Theme.text;
            ctx.textAlign = "center"; ctx.textBaseline = "middle";
            ctx.font = "600 " + Math.round(r * 0.22) + "px '" + root.font + "'";
            for (let h = 1; h <= 12; h++) {
                const a = h * Math.PI / 6;
                ctx.fillText(String(h), Math.sin(a) * r * 0.74, -Math.cos(a) * r * 0.74 + 1);
            }

            // Weekday
            ctx.fillStyle = Theme.textDim;
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
            hand(h * Math.PI / 6, r * 0.5, 4.5, Theme.text, 0);
            hand(m * Math.PI / 30, r * 0.78, 3.5, Theme.text, 0);
            ctx.beginPath(); ctx.arc(0, 0, 4, 0, 2 * Math.PI); ctx.fillStyle = Theme.text; ctx.fill();
            if (root.seconds) {
                hand(s * Math.PI / 30, r * 0.86, 1.5, "#ff9f0a", r * 0.16);
                ctx.beginPath(); ctx.arc(0, 0, 2.5, 0, 2 * Math.PI); ctx.fillStyle = "#ff9f0a"; ctx.fill();
            }
        }
    }
}
