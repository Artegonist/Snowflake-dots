import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub

    readonly property color accentPrimary: root.hub.accentPrimary
    readonly property color bgTrack: root.hub.bgTrack
    readonly property color textMain: root.hub.textMain
    readonly property color textDim: root.hub.textDim

    Layout.fillWidth: true
    implicitHeight: Math.max(260, topBar.implicitHeight + content.implicitHeight + 40)

    // ------------------------- SETTINGS -------------------------
    property string city: "Aalborg"
    property int px: 3
    property real effectOpacity: 0.95
    property bool animate: root.hub.expanded
    property double lastUpdate: 0

    // ------------------------- DATA -------------------------
    property var forecast: []
    property int selectedDay: 0
    property string status: "загрузка…"

    property string provider: "wttr"
    property string owmKey: ""
    property string settingsMsg: ""
    property var owmCur: null
    property var owmFc: null

    readonly property var day: forecast.length > 0 ? forecast[Math.min(selectedDay, forecast.length - 1)] : null

    readonly property string cond: day ? day.cond : "cloudy"
    readonly property bool night: day ? day.night : false
    readonly property int intensity: day ? day.intensity : 1

    // ------------------------- WIND -------------------------
    readonly property real windKmh: day ? day.windKmh : 0
    readonly property real windDeg: day ? day.windDeg : 270
    readonly property real windFactor: Math.min(1.5, windKmh / 35)
    readonly property real windDirX: -Math.sin(windDeg * Math.PI / 180)
    readonly property int windSign: windDirX >= 0 ? 1 : -1
    readonly property real windVx: windSign * windFactor * (0.35 + 0.65 * Math.abs(windDirX))

    function reseed() { seed(); sky.requestPaint() }

    function transitionSky() {
        if (!root.animate) {
            root.reseed()
            return
        }
        skySwap.restart()
    }

    SequentialAnimation {
        id: skySwap
        NumberAnimation { target: sky; property: "opacity"; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScriptAction { script: root.reseed() }
        NumberAnimation { target: sky; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
    }

    onCondChanged: transitionSky()
    onNightChanged: transitionSky()
    onIntensityChanged: transitionSky()
    onPxChanged: reseed()
    onWindFactorChanged: transitionSky()
    onWindVxChanged: transitionSky()
    onEffectOpacityChanged: sky.requestPaint()
    onAccentPrimaryChanged: chart.requestPaint()
    onTextMainChanged: chart.requestPaint()
    onTextDimChanged: chart.requestPaint()
    onDayChanged: root.revealChart()
    onAnimateChanged: { chart.requestPaint(); sky.requestPaint() }

    // ------------------------- CONTENT TRANSITIONS -------------------------
    property real detailsOpacity: 1
    property real detailsShift: 0
    property int lastDay: 0

    function playDetails(dir) {
        detailsIn.stop()
        root.detailsOpacity = 0
        root.detailsShift = 28 * dir
        detailsIn.start()
    }

    ParallelAnimation {
        id: detailsIn
        NumberAnimation { target: root; property: "detailsOpacity"; to: 1; duration: 280; easing.type: Easing.OutCubic }
        Anim { target: root; property: "detailsShift"; to: 0 }
    }

    property bool hadForecast: false
    onForecastChanged: {
        if (root.forecast.length > 0 && !root.hadForecast)
            root.playDetails(0)
        root.hadForecast = root.forecast.length > 0
    }

    onSelectedDayChanged: {
        root.playDetails(root.selectedDay > root.lastDay ? 1 : -1)
        root.lastDay = root.selectedDay
    }

    readonly property real targetTemp: root.day ? parseInt(root.day.big) : NaN
    property real shownTemp: 0
    onTargetTempChanged: {
        if (!isNaN(root.targetTemp))
            root.shownTemp = root.targetTemp
    }
    Behavior on shownTemp { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

    property real chartReveal: 1
    onChartRevealChanged: chart.requestPaint()
    function revealChart() {
        chartRevealAnim.stop()
        root.chartReveal = 0
        chartRevealAnim.start()
    }
    NumberAnimation {
        id: chartRevealAnim
        target: root
        property: "chartReveal"
        to: 1
        duration: 750
        easing.type: Easing.OutCubic
    }

    // ------------------------- WTTR.IN PARSING -------------------------
    readonly property var compassRu: ({
        N: "С", NNE: "ССВ", NE: "СВ", ENE: "ВСВ", E: "В", ESE: "ВЮВ", SE: "ЮВ", SSE: "ЮЮВ",
        S: "Ю", SSW: "ЮЮЗ", SW: "ЮЗ", WSW: "ЗЮЗ", W: "З", WNW: "ЗСЗ", NW: "СЗ", NNW: "ССЗ"
    })

    readonly property var compass16: ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    function classify(code) {
        const c = parseInt(code)
        if ([200, 386, 389, 392, 395].includes(c)) return "thunder"
        if ([179, 182, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350,
             362, 365, 368, 371, 374, 377].includes(c)) return "snow"
        if ([176, 185, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308, 311,
             314, 353, 356, 359].includes(c)) return "rain"
        if ([143, 248, 260].includes(c)) return "fog"
        if (c === 113) return "clear"
        if (c === 116) return "partly"
        return "cloudy"
    }

    function rainIntensity(code) {
        const c = parseInt(code)
        if ([305, 308, 314, 359, 389, 284].includes(c)) return 3
        if ([299, 302, 356].includes(c)) return 2
        return 1
    }

    function parseClock(str) {
        const m = (str || "").match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i)
        if (!m) return -1
        let h = parseInt(m[1]) % 12
        if (m[3].toUpperCase() === "PM") h += 12
        return h * 60 + parseInt(m[2])
    }

    function toHM(str) {
        const min = root.parseClock(str)
        if (min < 0) return "--:--"
        return String(Math.floor(min / 60)).padStart(2, "0") + ":" + String(min % 60).padStart(2, "0")
    }

    function ruDesc(obj) {
        if (!obj) return ""
        if (obj.lang_ru && obj.lang_ru[0] && obj.lang_ru[0].value) return obj.lang_ru[0].value
        if (obj.weatherDesc && obj.weatherDesc[0]) return obj.weatherDesc[0].value
        return ""
    }

    function windArrow(deg) {
        const arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
        const idx = Math.round(((deg + 180) % 360) / 45) % 8
        return arrows[idx]
    }

    function uvWord(uv) {
        const v = parseInt(uv)
        if (isNaN(v)) return ""
        if (v <= 2) return "низк."
        if (v <= 5) return "умер."
        if (v <= 7) return "высок."
        if (v <= 10) return "оч. выс."
        return "экстр."
    }

    function buildDay(w, idx, cur) {
        const hourly = w.hourly || []
        const noon = hourly[4] || hourly[Math.floor(hourly.length / 2)] || {}
        const astro = (w.astronomy && w.astronomy[0]) || {}
        const src = (idx === 0 && cur) ? cur : noon

        let precip = 0
        for (const h of hourly) precip += parseFloat(h.precipMM) || 0

        const windKmh = parseInt(src.windspeedKmph) || 0
        const windDeg = parseInt(src.winddirDegree) || 0
        const uv = (idx === 0 && cur) ? cur.uvIndex : w.uvIndex

        const names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
        const dp = String(w.date || "").split("-")
        let tab = "День " + (idx + 1)
        if (idx === 0) tab = "Сегодня"
        else if (idx === 1) tab = "Завтра"
        else if (dp.length === 3)
            tab = names[new Date(parseInt(dp[0]), parseInt(dp[1]) - 1, parseInt(dp[2])).getDay()] + " " + parseInt(dp[2])

        let night = false
        if (idx === 0) {
            const rise = root.parseClock(astro.sunrise)
            const set = root.parseClock(astro.sunset)
            const now = new Date()
            const nowMin = now.getHours() * 60 + now.getMinutes()
            night = (rise >= 0 && set >= 0)
                ? (nowMin < rise || nowMin > set)
                : (now.getHours() < 6 || now.getHours() >= 21)
        }

        return {
            tab: tab,
            cond: root.classify(src.weatherCode),
            intensity: root.rainIntensity(src.weatherCode),
            night: night,
            big: ((idx === 0 && cur) ? cur.temp_C : w.maxtempC) + "°",
            sub: idx === 0 ? ("ощущ. " + (cur ? cur.FeelsLikeC : "?") + "°") : ("ср. " + w.avgtempC + "°"),
            range: "↑ " + w.maxtempC + "°  ↓ " + w.mintempC + "°",
            desc: root.ruDesc(src),
            sun: "Восход " + root.toHM(astro.sunrise) + " · Закат " + root.toHM(astro.sunset),
            windKmh: windKmh,
            windDeg: windDeg,
            tiles: [
                { label: "Ветер " + (root.compassRu[src.winddir16Point] || ""), value: root.windArrow(windDeg) + " " + windKmh + " км/ч" },
                { label: "Давление", value: (src.pressure || "—") + " гПа" },
                { label: "Осадки", value: precip.toFixed(1) + " мм" },
                { label: "УФ-индекс", value: (uv !== undefined ? uv : "—") + " · " + root.uvWord(uv) },
                { label: "Видимость", value: (src.visibility || "—") + " км" },
                { label: "Влажность", value: (src.humidity || "—") + "%" }
            ],
            nowTemp: (idx === 0 && cur) ? parseInt(cur.temp_C) : undefined,
            hourly: hourly.map(h => ({ h: parseInt(h.time) / 100, temp: parseInt(h.tempC) }))
        }
    }

    // ------------------------- OPENWEATHER CONDITIONS -------------------------
    function owmCond(id) {
        const c = parseInt(id)
        if (c >= 200 && c < 300) return "thunder"
        if (c >= 300 && c < 600) return "rain"
        if (c >= 600 && c < 700) return "snow"
        if (c >= 700 && c < 800) return "fog"
        if (c === 800) return "clear"
        if (c === 801 || c === 802) return "partly"
        return "cloudy"
    }

    function owmIntensity(id) {
        const c = parseInt(id)
        if ([502, 503, 504, 522, 531, 202, 212, 221, 232].includes(c)) return 3
        if ([501, 521, 201, 211, 230, 231, 511].includes(c)) return 2
        return 1
    }

    function localParts(ts, tz) {
        const d = new Date((ts + tz) * 1000)
        return { y: d.getUTCFullYear(), mo: d.getUTCMonth(), d: d.getUTCDate(),
                 h: d.getUTCHours(), mi: d.getUTCMinutes(), wd: d.getUTCDay() }
    }

    function hmOf(ts, tz) {
        const p = root.localParts(ts, tz)
        return String(p.h).padStart(2, "0") + ":" + String(p.mi).padStart(2, "0")
    }

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : "" }

    function buildOwmDays(cur, fc) {
        const tz = (fc.city && fc.city.timezone !== undefined) ? fc.city.timezone : (cur.timezone || 0)
        const nowTs = Math.floor(Date.now() / 1000)
        const keyOf = p => p.y + "-" + String(p.mo + 1).padStart(2, "0") + "-" + String(p.d).padStart(2, "0")

        const groups = {}
        for (const it of fc.list) {
            const p = root.localParts(it.dt, tz)
            const k = keyOf(p)
            if (!groups[k]) groups[k] = []
            groups[k].push({ it: it, p: p })
        }

        const todayP = root.localParts(nowTs, tz)
        const names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
        const sunrise = (cur.sys && cur.sys.sunrise) || 0
        const sunset = (cur.sys && cur.sys.sunset) || 0
        const sunText = "Восход " + (sunrise ? root.hmOf(sunrise, tz) : "--:--")
                        + " · Закат " + (sunset ? root.hmOf(sunset, tz) : "--:--")

        const days = []
        for (let k = 0; k < 3; k++) {
            const dd = new Date(Date.UTC(todayP.y, todayP.mo, todayP.d + k))
            const key = keyOf({ y: dd.getUTCFullYear(), mo: dd.getUTCMonth(), d: dd.getUTCDate() })
            const slots = groups[key] || []
            if (slots.length === 0 && k > 0) continue

            let noon = slots[0]
            let best = 99
            for (const s of slots) {
                const dist = Math.abs(s.p.h - 12)
                if (dist < best) { best = dist; noon = s }
            }
            const src = (k === 0) ? cur : noon.it

            const w0 = (src.weather && src.weather[0]) ? src.weather[0] : { id: 804, description: "" }
            const temps = slots.map(s => s.it.main.temp)
            if (k === 0) temps.push(cur.main.temp)
            const maxT = Math.round(Math.max(...temps))
            const minT = Math.round(Math.min(...temps))
            const avgT = Math.round(temps.reduce((a, b) => a + b, 0) / temps.length)

            let precip = 0
            for (const s of slots)
                precip += ((s.it.rain && s.it.rain["3h"]) || 0) + ((s.it.snow && s.it.snow["3h"]) || 0)

            const windKmh = Math.round(((src.wind && src.wind.speed) || 0) * 3.6)
            const windDeg = (src.wind && src.wind.deg) || 0
            const dirName = root.compassRu[root.compass16[Math.round(windDeg / 22.5) % 16]] || ""
            const clouds = (src.clouds && src.clouds.all !== undefined) ? src.clouds.all : "—"
            const vis = (src.visibility !== undefined) ? src.visibility / 1000 : -1

            let tab = "День " + (k + 1)
            if (k === 0) tab = "Сегодня"
            else if (k === 1) tab = "Завтра"
            else tab = names[dd.getUTCDay()] + " " + dd.getUTCDate()

            let night = false
            if (k === 0 && sunrise && sunset) night = nowTs < sunrise || nowTs > sunset

            days.push({
                tab: tab,
                cond: root.owmCond(w0.id),
                intensity: root.owmIntensity(w0.id),
                night: night,
                big: (k === 0 ? Math.round(cur.main.temp) : maxT) + "°",
                sub: k === 0 ? ("ощущ. " + Math.round(cur.main.feels_like) + "°") : ("ср. " + avgT + "°"),
                range: "↑ " + maxT + "°  ↓ " + minT + "°",
                desc: root.cap(w0.description),
                sun: sunText,
                windKmh: windKmh,
                windDeg: windDeg,
                tiles: [
                    { label: "Ветер " + dirName, value: root.windArrow(windDeg) + " " + windKmh + " км/ч" },
                    { label: "Давление", value: ((src.main && src.main.pressure) || "—") + " гПа" },
                    { label: "Осадки", value: precip.toFixed(1) + " мм" },
                    { label: "Облачность", value: clouds + "%" },
                    { label: "Видимость", value: vis < 0 ? "—" : (vis >= 10 ? "10+ км" : vis.toFixed(1) + " км") },
                    { label: "Влажность", value: ((src.main && src.main.humidity) || "—") + "%" }
                ],
                nowTemp: k === 0 ? Math.round(cur.main.temp) : undefined,
                hourly: slots.map(s => ({ h: s.p.h + s.p.mi / 60, temp: Math.round(s.it.main.temp) }))
            })
        }
        return days
    }

    // ------------------------- SETTINGS FILE -------------------------
    JsonFile {
        id: settingsFile
        path: root.hub.dataDir + "/weather.json"
        legacyPath: ".config/hub-module/weather.json"
        secret: true
        onLoaded: function(s) {
            if (s) {
                if (s.provider === "owm" || s.provider === "wttr") root.provider = s.provider
                if (typeof s.city === "string" && s.city.length > 0) root.city = s.city
                if (typeof s.owmKey === "string") root.owmKey = s.owmKey
            }
            root.afterSettingsLoaded()
        }
    }

    function afterSettingsLoaded() {
        if (root.provider === "owm" && root.owmKey.length === 0)
            root.status = "Нужен API-ключ OpenWeather"
        else
            root.refresh()
    }

    function applySettings(provider, city, key) {
        city = String(city || "").trim()
        key = String(key || "").trim()
        if (city.length === 0) return "Укажите город"
        if (provider === "owm" && key.length === 0) return "Для OpenWeather нужен API-ключ"
        root.provider = provider === "owm" ? "owm" : "wttr"
        root.city = city
        root.owmKey = key

        settingsFile.save({ provider: root.provider, city: root.city, owmKey: root.owmKey })

        root.forecast = []
        root.selectedDay = 0
        root.status = "загрузка…"
        root.settingsMsg = "Сохранено, обновляю…"
        root.refresh()
        return ""
    }

    // ------------------------- FETCH -------------------------
    function fail(msg) {
        root.status = msg
        root.settingsMsg = msg
        root.owmCur = null
        root.owmFc = null
    }

    Process {
        id: weatherProc
        running: false
        command: ["curl", "-s", "--max-time", "5", "wttr.in/" + encodeURIComponent(root.city) + "?format=j1&lang=ru"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const cur = data.current_condition[0]
                    const days = []
                    for (let i = 0; i < data.weather.length && i < 3; i++)
                        days.push(root.buildDay(data.weather[i], i, cur))
                    root.forecast = days
                    root.status = ""
                    root.settingsMsg = "Готово — погода обновлена"
                    root.lastUpdate = Date.now()
                    root.offline = false
                } catch (e) {
                    root.offline = true
                    if (root.forecast.length === 0) root.status = "нет связи с wttr.in"
                    root.settingsMsg = "wttr.in: нет данных (проверьте город и сеть)"
                }
            }
        }
    }

    Process {
        id: owmCurProc
        running: false
        command: ["curl", "-s", "--max-time", "8",
            "https://api.openweathermap.org/data/2.5/weather?q=" + encodeURIComponent(root.city)
            + "&appid=" + root.owmKey + "&units=metric&lang=ru"]
        stdout: StdioCollector { onStreamFinished: root.handleOwm("cur", text) }
    }

    Process {
        id: owmFcProc
        running: false
        command: ["curl", "-s", "--max-time", "8",
            "https://api.openweathermap.org/data/2.5/forecast?q=" + encodeURIComponent(root.city)
            + "&appid=" + root.owmKey + "&units=metric&lang=ru"]
        stdout: StdioCollector { onStreamFinished: root.handleOwm("fc", text) }
    }

    function handleOwm(kind, text) {
        let data = null
        try { data = JSON.parse(text) } catch (e) { root.offline = true; root.fail("Нет связи"); return }
        root.offline = false
        if (String(data.cod) !== "200") {
            const code = parseInt(data.cod)
            root.fail(code === 401 ? "OpenWeather: неверный или ещё не активный ключ"
                      : code === 404 ? "OpenWeather: город не найден"
                      : "OpenWeather: " + (data.message || data.cod))
            return
        }
        if (kind === "cur") root.owmCur = data
        else root.owmFc = data

        if (root.owmCur && root.owmFc) {
            try {
                const days = root.buildOwmDays(root.owmCur, root.owmFc)
                if (days.length === 0) { root.fail("OpenWeather: нет данных"); return }
                root.forecast = days
                root.status = ""
                root.settingsMsg = "Готово — погода обновлена"
                root.lastUpdate = Date.now()
            } catch (e) {
                root.fail("OpenWeather: не удалось разобрать ответ")
            }
        }
    }

    function refresh() {
        if (root.provider === "owm") {
            if (root.owmKey.length === 0) { root.status = "Нужен API-ключ OpenWeather"; return }
            root.owmCur = null
            root.owmFc = null
            owmCurProc.running = false
            owmFcProc.running = false
            owmCurProc.running = true
            owmFcProc.running = true
        } else {
            weatherProc.running = false
            weatherProc.running = true
        }
    }

    Component.onCompleted: settingsFile.load()
    Timer { interval: 15 * 60 * 1000; running: true; repeat: true; onTriggered: root.refresh() }

    property bool offline: false

    Timer {
        interval: 30000
        repeat: true
        running: root.offline
        onTriggered: root.refresh()
    }

    Timer {
        id: reconnectDelay
        interval: 3000
        onTriggered: root.refresh()
    }

    Process {
        running: root.offline
        command: ["nmcli", "monitor"]
        environment: ({ LC_ALL: "C", LANG: "C" })
        stdout: SplitParser {
            onRead: function(line) {
                if (/'full'|\bconnected\b/i.test(line) && !/disconnected/i.test(line))
                    reconnectDelay.restart()
            }
        }
    }

    Connections {
        target: root.hub
        function onExpandedChanged() {
            if (root.hub.expanded && root.lastUpdate > 0 && Date.now() - root.lastUpdate > 15 * 60 * 1000)
                root.refresh()
        }
    }

    // ------------------------- PIXEL ANIMATION -------------------------
    property var drops: []
    property var splashes: []
    property var flakes: []
    property var clouds: []
    property var stars: []
    property var fogBands: []
    property var ground: []
    property var gusts: []
    property var bolt: []
    property var fliers: []
    property real boltLife: 0
    property real flash: 0
    property real tick: 0
    property double lastFrame: 0

    readonly property int skyOff: Math.ceil((topBar.y + topBar.height + 4) / root.px)
    readonly property int skyFree: Math.max(18, Math.floor((content.y - 8) / root.px) - root.skyOff)

    function rnd(a, b) { return a + Math.random() * (b - a) }

    function seed() {
        if (sky.width <= 0 || sky.height <= 0) return
        const gw = Math.ceil(sky.width / root.px)
        const gh = Math.ceil(sky.height / root.px)
        const c = root.cond
        const wf = root.windFactor
        const vx = root.windVx
        const o = root.skyOff
        const fh = root.skyFree

        const drops = [], flakes = [], clouds = [], stars = [], bands = [], ground = [], gusts = []

        const shapes = [
            { w: 17, rows: [[6, 5], [3, 11], [1, 15], [0, 17], [0, 17], [2, 13]] },
            { w: 11, rows: [[3, 5], [1, 9], [0, 11], [1, 9]] }
        ]

        let cloudCount = 0, yMin = 0, yMax = 0.3
        if (c === "partly") { cloudCount = 2; yMin = 0.12; yMax = 0.55 }
        else if (c === "cloudy") { cloudCount = 4; yMin = 0.04; yMax = 0.6 }
        else if (c === "rain") { cloudCount = 4; yMin = 0; yMax = 0.22 }
        else if (c === "thunder") { cloudCount = 5; yMin = 0; yMax = 0.22 }
        else if (c === "snow") { cloudCount = 3; yMin = 0; yMax = 0.22 }
        for (let i = 0; i < cloudCount; i++) {
            const shape = shapes[Math.random() < 0.55 ? 0 : 1]
            clouds.push({
                x: rnd(-shape.w, gw),
                y: Math.max(0, Math.min(fh - shape.rows.length - 1, Math.floor(rnd(fh * yMin, fh * yMax)))),
                base: rnd(0.03, 0.1),
                shape: shape
            })
        }

        if (c === "rain" || c === "thunder") {
            const margin = Math.ceil(Math.abs(vx) * gh / 1.4) + 2
            const lo = vx > 0 ? -margin : 0
            const hi = vx < 0 ? gw + margin : gw
            const n = Math.min(560, Math.round(gw * gh / 110 * (0.6 + root.intensity * 0.5) * (hi - lo) / gw))
            for (let i = 0; i < n; i++)
                drops.push({
                    x: rnd(lo, hi), y: rnd(o, gh),
                    v: rnd(1.4, 2.4), len: Math.random() < 0.5 ? 2 : 3, k: rnd(0.85, 1.15)
                })
        }

        if (c === "snow") {
            const n = Math.min(380, Math.round(gw * gh / 80))
            for (let i = 0; i < n; i++)
                flakes.push({
                    x: rnd(0, gw), y: rnd(o, gh), v: rnd(0.12, 0.4),
                    phase: rnd(0, 6.28), amp: rnd(0.05, 0.15), k: rnd(0.7, 1.3),
                    size: Math.random() < 0.25 ? 2 : 1
                })
            let h = 2
            for (let x = 0; x < gw; x++) {
                const r = Math.random()
                if (r < 0.25) h -= 1
                else if (r > 0.75) h += 1
                h = Math.max(1, Math.min(3, h))
                ground.push(h)
            }
        }

        if (root.night && (c === "clear" || c === "partly")) {
            const n = Math.round(gw * gh / 140)
            for (let i = 0; i < n; i++)
                stars.push({ x: rnd(0, gw), y: rnd(-4, fh * 0.95), phase: rnd(0, 6.28), big: Math.random() < 0.15 })
        }

        if (c === "fog") {
            for (let i = 0; i < 5; i++) {
                const pattern = []
                let cursor = 0
                while (cursor < 70) {
                    const w = Math.floor(rnd(8, 20))
                    const gap = Math.floor(rnd(5, 14))
                    pattern.push({ x0: cursor, w: w })
                    cursor += w + gap
                }
                bands.push({
                    y: Math.floor(fh * (0.06 + i * 0.19)),
                    h: i % 2 === 0 ? 1 : 2,
                    pattern: pattern, period: cursor,
                    off: rnd(0, cursor),
                    base: rnd(0.04, 0.12)
                })
            }
        }

        if (["clear", "partly", "cloudy", "fog"].includes(c) && wf >= 0.3) {
            const n = Math.round(wf * 6)
            for (let i = 0; i < n; i++)
                gusts.push({ x: rnd(-10, gw), y: Math.floor(rnd(1, fh - 2)), len: Math.floor(rnd(4, 10)), k: rnd(0.7, 1.3) })
        }

        root.drops = drops
        root.splashes = []
        root.flakes = flakes
        root.clouds = clouds
        root.stars = stars
        root.fogBands = bands
        root.ground = ground
        root.gusts = gusts
        root.bolt = []
        root.boltLife = 0
        root.flash = 0

        root.fliers = []
        if (c === "clear" && !root.night) {
            root.spawnCloud(gw, true)
            root.spawnBirds(gw)
        }
    }

    function spawnBirds(gw) {
        const dir = Math.random() < 0.5 ? 1 : -1
        const n = 1 + Math.floor(rnd(0, 3))
        const baseY = rnd(2, Math.max(4, root.skyFree * 0.55))
        const v = rnd(0.3, 0.5) * dir
        for (let i = 0; i < n; i++) {
            root.fliers.push({
                kind: "bird",
                x: dir > 0 ? -6 - i * 6 : gw + 6 + i * 6,
                y: baseY + (i === 0 ? 0 : (i % 2 === 1 ? 2.5 : -2.5)),
                v: v,
                phase: i
            })
        }
    }

    function spawnCloud(gw, onScreen) {
        const shape = { w: 11, rows: [[3, 5], [1, 9], [0, 11], [1, 9]] }
        root.fliers.push({
            kind: "cloud",
            x: onScreen ? rnd(0, gw * 0.6) : (root.windSign > 0 ? -shape.w : gw + 2),
            y: Math.floor(rnd(1, Math.max(3, root.skyFree * 0.45))),
            base: rnd(0.06, 0.12),
            shape: shape
        })
    }

    function step(k) {
        root.tick += k
        const gw = Math.ceil(sky.width / root.px)
        const gh = Math.ceil(sky.height / root.px)
        const wf = root.windFactor
        const vx = root.windVx
        const sign = root.windSign
        const o = root.skyOff
        const fh = root.skyFree

        const margin = Math.ceil(Math.abs(vx) * gh / 1.4) + 2
        const lo = vx > 0 ? -margin : 0
        const hi = vx < 0 ? gw + margin : gw
        for (const d of root.drops) {
            d.y += d.v * k
            d.x += vx * d.k * k
            if (d.y >= gh) {
                if (Math.random() < 0.6 && d.x >= 1 && d.x < gw - 1)
                    root.splashes.push({ x: Math.floor(d.x), life: 3 })
                d.y = o + rnd(-3, 5)
                d.x = rnd(lo, hi)
            }
        }
        if (root.splashes.length > 0)
            root.splashes = root.splashes.filter(s => (s.life -= k) > 0)

        for (const f of root.flakes) {
            f.y += f.v * k
            f.x += (Math.sin(root.tick * 0.12 + f.phase) * f.amp + vx * 0.6 * f.k) * k
            if (f.x > gw + 2) f.x = -2
            else if (f.x < -2) f.x = gw + 2
            if (f.y >= gh) { f.y = o + rnd(-2, 2); f.x = rnd(0, gw) }
        }

        for (const c of root.clouds) {
            c.x += c.base * (1 + wf * 3) * sign * k
            if (sign > 0 && c.x > gw + 2) c.x = -c.shape.w - rnd(0, 10)
            else if (sign < 0 && c.x < -c.shape.w - 2) c.x = gw + 2 + rnd(0, 10)
        }

        for (const b of root.fogBands) {
            b.off += b.base * (1 + wf * 4) * sign * k
            if (b.off >= b.period) b.off -= b.period
            if (b.off < 0) b.off += b.period
        }

        for (const g of root.gusts) {
            g.x += sign * (1.0 + wf * 1.5) * g.k * k
            if (sign > 0 && g.x > gw + 2) { g.x = -g.len - rnd(0, 15); g.y = Math.floor(rnd(1, fh - 2)) }
            else if (sign < 0 && g.x < -g.len - 2) { g.x = gw + 2 + rnd(0, 15); g.y = Math.floor(rnd(1, fh - 2)) }
        }

        if (root.cond === "clear" && !root.night) {
            let birds = 0, clouds = 0
            for (const f of root.fliers) { if (f.kind === "bird") birds++; else clouds++ }
            if (birds === 0 && Math.random() < 0.004 * k) root.spawnBirds(gw)
            if (clouds < 2 && Math.random() < 0.003 * k) root.spawnCloud(gw, false)
            for (const f of root.fliers) {
                if (f.kind === "bird") f.x += (f.v + vx * 0.25) * k
                else f.x += f.base * (1 + wf * 3) * sign * k
            }
            root.fliers = root.fliers.filter(f => f.kind === "bird"
                ? (f.v > 0 ? f.x < gw + 8 : f.x > -10)
                : (f.x < gw + 12 && f.x > -f.shape.w - 12))
        }

        if (root.cond === "thunder") {
            if (root.boltLife > 0) root.boltLife = Math.max(0, root.boltLife - k)
            if (root.flash > 0) root.flash = Math.max(0, root.flash - k)
            if (root.boltLife <= 0 && Math.random() < 0.012 * k) {
                const path = []
                let x = rnd(gw * 0.2, gw * 0.8)
                let y = 5
                const yEnd = Math.max(20, Math.min(fh + 6, 70))
                while (y < yEnd) {
                    path.push({ x: Math.floor(x), y: y })
                    y += 1
                    if (y % 2 === 0) x += Math.floor(rnd(-2, 2.99))
                }
                root.bolt = path
                root.boltLife = 3
                root.flash = 3
            }
        }
    }

    function cloudRGB() {
        const c = root.cond, n = root.night
        if (c === "thunder") return [95, 100, 122]
        if (c === "rain") return [132, 142, 160]
        if (c === "snow") return n ? [150, 160, 185] : [205, 214, 228]
        if (c === "partly") return n ? [135, 145, 172] : [220, 226, 236]
        return n ? [118, 128, 152] : [185, 194, 208]
    }

    function tint() {
        const c = root.cond
        if (root.night) return [6, 10, 38, 0.48]
        if (c === "thunder") return [22, 26, 48, 0.46]
        if (c === "rain") return [38, 52, 78, 0.32]
        if (c === "snow") return [190, 208, 232, 0.14]
        if (c === "clear") return [255, 196, 84, 0.12]
        if (c === "fog") return [200, 208, 214, 0.14]
        return [70, 80, 96, 0.16]
    }

    readonly property var tintNow: root.tint()
    property color skyTop: Qt.rgba(root.tintNow[0] / 255, root.tintNow[1] / 255, root.tintNow[2] / 255, root.tintNow[3])
    property color skyBottom: Qt.rgba(root.tintNow[0] / 255, root.tintNow[1] / 255, root.tintNow[2] / 255, root.tintNow[3] * 0.3)
    Behavior on skyTop { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on skyBottom { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }

    Timer {
        interval: 33
        running: root.animate && root.width > 0
        repeat: true
        onRunningChanged: root.lastFrame = 0
        onTriggered: {
            const now = Date.now()
            const dt = root.lastFrame > 0 ? Math.min(120, now - root.lastFrame) : 33
            root.lastFrame = now
            root.step(dt / 70)
            sky.requestPaint()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.bgTrack

        Rectangle {
            anchors.fill: parent
            radius: 10
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.skyTop }
                GradientStop { position: 1.0; color: root.skyBottom }
            }
        }
    }

    Canvas {
        id: sky
        anchors.fill: parent
        renderTarget: Canvas.Image

        onWidthChanged: { root.seed(); requestPaint() }
        onHeightChanged: { root.seed(); requestPaint() }
        Component.onCompleted: { root.seed(); requestPaint() }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const P = root.px
            const w = width
            const h = height
            if (w <= 0 || h <= 0) return
            const gw = Math.ceil(w / P)
            const gh = Math.ceil(h / P)
            const cond = root.cond
            const night = root.night
            const vx = root.windVx
            const o = root.skyOff
            const fh = root.skyFree
            const cell = (x, y, cw, ch) => ctx.fillRect(Math.floor(x) * P, Math.floor(y) * P, cw * P, ch * P)
            const sc = (x, y, cw, ch) => cell(x, o + y, cw, ch)

            ctx.save()
            ctx.beginPath()
            ctx.roundedRect(0, 0, w, h, 10, 10)
            ctx.clip()

            ctx.globalAlpha = root.effectOpacity

            if (night && (cond === "clear" || cond === "partly")) {
                for (const s of root.stars) {
                    const a = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(root.tick * 0.3 + s.phase))
                    ctx.fillStyle = "rgba(255,252,230," + a.toFixed(2) + ")"
                    sc(s.x, s.y, 1, 1)
                    if (s.big) { sc(s.x - 1, s.y, 3, 1); sc(s.x, s.y - 1, 1, 3) }
                }
            }

            if (cond === "clear" || cond === "partly") {
                const cx = Math.floor(gw - 12)
                const cy = Math.max(10, Math.min(Math.floor(fh * 0.38), 26))
                const glow = 0.07 + 0.05 * (0.5 + 0.5 * Math.sin(root.tick * 0.09))
                ctx.fillStyle = night ? "rgba(245,240,205," + glow.toFixed(3) + ")"
                                      : "rgba(255,214,80," + (glow * 1.4).toFixed(3) + ")"
                for (let dy = -9; dy <= 9; dy++) {
                    const hw = Math.floor(Math.sqrt(81 - dy * dy + 0.5))
                    sc(cx - hw, cy + dy, hw * 2 + 1, 1)
                }
                if (night) {
                    ctx.fillStyle = "rgba(245,240,205,0.95)"
                    for (let dy = -5; dy <= 5; dy++) {
                        for (let dx = -5; dx <= 5; dx++) {
                            if (dx * dx + dy * dy > 25) continue
                            const ex = dx - 2, ey = dy + 1
                            if (ex * ex + ey * ey <= 18) continue
                            sc(cx + dx, cy + dy, 1, 1)
                        }
                    }
                } else {
                    ctx.fillStyle = "rgba(255,214,80,0.95)"
                    for (let dy = -5; dy <= 5; dy++) {
                        const hw = Math.floor(Math.sqrt(25 - dy * dy + 0.5))
                        sc(cx - hw, cy + dy, hw * 2 + 1, 1)
                    }
                    ctx.fillStyle = "rgba(255,214,80,0.7)"
                    if (Math.floor(root.tick / 7) % 2 === 0) {
                        sc(cx, cy - 9, 1, 2); sc(cx, cy + 8, 1, 2)
                        sc(cx - 9, cy, 2, 1); sc(cx + 8, cy, 2, 1)
                    } else {
                        sc(cx - 8, cy - 8, 1, 1); sc(cx - 7, cy - 7, 1, 1)
                        sc(cx + 8, cy - 8, 1, 1); sc(cx + 7, cy - 7, 1, 1)
                        sc(cx - 8, cy + 8, 1, 1); sc(cx - 7, cy + 7, 1, 1)
                        sc(cx + 8, cy + 8, 1, 1); sc(cx + 7, cy + 7, 1, 1)
                    }
                }
            }

            if (root.fliers.length > 0) {
                for (const f of root.fliers) {
                    if (f.kind === "cloud") {
                        const rows = f.shape.rows
                        for (let r = 0; r < rows.length; r++) {
                            ctx.fillStyle = (r === rows.length - 1) ? "rgba(190,198,212,0.9)" : "rgba(232,238,246,0.9)"
                            sc(f.x + rows[r][0], f.y + r, rows[r][1], 1)
                        }
                    } else {
                        ctx.fillStyle = "rgba(245,248,250,0.95)"
                        const up = Math.floor((root.tick + f.phase * 2) / 3) % 2 === 0
                        if (up) {
                            sc(f.x, f.y, 1, 1); sc(f.x + 4, f.y, 1, 1)
                            sc(f.x + 1, f.y + 1, 1, 1); sc(f.x + 3, f.y + 1, 1, 1)
                            sc(f.x + 2, f.y + 2, 1, 1)
                        } else {
                            sc(f.x + 2, f.y, 1, 1)
                            sc(f.x, f.y + 1, 2, 1); sc(f.x + 3, f.y + 1, 2, 1)
                        }
                    }
                }
            }

            if (root.clouds.length > 0) {
                const rgb = root.cloudRGB()
                const main = "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ",0.9)"
                const shade = "rgba(" + Math.round(rgb[0] * 0.78) + "," + Math.round(rgb[1] * 0.78) + "," + Math.round(rgb[2] * 0.78) + ",0.9)"
                for (const c of root.clouds) {
                    const rows = c.shape.rows
                    for (let r = 0; r < rows.length; r++) {
                        ctx.fillStyle = (r === rows.length - 1) ? shade : main
                        sc(c.x + rows[r][0], c.y + r, rows[r][1], 1)
                    }
                }
            }

            if (root.gusts.length > 0) {
                ctx.fillStyle = "rgba(235,242,248,0.45)"
                for (const g of root.gusts) sc(g.x, g.y, g.len, 1)
            }

            if (root.fogBands.length > 0) {
                ctx.fillStyle = "rgba(225,230,236,0.6)"
                for (const b of root.fogBands) {
                    const tiles = Math.ceil(gw / b.period) + 2
                    for (let k = -1; k < tiles; k++) {
                        for (const seg of b.pattern) {
                            const x = seg.x0 + b.off + k * b.period
                            if (x < gw && x + seg.w > 0) sc(x, b.y, seg.w, b.h)
                        }
                    }
                }
            }

            if (root.drops.length > 0) {
                const rain = cond === "thunder" ? "170,190,235" : "160,205,255"
                for (let layer = 0; layer < 2; layer++) {
                    const near = layer === 1
                    for (let i = 0; i < 3; i++) {
                        const a = (near ? 0.95 : 0.6) - i * 0.25
                        ctx.fillStyle = "rgba(" + rain + "," + a.toFixed(2) + ")"
                        for (const d of root.drops) {
                            if (i >= d.len || (d.v > 1.9) !== near)
                                continue
                            const slope = (vx * d.k) / d.v
                            cell(d.x - i * slope, d.y - i, 1, 1)
                        }
                    }
                }
                for (const s of root.splashes) {
                    const a = (s.life / 3) * 0.8
                    ctx.fillStyle = "rgba(" + rain + "," + a.toFixed(2) + ")"
                    cell(s.x - 1, gh - 2, 1, 1)
                    cell(s.x + 1, gh - 2, 1, 1)
                    cell(s.x, gh - 1, 1, 1)
                }
            }

            if (root.flakes.length > 0) {
                for (let size = 1; size <= 2; size++) {
                    ctx.fillStyle = size === 2 ? "rgba(255,255,255,0.95)" : "rgba(255,255,255,0.75)"
                    for (const f of root.flakes)
                        if (f.size === size) cell(f.x, f.y, size, size)
                }
                ctx.fillStyle = "rgba(238,243,252,0.85)"
                for (let gx = 0; gx < root.ground.length; gx++)
                    cell(gx, gh - root.ground[gx], 1, root.ground[gx])
            }

            ctx.globalAlpha = 1
            if (root.boltLife > 0) {
                ctx.fillStyle = "rgba(255,250,200,1)"
                for (const p of root.bolt) sc(p.x, p.y, 2, 1)
            }
            if (root.flash > 0) {
                ctx.fillStyle = "rgba(255,255,255," + (0.26 * root.flash / 3).toFixed(3) + ")"
                ctx.fillRect(0, 0, w, h)
            }

            ctx.restore()
        }
    }

    // ------------------------- CONTENT -------------------------
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(parent.height, content.implicitHeight + 24 + 90)
        bottomLeftRadius: 10
        bottomRightRadius: 10
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.bgTrack.r, root.bgTrack.g, root.bgTrack.b, 0.0) }
            GradientStop { position: 0.35; color: Qt.rgba(root.bgTrack.r, root.bgTrack.g, root.bgTrack.b, 0.55) }
            GradientStop { position: 1.0; color: Qt.rgba(root.bgTrack.r, root.bgTrack.g, root.bgTrack.b, 0.82) }
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        spacing: 7

        // ------------------------- TEMPERATURE -------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: root.day !== null
            opacity: root.detailsOpacity
            transform: Translate { x: root.detailsShift }

            Text {
                text: !root.day ? "" : (isNaN(root.targetTemp) ? root.day.big : Math.round(root.shownTemp) + "°")
                color: root.textMain
                font.pixelSize: 34
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                spacing: 1

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.day ? root.day.range : ""
                    color: root.textMain
                    font.pixelSize: 13
                }

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.day ? root.day.sub : ""
                    color: root.textDim
                    font.pixelSize: 12
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.day !== null
            opacity: root.detailsOpacity
            transform: Translate { x: root.detailsShift * 0.8 }
            text: root.day ? root.day.desc : ""
            color: root.textMain
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: root.day !== null
            opacity: root.detailsOpacity
            transform: Translate { x: root.detailsShift * 0.7 }
            text: root.day ? root.day.sun : ""
            color: root.textDim
            font.pixelSize: 11
        }

        // ------------------------- STATS -------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.day !== null
            opacity: root.detailsOpacity
            transform: Translate { x: root.detailsShift * 0.55 }
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.12)
            implicitHeight: statsGrid.implicitHeight + 12

            GridLayout {
                id: statsGrid
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                columns: 2
                columnSpacing: 6
                rowSpacing: 4

                Repeater {
                    model: root.day ? root.day.tiles : []
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 0

                        Text {
                            text: modelData.label
                            color: root.textDim
                            font.pixelSize: 11
                        }

                        Text {
                            text: modelData.value
                            color: root.textMain
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }
            }
        }

        // ------------------------- HOURLY CHART -------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.day !== null && root.day.hourly.length >= 2
            opacity: root.detailsOpacity
            transform: Translate { x: root.detailsShift * 0.4 }
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.12)
            implicitHeight: 80

            Canvas {
                id: chart
                anchors.fill: parent
                anchors.margins: 4
                renderTarget: Canvas.Image

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const w = width
                    const h = height
                    const d = root.day
                    if (!d || !d.hourly || d.hourly.length < 2 || w <= 0 || h <= 0) return

                    ctx.save()
                    ctx.beginPath()
                    ctx.rect(0, 0, w * root.chartReveal, h)
                    ctx.clip()

                    const temps = d.hourly.map(p => p.temp)
                    const n = temps.length
                    let mn = Math.min(...temps)
                    let mx = Math.max(...temps)
                    if (root.selectedDay === 0 && d.nowTemp !== undefined) {
                        mn = Math.min(mn, d.nowTemp)
                        mx = Math.max(mx, d.nowTemp)
                    }
                    if (mx - mn < 2) { mx += 1; mn -= 1 }

                    const hMin = d.hourly[0].h
                    const hMax = d.hourly[n - 1].h
                    const hSpan = Math.max(1, hMax - hMin)

                    const padT = 14, padB = 12, padX = 8
                    const gxh = hh => padX + (w - 2 * padX) * (hh - hMin) / hSpan
                    const gx = i => gxh(d.hourly[i].h)
                    const gy = t => padT + (h - padT - padB) * (1 - (t - mn) / (mx - mn))

                    const ac = root.accentPrimary

                    ctx.beginPath()
                    ctx.moveTo(gx(0), h - padB)
                    ctx.lineTo(gx(0), gy(temps[0]))
                    for (let i = 1; i < n; i++) {
                        const xm = (gx(i - 1) + gx(i)) / 2
                        ctx.bezierCurveTo(xm, gy(temps[i - 1]), xm, gy(temps[i]), gx(i), gy(temps[i]))
                    }
                    ctx.lineTo(gx(n - 1), h - padB)
                    ctx.closePath()
                    ctx.fillStyle = Qt.rgba(ac.r, ac.g, ac.b, 0.18)
                    ctx.fill()

                    ctx.beginPath()
                    ctx.moveTo(gx(0), gy(temps[0]))
                    for (let i = 1; i < n; i++) {
                        const xm = (gx(i - 1) + gx(i)) / 2
                        ctx.bezierCurveTo(xm, gy(temps[i - 1]), xm, gy(temps[i]), gx(i), gy(temps[i]))
                    }
                    ctx.lineWidth = 2
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = ac
                    ctx.stroke()

                    ctx.fillStyle = ac
                    for (let i = 0; i < n; i++) {
                        ctx.beginPath()
                        ctx.arc(gx(i), gy(temps[i]), 2, 0, Math.PI * 2)
                        ctx.fill()
                    }

                    ctx.font = "9px sans-serif"
                    ctx.textAlign = "center"
                    ctx.fillStyle = root.textMain
                    const iMax = temps.indexOf(Math.max(...temps))
                    const iMin = temps.indexOf(Math.min(...temps))
                    const lx = i => Math.max(10, Math.min(w - 10, gx(i)))
                    ctx.fillText(temps[iMax] + "°", lx(iMax), gy(temps[iMax]) - 5)
                    if (iMin !== iMax) ctx.fillText(temps[iMin] + "°", lx(iMin), gy(temps[iMin]) - 5)

                    ctx.fillStyle = root.textDim
                    for (let i = 0; i < n; i += 2)
                        ctx.fillText(String(Math.round(d.hourly[i].h)).padStart(2, "0"), gx(i), h - 2)

                    if (root.selectedDay === 0) {
                        const now = new Date()
                        const nowH = now.getHours() + now.getMinutes() / 60
                        let tNow = d.nowTemp !== undefined ? d.nowTemp : temps[0]
                        if (nowH >= hMin) {
                            for (let i = 0; i < n - 1; i++) {
                                const h0 = d.hourly[i].h
                                const h1 = d.hourly[i + 1].h
                                if (nowH >= h0 && nowH <= h1) {
                                    tNow = temps[i] + (temps[i + 1] - temps[i]) * (h1 > h0 ? (nowH - h0) / (h1 - h0) : 0)
                                    break
                                }
                            }
                        }
                        const x = gxh(Math.min(hMax, Math.max(hMin, nowH)))
                        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.35)
                        for (let y = padT - 4; y < h - padB; y += 4) ctx.fillRect(x, y, 1, 2)
                        ctx.fillStyle = "white"
                        ctx.beginPath()
                        ctx.arc(x, gy(tNow), 3, 0, Math.PI * 2)
                        ctx.fill()
                        ctx.fillStyle = ac
                        ctx.beginPath()
                        ctx.arc(x, gy(tNow), 1.6, 0, Math.PI * 2)
                        ctx.fill()
                    }
                    ctx.restore()
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(parent.height, topBar.implicitHeight + 24 + 40)
        topLeftRadius: 10
        topRightRadius: 10
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.bgTrack.r, root.bgTrack.g, root.bgTrack.b, 0.7) }
            GradientStop { position: 0.6; color: Qt.rgba(root.bgTrack.r, root.bgTrack.g, root.bgTrack.b, 0.4) }
            GradientStop { position: 1.0; color: Qt.rgba(root.bgTrack.r, root.bgTrack.g, root.bgTrack.b, 0.0) }
        }
    }

    ColumnLayout {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 7

        // ------------------------- CITY -------------------------
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.city
                color: root.textMain
                font.bold: true
                font.pixelSize: 14
            }

            Item { Layout.fillWidth: true }

            Text {
                id: statusText
                visible: root.forecast.length === 0
                text: root.status === "загрузка…" ? root.status : root.status + "  ·  настройки"
                color: statusHover.hovered ? root.textMain : root.textDim
                font.pixelSize: 12

                HoverHandler {
                    id: statusHover
                    enabled: root.status !== "загрузка…"
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: root.status !== "загрузка…"
                    onTapped: root.hub.openSettings("weather")
                }

                SequentialAnimation on opacity {
                    running: statusText.visible && root.animate
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    onRunningChanged: {
                        if (!running)
                            statusText.opacity = 1
                    }
                }
            }
        }

        // ------------------------- DAY TABS -------------------------
        Item {
            Layout.fillWidth: true
            implicitHeight: tabsRow.implicitHeight

            Rectangle {
                id: tabHighlight
                readonly property Item target: tabRepeater.count > 0
                    ? tabRepeater.itemAt(Math.min(root.selectedDay, tabRepeater.count - 1)) : null
                visible: target !== null
                x: target ? target.x : 0
                width: target ? target.width : 0
                height: 26
                radius: 13
                color: root.accentPrimary

                Behavior on x { Anim {} }
                Behavior on width { Anim {} }
            }

            RowLayout {
                id: tabsRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 4

                Repeater {
                    id: tabRepeater
                    model: root.forecast
                    delegate: Rectangle {
                        readonly property bool active: index === root.selectedDay
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        height: 26
                        radius: 13
                        color: active ? "transparent"
                               : (tabArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.18))

                        Behavior on color { ColorAnimation { duration: 160 } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.tab
                            font.pixelSize: 12
                            font.bold: parent.active
                            color: parent.active ? root.bgTrack : root.textMain

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedDay = index
                        }
                    }
                }

                Item { Layout.fillWidth: true; visible: root.forecast.length === 0 }
            }
        }
    }
}
