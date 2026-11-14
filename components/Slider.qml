import QtQuick
import qs.services

// macOS slider: thin track, accent fill, white round knob. Optional min/max captions
// (minText/maxText, like "Slow" … "Fast"); the exact value shows in a bubble while dragging.
// Emits moved(value) while dragging.
Item {
    id: root
    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 1
    property int decimals: 0
    property string suffix: ""
    property string minText: ""
    property string maxText: ""
    // When true (Settings), the wheel only adjusts the slider after it's been clicked, so
    // scrolling the page past it doesn't change the value. Arrow keys work while focused.
    property bool wheelNeedsFocus: false
    signal moved(real value)
    activeFocusOnTab: true

    function nudge(dir) {
        const v = Math.max(from, Math.min(to, value + dir * (stepSize || (to - from) / 100)));
        if (+v.toFixed(4) !== value) moved(+v.toFixed(4));
    }
    Keys.onLeftPressed: nudge(-1)
    Keys.onDownPressed: nudge(-1)
    Keys.onRightPressed: nudge(1)
    Keys.onUpPressed: nudge(1)

    implicitWidth: 230; implicitHeight: minText || maxText ? 34 : 22
    readonly property real fraction: Math.max(0, Math.min(1, (value - from) / (to - from)))
    readonly property real shown: area.pressed ? area.dragFraction : fraction
    readonly property real shownValue: area.pressed ? area.dragValue : value

    Rectangle {
        id: track
        x: 9; width: parent.width - 18
        y: 11 - height / 2
        height: 4; radius: 2
        color: Theme.switchOff
        Rectangle { width: parent.width * root.shown; height: parent.height; radius: 2; color: Theme.accent }
    }
    Rectangle {                                            // knob shadow
        x: knob.x; y: knob.y + 0.5; width: knob.width; height: knob.height; radius: knob.radius
        color: Qt.rgba(0, 0, 0, 0.22)
    }
    Rectangle {
        id: knob
        x: track.x + track.width * root.shown - width / 2
        y: 11 - height / 2
        width: 18; height: 18; radius: 9
        color: Theme.knob
        border { width: root.activeFocus && root.wheelNeedsFocus ? 3 : 0; color: Theme.focusRing }
    }
    Text {
        visible: root.minText !== ""
        anchors { left: track.left; top: track.bottom; topMargin: 8 }
        text: root.minText; color: Theme.textDim
        font { family: Theme.font; pixelSize: 10 }
    }
    Text {
        visible: root.maxText !== ""
        anchors { right: track.right; top: track.bottom; topMargin: 8 }
        text: root.maxText; color: Theme.textDim
        font { family: Theme.font; pixelSize: 10 }
    }
    // Value bubble while dragging or focused
    Rectangle {
        visible: area.pressed || area.containsMouse
        x: knob.x + knob.width / 2 - width / 2
        y: knob.y - height - 6
        width: bubble.implicitWidth + 12; height: 18; radius: 5
        color: Theme.dark ? "#3a3a3c" : "#ffffff"
        border { width: 1; color: Theme.hairline }
        z: 2
        Text { id: bubble; anchors.centerIn: parent; text: root.shownValue.toFixed(root.decimals) + root.suffix
            color: Theme.text; font { family: Theme.font; pixelSize: 11 } }
    }
    MouseArea {
        id: area
        property real dragFraction: 0
        property real dragValue: 0
        x: 0; y: 0; width: parent.width; height: 22
        hoverEnabled: true
        preventStealing: true
        function update(x) {
            let f = Math.max(0, Math.min(1, (x - track.x) / track.width));
            let v = root.from + f * (root.to - root.from);
            if (root.stepSize > 0) v = +(Math.round(v / root.stepSize) * root.stepSize).toFixed(4);
            dragFraction = (v - root.from) / (root.to - root.from);
            dragValue = v;
            if (v !== root.value) root.moved(v);
        }
        onPressed: e => { if (root.wheelNeedsFocus) root.forceActiveFocus(); update(e.x); }
        onPositionChanged: e => { if (pressed) update(e.x); }
    }
    WheelHandler {
        enabled: !root.wheelNeedsFocus || root.activeFocus
        onWheel: e => { if (e.angleDelta.y !== 0) root.nudge(e.angleDelta.y > 0 ? 1 : -1); }
    }
}
