import QtQuick
import Quickshell
import qs.services

// What a lock surface shows. Separate so `ipc call lock preview` can show it in a normal window.
// Typing deepens the frost; the right password melts it away before the session is released.
Item {
    id: content
    required property var lock           // the Lock scope: password, pam, realName, …
    property bool main: true             // show the picture / name / password field
    property bool preview: false
    anchors.fill: parent

    readonly property bool typing: lock.typing || lock.pam.active
    readonly property bool h24: Config.saved.clock24h ?? true
    readonly property color errColor: Theme.pal.red || "#ff5f6d"

    // "22:42" or ["10:42", "PM"], so the suffix can be smaller than the clock.
    function clockParts(d) {
        if (h24) return [Qt.formatTime(d, "HH:mm"), ""];
        const h = d.getHours() % 12 || 12;
        return [h + ":" + String(d.getMinutes()).padStart(2, "0"), d.getHours() < 12 ? "AM" : "PM"];
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var time: clockParts(clock.date)

    // Entrance / exit animations
    property real frost: 0               // frosted wallpaper fades in on lock
    property real clockIntro: 0
    property real loginIntro: 0

    function playIntro() {
        frostIn.stop(); frostOut.stop(); clockIn.stop(); loginIn.stop();
        frost = 0; clockIntro = 0; loginIntro = 0;
        frostIn.restart(); clockIn.restart(); loginIn.restart();
    }
    Component.onCompleted: playIntro()
    Connections {
        target: LockState
        function onLockedChanged() { if (LockState.locked) content.playIntro(); }
    }
    Connections {
        target: content.lock
        function onUnlockingChanged() { if (content.lock.unlocking) frostOut.restart(); }
    }
    NumberAnimation { id: frostIn; target: content; property: "frost"; from: 0; to: 1; duration: 340; easing.type: Easing.InOutCubic }
    NumberAnimation { id: frostOut; target: content; property: "frost"; to: 0; duration: 260; easing.type: Easing.InOutCubic }
    NumberAnimation { id: clockIn; target: content; property: "clockIntro"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: loginIn
        PauseAnimation { duration: 200 }
        NumberAnimation { target: content; property: "loginIntro"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
    }

    // Wallpaper
    // Sharp copy underneath: the unlock animation fades the frost away to reveal exactly what
    // the desktop shows once the lock surface is gone.
    Image {
        id: sharp
        anchors.fill: parent
        source: lock.wallpaper ? "file://" + lock.wallpaper : ""
        sourceSize.width: Math.max(1, content.width)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }

    // Frosted copy: a low-res decode scaled up is a cheap blur for the software renderer.
    Item {
        anchors.fill: parent
        opacity: content.frost

        Image {
            anchors.fill: parent
            source: sharp.source
            sourceSize.width: 560
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            cache: true
        }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.10 }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.50) }
                GradientStop { position: 0.32; color: Qt.rgba(0, 0, 0, 0.06) }
                GradientStop { position: 0.62; color: Qt.rgba(0, 0, 0, 0.07) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }
    }

    // Deeper frost while a password is being entered or checked.
    Item {
        anchors.fill: parent
        opacity: content.typing && !lock.unlocking ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Image {
            anchors.fill: parent
            source: sharp.source
            sourceSize.width: 80
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            cache: true
        }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.16 }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.56) }
                GradientStop { position: 0.32; color: Qt.rgba(0, 0, 0, 0.12) }
                GradientStop { position: 0.62; color: Qt.rgba(0, 0, 0, 0.14) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
            }
        }
    }

    // Foreground
    Item {
        id: ui
        anchors.fill: parent
        opacity: lock.unlocking ? 0 : 1
        scale: lock.unlocking ? 1.02 : 1
        transformOrigin: Item.Center
        Behavior on opacity { NumberAnimation { duration: 230; easing.type: Easing.InCubic } }
        Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.InCubic } }

        // Date and time
        Column {
            id: clockGroup
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(content.height * 0.075) - (1 - content.clockIntro) * 14
            spacing: -Math.round(content.height * 0.012)
            opacity: content.clockIntro

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.date, "dddd, MMMM d")
                color: Qt.rgba(1, 1, 1, 0.80)
                font { family: Theme.font; pixelSize: Math.round(content.height * 0.023); weight: Theme.w(Font.DemiBold); letterSpacing: 0.3 }
            }
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: bigClock.implicitWidth + (meridiem.visible ? meridiem.implicitWidth + 10 : 0)
                height: bigClock.implicitHeight
                Text {
                    id: bigClock
                    text: content.time[0]
                    color: Qt.rgba(1, 1, 1, 0.96)
                    font { family: Theme.font; pixelSize: Math.round(content.height * 0.155); weight: Theme.w(Font.Bold); letterSpacing: -5 }
                }
                Text {
                    id: meridiem
                    visible: text !== ""
                    anchors { left: bigClock.right; leftMargin: 10; baseline: bigClock.baseline }
                    text: content.time[1]
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font { family: Theme.font; pixelSize: Math.round(content.height * 0.030); weight: Theme.w(Font.DemiBold); letterSpacing: 1.5 }
                }
            }
        }

        // Verse of the day (services/Verse, ESV)
        Column {
            id: verse
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: login.top
            anchors.bottomMargin: Math.round(content.height * 0.055)
            width: Math.min(Math.round(content.width * 0.46), 600)
            spacing: 10
            opacity: content.main && (Config.saved.lockVerse ?? true) && Verse.ok && !content.typing ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            Text {
                width: parent.width
                text: "\u201C" + Verse.text + "\u201D"
                color: Qt.rgba(1, 1, 1, 0.84)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                lineHeight: 1.22
                font { family: Theme.font; pixelSize: Math.max(15, Math.round(content.height * 0.0185)); weight: Theme.w(Font.Medium) }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 9
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 1; color: Qt.rgba(1, 1, 1, 0.32) }
                Text {
                    text: Verse.ref
                    color: Qt.rgba(1, 1, 1, 0.52)
                    font { family: Theme.font; pixelSize: 11; weight: Theme.w(Font.DemiBold); letterSpacing: 1.1 }
                }
            }
        }

        // Picture, name, password
        Column {
            id: login
            visible: content.main
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: shakeX
            width: Math.min(320, content.width - 48)
            y: content.height - height - Math.round(content.height * 0.07) + (1 - content.loginIntro) * 18
            spacing: 11
            opacity: content.loginIntro
            property real shakeX: 0

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: login; property: "shakeX"; to: -14; duration: 50 }
                NumberAnimation { target: login; property: "shakeX"; to: 14; duration: 70 }
                NumberAnimation { target: login; property: "shakeX"; to: -10; duration: 70 }
                NumberAnimation { target: login; property: "shakeX"; to: 8; duration: 60 }
                NumberAnimation { target: login; property: "shakeX"; to: 0; duration: 50 }
            }
            Connections { target: lock; function onShake() { shakeAnim.restart(); } }

            // Round picture (Canvas clip: the software renderer can't mask), or an initial.
            Item {
                id: avatarBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: 86; height: 86
                scale: 0.88 + 0.12 * content.loginIntro
                property int tryIdx: 0

                Image {
                    id: face
                    visible: false
                    source: parent.tryIdx < lock.avatars.length ? "file://" + lock.avatars[parent.tryIdx] : ""
                    onStatusChanged: {
                        if (status === Image.Error) Qt.callLater(() => avatarBox.tryIdx++);
                        else if (status === Image.Ready) avatarCanvas.requestPaint();
                    }
                }
                Canvas {
                    id: avatarCanvas
                    anchors.fill: parent
                    anchors.margins: 2
                    onImageLoaded: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d"), w = width;
                        ctx.reset();
                        ctx.beginPath(); ctx.arc(w / 2, w / 2, w / 2, 0, 2 * Math.PI); ctx.closePath();
                        if (face.status === Image.Ready && isImageLoaded(face.source)) {
                            ctx.save();
                            ctx.clip();
                            const iw = face.implicitWidth, ih = face.implicitHeight, side = Math.min(iw, ih);
                            ctx.drawImage(face.source, (iw - side) / 2, (ih - side) / 2, side, side, 0, 0, w, w);
                            ctx.restore();
                        } else {
                            const g = ctx.createLinearGradient(0, 0, 0, w);
                            g.addColorStop(0, Theme.pal.accent);
                            g.addColorStop(1, Theme.pal.overlay);
                            ctx.fillStyle = g;
                            ctx.fill();
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border { width: 1; color: Qt.rgba(1, 1, 1, 0.28) }
                }
                Text {
                    anchors.centerIn: parent
                    visible: face.status !== Image.Ready
                    text: (lock.realName[0] ?? "?").toUpperCase()
                    color: "white"
                    font { family: Theme.font; pixelSize: 34; weight: Theme.w(Font.DemiBold) }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lock.realName
                color: Qt.rgba(1, 1, 1, 0.94)
                font { family: Theme.font; pixelSize: 17; weight: Theme.w(Font.DemiBold) }
            }

            Rectangle {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(300, parent.width)
                height: 44
                radius: height / 2
                property color fill: input.activeFocus ? Qt.rgba(0, 0, 0, 0.34) : Qt.rgba(0, 0, 0, 0.26)
                property color edge: lock.failed ? Qt.alpha(content.errColor, 0.85)
                                   : input.activeFocus ? Qt.rgba(1, 1, 1, 0.44) : Qt.rgba(1, 1, 1, 0.20)
                color: fill
                border { width: 1; color: edge }
                Behavior on fill { ColorAnimation { duration: 160 } }
                Behavior on edge { ColorAnimation { duration: 160 } }

                MouseArea { anchors.fill: parent; z: -1; onClicked: input.forceActiveFocus() }

                Text {
                    id: lockGlyph
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "\uf023"
                    color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.8 : 0.5)
                    font { family: Theme.mono; pixelSize: 13 }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                TextInput {
                    id: input
                    anchors { left: lockGlyph.right; leftMargin: 10; right: action.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    focus: content.main
                    enabled: !lock.pam.active
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    selectByMouse: true
                    color: "white"
                    selectionColor: Qt.rgba(1, 1, 1, 0.3)
                    font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 14; letterSpacing: 2 }
                    clip: true
                    onTextChanged: if (lock.password !== text) lock.password = text
                    Connections { target: lock; function onPasswordChanged() { if (input.text !== lock.password) input.text = lock.password; } }
                    Connections { target: lock; function onFailedChanged() { if (lock.failed) Qt.callLater(() => input.forceActiveFocus()); } }
                    Connections { target: lock.pam; function onActiveChanged() { if (!lock.pam.active) Qt.callLater(() => input.forceActiveFocus()); } }
                    onAccepted: lock.submit()
                    Keys.onEscapePressed: lock.password = ""
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !parent.text
                        text: lock.pam.active ? "Checking…" : "Enter Password"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 14 }
                    }
                }

                Item {
                    id: action
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28

                    Text {
                        anchors.centerIn: parent
                        visible: !lock.typing && !lock.pam.active
                        text: "\u21B5"
                        color: Qt.rgba(1, 1, 1, 0.38)
                        font { family: Theme.font; pixelSize: 15; weight: Theme.w(Font.DemiBold) }
                    }

                    Rectangle {
                        id: go
                        anchors.fill: parent
                        radius: width / 2
                        color: goArea.containsMouse ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.20)
                        border { width: 1; color: Qt.rgba(1, 1, 1, 0.18) }
                        opacity: lock.typing && !lock.pam.active ? 1 : 0
                        scale: lock.typing && !lock.pam.active ? 1 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                        Text {
                            anchors.centerIn: parent
                            text: "→"
                            color: "white"
                            font { family: Theme.font; pixelSize: 14; weight: Theme.w(Font.Bold) }
                        }
                        MouseArea {
                            id: goArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: lock.submit()
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: lock.pam.active
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d"), w = width;
                                ctx.reset();
                                ctx.strokeStyle = "rgba(255,255,255,0.85)";
                                ctx.lineWidth = 2;
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.arc(w / 2, w / 2, w / 2 - 3, 0.3, Math.PI * 1.45);
                                ctx.stroke();
                            }
                        }
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 900
                            loops: Animation.Infinite
                            running: lock.pam.active
                        }
                    }
                }
            }

            // Error / PAM chatter. Fixed height so the login area doesn't jump.
            Item {
                width: parent.width
                height: 16

                Text {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Incorrect password"
                    color: content.errColor
                    opacity: lock.failed ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    font { family: Theme.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) }
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: lock.pam.active && !lock.pam.responseRequired ? lock.pam.message : ""
                    color: Qt.rgba(1, 1, 1, 0.75)
                    opacity: text !== "" && !lock.failed ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
                }
            }
        }

        // A quiet status mark in the corner.
        Row {
            visible: !content.preview
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 26; bottomMargin: 22 }
            spacing: 8
            opacity: 0.55
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf023"
                color: "white"
                font { family: Theme.mono; pixelSize: 10 }
            }
            Text {
                text: "Locked"
                color: "white"
                font { family: Theme.font; pixelSize: 11; weight: Theme.w(Font.Medium); letterSpacing: 0.4 }
            }
        }

        Text {
            visible: content.preview
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 22 }
            text: "Click anywhere to close"
            color: Qt.rgba(1, 1, 1, 0.45)
            font { family: Theme.font; pixelSize: 11; weight: Theme.w(Font.Medium) }
        }
    }

    // Clicking anywhere puts the cursor back in the field.
    MouseArea { anchors.fill: parent; z: -1; onPressed: input.forceActiveFocus() }
}
