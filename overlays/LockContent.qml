import QtQuick
import Quickshell
import qs.services

// What a lock surface shows (see Lock.qml). Separate so `ipc call lock preview` can show the
// same thing in an ordinary window, without locking anything.
Item {
    id: content
    required property var lock           // the Lock scope: password, pam, realName, …
    property bool main: true             // show the picture / name / password field
    property bool preview: false
    anchors.fill: parent

    // Wallpaper: sharp, plus a tiny copy scaled up as a cheap blur (the shell renders on
    // the CPU, where a real blur of a whole screen is too slow).
    Image {
        anchors.fill: parent
        source: lock.wallpaper ? "file://" + lock.wallpaper : ""
        sourceSize.width: content.width
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Image {
        anchors.fill: parent
        source: lock.wallpaper ? "file://" + lock.wallpaper : ""
        sourceSize.width: 96
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        opacity: lock.typing || lock.pam.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    }
    // Shade behind the clock and the login area so white text always reads.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
        }
    }

    // ── Date and time ─────────────────────────────────────────
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(content.height * 0.07)
        spacing: -Math.round(content.height * 0.012)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "dddd, MMMM d")
            color: Qt.rgba(1, 1, 1, 0.85)
            font { family: Theme.font; pixelSize: Math.round(content.height * 0.024); weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, (Config.saved.clock24h ?? true) ? "HH:mm" : "h:mm")
            color: Qt.rgba(1, 1, 1, 0.9)
            font { family: Theme.font; pixelSize: Math.round(content.height * 0.15); weight: Font.Bold; letterSpacing: -2 }
        }
    }

    // ── Verse of the day (services/Verse, ESV) ────────────────
    Rectangle {
        visible: (Config.saved.lockVerse ?? true) && Verse.ok
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(content.height * 0.36)
        width: Math.min(Math.round(content.width * 0.42), 640)
        height: verseCol.height + 32
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.22)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
        Column {
            id: verseCol
            anchors { left: parent.left; right: parent.right; margins: 22; verticalCenter: parent.verticalCenter }
            spacing: 8
            Text {
                text: "VERSE OF THE DAY"
                color: Qt.rgba(1, 1, 1, 0.6)
                font { family: Theme.font; pixelSize: 11; weight: Font.Bold; letterSpacing: 0.8 }
            }
            Text {
                width: parent.width
                text: "\u201c" + Verse.text + "\u201d"
                color: Theme.inkSet ? Theme.ink : Qt.rgba(1, 1, 1, 0.92)
                wrapMode: Text.WordWrap
                lineHeight: 1.1
                font { family: Theme.font; pixelSize: Math.max(15, Math.round(content.height * 0.019)); weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: "— " + Verse.ref
                color: Qt.rgba(1, 1, 1, 0.7)
                font { family: Theme.font; pixelSize: 13; italic: true }
            }
        }
    }

    // ── Picture, name, password ───────────────────────────────
    Column {
        id: login
        visible: content.main
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shakeX
        y: content.height - height - Math.round(content.height * 0.08)
        spacing: 10
        property real shakeX: 0

        SequentialAnimation {
            id: shakeAnim
            loops: 1
            NumberAnimation { target: login; property: "shakeX"; to: -14; duration: 50 }
            NumberAnimation { target: login; property: "shakeX"; to: 14; duration: 70 }
            NumberAnimation { target: login; property: "shakeX"; to: -10; duration: 70 }
            NumberAnimation { target: login; property: "shakeX"; to: 8; duration: 60 }
            NumberAnimation { target: login; property: "shakeX"; to: 0; duration: 50 }
        }
        Connections { target: lock; function onShake() { shakeAnim.restart(); } }

        // Round picture (Canvas clip: the software renderer can't mask), or an initial.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72
            property int tryIdx: 0
            Image {
                id: face
                visible: false
                source: parent.tryIdx < lock.avatars.length ? "file://" + lock.avatars[parent.tryIdx] : ""
                onStatusChanged: {
                    if (status === Image.Error) Qt.callLater(() => parent.tryIdx++);
                    else if (status === Image.Ready) { avatar.loadImage(source); }
                }
            }
            Canvas {
                id: avatar
                anchors.fill: parent
                onImageLoaded: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"), w = width;
                    ctx.reset();
                    ctx.beginPath(); ctx.arc(w / 2, w / 2, w / 2, 0, 2 * Math.PI); ctx.closePath();
                    if (face.status === Image.Ready && isImageLoaded(face.source)) {
                        ctx.clip();
                        const iw = face.implicitWidth, ih = face.implicitHeight, side = Math.min(iw, ih);
                        ctx.drawImage(face.source, (iw - side) / 2, (ih - side) / 2, side, side, 0, 0, w, w);
                    } else {
                        const g = ctx.createLinearGradient(0, 0, 0, w);
                        g.addColorStop(0, "#a1a1a6"); g.addColorStop(1, "#6e6e73");
                        ctx.fillStyle = g; ctx.fill();
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: face.status !== Image.Ready
                text: (lock.realName[0] ?? "?").toUpperCase()
                color: "white"
                font { family: Theme.font; pixelSize: 32; weight: Font.DemiBold }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: lock.realName
            color: Theme.inkSet ? Theme.ink : "white"
            font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
        }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200; height: 30; radius: 15
            color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.22 : 0.16)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.18) }

            TextInput {
                id: input
                anchors { left: parent.left; leftMargin: 14; right: go.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                focus: content.main
                enabled: !lock.pam.active
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: Theme.inkSet ? Theme.ink : "white"
                selectionColor: Qt.rgba(1, 1, 1, 0.3)
                font { family: Theme.font; pixelSize: 13; letterSpacing: 1 }
                clip: true
                onTextChanged: if (lock.password !== text) lock.password = text
                Connections { target: lock; function onPasswordChanged() { if (input.text !== lock.password) input.text = lock.password; } }
                onAccepted: lock.submit()
                Keys.onEscapePressed: lock.password = ""
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text
                    text: lock.pam.active ? "Checking…" : "Enter Password"
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font { family: Theme.font; pixelSize: 13 }
                }
            }
            // Arrow button, once there's something to submit.
            MouseArea {
                id: go
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                width: 22; height: 22
                visible: lock.typing
                cursorShape: Qt.PointingHandCursor
                onClicked: lock.submit()
                Rectangle { anchors.fill: parent; radius: 11; color: Qt.rgba(1, 1, 1, 0.28) }
                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: Theme.inkSet ? Theme.ink : "white"
                    font { family: Theme.font; pixelSize: 13; weight: Font.Bold }
                }
            }
        }

        // PAM chatter that isn't the password prompt (e.g. "Place your finger…", lockouts).
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            text: lock.pam.active && !lock.pam.responseRequired ? lock.pam.message : ""
            color: Qt.rgba(1, 1, 1, 0.75)
            font { family: Theme.font; pixelSize: 11 }
        }
    }

    // Clicking anywhere puts the cursor back in the field.
    MouseArea { anchors.fill: parent; z: -1; onPressed: input.forceActiveFocus() }
}
