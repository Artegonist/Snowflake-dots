import QtQuick

Rectangle {
    id: field

    required property var hub

    property alias text: input.text
    property alias input: input
    property alias validator: input.validator
    property alias echoMode: input.echoMode
    property alias maximumLength: input.maximumLength
    property string placeholder: ""
    property bool centered: false

    signal accepted

    implicitWidth: 120
    implicitHeight: 32
    radius: 8
    color: field.hub.bgInput
    border.width: 1
    border.color: input.activeFocus ? field.hub.accentPrimary : field.hub.separatorColor

    Behavior on border.color { ColorAnimation { duration: 120 } }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: field.centered ? 4 : 8
        anchors.rightMargin: field.centered ? 4 : 8
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: field.centered ? TextInput.AlignHCenter : TextInput.AlignLeft
        color: field.hub.inputTextColor
        selectionColor: field.hub.accentSecondary
        selectedTextColor: field.hub.textMain
        passwordCharacter: "•"
        font.pixelSize: 13
        selectByMouse: true
        activeFocusOnTab: true
        clip: true
        onAccepted: field.accepted()
    }

    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: field.centered ? Text.AlignHCenter : Text.AlignLeft
        visible: input.text.length === 0 && !input.activeFocus
        text: field.placeholder
        color: field.hub.textDim
        font.pixelSize: 13
        elide: Text.ElideRight
    }
}
