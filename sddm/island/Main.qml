// Island SDDM theme: the macOS login window. Same layout as Island's lock screen
// (overlays/LockContent.qml): date and a big clock at the top, the user's picture, name and a
// password pill at the bottom, Sleep / Restart / Shut Down underneath, session at the bottom left.
import QtQuick
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.backgroundColor || "#000000"

    readonly property string font: config.font || "Adwaita Sans"
    readonly property bool primary: typeof primaryScreen === "undefined" ? true : primaryScreen
    readonly property int blurMax: Number(config.blur ?? 48)

    // Selected user / session (filled from the models by the Repeaters below).
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property string userName: ""
    property string userReal: ""
    property string userIcon: ""
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property var sessions: []
    property bool busy: false
    readonly property bool typing: password.text !== ""

    function login() {
        if (busy || !userName) return;
        busy = true;
        sddm.login(userName, password.text, sessionIndex);
    }
    Connections {
        target: sddm
        function onLoginFailed() { root.busy = false; password.text = ""; shake.restart(); password.forceActiveFocus(); }
        function onLoginSucceeded() { root.busy = false; }
    }

    // Hidden collectors: models only expose roles inside delegates.
    Repeater {
        model: userModel
        Item {
            required property int index
            required property string name
            required property string realName
            required property string icon
            readonly property bool current: index === root.userIndex
            onCurrentChanged: if (current) sync()
            Component.onCompleted: if (current) sync()
            function sync() { root.userName = name; root.userReal = realName || name; root.userIcon = icon; }
        }
    }
    Repeater {
        model: sessionModel
        Item {
            required property int index
            required property string name
            Component.onCompleted: { const s = root.sessions.slice(); s[index] = name; root.sessions = s; }
        }
    }

    // ── Wallpaper ─────────────────────────────────────────────────────
    // Rendered into a layer first, so the effect gets the cropped, screen-sized picture.
    Item {
        id: wallBox
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Image {
            id: wall
            anchors.fill: parent
            source: config.background ? Qt.resolvedUrl(config.background) : ""
            sourceSize { width: root.width; height: root.height }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: wallBox
        autoPaddingEnabled: false
        visible: wall.status === Image.Ready
        blurEnabled: root.blurMax > 0
        blurMax: Math.max(1, root.blurMax)
        blur: root.typing || root.busy ? 1 : 0
        Behavior on blur { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }

    // ── Date and time ─────────────────────────────────────────────────
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.07)
        spacing: -Math.round(root.height * 0.012)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            color: Qt.rgba(1, 1, 1, 0.85)
            font { family: root.font; pixelSize: Math.round(root.height * 0.024); weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, String(config.clock24h) !== "false" ? "HH:mm" : "h:mm")
            color: Qt.rgba(1, 1, 1, 0.9)
            font { family: root.font; pixelSize: Math.round(root.height * 0.15); weight: Font.DemiBold; letterSpacing: -2 }
        }
    }

    // ── Users, password ───────────────────────────────────────────────
    Column {
        id: login
        visible: root.primary
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shakeX
        y: root.height - height - Math.round(root.height * 0.15)
        spacing: 10
        property real shakeX: 0

        SequentialAnimation {
            id: shake
            NumberAnimation { target: login; property: "shakeX"; to: -14; duration: 50 }
            NumberAnimation { target: login; property: "shakeX"; to: 14; duration: 70 }
            NumberAnimation { target: login; property: "shakeX"; to: -10; duration: 70 }
            NumberAnimation { target: login; property: "shakeX"; to: 8; duration: 60 }
            NumberAnimation { target: login; property: "shakeX"; to: 0; duration: 50 }
        }

        // Every user as a picture; the selected one is big. Click another to switch.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            Repeater {
                model: userModel
                delegate: Column {
                    required property int index
                    required property string name
                    required property string realName
                    required property string icon
                    readonly property bool current: index === root.userIndex
                    visible: current || userModel.count <= 6
                    spacing: 6
                    opacity: current ? 1 : 0.7
                    Avatar {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: parent.current ? 72 : 48
                        source: parent.icon
                        letter: (parent.realName || parent.name)[0] ?? "?"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.userIndex = index; password.text = ""; password.forceActiveFocus(); }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: parent.current || userModel.count > 1
                        text: parent.realName || parent.name
                        color: "white"
                        font { family: root.font; pixelSize: parent.current ? 15 : 12; weight: Font.DemiBold }
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200; height: 30; radius: 15
            color: Qt.rgba(1, 1, 1, password.activeFocus ? 0.22 : 0.16)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.18) }

            TextInput {
                id: password
                anchors { left: parent.left; leftMargin: 14; right: go.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                focus: true
                enabled: !root.busy
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: "white"
                selectionColor: Qt.rgba(1, 1, 1, 0.3)
                font { family: root.font; pixelSize: 13; letterSpacing: 1 }
                clip: true
                onAccepted: root.login()
                Keys.onEscapePressed: text = ""
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !password.text
                    text: root.busy ? "Logging in…" : "Enter Password"
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font { family: root.font; pixelSize: 13 }
                }
            }
            MouseArea {
                id: go
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                width: 22; height: 22
                visible: root.typing
                cursorShape: Qt.PointingHandCursor
                onClicked: root.login()
                Rectangle { anchors.fill: parent; radius: 11; color: Qt.rgba(1, 1, 1, 0.28) }
                Text { anchors.centerIn: parent; text: "→"; color: "white"; font { family: root.font; pixelSize: 13; weight: Font.Bold } }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: keyboard.capsLock
            text: "Caps Lock is on"
            color: Qt.rgba(1, 1, 1, 0.75)
            font { family: root.font; pixelSize: 11 }
        }
    }

    // ── Sleep / Restart / Shut Down ───────────────────────────────────
    Row {
        visible: root.primary
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(root.height * 0.04) }
        spacing: 36
        PowerButton { label: "Sleep"; kind: "sleep"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
        PowerButton { label: "Restart"; kind: "restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        PowerButton { label: "Shut Down"; kind: "off"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    // ── Session (bottom left): click to cycle ─────────────────────────
    MouseArea {
        visible: root.primary && root.sessions.length > 1
        anchors { left: parent.left; bottom: parent.bottom; margins: 24 }
        width: sessionText.implicitWidth + 24; height: 28
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length
        Rectangle { anchors.fill: parent; radius: 14; color: Qt.rgba(1, 1, 1, parent.containsMouse ? 0.22 : 0.12) }
        Text {
            id: sessionText
            anchors.centerIn: parent
            text: (root.sessions[root.sessionIndex] ?? "Session") + "  ⌄"
            color: "white"
            font { family: root.font; pixelSize: 12; weight: Font.Medium }
        }
    }

    // ── Components ────────────────────────────────────────────────────
    // Round picture with a grey initial when there isn't one.
    component Avatar: Item {
        id: av
        property int size: 72
        property string source: ""
        property string letter: "?"
        width: size; height: size
        Behavior on size { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Rectangle {
            id: disc
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient { GradientStop { position: 0; color: "#a1a1a6" } GradientStop { position: 1; color: "#6e6e73" } }
            Text {
                anchors.centerIn: parent
                visible: pic.status !== Image.Ready
                text: av.letter.toUpperCase()
                color: "white"
                font { family: root.font; pixelSize: av.size * 0.44; weight: Font.DemiBold }
            }
        }
        Image {
            id: pic
            anchors.fill: parent
            source: av.source
            sourceSize { width: 144; height: 144 }
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        Rectangle { id: mask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: pic
            visible: pic.status === Image.Ready
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Round frosted button with a drawn icon (no icon font needed in the greeter).
    component PowerButton: Column {
        id: pb
        property string label
        property string kind
        signal clicked()
        spacing: 6
        MouseArea {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44; height: 44
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
            Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(1, 1, 1, parent.containsMouse ? 0.3 : 0.16) }
            Canvas {
                anchors.centerIn: parent
                width: 20; height: 20
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    c.strokeStyle = "white"; c.fillStyle = "white"; c.lineWidth = 2; c.lineCap = "round";
                    if (pb.kind === "off") {
                        c.beginPath(); c.arc(10, 11, 7, -Math.PI / 2 + 0.75, 1.5 * Math.PI - 0.75); c.stroke();
                        c.beginPath(); c.moveTo(10, 2); c.lineTo(10, 10); c.stroke();
                    } else if (pb.kind === "restart") {
                        c.beginPath(); c.arc(10, 10, 7, -Math.PI / 2, 1.5 * Math.PI - 0.9); c.stroke();
                        c.beginPath(); c.moveTo(10, 0); c.lineTo(14, 3); c.lineTo(10, 6); c.closePath(); c.fill();
                    } else {
                        c.beginPath(); c.arc(10, 10, 8, 0, 2 * Math.PI); c.fill();
                        c.globalCompositeOperation = "destination-out";
                        c.beginPath(); c.arc(14, 7, 7, 0, 2 * Math.PI); c.fill();
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pb.label
            color: Qt.rgba(1, 1, 1, 0.85)
            font { family: root.font; pixelSize: 11; weight: Font.Medium }
        }
    }
}
