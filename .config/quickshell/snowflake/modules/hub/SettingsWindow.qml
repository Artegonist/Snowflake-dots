import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../services"

Item {
    id: win

    // ------------------------- STATE -------------------------
    required property var hub
    required property var weather
    required property var worldClock
    required property var timer

    property bool open: false
    property string section: "weather"

    signal closeRequested
    signal sectionRequested(string id)

    readonly property var sections: [
        { id: "weather",    title: "Погода",        icon: "󰖕" },
        { id: "clock",      title: "Мировое время", icon: "󰇧" },
        { id: "timer",      title: "Таймер",        icon: "󰔛" },
        { id: "wallpaper",  title: "Тема из обоев", icon: "󰋩" },
        { id: "interface",  title: "Интерфейс",     icon: "󰍹" }
    ]

    readonly property var wt: win.hub.wallpaperTheme

    function wtColor(i) {
        const keys = ["accent_primary", "accent_secondary", "workspace_active", "hover_light",
                      "text_main", "text_dim", "bg_panel_battery", "bg_track"]
        const c = win.wt.lastColors
        return c && c[keys[i]] ? c[keys[i]] : Qt.rgba(win.hub.textDim.r, win.hub.textDim.g, win.hub.textDim.b, 0.25)
    }

    visible: opacity > 0.01
    opacity: win.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    onOpenChanged: if (win.open) win.prepare()
    onSectionChanged: if (win.open) win.prepare()

    function prepare() {
        win.hub.activeDropdown = null
        if (win.section === "weather") {
            win.draftProvider = win.weather.provider
            cityField.text = win.weather.city
            keyField.text = win.weather.owmKey
            win.showKey = false
            win.weatherMsg = ""
            win.weather.settingsMsg = ""
        } else if (win.section === "clock") {
            win.clockMsg = ""
            if (win.zones.length === 0)
                zonesProc.running = true
        } else if (win.section === "timer") {
            win.timerMsg = ""
        }
    }

    function successText(t) {
        return t.indexOf("Сохранено") === 0 || t.indexOf("Готово") === 0 || t.indexOf("Добавлено") === 0
    }

    // ------------------------- COMPONENTS -------------------------
    component SectionTitle: ColumnLayout {
        id: st
        required property var hub
        property string title: ""
        property string text: ""

        Layout.fillWidth: true
        spacing: 4

        Text {
            text: st.title
            color: st.hub.textMain
            font.pixelSize: 20
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: st.text
            color: st.hub.textDim
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    component FieldLabel: Text {
        required property var hub
        color: hub.textDim
        font.pixelSize: 12
        font.bold: true
    }

    component Toggle: Rectangle {
        id: tg
        required property var hub
        property bool checked: false
        signal toggled(bool value)

        implicitWidth: 46
        implicitHeight: 26
        radius: 13
        color: tg.checked ? tg.hub.accentPrimary : tg.hub.bgTrack

        Behavior on color { ColorAnimation { duration: 160 } }

        Rectangle {
            y: 3
            x: tg.checked ? tg.width - width - 3 : 3
            width: 20
            height: 20
            radius: 10
            color: tg.checked ? tg.hub.bgPanel : tg.hub.textDim

            Behavior on x { Anim { kind: "fast" } }
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tg.toggled(!tg.checked)
        }
    }

    component StepButton: Rectangle {
        id: sb
        required property var hub
        property string label: ""
        property bool wide: false

        signal clicked

        implicitWidth: sb.wide ? 84 : 32
        implicitHeight: 32
        radius: 16
        color: sbArea.pressed ? Qt.darker(sb.hub.bgTrack, 1.3) : (sbArea.containsMouse ? Qt.lighter(sb.hub.bgTrack, 1.25) : sb.hub.bgTrack)

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: sb.label
            color: sb.hub.textMain
            font.pixelSize: 15
            font.bold: true
        }

        MouseArea {
            id: sbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }

    function stepGlobalScale(dir) {
        const cur = UiScale.baseScale(win.hub.screen)
        UiScale.setUserScale(Math.round(cur / UiScale.step) * UiScale.step + dir * UiScale.step)
    }

    function stepPanelScale(key, dir) {
        const cur = UiScale.panelMultiplier(key)
        UiScale.setPanelScale(key, Math.round(cur / UiScale.step) * UiScale.step + dir * UiScale.step)
    }

    component Page: Item {
        id: pg
        property bool current: false

        opacity: pg.current ? 1 : 0
        visible: opacity > 0.01
        enabled: pg.current

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        transform: Translate {
            x: pg.current ? 0 : 18
            Behavior on x { Anim { kind: "fast" } }
        }
    }

    // ------------------------- BACKDROP -------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onClicked: win.closeRequested()
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }

    // ------------------------- WINDOW -------------------------
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 1000)
        height: Math.min(parent.height - 24, 630)
        radius: 10
        color: win.hub.bgPanel
        border.width: 2
        border.color: win.hub.accentPrimary
        scale: win.open ? 1 : 0.95

        Behavior on scale { Anim {} }

        transform: Translate {
            y: win.open ? 0 : 14
            Behavior on y { Anim {} }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                win.hub.activeDropdown = null
                panel.forceActiveFocus()
            }
            onWheel: function(wheel) { wheel.accepted = true }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18

            // ------------------------- SIDEBAR -------------------------
            ColumnLayout {
                Layout.preferredWidth: 220
                Layout.maximumWidth: 220
                Layout.fillHeight: true
                spacing: 6

                RowLayout {
                    spacing: 10

                    Text {
                        text: "󰒓"
                        font.family: win.hub.iconFont
                        font.pixelSize: 22
                        color: win.hub.accentPrimary
                    }

                    Text {
                        text: "Настройки"
                        color: win.hub.textMain
                        font.pixelSize: 20
                        font.bold: true
                    }
                }

                Repeater {
                    model: win.sections

                    delegate: Rectangle {
                        id: navItem
                        required property var modelData
                        readonly property bool current: win.section === navItem.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 50
                        radius: 10
                        color: navItem.current ? win.hub.accentPrimary
                             : navArea.containsMouse ? win.hub.bgTrack : "transparent"
                        scale: navArea.pressed ? 0.97 : 1.0

                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: navItem.modelData.icon
                                font.family: win.hub.iconFont
                                font.pixelSize: 18
                                color: navItem.current ? win.hub.bgPanel : win.hub.accentPrimary
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: navItem.modelData.title
                                color: navItem.current ? win.hub.bgPanel : win.hub.textMain
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.sectionRequested(navItem.modelData.id)
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            Separator { vertical: true }

            // ------------------------- SECTIONS -------------------------
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ------------------------- WEATHER -------------------------
                Page {
                    anchors.fill: parent
                    current: win.section === "weather"

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 10

                        SectionTitle {
                            hub: win.hub
                            Layout.bottomMargin: 6
                            title: "Погода"
                        }

                        FieldLabel { hub: win.hub; text: "Источник данных" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Repeater {
                                model: [
                                    { pid: "wttr", name: "wttr.in", sub: "без ключа, иногда медленно" },
                                    { pid: "owm",  name: "OpenWeather", sub: "нужен бесплатный API-ключ" }
                                ]

                                delegate: Rectangle {
                                    id: provBtn
                                    required property var modelData
                                    readonly property bool active: win.draftProvider === provBtn.modelData.pid

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 54
                                    radius: 10
                                    color: provBtn.active ? win.hub.accentPrimary
                                         : provArea.containsMouse ? Qt.lighter(win.hub.bgTrack, 1.15) : win.hub.bgTrack
                                    scale: provArea.pressed ? 0.97 : 1.0

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: provBtn.modelData.name
                                            color: provBtn.active ? win.hub.bgPanel : win.hub.textMain
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: provBtn.modelData.sub
                                            color: provBtn.active
                                                ? Qt.rgba(win.hub.bgPanel.r, win.hub.bgPanel.g, win.hub.bgPanel.b, 0.75)
                                                : win.hub.textDim
                                            font.pixelSize: 11
                                        }
                                    }

                                    MouseArea {
                                        id: provArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.draftProvider = provBtn.modelData.pid
                                    }
                                }
                            }
                        }

                        FieldLabel { hub: win.hub; text: "Город"; Layout.topMargin: 6 }

                        HubInput {
                            id: cityField
                            hub: win.hub
                            Layout.fillWidth: true
                            placeholder: "Например, Aalborg"
                            onAccepted: win.saveWeather()
                        }

                        FieldLabel {
                            hub: win.hub
                            Layout.topMargin: 6
                            visible: win.draftProvider === "owm"
                            text: "API-ключ OpenWeather"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.draftProvider === "owm"
                            spacing: 6

                            HubInput {
                                id: keyField
                                hub: win.hub
                                Layout.fillWidth: true
                                placeholder: "вставьте ключ (Ctrl+V)"
                                echoMode: win.showKey ? TextInput.Normal : TextInput.Password
                                onAccepted: win.saveWeather()
                            }

                            IconButton {
                                hub: win.hub
                                size: 32
                                glyph: win.showKey ? "󰈉" : "󰈈"
                                glyphColor: win.hub.textDim
                                onClicked: win.showKey = !win.showKey
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: win.draftProvider === "owm"
                                ? "Бесплатный ключ: openweathermap.org → API keys. Новый ключ может заработать "
                                  + "только через 1–2 часа. Хранится в ~/.local/share/snowflake/hub/weather.json"
                                : "wttr.in работает без ключа, но иногда отвечает медленно."
                            color: win.hub.textDim
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 12

                            HubButton {
                                hub: win.hub
                                icon: "󰑐"
                                text: "Сохранить и обновить"
                                onClicked: win.saveWeather()
                            }

                            Text {
                                Layout.fillWidth: true
                                readonly property string msg: win.weatherMsg !== "" ? win.weatherMsg : win.weather.settingsMsg
                                text: msg
                                color: win.successText(msg) ? win.hub.accentPrimary : win.hub.danger
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            text: "Сейчас: " + win.weather.city + " · " + (win.weather.provider === "owm" ? "OpenWeather" : "wttr.in")
                                + (win.weather.lastUpdate > 0 ? " · обновлено в " + Qt.formatTime(new Date(win.weather.lastUpdate), "HH:mm") : "")
                            color: win.hub.textDim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                // ------------------------- WORLD CLOCK -------------------------
                Page {
                    anchors.fill: parent
                    current: win.section === "clock"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        SectionTitle {
                            hub: win.hub
                            Layout.bottomMargin: 6
                            title: "Мировое время"
                            text: "Максимум 8"
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 110

                            ListView {
                                id: cityList
                                anchors.fill: parent
                                clip: true
                                spacing: 6
                                boundsBehavior: Flickable.StopAtBounds
                                model: win.worldClock.cities

                                SmoothScroll { flick: cityList }

                                delegate: Rectangle {
                                    id: cityRow
                                    required property var modelData
                                    required property int index
                                    readonly property var info: win.worldClock.cityInfo(cityRow.modelData, win.worldClock.nowMs, win.worldClock.offsets)

                                    width: cityList.width
                                    height: 50
                                    radius: 10
                                    color: rowHover.hovered ? Qt.lighter(win.hub.bgTrack, 1.15) : win.hub.bgTrack

                                    Behavior on color { ColorAnimation { duration: 140 } }

                                    HoverHandler { id: rowHover }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 8
                                        spacing: 10

                                        Text {
                                            text: String(cityRow.index + 1)
                                            color: win.hub.accentPrimary
                                            font.pixelSize: 13
                                            font.bold: true
                                            font.family: win.hub.monoFont
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                Layout.fillWidth: true
                                                text: cityRow.modelData.label
                                                color: win.hub.textMain
                                                font.pixelSize: 14
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: cityRow.modelData.zone + " · " + cityRow.info.sub
                                                color: win.hub.textDim
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            text: cityRow.info.hm
                                            color: win.hub.textMain
                                            font.pixelSize: 18
                                            font.bold: true
                                            font.family: win.hub.monoFont
                                        }

                                        IconButton {
                                            hub: win.hub
                                            size: 28
                                            glyph: "󰅃"
                                            glyphColor: win.hub.textDim
                                            opacity: cityRow.index > 0 ? 1 : 0.3
                                            enabled: cityRow.index > 0
                                            onClicked: win.worldClock.moveCity(cityRow.index, -1)
                                        }

                                        IconButton {
                                            hub: win.hub
                                            size: 28
                                            glyph: "󰅀"
                                            glyphColor: win.hub.textDim
                                            opacity: cityRow.index < win.worldClock.cities.length - 1 ? 1 : 0.3
                                            enabled: cityRow.index < win.worldClock.cities.length - 1
                                            onClicked: win.worldClock.moveCity(cityRow.index, 1)
                                        }

                                        IconButton {
                                            hub: win.hub
                                            size: 28
                                            glyph: "󰧧"
                                            glyphColor: win.hub.danger
                                            onClicked: win.worldClock.removeCity(cityRow.index)
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: cityList.count === 0
                                text: "Пока ни одного города — добавьте ниже"
                                color: win.hub.textDim
                                font.pixelSize: 13
                            }
                        }

                        Separator {}

                        FieldLabel { hub: win.hub; text: "Добавить город" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            z: suggestBox.visible ? 100 : 1

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1.5
                                implicitHeight: 32

                                HubInput {
                                    id: zoneSearch
                                    anchors.fill: parent
                                    hub: win.hub
                                    placeholder: "Город или пояс: Москва, Paris, Europe/Belgrade"
                                    onAccepted: win.addCity()
                                }

                                Rectangle {
                                    id: suggestBox
                                    visible: zoneSearch.input.activeFocus && win.suggestions.length > 0
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: 6
                                    height: suggestCol.implicitHeight + 8
                                    radius: 8
                                    color: win.hub.bgPanel
                                    border.width: 1
                                    border.color: win.hub.accentPrimary

                                    Column {
                                        id: suggestCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 4
                                        spacing: 2

                                        Repeater {
                                            model: win.suggestions

                                            delegate: Rectangle {
                                                id: sugItem
                                                required property var modelData

                                                width: suggestCol.width
                                                height: 30
                                                radius: 6
                                                color: sugArea.containsMouse ? win.hub.bgTrack : "transparent"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 10

                                                    Text {
                                                        text: sugItem.modelData.name
                                                        color: win.hub.textMain
                                                        font.pixelSize: 13
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: sugItem.modelData.zone
                                                        color: win.hub.textDim
                                                        font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                MouseArea {
                                                    id: sugArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: win.pickSuggestion(sugItem.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            HubInput {
                                id: nameField
                                hub: win.hub
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                placeholder: "Название (необязательно)"
                                onAccepted: win.addCity()
                            }

                            HubButton {
                                hub: win.hub
                                icon: "󰐕"
                                text: "Добавить"
                                active: win.worldClock.cities.length < win.worldClock.maxCities
                                onClicked: win.addCity()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumHeight: 16
                            text: win.clockMsg
                            color: win.successText(win.clockMsg) ? win.hub.accentPrimary : win.hub.danger
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                // ------------------------- TIMER -------------------------
                Page {
                    anchors.fill: parent
                    current: win.section === "timer"

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 10

                        SectionTitle {
                            hub: win.hub
                            Layout.bottomMargin: 6
                            title: "Таймер"
                            text: "Настройка быстрых пресетов"
                        }

                        FieldLabel { hub: win.hub; text: "Пресеты" }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: win.timer.presets

                                delegate: Rectangle {
                                    id: presetChip
                                    required property int modelData
                                    required property int index

                                    width: chipRow.implicitWidth + 24
                                    height: 36
                                    radius: 18
                                    color: win.hub.bgTrack

                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 10

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: win.timer.presetLabel(presetChip.modelData, true)
                                            color: win.hub.textMain
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 24
                                            height: 24
                                            radius: 12
                                            color: delArea.containsMouse ? win.hub.danger : "transparent"

                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰧧"
                                                font.family: win.hub.iconFont
                                                font.pixelSize: 13
                                                color: delArea.containsMouse ? win.hub.bgPanel : win.hub.textDim
                                            }

                                            MouseArea {
                                                id: delArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.timerMsg = win.timer.removePreset(presetChip.index)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            HubInput {
                                id: presetH
                                hub: win.hub
                                implicitWidth: 56
                                centered: true
                                placeholder: "ч"
                                maximumLength: 2
                                validator: IntValidator { bottom: 0; top: 99 }
                                onAccepted: win.addPreset()
                            }

                            Text {
                                text: ":"
                                color: win.hub.textDim
                                font.pixelSize: 18
                                font.bold: true
                            }

                            HubInput {
                                id: presetM
                                hub: win.hub
                                implicitWidth: 56
                                centered: true
                                placeholder: "мин"
                                maximumLength: 2
                                validator: IntValidator { bottom: 0; top: 59 }
                                onAccepted: win.addPreset()
                            }

                            Text {
                                text: ":"
                                color: win.hub.textDim
                                font.pixelSize: 18
                                font.bold: true
                            }

                            HubInput {
                                id: presetS
                                hub: win.hub
                                implicitWidth: 56
                                centered: true
                                placeholder: "сек"
                                maximumLength: 2
                                validator: IntValidator { bottom: 0; top: 59 }
                                onAccepted: win.addPreset()
                            }

                            HubButton {
                                hub: win.hub
                                icon: "󰐕"
                                text: "Добавить"
                                active: win.timer.presets.length < win.timer.maxPresets
                                onClicked: win.addPreset()
                            }

                            Text {
                                Layout.fillWidth: true
                                text: win.timerMsg
                                color: win.successText(win.timerMsg) ? win.hub.accentPrimary : win.hub.danger
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        Separator { Layout.topMargin: 8; Layout.bottomMargin: 8 }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Уведомление, когда время вышло"
                                    color: win.hub.textMain
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: "необходим notify-send"
                                    color: win.hub.textDim
                                    font.pixelSize: 11
                                }
                            }

                            Toggle {
                                hub: win.hub
                                checked: win.timer.notify
                                onToggled: function(value) { win.timer.setNotify(value) }
                            }
                        }
                    }
                }

                // ------------------------- INTERFACE -------------------------
                Page {
                    anchors.fill: parent
                    current: win.section === "interface"

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 10

                        SectionTitle {
                            hub: win.hub
                            Layout.bottomMargin: 6
                            title: "Интерфейс"
                            text: "Масштаб окон. «Авто» подбирает его по размеру экрана; ниже каждое окно можно подстроить отдельно"
                        }

                        FieldLabel { hub: win.hub; text: "Общий масштаб" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StepButton {
                                hub: win.hub
                                label: "−"
                                onClicked: win.stepGlobalScale(-1)
                            }

                            Rectangle {
                                Layout.preferredWidth: 140
                                Layout.preferredHeight: 32
                                radius: 16
                                color: "transparent"
                                border.width: 1
                                border.color: win.hub.accentPrimary

                                Text {
                                    anchors.centerIn: parent
                                    text: (UiScale.userScale > 0 ? "" : "Авто · ") + Math.round(UiScale.baseScale(win.hub.screen) * 100) + "%"
                                    color: win.hub.textMain
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }

                            StepButton {
                                hub: win.hub
                                label: "+"
                                onClicked: win.stepGlobalScale(1)
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [0, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

                                delegate: Rectangle {
                                    id: scaleChip
                                    required property real modelData
                                    readonly property bool active: Math.abs(UiScale.userScale - scaleChip.modelData) < 0.001

                                    width: 81
                                    height: 32
                                    radius: 16
                                    color: scaleChip.active ? win.hub.accentPrimary : win.hub.bgTrack

                                    Behavior on color { ColorAnimation { duration: 160 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: scaleChip.modelData === 0 ? "Авто" : Math.round(scaleChip.modelData * 100) + "%"
                                        color: scaleChip.active ? win.hub.bgPanel : win.hub.textMain
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: UiScale.setUserScale(scaleChip.modelData)
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Окно никогда не станет больше экрана, даже при большом значении"
                            color: win.hub.textDim
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        FieldLabel { hub: win.hub; text: "Отдельные окна (множитель к общему масштабу)"; Layout.topMargin: 6 }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 28
                            rowSpacing: 6

                            Repeater {
                                model: UiScale.panelList

                                delegate: RowLayout {
                                    id: panelRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: panelRow.modelData.title
                                        color: win.hub.textMain
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }

                                    StepButton {
                                        hub: win.hub
                                        label: "−"
                                        onClicked: win.stepPanelScale(panelRow.modelData.id, -1)
                                    }

                                    Text {
                                        Layout.preferredWidth: 46
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Math.round(UiScale.panelMultiplier(panelRow.modelData.id) * 100) + "%"
                                        color: Math.abs(UiScale.panelMultiplier(panelRow.modelData.id) - 1) < 0.001 ? win.hub.textDim : win.hub.accentPrimary
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    StepButton {
                                        hub: win.hub
                                        label: "+"
                                        onClicked: win.stepPanelScale(panelRow.modelData.id, 1)
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 8

                            StepButton {
                                hub: win.hub
                                wide: true
                                label: "Сбросить"
                                implicitWidth: 110
                                onClicked: UiScale.resetAll()
                            }

                            Text {
                                text: "общий масштаб → Авто, все окна → 100%"
                                color: win.hub.textDim
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // ------------------------- WALLPAPER THEME -------------------------
                Page {
                    anchors.fill: parent
                    current: win.section === "wallpaper"

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 10

                        SectionTitle {
                            hub: win.hub
                            Layout.bottomMargin: 6
                            title: "Тема из обоев"
                            text: "Настройки автоматического подбора тем из обоев с помощью матугена"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: wtRow.implicitHeight + 24
                            radius: 10
                            color: win.hub.bgTrack

                            RowLayout {
                                id: wtRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12
                                spacing: 14

                                Grid {
                                    columns: 4
                                    spacing: 4

                                    Repeater {
                                        model: 8

                                        delegate: Rectangle {
                                            required property int index
                                            width: 14
                                            height: 14
                                            radius: 4
                                            color: win.wtColor(index)
                                            border.width: 1
                                            border.color: Qt.rgba(0, 0, 0, 0.25)
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: win.wt.busy ? "Сканирую обои…" : win.wt.active ? "Включено" : "Выключено"
                                        color: win.wt.active ? win.hub.accentPrimary : win.hub.textMain
                                        font.pixelSize: 15
                                        font.bold: true
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (win.wt.lastWallpaper !== ""
                                                ? "Обои: " + win.wt.lastWallpaper.split("/").pop()
                                                : "Обои ещё не сканировались")
                                            + (win.wt.lastRun > 0 ? " · " + Qt.formatDateTime(new Date(win.wt.lastRun), "dd.MM HH:mm") : "")
                                        color: win.hub.textDim
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }
                                }

                                HubButton {
                                    hub: win.hub
                                    icon: "󰑐"
                                    text: win.wt.active ? "Пересобрать" : "Включить"
                                    active: !win.wt.busy
                                    onClicked: win.wt.enable()
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: win.wt.status !== ""
                            text: win.wt.status
                            color: win.wt.failed ? win.hub.danger : win.hub.textDim
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        FieldLabel { hub: win.hub; text: "Вариант"; Layout.topMargin: 6 }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Repeater {
                                model: [{ mid: "dark", name: "Тёмная" }, { mid: "light", name: "Светлая" }]

                                delegate: Rectangle {
                                    id: modeBtn
                                    required property var modelData
                                    readonly property bool active: win.wt.mode === modeBtn.modelData.mid

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 36
                                    radius: 10
                                    color: modeBtn.active ? win.hub.accentPrimary
                                         : modeArea.containsMouse ? Qt.lighter(win.hub.bgTrack, 1.15) : win.hub.bgTrack
                                    scale: modeArea.pressed ? 0.97 : 1.0

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modeBtn.modelData.name
                                        color: modeBtn.active ? win.hub.bgPanel : win.hub.textMain
                                        font.pixelSize: 13
                                        font.bold: modeBtn.active
                                    }

                                    MouseArea {
                                        id: modeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.wt.setMode(modeBtn.modelData.mid)
                                    }
                                }
                            }
                        }

                        FieldLabel { hub: win.hub; text: "Схема Material You"; Layout.topMargin: 6 }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: win.wt.schemes

                                delegate: Rectangle {
                                    id: schemeChip
                                    required property var modelData
                                    readonly property bool active: win.wt.scheme === schemeChip.modelData.id

                                    width: schemeText.implicitWidth + 28
                                    height: 32
                                    radius: 16
                                    color: schemeChip.active ? win.hub.accentPrimary
                                         : schemeArea.containsMouse ? Qt.lighter(win.hub.bgTrack, 1.15) : win.hub.bgTrack

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        id: schemeText
                                        anchors.centerIn: parent
                                        text: schemeChip.modelData.title
                                        color: schemeChip.active ? win.hub.bgPanel : win.hub.textMain
                                        font.pixelSize: 13
                                        font.bold: schemeChip.active
                                    }

                                    MouseArea {
                                        id: schemeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.wt.setScheme(schemeChip.modelData.id)
                                    }
                                }
                            }
                        }

                        FieldLabel { hub: win.hub; text: "Основной цвет с обоев"; Layout.topMargin: 6 }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: win.wt.sources

                                delegate: Rectangle {
                                    id: srcChip
                                    required property var modelData
                                    required property int index
                                    readonly property bool active: win.wt.sourceIndex === srcChip.index

                                    implicitWidth: 64
                                    implicitHeight: 34
                                    radius: 17
                                    color: srcArea.containsMouse ? Qt.lighter(win.hub.bgTrack, 1.15) : win.hub.bgTrack
                                    border.width: srcChip.active ? 2 : 0
                                    border.color: win.hub.accentPrimary

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 18
                                            height: 18
                                            radius: 9
                                            color: srcChip.modelData
                                            border.width: 1
                                            border.color: Qt.rgba(0, 0, 0, 0.3)
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(srcChip.index + 1)
                                            color: srcChip.active ? win.hub.accentPrimary : win.hub.textMain
                                            font.pixelSize: 13
                                            font.bold: srcChip.active
                                        }
                                    }

                                    MouseArea {
                                        id: srcArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.wt.setSourceIndex(srcChip.index)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                color: win.hub.textDim
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Свечение часов в Waybar"
                                    color: win.hub.textMain
                                    font.pixelSize: 14
                                }
                            }

                            Toggle {
                                hub: win.hub
                                checked: win.wt.glow
                                onToggled: function(value) { win.wt.setGlow(value) }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            color: win.hub.textDim
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    // ------------------------- WEATHER LOGIC -------------------------
    property string draftProvider: "wttr"
    property bool showKey: false
    property string weatherMsg: ""

    function saveWeather() {
        win.weatherMsg = win.weather.applySettings(win.draftProvider, cityField.text, keyField.text)
    }

    // ------------------------- TIMER LOGIC -------------------------
    property string timerMsg: ""

    function addPreset() {
        const h = parseInt(presetH.text, 10) || 0
        const m = parseInt(presetM.text, 10) || 0
        const s = parseInt(presetS.text, 10) || 0
        const err = win.timer.addPreset(Math.min(99, h) * 3600 + Math.min(59, m) * 60 + Math.min(59, s))
        win.timerMsg = err
        if (err === "") {
            presetH.text = ""
            presetM.text = ""
            presetS.text = ""
        }
    }

    // ------------------------- WORLD CLOCK LOGIC -------------------------
    property string clockMsg: ""
    property var zones: []
    readonly property string query: zoneSearch.text

    readonly property var aliases: [
        { name: "Москва", zone: "Europe/Moscow" }, { name: "Санкт-Петербург", zone: "Europe/Moscow" },
        { name: "Киев", zone: "Europe/Kyiv|Europe/Kiev" }, { name: "Минск", zone: "Europe/Minsk" },
        { name: "Варшава", zone: "Europe/Warsaw" }, { name: "Берлин", zone: "Europe/Berlin" },
        { name: "Париж", zone: "Europe/Paris" }, { name: "Лондон", zone: "Europe/London" },
        { name: "Мадрид", zone: "Europe/Madrid" }, { name: "Рим", zone: "Europe/Rome" },
        { name: "Амстердам", zone: "Europe/Amsterdam" }, { name: "Прага", zone: "Europe/Prague" },
        { name: "Вена", zone: "Europe/Vienna" }, { name: "Белград", zone: "Europe/Belgrade" },
        { name: "Копенгаген", zone: "Europe/Copenhagen" }, { name: "Ольборг", zone: "Europe/Copenhagen" },
        { name: "Стокгольм", zone: "Europe/Stockholm" }, { name: "Осло", zone: "Europe/Oslo" },
        { name: "Хельсинки", zone: "Europe/Helsinki" }, { name: "Рига", zone: "Europe/Riga" },
        { name: "Вильнюс", zone: "Europe/Vilnius" }, { name: "Таллин", zone: "Europe/Tallinn" },
        { name: "Стамбул", zone: "Europe/Istanbul" }, { name: "Афины", zone: "Europe/Athens" },
        { name: "Дубай", zone: "Asia/Dubai" }, { name: "Тбилиси", zone: "Asia/Tbilisi" },
        { name: "Ереван", zone: "Asia/Yerevan" }, { name: "Баку", zone: "Asia/Baku" },
        { name: "Алматы", zone: "Asia/Almaty" }, { name: "Ташкент", zone: "Asia/Tashkent" },
        { name: "Екатеринбург", zone: "Asia/Yekaterinburg" }, { name: "Новосибирск", zone: "Asia/Novosibirsk" },
        { name: "Владивосток", zone: "Asia/Vladivostok" }, { name: "Дели", zone: "Asia/Kolkata" },
        { name: "Пекин", zone: "Asia/Shanghai" }, { name: "Шанхай", zone: "Asia/Shanghai" },
        { name: "Гонконг", zone: "Asia/Hong_Kong" }, { name: "Сингапур", zone: "Asia/Singapore" },
        { name: "Сеул", zone: "Asia/Seoul" }, { name: "Токио", zone: "Asia/Tokyo" },
        { name: "Сидней", zone: "Australia/Sydney" }, { name: "Нью-Йорк", zone: "America/New_York" },
        { name: "Лос-Анджелес", zone: "America/Los_Angeles" }, { name: "Чикаго", zone: "America/Chicago" },
        { name: "Торонто", zone: "America/Toronto" }, { name: "Мехико", zone: "America/Mexico_City" },
        { name: "Сан-Паулу", zone: "America/Sao_Paulo" }, { name: "Буэнос-Айрес", zone: "America/Argentina/Buenos_Aires" },
        { name: "Каир", zone: "Africa/Cairo" }, { name: "Йоханнесбург", zone: "Africa/Johannesburg" },
        { name: "Гонолулу", zone: "Pacific/Honolulu" }, { name: "UTC", zone: "UTC|Etc/UTC" }
    ]

    function aliasZone(a) {
        const options = a.zone.split("|")
        if (win.zones.length === 0) return options[0]
        for (const z of options)
            if (win.zones.indexOf(z) >= 0) return z
        return options[0]
    }

    readonly property var suggestions: {
        const q = win.query.trim().toLowerCase()
        if (q.length < 2) return []
        const out = []
        const seen = {}
        const push = (name, zone) => {
            const key = name + "|" + zone
            if (out.length >= 6 || seen[key]) return
            seen[key] = true
            out.push({ name: name, zone: zone })
        }
        for (const a of win.aliases)
            if (a.name.toLowerCase().indexOf(q) === 0) push(a.name, win.aliasZone(a))
        for (const a of win.aliases)
            if (a.name.toLowerCase().indexOf(q) > 0) push(a.name, win.aliasZone(a))
        const qz = q.replace(/\s+/g, "_")
        for (const z of win.zones)
            if (z.split("/").pop().toLowerCase().indexOf(qz) === 0) push(win.worldClock.zoneLabel(z), z)
        for (const z of win.zones)
            if (z.toLowerCase().indexOf(qz) >= 0) push(win.worldClock.zoneLabel(z), z)
        return out
    }

    function resolveZone(text) {
        const t = String(text).trim()
        if (t === "") return null
        const lower = t.toLowerCase()
        for (const z of win.zones)
            if (z.toLowerCase() === lower) return { name: "", zone: z }
        for (const a of win.aliases)
            if (a.name.toLowerCase() === lower) return { name: a.name, zone: win.aliasZone(a) }
        if (win.zones.length === 0 && t.indexOf("/") > 0) return { name: "", zone: t }
        if (win.suggestions.length === 1) return win.suggestions[0]
        return null
    }

    function pickSuggestion(s) {
        zoneSearch.text = s.zone
        if (nameField.text.trim() === "")
            nameField.text = s.name
        win.clockMsg = ""
        nameField.input.forceActiveFocus()
    }

    function addCity() {
        const found = win.resolveZone(zoneSearch.text)
        if (!found) {
            win.clockMsg = "Не нашёл такой часовой пояс — выберите из подсказок"
            return
        }
        const name = nameField.text.trim() || found.name || win.worldClock.zoneLabel(found.zone)
        const err = win.worldClock.addCity(name, found.zone)
        if (err !== "") {
            win.clockMsg = err
            return
        }
        win.clockMsg = "Добавлено: " + name
        zoneSearch.text = ""
        nameField.text = ""
        Qt.callLater(function() { cityList.positionViewAtEnd() })
    }

    Process {
        id: zonesProc
        command: ["sh", "-c",
            "timedatectl list-timezones 2>/dev/null || "
            + "(cd /usr/share/zoneinfo 2>/dev/null && find . \\( -type f -o -type l \\) | sed 's|^\\./||' "
            + "| grep -E '^(UTC|[A-Z][A-Za-z_]+(/[A-Za-z0-9_+-]+)+)$' | sort)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").map(s => s.trim()).filter(s => s.length > 0)
                if (list.length > 0)
                    win.zones = list
            }
        }
    }
}
