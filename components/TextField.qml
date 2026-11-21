import QtQuick
import qs.services

// macOS text field: rounded, with the accent focus ring while editing.
Rectangle {
    id: root
    property alias text: input.text
    property alias input: input
    property string placeholder
    signal accepted()
    signal edited()                      // every keystroke (textEdited), for live-saving fields
    implicitWidth: 220; implicitHeight: 26
    radius: 8
    antialiasing: true
    color: input.activeFocus ? (Theme.dark ? Qt.alpha(Theme.text, 0.11) : "#ffffff") : (Theme.dark ? Qt.alpha(Theme.text, 0.07) : Qt.alpha(Theme.text, 0.04))
    border { width: input.activeFocus ? 2 : 1; color: input.activeFocus ? Theme.focusRing : Qt.alpha(Theme.text, Theme.dark ? 0.08 : 0.1) }
    Behavior on color { ColorAnimation { duration: 120 } }
    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.text
        selectionColor: Theme.selection
        selectedTextColor: Theme.onAccent
        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 }
        onAccepted: root.accepted()
        onTextEdited: root.edited()
        onActiveFocusChanged: if (!activeFocus) root.accepted()
        Text { anchors.verticalCenter: parent.verticalCenter; visible: input.text === ""; text: root.placeholder
            color: Theme.textFaint; font: input.font }
    }
}
