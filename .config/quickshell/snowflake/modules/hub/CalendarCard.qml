import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub

    spacing: 10

    signal daySelected(int day, int month, int year)

    property var cursorDate: new Date()
    property int selectedDay: 0
    property string todayKey: root.dateKey(new Date())

    property var customDates: []

    property int slideDir: 0

    readonly property var monthNames: ["январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
    readonly property var monthNamesGen: ["января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property var dowNames: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    readonly property var holidays: ({
        "01-01": "Новый год",
        "01-07": "Рождество",
        "02-23": "День защитника Отечества",
        "03-08": "Международный женский день",
        "05-01": "Праздник Весны и Труда",
        "05-09": "День Победы",
        "06-12": "День России",
        "11-04": "День народного единства"
    })

    // ------------------------- DATES -------------------------
    function dateKey(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
    }

    function shiftMonth(delta) {
        root.slideDir = delta > 0 ? 1 : -1
        root.cursorDate = new Date(root.cursorDate.getFullYear(), root.cursorDate.getMonth() + delta, 1)
        gridSlide.restart()
    }

    function goToday() {
        const t = new Date()
        const diff = (t.getFullYear() - root.cursorDate.getFullYear()) * 12 + t.getMonth() - root.cursorDate.getMonth()
        if (diff !== 0)
            root.shiftMonth(diff)
    }

    onCursorDateChanged: root.selectedDay = 0

    function holidayName(m, d) {
        const key = String(m + 1).padStart(2, "0") + "-" + String(d).padStart(2, "0")
        return root.holidays[key] || ""
    }

    function customNamesForDay(y, m, d, list) {
        const names = []
        for (const e of list) {
            if (e.month === m && e.day === d && (e.year === null || e.year === undefined || e.year === y))
                names.push(e.label)
        }
        return names
    }

    function eventNameForDay(y, m, d, list) {
        const parts = []
        const h = root.holidayName(m, d)
        if (h !== "")
            parts.push(h)
        for (const n of root.customNamesForDay(y, m, d, list))
            parts.push(n)
        return parts.join(", ")
    }

    function buildDays(cursor, list, todayKey) {
        const y = cursor.getFullYear()
        const m = cursor.getMonth()
        const firstDow = (new Date(y, m, 1).getDay() + 6) % 7
        const daysInMonth = new Date(y, m + 1, 0).getDate()
        const prevDays = new Date(y, m, 0).getDate()

        const cells = []
        for (let i = 0; i < firstDow; i++)
            cells.push({ label: "" + (prevDays - firstDow + 1 + i), day: 0, muted: true,
                         today: false, holiday: "", custom: false, weekend: i >= 5 })
        for (let d = 1; d <= daysInMonth; d++) {
            const col = cells.length % 7
            cells.push({ label: "" + d, day: d, muted: false,
                         today: root.dateKey(new Date(y, m, d)) === todayKey,
                         holiday: root.holidayName(m, d),
                         custom: root.customNamesForDay(y, m, d, list).length > 0,
                         weekend: col >= 5 })
        }
        let next = 1
        while (cells.length < 42) {
            const col = cells.length % 7
            cells.push({ label: "" + next, day: 0, muted: true,
                         today: false, holiday: "", custom: false, weekend: col >= 5 })
            next++
        }
        return cells
    }

    readonly property var days: root.buildDays(root.cursorDate, root.customDates, root.todayKey)

    readonly property var monthEvents: {
        const y = root.cursorDate.getFullYear()
        const m = root.cursorDate.getMonth()
        const daysInMonth = new Date(y, m + 1, 0).getDate()
        const list = []
        for (let d = 1; d <= daysInMonth; d++) {
            const name = root.eventNameForDay(y, m, d, root.customDates)
            if (name !== "")
                list.push({ day: d, name: name })
        }
        return list
    }

    readonly property bool isCurrentMonth: {
        const t = new Date()
        const k = root.todayKey
        return root.cursorDate.getFullYear() === t.getFullYear() && root.cursorDate.getMonth() === t.getMonth()
    }

    readonly property string monthTitle: {
        const n = root.monthNames[root.cursorDate.getMonth()]
        return n.charAt(0).toUpperCase() + n.slice(1) + " " + root.cursorDate.getFullYear()
    }

    readonly property int daysInShownMonth: new Date(root.cursorDate.getFullYear(), root.cursorDate.getMonth() + 1, 0).getDate()
    readonly property int todayDate: parseInt(root.todayKey.split("-")[2], 10)
    readonly property real monthProgress: Math.min(1, root.todayDate / root.daysInShownMonth)

    readonly property string selectedText: {
        if (root.selectedDay <= 0)
            return "Выберите день — он подставится в «Мои даты»"
        const y = root.cursorDate.getFullYear()
        const m = root.cursorDate.getMonth()
        const name = root.eventNameForDay(y, m, root.selectedDay, root.customDates)
        return root.selectedDay + " " + root.monthNamesGen[m] + " · " + (name !== "" ? name : "нет событий")
    }

    readonly property var customDatesSorted: {
        const list = root.customDates.map((e, i) => Object.assign({ idx: i }, e))
        list.sort((a, b) => (a.month - b.month) || (a.day - b.day) || ((a.year || 0) - (b.year || 0)))
        return list
    }

    Timer {
        interval: 60000
        running: root.hub.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const k = root.dateKey(new Date())
            if (k !== root.todayKey)
                root.todayKey = k
        }
    }

    // ------------------------- PERSISTENT STATE -------------------------
    JsonFile {
        id: datesFile
        path: root.hub.dataDir + "/important_dates.json"
        legacyPath: ".cache/hub-module/important_dates.json"
        onLoaded: function(value) {
            root.customDates = Array.isArray(value) ? value : []
        }
    }

    Component.onCompleted: datesFile.load()

    function addCustomDate(label, month, day, recurring, year) {
        const arr = root.customDates.slice()
        arr.push({ label: label, month: month, day: day, year: recurring ? null : year })
        root.customDates = arr
        datesFile.save(arr)
    }

    function removeCustomDate(idx) {
        const arr = root.customDates.slice()
        arr.splice(idx, 1)
        root.customDates = arr
        datesFile.save(arr)
    }

    // ------------------------- MY DATES FORM -------------------------
    property string formError: ""
    readonly property bool popupOpen: myDates.popupVisible

    function submitForm() {
        const day = parseInt(dayField.text, 10)
        const month = parseInt(monthField.text, 10)
        const year = parseInt(yearField.text, 10)
        const label = labelField.text.trim()
        const recurring = recurringToggle.checked

        if (!day || !month) {
            root.formError = "Укажите день и месяц"
            return
        }
        if (!recurring && !year) {
            root.formError = "Укажите год или отметьте «ежегодно»"
            return
        }
        const maxDay = new Date(recurring ? 2024 : year, month, 0).getDate()
        if (day > maxDay) {
            root.formError = "В " + root.monthNamesGen[month - 1].replace(/я$/, "е").replace(/а$/, "е") + " нет " + day + "-го числа"
            return
        }
        if (label.length === 0) {
            root.formError = "Добавьте название"
            labelField.input.forceActiveFocus()
            return
        }

        root.formError = ""
        root.addCustomDate(label, month - 1, day, recurring, year)
        dayField.text = ""
        monthField.text = ""
        yearField.text = ""
        labelField.text = ""
    }

    onDaySelected: function(day, month, year) {
        dayField.text = String(day)
        monthField.text = String(month)
        yearField.text = String(year)
    }

    // ------------------------- GRID + SIDEBAR -------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        // ------------------------- DAY GRID -------------------------
        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: 8

            Item {
                implicitWidth: grid.implicitWidth
                implicitHeight: grid.implicitHeight
                clip: true

                WheelHandler {
                    property real acc: 0
                    onWheel: function(event) {
                        acc += event.angleDelta.y
                        if (acc >= 120) {
                            acc = 0
                            root.shiftMonth(-1)
                        } else if (acc <= -120) {
                            acc = 0
                            root.shiftMonth(1)
                        }
                    }
                }

                SequentialAnimation {
                    id: gridSlide
                    ScriptAction {
                        script: {
                            gridShift.x = 30 * root.slideDir
                            grid.opacity = 0.2
                        }
                    }
                    ParallelAnimation {
                        Anim { target: gridShift; property: "x"; to: 0 }
                        NumberAnimation { target: grid; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }
                }

                GridLayout {
                    id: grid
                    anchors.fill: parent
                    columns: 7
                    rowSpacing: 5
                    columnSpacing: 5

                    transform: Translate { id: gridShift }

                    Repeater {
                        model: root.dowNames

                        delegate: Text {
                            required property string modelData
                            required property int index
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: 2
                            text: modelData
                            color: index >= 5 ? root.hub.accentPrimary : root.hub.textDim
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    Repeater {
                        model: root.days

                        delegate: Rectangle {
                            id: cell
                            required property var modelData

                            readonly property bool isHoliday: cell.modelData.holiday !== ""
                            readonly property bool isSelected: !cell.modelData.muted && cell.modelData.day === root.selectedDay

                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 30
                            radius: 8
                            color: cell.modelData.today ? root.hub.accentPrimary
                                 : cell.isSelected ? root.hub.bgTrack
                                 : (cellArea.containsMouse && !cell.modelData.muted) ? root.hub.hoverColor
                                 : "transparent"
                            border.width: cell.modelData.today ? 0 : ((cell.isHoliday || cell.isSelected) ? 1 : 0)
                            border.color: cell.isHoliday ? root.hub.accentPrimary : root.hub.accentSecondary

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: cell.modelData.custom ? -2 : 0
                                text: cell.modelData.label
                                font.pixelSize: 14
                                font.bold: cell.modelData.today || cell.isHoliday
                                color: cell.modelData.today ? root.hub.bgPanel
                                     : cell.modelData.muted ? Qt.rgba(root.hub.textDim.r, root.hub.textDim.g, root.hub.textDim.b, 0.35)
                                     : cell.isHoliday ? root.hub.accentPrimary
                                     : cell.modelData.weekend ? root.hub.weekendColor
                                     : root.hub.textMain
                            }

                            Rectangle {
                                visible: cell.modelData.custom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                width: 4
                                height: 4
                                radius: 2
                                color: cell.modelData.today ? root.hub.bgPanel : root.hub.accentPrimary
                            }

                            MouseArea {
                                id: cellArea
                                anchors.fill: parent
                                enabled: !cell.modelData.muted
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.selectedDay === cell.modelData.day) {
                                        root.selectedDay = 0
                                        return
                                    }
                                    root.selectedDay = cell.modelData.day
                                    root.daySelected(cell.modelData.day, root.cursorDate.getMonth() + 1, root.cursorDate.getFullYear())
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: grid.implicitWidth
                text: root.selectedText
                color: root.selectedDay > 0 ? root.hub.textMain : root.hub.textDim
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        // ------------------------- SIDEBAR -------------------------
        ColumnLayout {
            id: sidebar
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                IconButton {
                    hub: root.hub
                    glyph: ""
                    size: 26
                    glyphColor: root.hub.textDim
                    onClicked: root.shiftMonth(-1)
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.monthTitle
                    color: root.hub.textMain
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                }

                IconButton {
                    hub: root.hub
                    glyph: ""
                    size: 26
                    glyphColor: root.hub.textDim
                    onClicked: root.shiftMonth(1)
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 32

                HubButton {
                    anchors.centerIn: parent
                    visible: !root.isCurrentMonth
                    hub: root.hub
                    outline: true
                    icon: "󰃶"
                    text: "Сегодня"
                    fontSize: 12
                    implicitHeight: 28
                    onClicked: root.goToday()
                }

                Item {
                    anchors.fill: parent
                    visible: root.isCurrentMonth

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: "День " + root.todayDate + " из " + root.daysInShownMonth
                        color: root.hub.textDim
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: Math.round(root.monthProgress * 100) + "%"
                        color: root.hub.accentPrimary
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 5
                        radius: 2
                        color: root.hub.bgTrack

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * root.monthProgress
                            radius: 2

                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: root.hub.accentSecondary }
                                GradientStop { position: 1.0; color: root.hub.accentPrimary }
                            }
                        }
                    }
                }
            }

            Separator {}

            Text {
                text: "Праздники и важные даты"
                color: root.hub.textDim
                font.pixelSize: 13
                font.bold: true
            }

            // ------------------------- MONTH EVENTS -------------------------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 3 * 26 + 2 * 4
                clip: true

                ListView {
                    id: eventsList
                    anchors.fill: parent
                    model: root.monthEvents
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 4

                    SmoothScroll { flick: eventsList; keepPosition: false }

                    delegate: RowLayout {
                        id: eventRow
                        required property var modelData
                        width: eventsList.width
                        height: 26
                        spacing: 8

                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 22
                            radius: 5
                            color: root.hub.bgTrack

                            Text {
                                anchors.centerIn: parent
                                text: eventRow.modelData.day
                                color: root.hub.accentPrimary
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: eventRow.modelData.name
                            color: root.hub.textMain
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: root.monthEvents.length === 0
                    text: "В этом месяце нет дат"
                    color: root.hub.textDim
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ------------------------- MY DATES -------------------------
    Dropdown {
        id: myDates
        hub: root.hub
        Layout.fillWidth: true
        headerHeight: 36
        popupHeight: datesForm.implicitHeight + 16

        header: RowLayout {
            anchors.fill: parent
            spacing: 6

            Text {
                text: "󰓎"
                font.family: root.hub.iconFont
                font.pixelSize: 14
                color: root.hub.accentPrimary
            }

            Text {
                Layout.fillWidth: true
                text: "Мои даты"
                color: root.hub.textMain
                font.pixelSize: 14
                font.bold: true
            }

            Rectangle {
                visible: root.customDates.length > 0
                implicitWidth: countText.implicitWidth + 14
                implicitHeight: 20
                radius: 8
                color: root.hub.bgInput

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: root.customDates.length
                    color: root.hub.accentPrimary
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }

        ColumnLayout {
            id: datesForm
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 8

            // ------------------------- MY DATES LIST -------------------------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 3 * 34

                ListView {
                    id: customList
                    anchors.fill: parent
                    model: root.customDatesSorted
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    SmoothScroll { flick: customList }

                    delegate: Rectangle {
                        id: dateRow
                        required property var modelData
                        width: customList.width
                        height: 34
                        radius: 8
                        color: rowHover.hovered ? root.hub.hoverColor : "transparent"

                        HoverHandler { id: rowHover }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 2
                            spacing: 8

                            Text {
                                text: dateRow.modelData.day + "." + String(dateRow.modelData.month + 1).padStart(2, "0")
                                      + (dateRow.modelData.year === null || dateRow.modelData.year === undefined
                                         ? "" : "." + dateRow.modelData.year)
                                color: root.hub.accentPrimary
                                font.pixelSize: 12
                                font.bold: true
                                font.family: root.hub.monoFont
                            }

                            Text {
                                Layout.fillWidth: true
                                text: dateRow.modelData.label
                                color: root.hub.textMain
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: dateRow.modelData.year === null || dateRow.modelData.year === undefined
                                text: "ежегодно"
                                color: root.hub.textDim
                                font.pixelSize: 11
                            }

                            IconButton {
                                hub: root.hub
                                glyph: ""
                                size: 26
                                glyphColor: root.hub.textDim
                                onClicked: {
                                    const idx = dateRow.modelData.idx
                                    Qt.callLater(function() { root.removeCustomDate(idx) })
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.customDates.length === 0
                    text: "Пока нет своих дат"
                    color: root.hub.textDim
                    font.pixelSize: 13
                }
            }

            Separator {}

            // ------------------------- DATE INPUT -------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 3

                HubInput {
                    id: dayField
                    hub: root.hub
                    implicitWidth: 36
                    centered: true
                    placeholder: "ДД"
                    maximumLength: 2
                    validator: IntValidator { bottom: 1; top: 31 }
                    onAccepted: root.submitForm()
                }

                Text { text: "."; color: root.hub.textDim }

                HubInput {
                    id: monthField
                    hub: root.hub
                    implicitWidth: 36
                    centered: true
                    placeholder: "ММ"
                    maximumLength: 2
                    validator: IntValidator { bottom: 1; top: 12 }
                    onAccepted: root.submitForm()
                }

                Text { text: "."; color: root.hub.textDim; visible: !recurringToggle.checked }

                HubInput {
                    id: yearField
                    hub: root.hub
                    implicitWidth: 50
                    centered: true
                    visible: !recurringToggle.checked
                    placeholder: "ГГГГ"
                    maximumLength: 4
                    validator: IntValidator { bottom: 1900; top: 2200 }
                    onAccepted: root.submitForm()
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: recurringToggle
                    property bool checked: true

                    implicitWidth: toggleRow.implicitWidth + 14
                    implicitHeight: 28
                    radius: 14
                    color: recurringToggle.checked ? root.hub.accentPrimary
                         : toggleArea.containsMouse ? root.hub.accentSecondary : root.hub.bgInput
                    scale: toggleArea.pressed ? 0.93 : 1.0

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                    Row {
                        id: toggleRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            visible: recurringToggle.checked
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰄬"
                            font.family: root.hub.iconFont
                            font.pixelSize: 12
                            color: root.hub.bgPanel
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ежегодно"
                            color: recurringToggle.checked ? root.hub.bgPanel : root.hub.textMain
                            font.pixelSize: 11
                            font.bold: recurringToggle.checked
                        }
                    }

                    MouseArea {
                        id: toggleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: recurringToggle.checked = !recurringToggle.checked
                    }
                }
            }

            // ------------------------- NAME + ADD -------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                HubInput {
                    id: labelField
                    hub: root.hub
                    Layout.fillWidth: true
                    placeholder: "Название события"
                    onAccepted: root.submitForm()
                }

                IconButton {
                    hub: root.hub
                    glyph: "󰐕"
                    filled: true
                    size: 32
                    onClicked: root.submitForm()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.formError !== ""
                text: root.formError
                color: root.hub.danger
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }
}
