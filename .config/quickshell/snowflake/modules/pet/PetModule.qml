import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../services"

PanelWindow {
    id: root

    visible: false
    color: "transparent"
    implicitWidth: 480
    implicitHeight: 660
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true }
    margins { top: 30; left: 3 }
    mask: expanded ? null : emptyRegion
    WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool expanded: false
    property bool closing: false
    property int savedWorkspaceId: 0
    property string savedWorkspaceName: ""
    property bool restoreWorkspaceOnClose: false
    property bool choosing: false
    property bool stateReady: false
    property bool stateWritable: false
    property bool dirty: false
    property bool saving: false
    property int revision: 0
    property int savedRevision: 0
    property string stateIssue: ""
    property real nowEpoch: Date.now()
    property var saveData: ({ version: 2, selectedPet: "", pets: {} })
    property string notice: ""
    property string reaction: ""
    property real reactionLife: 0
    property real toyX: 160
    property real toyY: 170
    property real pointerX: 160
    property bool pointerInside: false

    function themeColor(value, fallback) {
        return /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value) ? value : fallback
    }

    readonly property color accentPrimary: themeColor(Theme.accentPrimary, "#5fa77c")
    readonly property color accentSecondary: themeColor(Theme.accentSecondary, "#446b56")
    readonly property color bgPanel: themeColor(Theme.bgPanelBattery, "#1c211e")
    readonly property color bgTrack: themeColor(Theme.bgTrack, "#2a322d")
    readonly property color textMain: themeColor(Theme.textMain, "#eef3ef")
    readonly property color textDim: themeColor(Theme.textDim, "#8fa196")
    readonly property color borderColor: accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hoverLight: themeColor(Theme.hoverLight, "#b7d3a8")
    readonly property color workspaceActive: themeColor(Theme.workspaceActive, "#6e8f72")
    readonly property color danger: "#c96a5a"
    readonly property bool isNightTime: {
        const hour = new Date(nowEpoch).getHours()
        return hour >= 23 || hour < 7
    }

    readonly property var petDefs: [
        { key: "cat", name: "Кот", detail: "Любит ласку", accent: "#eda466", speed: 43, food: "рыбка" },
        { key: "parrot", name: "Попугай", detail: "Всегда в движении", accent: "#b6d879", speed: 52, food: "зёрнышки" },
        { key: "hamster", name: "Хомяк", detail: "Маленький непоседа", accent: "#eab780", speed: 58, food: "семечки" },
        { key: "fish", name: "Рыбка", detail: "Плывёт за тобой", accent: "#9dc9e1", speed: 42, food: "хлопья" },
        { key: "frog", name: "Лягух", detail: "Мастер прыжков", accent: "#a5ce73", speed: 48, food: "мошки" },
        { key: "duck", name: "Гусь", detail: "Гуляет вразвалку", accent: "#fff5d7", speed: 36, food: "зерно" }
    ]
    readonly property var emptyStats: ({ hunger: 80, mood: 75, energy: 85, hygiene: 90,
        bond: 10, xp: 0, sleeping: false, createdAt: 0, updatedAt: 0,
        lastFeed: 0, lastPlay: 0, lastWash: 0, lastPet: 0, lastExplore: 0, lastRest: 0 })
    readonly property var habitatDefs: ({
        cat: { title: "Уютный уголок", skyTop: "#48433e", skyBottom: "#716047",
            nightTop: "#423e3b", nightBottom: "#63563f", objects: [
            { kind: "scratcher", name: "Когтеточка", hint: "Поточить когти", action: "explore", pose: "groom", seconds: 3.4,
                message: "Коготки в порядке!", energy: -3, mood: 12 },
            { kind: "cushion", name: "Подушка", hint: "Отдохнуть на подушке", action: "relax", pose: "sleep", seconds: 4.5,
                message: "Мягко и уютно. Можно снова играть!", energy: 9, mood: 6 } ] },
        parrot: { title: "Тропическая роща", skyTop: "#30594b", skyBottom: "#6c8b52",
            nightTop: "#294b43", nightBottom: "#536d46", objects: [
            { kind: "swing", name: "Качели", hint: "Покачаться на жердочке", action: "explore", pose: "curious", seconds: 4.2,
                message: "Выше, ещё выше!", energy: -3, mood: 14 },
            { kind: "bath", name: "Купальня", hint: "Искупаться и почистить перья", action: "relax", pose: "wash", seconds: 3.8,
                message: "Перья чистые, настроение отличное!", energy: 2, mood: 7, hygiene: 16 } ] },
        hamster: { title: "Лесная норка", skyTop: "#624932", skyBottom: "#94794f",
            nightTop: "#554331", nightBottom: "#806946", objects: [
            { kind: "wheel", name: "Колесо", hint: "Побегать в колесе", action: "explore", pose: "walk", seconds: 4.8,
                message: "Вот это пробежка!", energy: -7, mood: 16 },
            { kind: "burrow", name: "Норка", hint: "Забраться в норку и отдохнуть", action: "relax", pose: "sleep", seconds: 4.5,
                message: "В норке тепло. Я отдохнул!", energy: 11, mood: 5 } ] },
        fish: { title: "Тихий аквариум", skyTop: "#24516c", skyBottom: "#4b9396",
            nightTop: "#203e58", nightBottom: "#39757c", objects: [
            { kind: "bubbles", name: "Пузырьки", hint: "Поплавать в потоке пузырьков", action: "explore", pose: "trick", seconds: 4.2,
                message: "Поймал целую стайку пузырьков!", energy: -3, mood: 13 },
            { kind: "cave", name: "Укрытие", hint: "Отдохнуть среди камней", action: "relax", pose: "idle", seconds: 4.5,
                message: "Тихо, спокойно. Плывём дальше!", energy: 8, mood: 6 } ] },
        frog: { title: "Пруд с кувшинками", skyTop: "#567b7c", skyBottom: "#8ca27a",
            nightTop: "#2d4558", nightBottom: "#597963", objects: [
            { kind: "fireflies", name: "Мошки", hint: "Поохотиться на мошек", action: "explore", pose: "eat", seconds: 3.2,
                message: "Ква! Поймал вкусную мошку.", energy: -3, mood: 12, hunger: 5 },
            { kind: "lily", name: "Кувшинка", hint: "Отдохнуть на листе", action: "relax", pose: "curious", seconds: 4.5,
                message: "Покачался на листе и набрался сил.", energy: 8, mood: 7 } ] },
        duck: { title: "Берег пруда", skyTop: "#69959e", skyBottom: "#bfcaad",
            nightTop: "#344f66", nightBottom: "#708b7c", objects: [
            { kind: "splash", name: "Вода", hint: "Поплескаться у берега", action: "explore", pose: "wash", seconds: 4.0,
                message: "Га-га! Брызги во все стороны!", energy: -3, mood: 13, hygiene: 9 },
            { kind: "nest", name: "Гнездо", hint: "Устроиться в тёплом гнезде", action: "relax", pose: "sleep", seconds: 4.8,
                message: "Хорошо посидели. Силы вернулись!", energy: 10, mood: 6 } ] }
    })
    readonly property string selectedPet: saveData.selectedPet || ""
    readonly property var currentPetDef: petDefByKey(selectedPet)
    readonly property var currentStats: saveData.pets[selectedPet] || emptyStats
    readonly property real currentMood: currentStats.mood
    readonly property bool sleeping: selectedPet !== "" && currentStats.sleeping
    readonly property bool picking: choosing || selectedPet === ""
    readonly property bool busy: motion.remaining > 0
    readonly property var habitatDef: habitatDefs[selectedPet] || habitatDefs.cat
    readonly property var habitatObjects: habitatDef.objects
    readonly property var activeHabitatObject: habitatObjects[motion.habitatIndex] || habitatObjects[0]
    readonly property bool habitatActive: busy && (motion.activity === "explore" || motion.activity === "relax")
    readonly property bool habitatUsing: habitatActive && motion.habitatPhase === "use"
    readonly property int level: 1 + Math.floor(currentStats.xp / 40)
    readonly property int ageDays: currentStats.createdAt > 0
        ? Math.max(1, Math.floor((nowEpoch - currentStats.createdAt) / 86400000) + 1) : 1
    readonly property string growth: currentStats.xp < 60 ? "Малыш" : currentStats.xp < 200 ? "Подросток" : "Взрослый"
    readonly property real growthScale: currentStats.xp < 60 ? 0.90 : currentStats.xp < 200 ? 0.96 : 1.0
    readonly property real floorFar: Math.max(106, habitatFloor.height * 0.52)
    readonly property real floorNear: Math.max(floorFar + 8, habitatFloor.height - 14)
    readonly property real floorLeft: 57
    readonly property real floorRight: Math.max(floorLeft + 1, habitatFloor.width - 57)
    readonly property real depth: clamp((motion.groundY - floorFar) / Math.max(1, floorNear - floorFar), 0, 1)
    readonly property real spriteScale: (0.88 + depth * 0.16) * growthScale
    readonly property real pondCenterY: floorFar + (habitatFloor.height-floorFar)*0.52
    readonly property real pondRadiusY: Math.max(54,(habitatFloor.height-floorFar)*0.53)
    readonly property var waterZone: selectedPet === "frog"
        ? ({ x: habitatFloor.width * 0.54, y: pondCenterY, rx: habitatFloor.width * 0.49, ry: pondRadiusY })
        : selectedPet === "duck"
        ? ({ x: habitatFloor.width * 0.14, y: pondCenterY, rx: habitatFloor.width * 0.29, ry: pondRadiusY }) : null
    readonly property bool surfaceSwimming: (selectedPet === "frog" || selectedPet === "duck")
        && motion.waterContact && motion.lift === 0 && motion.vz <= 0 && !motion.held
    readonly property bool swimming: surfaceSwimming || (selectedPet === "fish" && !motion.held)
    readonly property real immersion: motion.held ? 0 : motion.swim
    readonly property real shorePulse: !motion.held && motion.shoreLife>0
        ? Math.sin(Math.PI*(1-motion.shoreLife/motion.shoreDuration)) : 0
    readonly property real shoreMotion: motion.shoreDirection*shorePulse
    readonly property real swimDepth: (selectedPet === "frog" ? 22 : 26)*spriteScale
    readonly property real waterClip: (selectedPet === "frog" || selectedPet === "duck") && !motion.held
        ? clamp((screenFoot-motion.groundY)/Math.max(1,swimDepth),0,1.25) : 0
    readonly property bool wading: selectedPet === "duck" && !motion.held && motion.lift<1
        && motion.swim>0.025 && motion.swim<0.92
    readonly property string travelPose: motion.lift>1 ? "jump" : wading ? "wade" : swimming ? "swim" : "walk"
    readonly property bool goingToSleep: busy && motion.activity === "nap"
    readonly property real napSecondsLeft: sleeping && currentStats.autoSleeping
        ? Math.max(0, currentStats.napRemaining - Math.max(0, nowEpoch - currentStats.updatedAt) / 1000) : 0
    readonly property bool sleepingAtHome: sleeping && currentStats.autoSleeping
    readonly property real hoverLift: !sleeping && !motion.held && motion.lift < 1
        ? (selectedPet === "fish" ? 7 + 3 * Math.sin(motion.clock * 2)
          : selectedPet === "parrot" && motion.moving ? 5 + 2 * Math.sin(motion.clock * 9) : 0) : 0
    readonly property real habitatLift: habitatUsing
        ? activeHabitatObject.kind === "bubbles" ? 6 + 4 * Math.sin(motion.clock * 3)
          : activeHabitatObject.kind === "swing" ? 5 : activeHabitatObject.kind === "lily" ? 1 + Math.sin(motion.clock * 2) : 0
        : sleepingAtHome && selectedPet === "parrot" ? 5 : 0
    readonly property real screenFoot: motion.groundY - motion.lift - hoverLift - habitatLift
        + immersion * swimDepth
        - immersion * Math.sin(motion.clock * 2) * (sleeping ? 0.6 : 1.3)
        + shoreMotion*(motion.shoreDirection>0 ? (selectedPet==="frog"?4:3) : 3)*spriteScale
    readonly property string pose: motion.held ? "held" : sleeping ? "sleep"
        : habitatActive ? habitatUsing ? activeHabitatObject.pose : travelPose
        : goingToSleep ? travelPose
        : busy ? motion.activity : motion.lift > 1 ? "jump" : motion.moving ? travelPose
        : motion.gestureRemaining > 0 ? motion.gesture : swimming ? "swim" : "idle"
    readonly property real actionProgress: busy ? clamp(1 - motion.remaining / motion.duration, 0, 1) : 0
    readonly property real frogCrouch: selectedPet === "frog" && motion.crouch > 0
        ? clamp(1 - motion.crouch / 0.16, 0, 1) : 0
    readonly property real frogJumpPhase: motion.hopSpeed > 0
        ? clamp((motion.hopSpeed - motion.vz) / (2 * motion.hopSpeed), 0, 1)
        : motion.vz > 0 ? 0.2 : 0.8
    readonly property string trickText: ({ cat: "Смотри, как я тянусь и даю лапку!",
        parrot: "Крылья шире — танцуем!", hamster: "Встал на лапки. Видишь меня?",
        fish: "Танец плавников и пузырьков!", frog: "Ква! Прыжок чемпиона!",
        duck: "Га-га! Крылья шире!" })[selectedPet] || "Смотри, что я умею!"
    readonly property string statusText: {
        if (!stateReady) return "Знакомимся…"
        if (stateIssue !== "") return stateIssue
        if (notice !== "") return notice
        if (sleeping) return currentStats.autoSleeping ? "Тихий час. Проснусь через " + sleepTimeText(napSecondsLeft) + "." : "Тихий час. Набираемся сил."
        if (motion.held) return "На ручках! Отпусти — я приземлюсь."
        if (goingToSleep) return "Пора отдохнуть. Направляюсь к месту для сна…"
        if (habitatActive) return habitatUsing ? activeHabitatObject.hint + "…" : "Сейчас подойду: " + activeHabitatObject.name.toLowerCase() + "."
        if (busy) return ({ eat: "Ням! Сегодня на обед — " + currentPetDef.food + ".",
            play: "Кликни или потяни мячик — я догоню!", wash: "Пена, пузырьки — и снова чисто!",
            pet: "Ещё немножко ласки…", trick: trickText })[motion.activity] || ""
        if (pickupArea.hoveredHabitat >= 0) return "Нажми на предмет: " + habitatObjects[pickupArea.hoveredHabitat].hint.toLowerCase() + "."
        if (currentStats.hunger < 25) return "Кажется, пора перекусить."
        if (currentStats.energy < 25) return "Устал. Уложишь меня спать?"
        if (currentStats.hygiene < 30) return "Мне бы немного пены и воды."
        if (currentStats.mood < 35) return "Давай поиграем вместе?"
        if (surfaceSwimming) return selectedPet === "duck" ? "Плыву и тихонько гребу лапками." : "Ква! В воде удобно плавать."
        if (isNightTime) return "За окном ночь. Можно устроить тихий час."
        return "Мне хорошо рядом с тобой."
    }

    function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }
    function finite(value, fallback) { return typeof value === "number" && isFinite(value) ? value : fallback }
    function copy(value) { return JSON.parse(JSON.stringify(value)) }
    function pointInWater(x, y) {
        if (selectedPet === "fish") return true
        if (!waterZone) return false
        if (selectedPet === "frog") {
            const lx=(x-habitatX(1))/32, ly=(y-habitatY(1)-3)/11
            if (lx*lx+ly*ly <= 1) return false // The large lily is a solid resting place.
        }
        const dx=(x-waterZone.x)/waterZone.rx, dy=(y-waterZone.y)/waterZone.ry
        return dx*dx+dy*dy <= 1
    }
    function waterDepthAt(x,y) {
        if(!waterZone)return -10000
        const dx=(x-waterZone.x)/waterZone.rx,dy=(y-waterZone.y)/waterZone.ry
        let depth=(1-Math.sqrt(dx*dx+dy*dy))*Math.min(waterZone.rx,waterZone.ry)
        if(selectedPet==="frog") {
            const lx=(x-habitatX(1))/32,ly=(y-habitatY(1)-3)/11
            depth=Math.min(depth,(Math.sqrt(lx*lx+ly*ly)-1)*11)
        }
        return depth
    }
    function smoothUnit(value) { const t=clamp(value,0,1);return t*t*(3-2*t) }
    function syncWaterState() {
        motion.waterContact=waterZone!==null && pointInWater(motion.posX,motion.groundY)
        motion.waterGrounded=surfaceSwimming
        motion.swim=motion.waterContact && !motion.held ? smoothUnit((waterDepthAt(motion.posX,motion.groundY)+4)/14) : 0
        motion.shoreLife=0;motion.shoreDirection=0;motion.splashLife=0
    }
    function startShoreMotion(entering) {
        motion.shoreDirection=entering?1:-1
        motion.shoreDuration=selectedPet==="frog"?(entering?0.55:0.65):(entering?0.65:0.8)
        motion.shoreLife=motion.shoreDuration
        motion.splashX=motion.posX;motion.splashY=motion.groundY
        motion.splashPower=clamp(0.35+Math.max(Math.abs(motion.vz),motion.waterImpact)/220
            +Math.sqrt(motion.vx*motion.vx+motion.vy*motion.vy)/150,0.35,1)
        motion.waterImpact=0
        motion.splashLife=0.85
    }
    function stepWater(dt) {
        motion.shoreLife=Math.max(0,motion.shoreLife-dt)
        motion.splashLife=Math.max(0,motion.splashLife-dt)
        if(!waterZone) {motion.waterContact=false;motion.waterGrounded=false;motion.swim=0;return}
        const depth=waterDepthAt(motion.posX,motion.groundY)
        if(depth>2)motion.waterContact=true
        else if(depth<-2)motion.waterContact=false
        const wet=surfaceSwimming
        if(wet && !motion.waterGrounded) startShoreMotion(true)
        else if(!wet && motion.waterGrounded && !motion.held
            && (depth<-2 || motion.vz>0)) startShoreMotion(false)
        motion.waterGrounded=wet
        if(motion.held)motion.shoreLife=0
        const contact=motion.held?0:1-smoothUnit(motion.lift/26)
        const target=smoothUnit((depth+4)/14)*contact
        const rate=target>motion.swim?5.5:6.5
        motion.swim+=(target-motion.swim)*(1-Math.exp(-dt*rate))
        if(motion.swim<0.0001)motion.swim=0
        else if(motion.swim>0.9999)motion.swim=1
    }
    function bankAhead(dx,dy,distance) {
        if(distance<4)return -1
        const limit=Math.min(26,distance)
        for(let ahead=4;ahead<=limit;ahead+=3)
            if(waterDepthAt(motion.posX+dx/distance*ahead,motion.groundY+dy/distance*ahead)<-2)return ahead
        return distance<=26 && waterDepthAt(motion.targetX,motion.targetY)<-2?distance:-1
    }
    function clipToPond(c,x,y) {
        if(!waterZone)return false
        c.beginPath()
        c.save();c.translate(waterZone.x-x,waterZone.y-y);c.scale(waterZone.rx,waterZone.ry)
        c.arc(0,0,1,0,Math.PI*2);c.restore()
        c.clip()
        return true
    }
    function sleepTimeText(seconds) {
        const total=Math.ceil(Math.max(0,seconds)), rest=total%60
        return Math.floor(total/60) + ":" + (rest<10?"0":"") + rest
    }
    function knownPet(key) {
        for (let i = 0; i < petDefs.length; ++i) if (petDefs[i].key === key) return true
        return false
    }
    function petDefByKey(key) {
        for (let i = 0; i < petDefs.length; ++i) if (petDefs[i].key === key) return petDefs[i]
        return petDefs[0]
    }

    function normalizeRecord(raw, legacyMood, now) {
        const p = raw && typeof raw === "object" && !Array.isArray(raw) ? copy(raw) : {}
        p.hunger = clamp(finite(p.hunger, 80), 0, 100)
        p.mood = clamp(finite(p.mood, finite(legacyMood, 75)), 0, 100)
        p.energy = clamp(finite(p.energy, 85), 0, 100)
        p.hygiene = clamp(finite(p.hygiene, 90), 0, 100)
        p.bond = clamp(finite(p.bond, 10), 0, 100)
        p.xp = Math.floor(clamp(finite(p.xp, 0), 0, 3920))
        p.sleeping = p.sleeping === true
        p.autoSleeping = p.sleeping && p.autoSleeping === true
        p.napRemaining = p.autoSleeping ? clamp(finite(p.napRemaining, 600), 0, 900) : 0
        p.awakeSeconds = clamp(finite(p.awakeSeconds, 0), 0, 28800)
        p.nextNapSeconds = clamp(finite(p.nextNapSeconds, newNapInterval()), 1800, 2700)
        p.createdAt = clamp(finite(p.createdAt, now), 0, now)
        p.updatedAt = clamp(finite(p.updatedAt, now), 0, now)
        const timestamps = ["lastFeed", "lastPlay", "lastWash", "lastPet", "lastExplore", "lastRest"]
        for (let i = 0; i < timestamps.length; ++i) {
            const key = timestamps[i]
            p[key] = clamp(finite(p[key], 0), 0, now)
        }
        return p
    }

    function newNapInterval() { return (30 + Math.floor(Math.random() * 16)) * 60 }
    function napDueIn(p) {
        const scheduled = Math.max(0, p.nextNapSeconds - p.awakeSeconds)
        const tired = Math.max(0, 120-p.awakeSeconds, (p.energy-25)/0.055*60)
        return Math.min(scheduled, tired)
    }
    function putRecordToSleep(p) {
        p.sleeping = true
        p.autoSleeping = true
        p.napRemaining = (10 + Math.floor(Math.random() * 6)) * 60
        p.awakeSeconds = 0
    }
    function wakeRecord(p) {
        p.sleeping = false; p.autoSleeping = false; p.napRemaining = 0
        p.awakeSeconds = 0; p.nextNapSeconds = newNapInterval()
    }
    function advanceNeeds(p, seconds, asleep) {
        const minutes=seconds/60
        p.hunger = clamp(p.hunger - minutes * (asleep ? 0.045 : 0.075), 0, 100)
        p.energy = clamp(p.energy + minutes * (asleep ? 1.3 : -0.055), 0, 100)
        p.hygiene = clamp(p.hygiene - minutes * (asleep ? 0.015 : 0.05), 0, 100)
        const unhappy=p.hunger<20 || p.hygiene<20 ? 0.07 : 0.025
        p.mood = clamp(p.mood + minutes * (asleep ? 0.01 : -unhappy), 0, 100)
    }
    function advanceRecord(record, now, simulateNaps) {
        const p = copy(record)
        let seconds = clamp((now - p.updatedAt) / 1000, 0, 28800)
        const automatic = simulateNaps !== false
        while (seconds > 0.00001) {
            if (p.sleeping) {
                const untilWake=p.autoSleeping ? p.napRemaining : Math.max(0,(96-p.energy)/1.3*60)
                const elapsed=Math.min(seconds,untilWake)
                advanceNeeds(p,elapsed,true)
                if(p.autoSleeping) p.napRemaining=Math.max(0,p.napRemaining-elapsed)
                seconds-=elapsed
                if(untilWake-elapsed<0.00001) wakeRecord(p)
            } else {
                const untilNap=napDueIn(p)
                if(automatic && untilNap<0.00001) { putRecordToSleep(p); continue }
                const elapsed=automatic?Math.min(seconds,untilNap):seconds
                advanceNeeds(p,elapsed,false)
                p.awakeSeconds+=elapsed
                seconds-=elapsed
            }
        }
        p.updatedAt = now
        return p
    }

    function loadState(text) {
        if (stateReady) return
        try {
            const raw = JSON.parse(text)
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("Invalid state object")
            if (finite(raw.version, 1) > 2) throw new Error("Newer state version")
            const now = Date.now()
            const data = copy(raw)
            const oldPets = raw.pets && typeof raw.pets === "object" && !Array.isArray(raw.pets) ? raw.pets : {}
            data.version = 2
            data.selectedPet = knownPet(raw.selectedPet) ? raw.selectedPet : ""
            data.pets = {}
            for (let i = 0; i < petDefs.length; ++i) {
                const key = petDefs[i].key
                if (oldPets[key] || typeof raw[key + "Mood"] === "number" || data.selectedPet === key) {
                    const p = normalizeRecord(oldPets[key], raw[key + "Mood"], now)
                    if (!oldPets[key]) {
                        p.createdAt = data.selectedPet === key ? clamp(finite(raw.lastSeenEpoch, now), 1, now) : 0
                        p.updatedAt = data.selectedPet === key ? clamp(finite(raw.lastSeenEpoch, now), 1, now) : now
                    }
                    data.pets[key] = key === data.selectedPet && p.createdAt > 0 ? advanceRecord(p, now) : p
                }
            }
            saveData = data
            stateReady = true
            stateWritable = true
            markDirty()
            Qt.callLater(resetMotion)
        } catch (error) {
            stateReady = true
            stateWritable = false
            stateIssue = "Сохранение не прочитано. Изменения временные."
            console.warn("PetModule: state was not loaded:", String(error))
        }
    }

    function markDirty() {
        dirty = true
        revision += 1
        if (stateWritable) saveTimer.restart()
    }
    function flushState() {
        if (!stateReady || !stateWritable || !dirty || saving) return
        saveTimer.stop()
        savedRevision = revision
        saving = true
        stateFile.setText(JSON.stringify(saveData, null, 2))
    }
    function applyElapsedDecay(at) {
        if (!stateReady) return
        const now = finite(at, Date.now())
        nowEpoch = now
        const key = selectedPet
        const record = saveData.pets[key]
        if (!knownPet(key) || !record || record.createdAt <= 0 || record.updatedAt === now) return
        const data = copy(saveData)
        data.pets[key] = advanceRecord(record, now, !expanded || picking)
        data[key + "Mood"] = data.pets[key].mood
        data.lastSeenEpoch = now
        saveData = data
        markDirty()
        if(record.sleeping !== data.pets[key].sleeping && expanded && !picking) {
            cancelAction()
            if(sleepingAtHome) placeAtRest()
            else if(!sleeping) {
                motion.gesture="stretch"; motion.gestureRemaining=1.8; motion.wait=2.1
                say("Выспался! Можно снова играть.", "♥")
            }
        }
    }
    function commitRecord(record) {
        if (!stateReady || !knownPet(selectedPet)) return
        const data = copy(saveData)
        data.pets[selectedPet] = normalizeRecord(record, 75, Date.now())
        data[selectedPet + "Mood"] = data.pets[selectedPet].mood
        data.lastSeenEpoch = Date.now()
        saveData = data
        markDirty()
    }
    function choosePet(key) {
        if (!stateReady || !knownPet(key)) return
        applyElapsedDecay()
        cancelAction()
        const now = Date.now()
        const data = copy(saveData)
        const p = normalizeRecord(data.pets[key], data[key + "Mood"], now)
        if (p.createdAt === 0) p.createdAt = now
        p.updatedAt = now
        data.pets[key] = p
        data.selectedPet = key
        saveData = data
        choosing = false
        notice = ""
        markDirty()
        Qt.callLater(resetMotion)
    }
    function releasePet() {
        cancelAction()
        choosing = true
        applyElapsedDecay()
        flushState()
    }

    function say(message, glyph) {
        notice = message
        noticeTimer.restart()
        if (glyph) { reaction = glyph; reactionLife = 1.2 }
    }
    function cooldownRemaining(action) {
        const names = { eat: "lastFeed", play: "lastPlay", trick: "lastPlay", wash: "lastWash", pet: "lastPet",
            explore: "lastExplore", relax: "lastRest" }
        const periods = { eat: 45000, play: 20000, trick: 20000, wash: 30000, pet: 5000, explore: 30000, relax: 45000 }
        if (!names[action]) return 0
        return Math.max(0, Math.ceil((finite(currentStats[names[action]], 0) + periods[action] - nowEpoch) / 1000))
    }
    function beginCare(action) {
        if (["eat", "play", "wash", "pet", "trick", "explore", "relax"].indexOf(action) < 0) return false
        if (!stateReady || !expanded || selectedPet === "" || picking || motion.held || motion.pointerDown || busy) return false
        if (sleeping) { say("Сначала разбуди меня кнопкой «Разбудить».", "z"); return false }
        if (motion.lift > 1) { say("Секундочку, я приземляюсь!", ""); return false }
        applyElapsedDecay()
        const remaining = cooldownRemaining(action)
        if (remaining > 0) { say("Ещё " + remaining + " с — и можно снова.", ""); return false }
        if (action === "eat" && currentStats.hunger >= 94) { say("Спасибо, я уже сыт!", "♥"); return false }
        if (action === "wash" && currentStats.hygiene >= 97) { say("Я уже чистенький!", "✦"); return false }
        if ((action === "play" || action === "trick" || action === "explore") && (currentStats.energy < 18 || currentStats.hunger < 12)) {
            say("Сначала еда и немного отдыха.", ""); return false
        }
        notice = ""
        motion.vx = 0
        motion.vy = 0
        motion.targetX = motion.posX
        motion.targetY = motion.groundY
        motion.gestureRemaining = 0
        motion.crouch = 0
        motion.hopDelay = 0
        motion.hopSpeed = 0
        motion.trickBeat = -1
        motion.playHits = 0
        motion.catchDelay = 0
        motion.habitatIndex = -1
        motion.habitatPhase = ""
        motion.activity = action
        motion.duration = ({ eat: 3.0, play: 7.0, wash: 3.6, pet: 1.8, trick: 2.8, explore: 4, relax: 4.5 })[action]
        motion.remaining = motion.duration
        if (action === "play") {
            toyX = clamp(motion.posX < habitatFloor.width / 2 ? floorRight - 8 : floorLeft + 8, floorLeft, floorRight)
            toyY = clamp(motion.groundY + 12, floorFar, floorNear)
            motion.targetX = toyX
            motion.targetY = toyY
            motion.toyVX = 0
            motion.toyVY = 0
            motion.toyLift = 16
            motion.toyVZ = 80
        }
        return true
    }
    function completeCare(action) {
        if (!knownPet(selectedPet)) return
        applyElapsedDecay()
        const p = copy(currentStats)
        const now = Date.now()
        if (action === "eat") {
            p.hunger += 25; p.mood += 4; p.hygiene -= 3; p.xp += 3; p.lastFeed = now
            say("Вкусно! Спасибо за заботу.", "♥")
        } else if (action === "play") {
            p.mood += 22; p.energy -= 13; p.hunger -= 7; p.hygiene -= 7; p.bond += 4; p.xp += 5; p.lastPlay = now
            say(motion.playHits > 0 ? "Касаний мяча: " + motion.playHits + ". Отлично поиграли!" : "Здорово побегали! Спасибо за игру.", "✦")
        } else if (action === "wash") {
            p.hygiene += 38; p.mood += 6; p.bond += 2; p.xp += 2; p.lastWash = now
            say("Теперь я чистый и довольный!", "✦")
        } else if (action === "pet") {
            p.mood += 6; p.bond += 2; p.xp += 1; p.lastPet = now
            say(selectedPet === "cat" ? "Мур-мур. Мне очень приятно." : "Как приятно! Побудь со мной.", "♥")
        } else if (action === "trick") {
            p.mood += 9; p.energy -= 5; p.hunger -= 2; p.bond += 2; p.xp += 2; p.lastPlay = now
            say("Получилось! Спасибо, что играешь со мной.", "✦")
        } else if ((action === "explore" || action === "relax") && motion.habitatIndex >= 0 && motion.habitatPhase === "use") {
            const prop = activeHabitatObject
            p.energy += prop.energy; p.mood += prop.mood
            p.hunger += finite(prop.hunger, action === "explore" ? -2 : 0)
            p.hygiene += finite(prop.hygiene, 0)
            p.bond += action === "explore" ? 3 : 1
            p.xp += action === "explore" ? 3 : 1
            p[action === "explore" ? "lastExplore" : "lastRest"] = now
            say(prop.message, action === "explore" ? "✦" : "♥")
        } else return
        commitRecord(p)
    }
    function pet() { beginCare("pet") }
    function feedPet() { beginCare("eat") }
    function playWithPet() { beginCare("play") }
    function washPet() { beginCare("wash") }
    function habitatX(index) { return index === 0 ? floorLeft + 6 : floorRight - 6 }
    function habitatY(index) { return clamp(floorFar + (floorNear-floorFar)*(index===1?0.37:0.26), floorFar, floorNear-14) }
    function travelDuration(x,y) {
        const dx=x-motion.posX,dy=y-motion.groundY
        const speed=currentPetDef.speed*(0.65+currentStats.energy*0.0035)
        return clamp(3+Math.sqrt(dx*dx+dy*dy)/Math.max(12,speed*0.65),8,45)
    }
    function habitatHit(x, y) {
        for (let i = 0; i < habitatObjects.length; ++i)
            if (Math.abs(x - habitatX(i)) <= 36 && y >= habitatY(i) - 64 && y <= habitatY(i) + 26) return i
        return -1
    }
    function interactWithHabitat(index) {
        if (index < 0 || index >= habitatObjects.length || Math.floor(index) !== index) return false
        const prop = habitatObjects[index]
        if (!beginCare(prop.action)) return false
        motion.habitatIndex = index
        motion.habitatPhase = "approach"
        const beside = prop.kind === "scratcher" || prop.kind === "fireflies"
        motion.targetX = clamp(habitatX(index) + (beside ? (index === 0 ? 22 : -22) : 0), floorLeft, floorRight)
        motion.targetY = clamp(habitatY(index) + (prop.kind === "cave" ? 17 : 5), floorFar, floorNear)
        motion.duration = travelDuration(motion.targetX,motion.targetY)
        motion.remaining = motion.duration
        return true
    }
    function showTrick() { return beginCare("trick") }
    function soothePet() {
        if (!beginCare("pet")) return false
        motion.duration = 3.2
        motion.remaining = motion.duration
        return true
    }
    function moveToy(x, y) {
        if (!busy || motion.activity !== "play") return
        toyX = clamp(x, floorLeft, floorRight)
        toyY = clamp(y, floorFar, floorNear)
        motion.toyVX = 0
        motion.toyVY = 0
        motion.toyLift = 5
        motion.toyVZ = 0
        motion.targetX = toyX
        motion.targetY = toyY
    }
    function cuddleAfterHold() { say("Спасибо, что подержал на ручках.", "♥") }
    function restIndex() { return selectedPet === "parrot" ? 0 : 1 }
    function restX() { return habitatX(restIndex()) }
    function restY() { return clamp(habitatY(restIndex()) + (selectedPet === "fish" ? 17 : 5), floorFar, floorNear) }
    function placeAtRest() {
        motion.posX=restX(); motion.groundY=restY()
        motion.targetX=motion.posX; motion.targetY=motion.groundY
        motion.facing=restIndex()===0?-1:1
    }
    function tryAutomaticSleep(at) {
        if(!stateReady || selectedPet==="" || sleeping || !expanded || picking
            || busy || motion.held || motion.pointerDown || motion.lift>1 || motion.gestureRemaining>0) return false
        const now=finite(at,Date.now())
        if(napDueIn(currentStats)>Math.max(0,now-currentStats.updatedAt)/1000) return false
        applyElapsedDecay(now)
        cancelAction()
        motion.activity="nap"
        motion.targetX=restX(); motion.targetY=restY()
        motion.duration=travelDuration(motion.targetX,motion.targetY);motion.remaining=motion.duration
        return true
    }
    function beginAutomaticNap() {
        if(!goingToSleep || !knownPet(selectedPet)) return
        applyElapsedDecay()
        const p=copy(currentStats)
        putRecordToSleep(p)
        commitRecord(p)
        cancelAction(); placeAtRest()
        syncWaterState()
        say("Устроился поудобнее. Посплю " + Math.round(p.napRemaining/60) + " мин.", "z")
    }
    function toggleSleep() {
        if (!stateReady || selectedPet === "" || picking || motion.held || motion.pointerDown || busy || motion.lift > 1) return
        const wasSleeping=sleeping
        applyElapsedDecay()
        if(wasSleeping && !sleeping) return
        const p = copy(currentStats)
        if (!p.sleeping && p.energy >= 96) { say("Я уже выспался!", ""); return }
        if(p.sleeping) wakeRecord(p)
        else { p.sleeping=true; p.autoSleeping=false; p.napRemaining=0 }
        commitRecord(p)
        cancelAction()
        if (!p.sleeping) { motion.gesture = "stretch"; motion.gestureRemaining = 1.8; motion.wait = 2.1 }
        say(p.sleeping ? "Сладких снов. Силы восстановятся во сне." : "Доброе утро!", p.sleeping ? "z" : "♥")
    }

    readonly property string petStateFile: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/snowflake/pet/state.json"
    property bool petStateMigrated: false

    Process {
        running: true
        command: ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && { [ -e "$1" ] || [ ! -f "$2" ] || cp -p "$2" "$1"; }',
            "snowflake-migrate", root.petStateFile, Quickshell.stateDir + "/pet-habitat-state.json"]
        onExited: root.petStateMigrated = true
    }

    FileView {
        id: stateFile
        path: root.petStateMigrated ? root.petStateFile : ""
        watchChanges: false
        atomicWrites: true
        onLoaded: root.loadState(stateFile.text())
        onLoadFailed: error => {
            if (stateFile.path === "" || root.stateReady) return
            root.stateReady = true
            root.stateWritable = error === FileViewError.FileNotFound
            if (!root.stateWritable) root.stateIssue = "Не удалось открыть сохранение. Изменения временные."
        }
        onSaved: {
            root.saving = false
            root.stateIssue = ""
            if (root.savedRevision === root.revision) root.dirty = false
            else saveTimer.restart()
        }
        onSaveFailed: error => {
            root.saving = false
            root.stateIssue = "Не удалось сохранить. Повторим при следующем действии."
            console.warn("PetModule: save failed:", error)
        }
    }
    Timer { id: saveTimer; interval: 800; onTriggered: root.flushState() }
    Timer { id: noticeTimer; interval: 3300; onTriggered: root.notice = "" }
    Timer {
        interval: 1000; repeat: true; running: root.expanded
        onTriggered: {
            root.nowEpoch=Date.now()
            if(root.sleeping && root.currentStats.autoSleeping && root.napSecondsLeft<=0) root.applyElapsedDecay()
            root.tryAutomaticSleep()
        }
    }
    Timer {
        interval: 60000; repeat: true; running: root.stateReady
        onTriggered: root.applyElapsedDecay()
    }

    QtObject {
        id: motion
        property real posX: 160
        property real groundY: 170
        property real lift: 0
        property real vz: 0
        property real vx: 0
        property real vy: 0
        property real targetX: 160
        property real targetY: 170
        property real clock: 0
        property real gait: 0
        property real wait: 1.2
        property real squash: 0
        property real remaining: 0
        property real duration: 1
        property real crouch: 0
        property real hopDelay: 0
        property real hopSpeed: 0
        property real lean: 0
        property real gaze: 0
        property real rest: 0
        property real swim: 0
        property real swimGait: 0
        property bool waterContact: false
        property bool waterGrounded: false
        property int shoreDirection: 0
        property real shoreLife: 0
        property real shoreDuration: 1
        property real splashLife: 0
        property real splashX: 0
        property real splashY: 0
        property real splashPower: 0.5
        property real waterImpact: 0
        property real gestureRemaining: 0
        property string gesture: "idle"
        property int trickBeat: -1
        property int playHits: 0
        property real catchDelay: 0
        property real toyVX: 0
        property real toyVY: 0
        property real toyLift: 0
        property real toyVZ: 0
        property real toySpin: 0
        property real goalLife: 0
        property int habitatIndex: -1
        property string habitatPhase: ""
        property string activity: "idle"
        property int facing: 1
        property bool held: false
        property bool pointerDown: false
        property bool initialized: false
        readonly property bool moving: Math.abs(vx) + Math.abs(vy) > 4
    }

    function cancelAction() {
        motion.remaining = 0
        motion.activity = "idle"
        motion.held = false
        motion.pointerDown = false
        motion.vx = 0
        motion.vy = 0
        motion.vz = 0
        motion.lift = 0
        motion.squash = 0
        motion.crouch = 0
        motion.hopDelay = 0
        motion.hopSpeed = 0
        motion.lean = 0
        motion.gaze = 0
        motion.gestureRemaining = 0
        motion.toyVX = 0
        motion.toyVY = 0
        motion.toyVZ = 0
        motion.toyLift = 0
        motion.catchDelay = 0
        motion.goalLife = 0
        motion.habitatIndex = -1
        motion.habitatPhase = ""
        motion.shoreLife=0;motion.shoreDirection=0;motion.splashLife=0
        motion.waterImpact=0
        motion.wait = 1.2
        reactionLife = 0
        pickupArea.resetPointer()
    }
    function resetMotion() {
        cancelAction()
        motion.posX = clamp(habitatFloor.width * 0.5, floorLeft, floorRight)
        motion.groundY = floorFar + (floorNear - floorFar) * 0.65
        motion.targetX = motion.posX
        motion.targetY = motion.groundY
        motion.facing = 1
        motion.rest = sleeping ? 1 : 0
        if(sleepingAtHome) placeAtRest()
        syncWaterState()
        motion.initialized = true
    }
    function confineMotion() {
        motion.posX = clamp(motion.posX, floorLeft, floorRight)
        motion.groundY = clamp(motion.groundY, floorFar, floorNear)
        motion.targetX = clamp(motion.targetX, floorLeft, floorRight)
        motion.targetY = clamp(motion.targetY, floorFar, floorNear)
        toyX = clamp(toyX, floorLeft, floorRight)
        toyY = clamp(toyY, floorFar, floorNear)
        const ceiling = Math.max(0, motion.groundY - 96 * spriteScale - 4)
        if (motion.lift > ceiling) { motion.lift = ceiling; motion.vz = Math.min(0, motion.vz) }
    }
    function startWalk() {
        if (!expanded || picking || sleeping || busy || motion.held || motion.pointerDown || motion.lift > 1) return
        motion.targetX = floorLeft + Math.random() * (floorRight - floorLeft)
        motion.targetY = floorFar + Math.random() * (floorNear - floorFar)
        motion.gestureRemaining = 0
        motion.activity = "walk"
    }
    function walkTo(x, y) {
        if (!stateReady || !expanded || picking || sleeping || busy || motion.held || motion.pointerDown || motion.lift > 1) return
        motion.targetX = clamp(x, floorLeft, floorRight)
        motion.targetY = clamp(y, floorFar, floorNear)
        motion.activity = "walk"
        motion.gestureRemaining = 0
        motion.goalLife = 1
        motion.wait = 0
    }

    function idleGesture() {
        const options = { cat: ["groom", "stretch"], parrot: ["groom", "curious"],
            hamster: ["groom", "curious"], fish: ["curious", "stretch"],
            frog: ["curious", "stretch"], duck: ["groom", "stretch"] }
        const gestures = options[selectedPet] || ["curious"]
        motion.gesture = gestures[Math.floor(Math.random() * gestures.length)]
        motion.gestureRemaining = 1.5 + Math.random() * 1.1
        motion.wait = motion.gestureRemaining + 0.5
    }

    function stepToy(dt) {
        motion.catchDelay = Math.max(0, motion.catchDelay - dt)
        if (!pickupArea.draggingToy) {
            toyX += motion.toyVX * dt
            toyY += motion.toyVY * dt
            if (toyX < floorLeft || toyX > floorRight) motion.toyVX *= -0.72
            if (toyY < floorFar || toyY > floorNear) motion.toyVY *= -0.72
            toyX = clamp(toyX, floorLeft, floorRight)
            toyY = clamp(toyY, floorFar, floorNear)
            motion.toyVX *= Math.exp(-dt * 1.2)
            motion.toyVY *= Math.exp(-dt * 1.2)
            if (motion.toyLift > 0 || motion.toyVZ > 0) {
                motion.toyVZ -= 440 * dt
                motion.toyLift += motion.toyVZ * dt
                if (motion.toyLift <= 0) {
                    motion.toyLift = 0
                    motion.toyVZ = motion.toyVZ < -45 ? -motion.toyVZ * 0.45 : 0
                }
            }
        }
        motion.toySpin += motion.toyVX * dt * 7
        motion.targetX = toyX
        motion.targetY = toyY
    }

    function physicsStep(dt) {
        motion.clock += dt
        motion.squash *= Math.exp(-dt * 12)
        stepWater(dt)
        motion.swimGait += dt * (sleeping ? 0.25 : motion.moving ? selectedPet==="frog"?1.35:1.05 : 0.45)
        const resting = sleeping || (habitatUsing && activeHabitatObject.pose === "sleep")
        motion.rest += ((resting ? 1 : 0) - motion.rest) * (1 - Math.exp(-dt * 5))
        const looking = pointerInside && !sleeping && !motion.held
            ? clamp((pointerX - motion.posX) / 70, -1, 1) * motion.facing : 0
        motion.gaze += (looking - motion.gaze) * (1 - Math.exp(-dt * 8))
        const targetLean = motion.held ? clamp(pickupArea.throwX * 0.025, -9, 9)
            : selectedPet === "fish" ? clamp(-motion.vy * 0.10, -7, 7)
            : surfaceSwimming ? Math.sin(motion.swimGait*Math.PI*2)*0.9
            : selectedPet === "frog" && motion.lift > 0 ? clamp(-motion.vz * 0.025, -4, 4) * motion.facing
            : selectedPet === "parrot" ? clamp(motion.vx * 0.06, -5, 5) : 0
        motion.lean += (targetLean+shoreMotion*(selectedPet==="frog"?6:4)*motion.facing-motion.lean) * (1 - Math.exp(-dt * 9))
        reactionLife = Math.max(0, reactionLife - dt)
        motion.goalLife = Math.max(0, motion.goalLife - dt)
        if (sleeping || motion.held || motion.pointerDown) return
        motion.hopDelay = Math.max(0, motion.hopDelay - dt)
        motion.gestureRemaining = Math.max(0, motion.gestureRemaining - dt)

        if (motion.remaining > 0) {
            motion.remaining = Math.max(0, motion.remaining - dt)
            if (motion.remaining === 0) {
                const finished = motion.activity
                if(finished === "nap") {
                    cancelAction();motion.wait=2
                    return 
                }
                const reached = motion.habitatPhase !== "approach"
                motion.activity = "idle"
                pickupArea.draggingToy = false
                motion.wait = 1.5
                if (reached) completeCare(finished)
                else say("Не успел добраться. Нажми на предмет ещё раз.", "")
                motion.habitatIndex = -1
                motion.habitatPhase = ""
                motion.gesture = finished === "wash" ? "shake" : "curious"
                motion.gestureRemaining = finished === "wash" ? 0.7 : 0.9
            }
        }
        if (motion.activity === "play") stepToy(dt)
        if (habitatUsing && activeHabitatObject.kind === "wheel") motion.gait += dt * 2.6
        if (motion.activity === "trick") {
            const elapsed = motion.duration - motion.remaining
            const beat = Math.floor(elapsed / 0.75)
            if (elapsed > 0.25 && beat !== motion.trickBeat && motion.lift === 0 && motion.remaining > 0.6) {
                motion.trickBeat = beat
                if (selectedPet === "frog" || selectedPet === "parrot" || selectedPet === "duck") {
                    motion.vz = selectedPet === "frog" ? 205 : selectedPet === "parrot" ? 150 : 100
                    if (selectedPet === "frog") motion.hopSpeed = motion.vz
                    motion.squash = 0.09
                }
            }
        }
        const travelling = motion.activity === "walk" || motion.activity === "play"
            || goingToSleep || (habitatActive && motion.habitatPhase === "approach")
        if (travelling) {
            const dx = motion.targetX - motion.posX
            const dy = motion.targetY - motion.groundY
            const distance = Math.sqrt(dx * dx + dy * dy)
            let speed = currentPetDef.speed * (0.65 + currentStats.energy * 0.0035)
            if (motion.activity === "play") speed *= 1.45
            if (habitatActive) speed *= 1.12
            if(surfaceSwimming) speed *= selectedPet==="frog" ? 0.95 : 0.82
            speed*=1-0.22*shorePulse
            const bank=selectedPet==="frog" && surfaceSwimming && motion.lift===0 && motion.vz===0
                ? bankAhead(dx,dy,distance) : -1
            if(bank>0 && bank<=19) {
                motion.vx*=Math.exp(-dt*16);motion.vy*=Math.exp(-dt*16)
                if(motion.crouch===0)motion.crouch=0.16
                motion.crouch=Math.max(0,motion.crouch-dt)
                if(motion.crouch===0) {
                    const reach=Math.min(distance,bank+12)
                    motion.vz=140;motion.hopSpeed=motion.vz
                    const flightTime=2*motion.vz/780
                    motion.vx=dx/distance*reach/flightTime;motion.vy=dy/distance*reach/flightTime
                }
            } else if (selectedPet === "frog" && !surfaceSwimming) {
                if (motion.lift === 0 && motion.vz === 0) {
                    motion.vx = 0
                    motion.vy = 0
                    if (distance > 3 && motion.hopDelay === 0) {
                        if (motion.crouch === 0) motion.crouch = 0.16
                        motion.crouch = Math.max(0, motion.crouch - dt)
                        if (motion.crouch === 0) {
                            motion.vz = clamp(85 + distance * 0.9, 95, 175)
                            motion.hopSpeed = motion.vz
                            const flightTime = 2 * motion.vz / 780
                            const hopSpeed = Math.min(speed * 1.65, distance / flightTime)
                            motion.vx = dx / distance * hopSpeed
                            motion.vy = dy / distance * hopSpeed
                        }
                    } else motion.crouch = 0
                }
            } else {
                motion.crouch=0
                speed = Math.min(speed, distance * 3)
                const blend = 1 - Math.exp(-dt * (surfaceSwimming ? 4 : 7))
                const desiredX = distance > 1 ? dx / distance * speed : 0
                const desiredY = distance > 1 ? dy / distance * speed : 0
                motion.vx += (desiredX - motion.vx) * blend
                motion.vy += (desiredY - motion.vy) * blend
            }
            if (distance <= (selectedPet === "frog" ? 3 : 4) && motion.activity === "walk"
                && (selectedPet !== "frog" || (motion.lift === 0 && motion.vz === 0))) {
                motion.activity = "idle"
                motion.wait = 0.8 + Math.random() * 2.4
            }
            if(goingToSleep && distance<4 && motion.lift<1 && motion.vz<=0) {
                beginAutomaticNap()
                return
            }
            if (habitatActive && motion.habitatPhase === "approach" && distance < 5 && motion.lift < 1 && motion.vz <= 0) {
                motion.vx = 0; motion.vy = 0; motion.vz = 0; motion.lift = 0
                motion.crouch = 0; motion.hopSpeed = 0
                motion.habitatPhase = "use"
                motion.duration = activeHabitatObject.seconds
                motion.remaining = motion.duration
                motion.facing = motion.habitatIndex === 0 ? -1 : 1
            }
            if (motion.activity === "play" && distance < 18 && motion.toyLift < 18
                && !pickupArea.draggingToy && motion.catchDelay === 0) {
                motion.playHits += 1
                motion.catchDelay = 0.85
                if (motion.lift === 0) {
                    motion.vz = selectedPet === "fish" ? 85 : 125
                    if (selectedPet === "frog") { motion.hopSpeed = motion.vz; motion.crouch = 0 }
                }
                const direction = toyX < habitatFloor.width / 2 ? 1 : -1
                motion.toyVX = direction * (115 + Math.random() * 30)
                motion.toyVY = (Math.random() - 0.5) * 45
                motion.toyVZ = 125
                reaction = "✦"
                reactionLife = 0.65
            }
        } else {
            motion.crouch = 0
            const friction = Math.exp(-dt * (motion.lift > 0 ? 2.5 : surfaceSwimming ? 4 : 10))
            motion.vx *= friction
            motion.vy *= friction
            if (selectedPet === "frog" && !surfaceSwimming && motion.lift === 0 && motion.vz <= 0) {
                motion.vx = 0
                motion.vy = 0
            }
            if (!busy && motion.lift === 0) {
                motion.wait -= dt
                if (motion.wait <= 0) {
                    if (Math.random() < 0.4) idleGesture()
                    else startWalk()
                }
            }
        }
        motion.posX += motion.vx * dt
        motion.groundY += motion.vy * dt
        if (motion.posX < floorLeft || motion.posX > floorRight) motion.vx *= -0.2
        if (motion.groundY < floorFar || motion.groundY > floorNear) motion.vy *= -0.2
        if (Math.abs(motion.vx) > 4) motion.facing = motion.vx < 0 ? -1 : 1
        const stride = selectedPet === "hamster" ? 19 : selectedPet === "duck" ? 33 : 28
        motion.gait += Math.sqrt(motion.vx * motion.vx + motion.vy * motion.vy) * dt / stride

        if (motion.lift > 0 || motion.vz > 0) {
            motion.vz -= 780 * dt
            motion.lift += motion.vz * dt
            if (motion.lift <= 0) {
                const impact = Math.max(0, -motion.vz)
                motion.lift = 0
                const waterLanding=waterZone!==null && pointInWater(motion.posX,motion.groundY)
                motion.waterImpact=waterLanding?impact:0
                motion.squash = waterLanding?Math.min(0.05,impact/3000):Math.min(0.17,impact/1700)
                motion.vz = 0
                if (selectedPet === "frog") {
                    motion.vx = waterLanding?motion.vx*0.82:0
                    motion.vy = waterLanding?motion.vy*0.82:0
                    motion.hopSpeed = 0
                    motion.hopDelay = waterLanding?0:0.1
                    motion.crouch = 0
                }
            }
        }
        confineMotion()
    }

    Timer {
        id: frameTimer
        interval: 16
        repeat: true
        running: root.visible && root.expanded && root.stateReady
        property real lastTick: 0
        property real accumulator: 0
        onRunningChanged: { lastTick = Date.now(); accumulator = 0 }
        onTriggered: {
            const now = Date.now()
            accumulator += root.clamp((now - lastTick) / 1000, 0, 0.1)
            lastTick = now
            while (accumulator >= 1 / 120) {
                if (root.picking) motion.clock += 1 / 120
                else root.physicsStep(1 / 120)
                accumulator -= 1 / 120
            }
        }
    }

    function show() { expanded = true }
    function hide() {
        if (!expanded) return
        restoreWorkspaceOnClose = true
        expanded = false
    }
    function toggle() { if (expanded) hide(); else show() }

    function restoreSavedWorkspace() {
        const current = Hyprland.focusedWorkspace
        if (current && current.id === savedWorkspaceId) return
        if (savedWorkspaceId > 0) {
            Hyprland.dispatch("workspace " + savedWorkspaceId)
        } else if (savedWorkspaceId < 0 && savedWorkspaceName !== "" &&
                   savedWorkspaceName !== "special" && savedWorkspaceName.indexOf("special:") !== 0) {
            Hyprland.dispatch("workspace name:" + savedWorkspaceName)
        }
    }

    Region { id: emptyRegion; width: 0; height: 0 }
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: {
            if (!root.expanded) return
            root.restoreWorkspaceOnClose = false
            root.expanded = false
        }
    }
    onExpandedChanged: {
        openAnim.stop()
        closeAnim.stop()
        if (expanded) {
            const workspace = Hyprland.focusedWorkspace
            savedWorkspaceId = workspace ? workspace.id : 0
            savedWorkspaceName = workspace ? workspace.name : ""
            restoreWorkspaceOnClose = false
            closing = false
            visible = true
            nowEpoch = Date.now()
            applyElapsedDecay()
            openAnim.start()
            if (!motion.initialized) Qt.callLater(resetMotion)
            else if (sleepingAtHome) {
                cancelAction(); placeAtRest(); syncWaterState(); motion.rest=1
            }
            Qt.callLater(function() {
                if (!root.expanded) return
                focusGrab.active = true
                card.forceActiveFocus()
            })
        } else {
            closing = true
            focusGrab.active = false
            cancelAction()
            applyElapsedDecay()
            flushState()
            if (restoreWorkspaceOnClose) restoreSavedWorkspace()
            restoreWorkspaceOnClose = false
            savedWorkspaceId = 0
            savedWorkspaceName = ""
            closeAnim.start()
        }
    }
    onVisibleChanged: {
        if (visible && !expanded && !closing) expanded = true
        else if (!visible && expanded) expanded = false
    }

    component HabitatScene: Canvas {
        id: scenery
        anchors.fill: parent
        property string kind: root.selectedPet
        property real time: root.expanded && !root.picking ? Math.floor(motion.clock * 12) / 12 : 0
        property real horizon: root.floorFar
        property int hovered: pickupArea.hoveredHabitat
        property string activeObject: root.habitatUsing ? root.activeHabitatObject.kind : ""
        property real progress: Math.floor(root.actionProgress * 24) / 24
        property bool night: root.isNightTime
        property color accent: root.accentPrimary
        property real cornerRadius: habitatFloor.radius
        smooth: false
        antialiasing: false
        opacity: root.sleeping ? 0.65 : 1
        Behavior on opacity { NumberAnimation { duration: 300 } }
        onKindChanged: requestPaint()
        onTimeChanged: requestPaint()
        onHorizonChanged: requestPaint()
        onHoveredChanged: requestPaint()
        onActiveObjectChanged: requestPaint()
        onProgressChanged: requestPaint()
        onNightChanged: requestPaint()
        onAccentChanged: requestPaint()
        onCornerRadiusChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: { if (visible) requestPaint() }
        onAvailableChanged: { if (available) requestPaint() }
        Component.onCompleted: requestPaint()
        onPaint: draw(getContext("2d"))

        function cell(c, x, y, w, h, color) {
            c.fillStyle = color
            c.fillRect(Math.round(x), Math.round(y), Math.max(1, Math.round(w)), Math.max(1, Math.round(h)))
        }
        function oval(c, x, y, rx, ry, color) {
            for (let row = -Math.floor(ry); row <= Math.floor(ry); ++row) {
                const span = Math.floor(rx * Math.sqrt(Math.max(0, 1-row*row/(ry*ry))))
                if (span > 0) cell(c, x-span, y+row, span*2, 1, color)
            }
        }
        function line(c, x1, y1, x2, y2, color, thickness) {
            c.strokeStyle = color; c.lineWidth = thickness || 1
            c.beginPath(); c.moveTo(x1,y1); c.lineTo(x2,y2); c.stroke()
        }
        function ring(c, x, y, rx, ry, color) {
            c.save(); c.translate(x,y); c.scale(1,ry/rx)
            c.strokeStyle=color; c.lineWidth=0.8
            c.beginPath(); c.arc(0,0,rx,0,Math.PI*2); c.stroke(); c.restore()
        }
        function plant(c, x, y, tall, aquatic) {
            const wind = Math.sin(time*1.6+x)*1.5
            const dark = aquatic ? "#356f68" : "#3e663f"
            const light = aquatic ? "#75ac89" : "#84a45b"
            for (let i=0;i<tall;i+=2) {
                const xx=x+Math.sin(i*0.11)*2+wind*i/tall
                cell(c,xx,y-i,1,3,dark)
                if (i%8===0) {
                    const side=i%16===0?1:-1
                    oval(c,xx+side*3,y-i-2,4,2,light)
                }
            }
        }
        function cloud(c, x, y, size, color) {
            cell(c,x-size,y,size*3,4,color)
            cell(c,x-size+3,y-3,size*2,3,color)
            cell(c,x,y-5,size,2,color)
        }
        function flower(c, x, y, color) {
            cell(c,x,y,1,5,"#4c7248")
            cell(c,x-2,y-1,5,1,color);cell(c,x,y-3,1,5,color)
            cell(c,x,y-1,1,1,"#e0ba68")
        }
        function sky(c, w, ground) {
            const sunX=kind==="frog"?w*0.38:24
            if (night) {
                oval(c,sunX,19,6,6,"#ded8ad")
                oval(c,sunX+3,17,6,6,kind==="frog"?"#354f5b":"#415d6c")
                for(let i=0;i<9;i++) {
                    c.save();c.globalAlpha=0.4+0.3*Math.sin(time*0.8+i*1.7)
                    cell(c,39+(i*23)%(w-47),8+(i*11)%Math.max(12,ground-22),1,1,"#dddcc2")
                    c.restore()
                }
            } else {
                oval(c,sunX,19,7,7,"#e9d59a")
                c.save();c.globalAlpha=0.5
                cloud(c,48+Math.sin(time*0.06)*9,27,9,"#e2dfbe")
                cloud(c,w-18+Math.sin(time*0.045+2)*6,19,7,"#d5ddc9")
                c.restore()
            }
        }
        function drawObject(c, object, x, y, active, index) {
            c.save(); c.globalAlpha=0.3
            oval(c,x,y+3,18,3,"#101814");c.restore()
            if (hovered===index || active) {
                c.save(); c.globalAlpha=active?0.35:0.65
                ring(c,x,y+3,20,5,String(accent));c.restore()
            }
            if (object==="scratcher") {
                cell(c,x-13,y-3,26,5,"#634e3a")
                cell(c,x-4,y-28,8,27,"#b19369")
                cell(c,x-4,y-28,2,27,"#806444")
                for(let i=0;i<6;i++) line(c,x-2,y-25+i*4,x+3,y-23+i*4,"#d5ba8d",1)
                cell(c,x-6,y-30,12,3,"#8b7050")
                if(active) for(let i=0;i<3;i++) cell(c,x+5+i,y-18+Math.sin(time*10+i)*3,1,2,"#d6c7a0")
            } else if (object==="cushion") {
                oval(c,x,y-3,20,8,"#40594c");oval(c,x,y-5,18,6,"#718773")
                line(c,x-12,y-4,x+12,y-4,"#91a181",1)
                cell(c,x-15,y-7,2,2,"#a7b798");cell(c,x+12,y-7,2,2,"#a7b798")
            } else if (object==="swing") {
                const sway=Math.sin(time*2.4)*(active?3:0.6)
                line(c,x-12,y-43,x-12+sway,y-3,"#8d9a79",1)
                line(c,x+12,y-43,x+12+sway,y-3,"#8d9a79",1)
                cell(c,x-16+sway,y-4,32,4,"#9f8054")
                cell(c,x-16+sway,y-4,32,1,"#c2aa79")
                cell(c,x-14,y-45,28,3,"#526447")
            } else if (object==="bath") {
                oval(c,x,y-2,20,7,"#788e86");oval(c,x,y-5,18,5,"#91b7bc")
                oval(c,x,y-5,14,3,"#527f86")
                if(active) for(let i=0;i<4;i++) {
                    const phase=(time*1.5+i/4)%1
                    cell(c,x-12+i*8,y-7-Math.sin(phase*Math.PI)*14,1,2,"#add1cb")
                }
            } else if (object==="wheel") {
                const center=y-17, angle=active?-motion.gait*3:0
                ring(c,x,center,16,16,"#ad956e");ring(c,x,center,14,14,"#695844")
                for(let i=0;i<8;i++) {
                    const a=angle+i*Math.PI/4
                    line(c,x,center,x+Math.cos(a)*13,center+Math.sin(a)*13,"#786448",1)
                }
                oval(c,x,center,2,2,"#bba57c")
                cell(c,x-2,y-7,4,9,"#836f51");cell(c,x-12,y,24,3,"#b09872")
            } else if (object==="burrow" || object==="cave") {
                const stone=object==="cave"
                oval(c,x,y-12,21,16,stone?"#52666a":"#7c6349")
                cell(c,x-20,y-12,40,15,stone?"#52666a":"#7c6349")
                oval(c,x,y-8,11,12,stone?"#233d44":"#2d3025")
                cell(c,x-10,y-8,20,11,stone?"#233d44":"#2d3025")
                for(let i=0;i<5;i++) cell(c,x-17+i*8,y-16-(i%2)*5,3,2,stone?"#7b8b88":"#a58960")
                if(!stone) for(let i=0;i<7;i++) cell(c,x-13+i*4,y+1+i%2,3,1,"#bba070")
            } else if (object==="bubbles") {
                oval(c,x,y,13,4,"#627b77");cell(c,x-6,y-4,12,4,"#9ca997")
                for(let i=0;i<5;i++) {
                    const phase=(time*(active?0.75:0.32)+i/5)%1
                    ring(c,x+Math.sin(phase*7+i)*4,y-5-phase*36,1+i%3,1+i%3,"#83afb5")
                }
            } else if (object==="fireflies") {
                plant(c,x-8,y,19,false)
                for(let i=0;i<3;i++) {
                    if(active && progress>0.45+i*0.17) continue
                    const xx=x+Math.sin(time*3+i*2)*6, yy=y-28+Math.sin(time*4+i)*4
                    cell(c,xx-2,yy,5,1,"#b8c68b");cell(c,xx,yy,2,2,"#e8ce7e")
                }
            } else if (object==="lily") {
                const bob=active?Math.sin(time*2):0
                oval(c,x,y-1+bob,21,7,"#315c43");oval(c,x,y-3+bob,19,6,"#668b4c")
                line(c,x,y-3+bob,x+17,y+1+bob,"#416b44",1)
                line(c,x,y-3+bob,x-9,y-6+bob,"#8ca868",1)
                oval(c,x+12,y-8+bob,4,2,"#cbb0a5");cell(c,x+11,y-9+bob,2,2,"#ead9ad")
            } else if (object==="splash") {
                oval(c,x,y-2,23,8,"#3c6a67")
                for(let i=0;i<3;i++) {
                    const phase=(time*(active?1.2:0.3)+i/3)%1
                    c.save();c.globalAlpha=(1-phase)*0.65
                    ring(c,x,y-2,5+phase*16,2+phase*5,"#89a9a0");c.restore()
                    if(active) cell(c,x-14+i*14,y-6-Math.sin(phase*Math.PI)*16,1,2,"#a5c7ba")
                }
            } else if (object==="nest") {
                oval(c,x,y-2,22,8,"#756244");oval(c,x,y-4,17,5,"#3e4330")
                for(let i=0;i<11;i++) {
                    const angle=i*Math.PI*2/11
                    line(c,x+Math.cos(angle)*16,y-2+Math.sin(angle)*5,
                        x+Math.cos(angle)*20+2,y-1+Math.sin(angle)*6,"#b49d6d",1)
                }
            }
        }
        function draw(c) {
            if(!c || width<=0 || height<=0) return
            c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,width,height);c.save()
            const radius=Math.max(0,Math.min(cornerRadius,width/2,height/2))
            c.beginPath();c.roundedRect(0,0,width,height,radius,radius);c.clip()
            c.scale(2,2)
            const w=width/2, h=height/2, ground=horizon/2-2
            if(kind==="cat") {
                cell(c,0,ground-11,w,11,"#615a46")
                for(let i=0;i<Math.ceil(w/15);i++) cell(c,i*15,ground-11,1,11,"#756d53")
                cell(c,0,ground-2,w,3,"#ad9364")
                cell(c,0,ground+1,w,h-ground,"#746044")
                for(let row=0;row<Math.ceil((h-ground)/12);row++) {
                    const yy=ground+1+row*12
                    cell(c,0,yy,w,1,"#514737");cell(c,0,yy+1,w,1,"#89704c")
                    for(let col=0;col<Math.ceil(w/39);col++) cell(c,col*39+(row%2)*19,yy,1,12,"#514737")
                }
                const wx=w/2-23, wy=14
                cell(c,wx-3,wy-3,52,36,"#ad9a72");cell(c,wx,wy,46,30,night?"#293f5c":"#6dabb0")
                if(night) {
                    oval(c,wx+33,wy+8,5,5,"#e1d9ac");oval(c,wx+35,wy+6,5,5,"#293f5c")
                    cell(c,wx+8,wy+6,1,1,"#b9d2cd");cell(c,wx+24,wy+4,1,1,"#b9d2cd")
                } else {
                    oval(c,wx+34,wy+8,5,5,"#f0d29b")
                    cloud(c,wx+11+Math.sin(time*0.09)*4,wy+12,5,"#cee0ca")
                }
                cell(c,wx,wy+25,46,5,night?"#354d4d":"#659067")
                cell(c,wx+22,wy,2,30,"#c2b693");cell(c,wx,wy+16,46,2,"#c2b693")
                for(let side=0;side<2;side++) {
                    const cx=side?wx+45:wx-6
                    cell(c,cx,wy-2,7,31,"#9b7560");cell(c,cx+2,wy-2,2,31,"#ba9170")
                    cell(c,cx,wy+20,7,2,"#d0b07b")
                }
                cell(c,wx-8,wy-4,62,2,"#cfaf7c");cell(c,wx-5,wy+32,56,3,"#bba67f")
                cell(c,9,29,27,3,"#ae8b5f")
                for(let i=0;i<4;i++) {
                    const bh=8+i%2*3
                    cell(c,12+i*5,29-bh,4,bh,["#92a47a","#ba876b","#b6a575","#738f90"][i])
                    cell(c,13+i*5,30-bh,2,1,"#d8c7a0")
                }
                cell(c,w-26,36,16,2,"#ae8b5f")
                cell(c,w-22,30,8,6,"#bb8460");plant(c,w-18,30,14,false)
                oval(c,w/2,h-13,38,10,"#a39568");oval(c,w/2,h-13,34,8,"#536e53")
                ring(c,w/2,h-13,30,6,"#8caa78")
                for(let i=0;i<5;i++) cell(c,w/2-20+i*10,h-13,2,1,"#a6b98a")
            } else if(kind==="parrot") {
                cell(c,18,8,5,ground,"#456649");cell(c,w-23,6,7,ground,"#456649")
                for(let i=0;i<Math.ceil(w/25)+1;i++) {
                    oval(c,8+i*25,ground-7,22,13,i%2?"#557d4a":"#456e46")
                    oval(c,10+i*23,ground+7,19,10,"#64854b")
                }
                cell(c,0,ground+7,w,h-ground,"#506941")
                const branchY=root.habitatY(0)/2-45
                line(c,0,branchY+3,w,branchY-2,"#8c784c",4)
                line(c,0,branchY+2,w,branchY-3,"#af9561",1)
                for(let i=0;i<Math.ceil(w/23)+1;i++) {
                    const xx=i*23-4
                    oval(c,xx,7+(i%2)*3,24,12,i%2?"#345e3d":"#3e6c40")
                    oval(c,xx+5,3+(i%2)*3,17,6,"#64874b")
                }
                for(let side=0;side<2;side++) {
                    const vx=side?w-9:11
                    for(let k=10;k<45;k+=3) {
                        const xx=vx+Math.sin(k*0.12+time*0.7)*2
                        cell(c,xx,k,1,4,"#98a768")
                        if(k%9===1) oval(c,xx+(k%2?3:-3),k,4,2,"#819f5d")
                    }
                }
                plant(c,7,h-4,46,false);plant(c,w-7,h-4,53,false)
                for(let i=0;i<21;i++) {
                    const xx=12+(i*37)%(w-24), yy=ground+11+(i*17)%Math.max(12,h-ground-15)
                    cell(c,xx,yy,3,1,i%3?"#7b9451":"#a4a86b")
                }
                flower(c,w-15,ground+7,"#dd9972");flower(c,15,h-14,"#c6b977")
                for(let i=0;i<3;i++) {
                    c.save();c.globalAlpha=0.25+0.15*Math.sin(time*1.4+i)
                    cell(c,58+i*17+Math.sin(time*0.8+i)*3,23+(i*11)%28,1,1,"#e4d9a3");c.restore()
                }
            } else if(kind==="hamster") {
                for(let row=0;row<4;row++) {
                    const yy=10+row*12
                    cell(c,0,yy,w,1,"#4d3c2e")
                    for(let i=0;i<Math.ceil(w/28);i++) cell(c,7+i*28+(row%2)*9,yy-3,9,1,"#91704a")
                }
                for(let side=0;side<2;side++) {
                    const x=side?w-10:11, direction=side?-1:1
                    line(c,x,0,x+direction*6,18,"#382f25",3)
                    line(c,x+direction*6,18,x+direction*19,30,"#382f25",2)
                    line(c,x+direction*6,18,x+direction*4,32,"#382f25",1)
                }
                oval(c,w/2,26,18,17,"#b79663");oval(c,w/2,26,15,14,"#463e2f")
                oval(c,w/2,26,12,11,night?"#46565e":"#96ad80")
                if(night) oval(c,w/2+4,23,3,3,"#d7c896")
                else {cloud(c,w/2-3,24,3,"#d2d3a3");oval(c,w/2+6,20,3,3,"#e7c785")}
                cell(c,w/2-1,16,2,22,"#b79663");cell(c,w/2-11,26,22,2,"#b79663")
                cell(c,w-35,35,24,3,"#b38c59")
                cell(c,w-29,22,12,13,"#a0a58a");cell(c,w-30,20,14,3,"#70563b")
                cell(c,w-27,25,8,9,"#796b4a")
                for(let i=0;i<6;i++) cell(c,w-26+(i*3)%7,27+Math.floor(i/3)*3,2,1,"#d2b47b")
                cell(c,0,ground,w,h-ground,"#897147")
                cell(c,0,ground,w,2,"#b3925a")
                for(let i=0;i<70;i++) {
                    const xx=5+(i*29+7)%(w-10), yy=ground+6+(i*13)%Math.max(8,h-ground-10)
                    cell(c,xx,yy,2+i%3,1,i%3===0?"#c5a56b":"#6c583b")
                }
                for(let i=0;i<4;i++) {
                    const x=7+i*4,y=h-7-(i%2)*3
                    line(c,x,y,x+10,y-6,"#c3a263",1)
                    line(c,x+2,y+1,x+8,y-8,"#d6b576",1)
                }
            } else if(kind==="fish") {
                for(let beam=0;beam<Math.ceil(w/49);beam++) {
                    const x=12+beam*49+Math.sin(time*0.6+beam)*3
                    c.save();c.globalAlpha=night?0.06:0.12;c.fillStyle="#c9ead2";c.beginPath()
                    c.moveTo(x,0);c.lineTo(x+7,0);c.lineTo(x+45,h);c.lineTo(x+19,h);c.closePath();c.fill();c.restore()
                }
                for(let i=0;i<Math.ceil(w/10);i++) cell(c,i*10,12+Math.sin(time*1.2+i*0.7),8,1,"#79b7b8")
                c.save();c.globalAlpha=0.35
                cell(c,4,17,1,h-23,"#a3cfbe");cell(c,w-5,17,1,h-23,"#a3cfbe")
                oval(c,w*0.6,h-17,23,24,"#396971")
                for(let i=0;i<8;i++) {
                    const phase=(time*0.075+i/8)%1
                    ring(c,55+(i*19)%(w-66)+Math.sin(time+i)*2,h-20-phase*(h-35),1+i%2,1+i%2,"#add9ce")
                }
                c.restore()
                cell(c,0,h-16,w,16,"#969c72");cell(c,0,h-16,w,2,"#b7b98a")
                for(let i=0;i<40;i++) cell(c,4+(i*31)%(w-8),h-13+(i*7)%11,2,1,i%2?"#c6c39a":"#7b855f")
                plant(c,9,h-8,64,true);plant(c,w-7,h-5,59,true);plant(c,w-18,h-5,33,true)
                oval(c,20,h-6,6,3,"#727f72");oval(c,w-32,h-5,5,3,"#bcc2a1")
                oval(c,w*0.49,h-7,5,3,"#c8b59a")
                for(let i=0;i<3;i++) line(c,w*0.49-3+i*3,h-9,w*0.49,h-5,"#927f6b",1)
            } else if(kind==="frog") {
                sky(c,w,ground)
                for(let i=0;i<Math.ceil(w/31)+1;i++) oval(c,i*31,ground-9,28,12,night?"#3c6055":"#66835e")
                for(let side=0;side<2;side++) {
                    const tx=side?w-7:8
                    cell(c,tx,15,3,ground-6,"#495e44")
                    oval(c,tx,17,19,8,"#557852")
                    for(let j=0;j<4;j++) {
                        const xx=tx-12+j*7
                        for(let yy=19;yy<35+j%2*8;yy+=3)
                            cell(c,xx+Math.sin(time*0.9+j)*1.2,yy,2,2,"#729057")
                    }
                }
                cell(c,0,ground,w,h-ground,"#637e4c")
                oval(c,root.waterZone.x/2,root.waterZone.y/2,w*0.52,root.waterZone.ry/2+3,"#8c9c63")
                oval(c,root.waterZone.x/2,root.waterZone.y/2,root.waterZone.rx/2,root.waterZone.ry/2,night?"#386963":"#498479")
                for(let i=0;i<9;i++) {
                    const xx=20+(i*29)%(w-36), yy=ground+8+(i*11)%Math.max(10,h-ground-15)
                    cell(c,xx,yy,6+Math.sin(time*1.4+i)*3,1,"#79a28a")
                }
                plant(c,6,h-5,47,false);plant(c,w-6,h-5,39,false)
                for(let i=0;i<4;i++) {
                    const xx=8+i*5
                    line(c,xx,h-9,xx-2,h-47+i*5,"#9eae67",1)
                    cell(c,xx-3,h-52+i*5,2,8,"#b2935c")
                }
                oval(c,w*0.54,h-13,10,4,"#8da95b");oval(c,w*0.38,h-34,7,3,"#799752")
                flower(c,w*0.54+3,h-17,"#dcafbb")
                oval(c,w-12,h-6,6,3,"#9aa485");oval(c,17,ground+5,6,3,"#919b78")
                for(let i=0;i<4;i++) {
                    c.save();c.globalAlpha=(night?0.7:0.25)*(0.6+0.4*Math.sin(time*2+i))
                    cell(c,45+i*20+Math.sin(time+i)*3,ground-16+Math.sin(time*1.4+i)*5,1,1,"#eadc8d");c.restore()
                }
            } else if(kind==="duck") {
                sky(c,w,ground)
                oval(c,w*0.25,ground-1,w*0.65,19,night?"#597355":"#91a16c")
                oval(c,w*0.95,ground+1,w*0.65,16,night?"#6f865b":"#a5b27a")
                const bx=w-31,by=ground-27
                cell(c,bx,by+6,18,12,"#956f59");cell(c,bx+2,by+7,14,10,"#b28b6c")
                cell(c,bx-2,by+5,22,3,"#5d6658");cell(c,bx+1,by+2,16,3,"#5d6658")
                cell(c,bx+5,by,8,2,"#5d6658");cell(c,bx+7,by+11,5,6,"#5a5d4b")
                cell(c,bx+3,by+9,3,3,night?"#dec17a":"#b8d0bd")
                const fy=ground-6
                cell(c,0,fy,w,2,"#b5a578");cell(c,0,fy+5,w,2,"#8e845e")
                for(let i=0;i<Math.ceil(w/18);i++) {
                    cell(c,3+i*18,fy-3,3,14,"#bdaf82");cell(c,3+i*18,fy-3,1,14,"#d4c393")
                }
                cell(c,0,ground+7,w,h-ground,"#7e945d")
                oval(c,root.waterZone.x/2,root.waterZone.y/2,w*0.32,root.waterZone.ry/2+3,"#b2b88a")
                oval(c,root.waterZone.x/2,root.waterZone.y/2,root.waterZone.rx/2,root.waterZone.ry/2,night?"#406f78":"#4e9297")
                for(let i=0;i<5;i++) cell(c,5+i*8,h-13-(i%3)*11,8+Math.sin(time*1.1+i)*2,1,"#8bb7ad")
                for(let i=0;i<4;i++) oval(c,w*0.37+i%2*5,h-11-i*9,3,2,"#b8b891")
                for(let i=0;i<14;i++) {
                    const xx=w*0.48+(i*19)%(w*0.48), yy=ground+12+(i*13)%Math.max(10,h-ground-15)
                    if(i%4===0) flower(c,xx,yy,"#e5dfb1")
                    else {cell(c,xx,yy,1,3,"#5f7e47");cell(c,xx+2,yy+1,1,2,"#a4b36f")}
                }
                plant(c,5,h-6,26,false);plant(c,w-5,h-5,28,false)
            }
            for(let i=0;i<root.habitatObjects.length;i++) {
                const object=root.habitatObjects[i].kind
                drawObject(c,object,root.habitatX(i)/2,root.habitatY(i)/2,activeObject===object,i)
            }
            c.restore()
        }
    }


    component SurfaceWake: Canvas {
        id: wake
        width: 96; height: 36
        x: motion.posX-width/2; y: motion.groundY-height/2
        property real time: Math.floor(motion.clock*18)/18
        property real size: root.spriteScale
        property int facing: motion.facing
        property bool moving: motion.moving
        opacity: Math.min(1,root.waterClip)
        visible: opacity>0.01
        smooth: false; antialiasing: false
        onTimeChanged: requestPaint()
        onSizeChanged: requestPaint()
        onFacingChanged: requestPaint()
        onMovingChanged: requestPaint()
        onVisibleChanged: { if(visible) requestPaint() }
        onAvailableChanged: { if(available) requestPaint() }
        onPaint: {
            const c=getContext("2d")
            if(!c) return
            c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,width,height)
            c.save()
            if(!root.clipToPond(c,x,y)) {c.restore();return}
            for(let i=0;i<3;i++) {
                const phase=(time*(moving?0.85:0.4)+i/3)%1
                c.save();c.translate(width/2-(moving?facing*phase*22:0),height/2)
                c.scale(size,0.22*size);c.globalAlpha=(1-phase)*0.55
                c.strokeStyle="#abd1b4";c.lineWidth=1.5
                c.beginPath();c.arc(0,0,19+phase*18,0,Math.PI*2);c.stroke();c.restore()
            }
            c.fillStyle="#91bca6"
            c.fillRect(Math.round(width/2-13*size),Math.round(height/2),Math.round(26*size),1)
            c.restore()
        }
    }

    component WaterSplash: Canvas {
        anchors.fill: parent
        property real life: Math.ceil(motion.splashLife*24)/24
        property real splashX: motion.splashX
        property real splashY: motion.splashY
        property real strength: motion.splashPower
        visible: life>0 && root.waterZone!==null
        smooth: false;antialiasing: false
        onLifeChanged: requestPaint()
        onSplashXChanged: requestPaint()
        onSplashYChanged: requestPaint()
        onStrengthChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onAvailableChanged: {if(available)requestPaint()}
        onPaint: {
            const c=getContext("2d")
            if(!c)return
            c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,width,height)
            if(life<=0)return
            const age=root.clamp(1-life/0.85,0,1)
            c.save()
            if(root.clipToPond(c,0,0)) {
                c.translate(splashX,splashY);c.scale(1,0.27)
                c.strokeStyle="#bbdfc9";c.lineWidth=1.5;c.globalAlpha=(1-age)*0.7
                c.beginPath();c.arc(0,0,7+age*(23+strength*12),0,Math.PI*2);c.stroke()
            }
            c.restore()
            for(let i=0;i<8;i++) {
                const phase=root.clamp(age*1.15-(i%3)*0.045,0,1)
                if(phase<=0 || phase>=1)continue
                const side=i%2?1:-1
                const xx=splashX+side*(4+phase*(12+(i%4)*5))*strength
                const yy=splashY-Math.sin(phase*Math.PI)*(12+(i%3)*8)*strength+phase*3
                c.globalAlpha=Math.sin(phase*Math.PI)*(1-phase*0.35)
                c.fillStyle=i%2?"#bbdfcf":"#89bfc1"
                c.fillRect(Math.round(xx),Math.round(yy),2,phase<0.6?3:2)
            }
            c.globalAlpha=1
        }
    }    
    component PetSprite: Canvas {
        id: sprite
        property string kind: "cat"
        property string pose: "idle"
        property real time: 0
        property int gaitFrame: 0
        property bool cheerful: true
        property bool inAir: false
        property real jumpPhase: 0.5
        property real crouchAmount: 0
        property real landingAmount: 0
        property real swimAmount: 0
        property real swimPhase: 0
        property real shoreMotion: 0
        property real wingSpread: kind === "duck" && (inAir || pose === "held" || pose === "play"
            || pose === "wash" || pose === "trick") ? (pose === "wash" ? 0.55 : 1)
            : kind === "duck" ? Math.max(0,-shoreMotion)*0.24 : 0
        Behavior on wingSpread { NumberAnimation { duration: 200; easing.type: Easing.InOutSine } }
        property real attention: 0
        property real progress: 0
        property real rest: pose === "sleep" ? 1 : 0
        readonly property real breath: Math.sin(time * (pose === "sleep" ? 1.8 : 2.8))
        readonly property real stretch: pose === "stretch" || pose === "trick"
            ? Math.max(0, Math.sin(pose === "trick" ? progress * Math.PI : time * 2.5)) : 0
        implicitWidth: 96
        implicitHeight: 96
        smooth: false
        antialiasing: false
        transform: Scale {
            origin.x: sprite.width / 2
            origin.y: sprite.height
            xScale: 1 + sprite.rest * 0.06 - sprite.stretch * 0.025
            yScale: 1 - sprite.rest * 0.19 + sprite.breath * (sprite.rest > 0.5 ? 0.015 : 0.009)
                + sprite.stretch * (sprite.kind === "cat" ? -0.06 : 0.035)
        }
        onKindChanged: requestPaint()
        onPoseChanged: requestPaint()
        onTimeChanged: requestPaint()
        onGaitFrameChanged: requestPaint()
        onCheerfulChanged: requestPaint()
        onInAirChanged: requestPaint()
        onJumpPhaseChanged: requestPaint()
        onCrouchAmountChanged: requestPaint()
        onLandingAmountChanged: requestPaint()
        onSwimAmountChanged: requestPaint()
        onSwimPhaseChanged: requestPaint()
        onShoreMotionChanged: requestPaint()
        onWingSpreadChanged: requestPaint()
        onAttentionChanged: requestPaint()
        onProgressChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onAvailableChanged: { if (available) requestPaint() }
        onPaint: paintSprite(getContext("2d"))

        function rect(c, x, y, w, h, color) {
            c.fillStyle = color
            c.fillRect(Math.round(x), Math.round(y), w, h)
        }
        function box(c, x, y, w, h, color) {
            rect(c, x, y, w, h, "#37303b")
            rect(c, x + 1, y + 1, w - 2, h - 2, color)
        }
        function oval(c, x, y, w, h, color) {
            const edge = "#37303b"
            rect(c, x + 4, y, w - 8, h, edge)
            rect(c, x + 2, y + 2, w - 4, h - 4, edge)
            rect(c, x, y + 4, w, h - 8, edge)
            rect(c, x + 4, y + 2, w - 8, h - 4, color)
            rect(c, x + 2, y + 4, w - 4, h - 8, color)
        }
        function eye(c, x, y, closed) {
            if (closed) rect(c, x, y + 2, 4, 1, "#37303b")
            else {
                const look = Math.round(attention)
                rect(c, x + 1 + look, y, 3, cheerful ? 4 : 3, "#37303b")
                rect(c, x + 1 + look, y, 1, 1, "#fff8e9")
            }
        }
        function pixelCell(c, x, y, w, h, color) {
            const sx = width / 48
            const sy = height / 48
            const left = Math.round(x * sx) / sx
            const top = Math.round(y * sy) / sy
            const right = Math.round((x + w) * sx) / sx
            const bottom = Math.round((y + h) * sy) / sy
            c.fillStyle = color
            c.fillRect(left, top, right - left, bottom - top)
        }
        function goosePatch(c, points, color, connected) {
            let top = points[0][1], bottom = top
            for (let i = 1; i < points.length; ++i) {
                top = Math.min(top, points[i][1]); bottom = Math.max(bottom, points[i][1])
            }
            const spans = []
            for (let y = Math.floor(top); y < Math.ceil(bottom); ++y) {
                const scan = y + 0.5
                const edges = []
                for (let i = 0; i < points.length; ++i) {
                    const a = points[i], b = points[(i + 1) % points.length]
                    if ((a[1] > scan) !== (b[1] > scan))
                        edges.push(a[0] + (scan - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
                }
                edges.sort(function(a, b) { return a - b })
                for (let i = 0; i + 1 < edges.length; i += 2) {
                    const left = Math.ceil(edges[i] - 0.5), right = Math.ceil(edges[i + 1] - 0.5)
                    if (right > left) spans.push([left, right, y])
                }
            }
            let kept = null
            if (connected) {
                const pending = {}
                for (let i = 0; i < spans.length; ++i)
                    for (let x = spans[i][0]; x < spans[i][1]; ++x)
                        pending[x + spans[i][2] * 64] = true
                let largest = []
                for (const key in pending) {
                    if (!pending[key]) continue
                    const group = [Number(key)]
                    pending[key] = false
                    for (let i = 0; i < group.length; ++i) {
                        const adjacent = [group[i]-1, group[i]+1, group[i]-64, group[i]+64]
                        for (let j = 0; j < adjacent.length; ++j) {
                            if (pending[adjacent[j]]) {
                                pending[adjacent[j]] = false
                                group.push(adjacent[j])
                            }
                        }
                    }
                    if (group.length > largest.length) largest = group
                }
                kept = {}
                for (let i = 0; i < largest.length; ++i) kept[largest[i]] = true
            }
            for (let i = 0; i < spans.length; ++i) {
                const span = spans[i]
                let start = span[0]
                for (let x = start; x <= span[1]; ++x) {
                    if (x === span[1] || (kept && !kept[x + span[2]*64])) {
                        if (x > start) pixelCell(c, 4+start*1.25, 6+span[2]*1.25,
                            (x-start)*1.25, 1.25, color)
                        start = x + 1
                    }
                }
            }
        }
        function gooseWing(c, amount, phase, farSide, palette) {
            if (amount < 0.015) return
            const cycle = (phase + (farSide ? 0.035 : 0)) % 1
            const t = cycle < 0.38 ? cycle / 0.38 : (cycle - 0.38) / 0.62
            const eased = t * t * (3 - 2 * t)
            const down = cycle < 0.38 ? eased : 1 - eased
            const upFrame = [[15,17], [20,6], [25,2], [28,1], [27,5], [30,4],
                [28,9], [31,8], [28,13], [30,13], [26,17], [23,20], [18,22], [15,20]]
            const downFrame = [[15,17], [22,18], [27,22], [31,24], [28,24], [31,27],
                [27,25], [29,29], [25,27], [26,30], [22,26], [20,23], [17,22], [15,20]]
            const points = []
            const reach = amount * (farSide ? 0.82 : 1)
            for (let i = 0; i < upFrame.length; ++i) {
                const x = upFrame[i][0] + (downFrame[i][0] - upFrame[i][0]) * down
                const y = upFrame[i][1] + (downFrame[i][1] - upFrame[i][1]) * down
                points.push([15 + (x - 15) * reach - (farSide ? 2 : 0),
                    19 + (y - 19) * reach - (farSide ? 1 : 0)])
            }
            goosePatch(c, points, farSide ? "#ded9c2" : palette.C, true)
            if (!farSide && amount > 0.25) {
                const x = 19 + 2 * down, y = 12 + 8 * down
                const stripe = [[16,19], [x,y], [x+1,y+1], [17,20]]
                const inset = []
                for (let i = 0; i < stripe.length; ++i)
                    inset.push([15+(stripe[i][0]-15)*reach, 19+(stripe[i][1]-19)*reach])
                goosePatch(c, inset, palette.O)
            }
        }
        function frogLimb(c, joints, radius, palette) {
            let left = joints[0][0], right = left, top = joints[0][1], bottom = top
            for (let i = 1; i < joints.length; ++i) {
                left = Math.min(left, joints[i][0]); right = Math.max(right, joints[i][0])
                top = Math.min(top, joints[i][1]); bottom = Math.max(bottom, joints[i][1])
            }
            for (let y = Math.floor(top-radius); y <= Math.ceil(bottom+radius); ++y) {
                for (let x = Math.floor(left-radius); x <= Math.ceil(right+radius); ++x) {
                    let distance = 1000
                    for (let i = 0; i + 1 < joints.length; ++i) {
                        const a = joints[i], b = joints[i+1]
                        const dx = b[0]-a[0], dy = b[1]-a[1]
                        const along = Math.max(0, Math.min(1,
                            ((x+0.5-a[0])*dx+(y+0.5-a[1])*dy) / Math.max(0.001,dx*dx+dy*dy)))
                        const px = x+0.5-a[0]-along*dx, py = y+0.5-a[1]-along*dy
                        distance = Math.min(distance, px*px+py*py)
                    }
                    if (distance <= radius*radius)
                        pixelCell(c, 4+x*1.5, 17+y*1.5, 1.5, 1.5,
                            distance < (radius-0.55)*(radius-0.55) ? palette.G : palette.K)
                }
            }
        }
        function drawFrog(c, moving, airborne, step, closed, nibble) {
            const rows = [
                ".............DDDDDDDDD....",
                "...........DDSKKSGLLGSKK..",
                "..........DSSKWWKSLLSKWWK.",
                ".........DSGKWWKWDLLDWWKWK",
                "........DGGGKWWWWDLLDWWWWK",
                ".......DSGLLGKWWDLLLLDWWDK",
                "......DSGGLLLGDDSGLLGSDDK.",
                ".....DGGGGGLLGGGYCCCCCYSK.",
                "....DGGGGGGGGGYCCCCCCCCYK.",
                "...DGGGGGGGGDCCCCCCCCCCK..",
                "..DGGGGGGLLDYCCCCCCCCCK...",
                ".DSGGGGSLLLDYCCCCCCCCK....",
                ".DGLLLGKGLLDYYCCCCCCKK....",
                ".DGLLLLDSLLLDYCCCCCKSK....",
                ".KKLLLLDSDLLDYYCCCYKSSK...",
                "KSGGLLGDSDLLDYYYYYKKSSK...",
                "KGGSKDDSSDLLDYYYYKKKSSK...",
                "KGLLKSSSSDLGLDYYKSSKGSGK..",
                ".KGLLKKKKKKKKKKKSSSSKKKK.."
            ]
            const palette = { K: "#050400", D: "#28401c", S: "#477334", G: "#61a53e",
                L: "#8cd234", C: "#f9f9bb", Y: "#f5d892", W: "#ffffff" }
            const pixel = 1.5
            const activeLegs = moving || airborne || crouchAmount > 0.01 || landingAmount > 0.08
            if (activeLegs) {
                const push = airborne && pose !== "held" ? Math.max(0, 1-Math.abs(jumpPhase-0.2)/0.25) : 0
                const tuck = Math.max(pose === "held" ? 1 : airborne ? Math.pow(Math.sin(jumpPhase*Math.PI), 2)
                    : crouchAmount * 0.25, Math.abs(shoreMotion)*0.4)
                const reach = Math.max(airborne && pose !== "held" ? Math.max(0, (jumpPhase-0.6)/0.4) : 0,
                    Math.max(0,-shoreMotion)*0.9)
                frogLimb(c, [[8,15], [4-2*push,16-1.8*tuck],
                    [6-7*push,17-2*tuck], [2-3*push,18-1.5*tuck]], 1.4, palette)
                frogLimb(c, [[19,13], [20,15-2*tuck],
                    [21+2*reach,17-2.5*tuck], [24,18-2*tuck]], 1.25, palette)
            }
            for (let row = 0; row < rows.length; ++row) {
                for (let col = 0; col < rows[row].length; ++col) {
                    const ink = rows[row][col]
                    if (ink === ".") continue
                    let color = palette[ink]
                    if (activeLegs && ((row >= 16 && col < 11) || (row >= 15 && col >= 19))) continue
                    if (closed && row >= 2 && row <= 5
                        && ((col >= 13 && col <= 16) || (col >= 21 && col <= 24)))
                        color = row === 4 ? palette.D : palette.G
                    pixelCell(c, 4 + col * pixel, 17 + row * pixel, pixel, pixel, color)
                }
            }
            if (pose === "curious" || pose === "trick") {
                const puff = 1.5 + Math.max(0, Math.sin(time * 7)) * 1.5
                pixelCell(c, 32.5, 32, 7.5, puff, palette.C)
            }
            if (pose === "eat" && nibble) {
                pixelCell(c, 37, 30, 4.5, 1.5, palette.K)
                pixelCell(c, 40, 30, 4.5, 1.5, "#e5a1a0")
            }
        }
        function drawGoose(c, moving, airborne, step, closed, nibble) {
            const rows = [
                "................................",
                "................................",
                "................................",
                "........CCCCCC..................",
                ".......CCCCCCCC.................",
                "......OCCKCCCCC.................",
                "....OOOCCCCCCCC.................",
                "..OOOOOCCCCCCCC.................",
                "...OOOOCCCCCCCC.................",
                ".........CCCCCC.................",
                "..........CCCCC.................",
                "..........CCCCC.................",
                "..........CCCCC.................",
                "..........CCCCC.................",
                ".........CCCCCCCC...............",
                ".........CCCCCCCCCCCC.......CC..",
                "........CCCCOCCCCCCCCC.....CCC..",
                "........CCCCOCCCCCCCCCC..CCCCC..",
                ".......CCCCCOCCCCCCCCCCCCCCCC...",
                ".......CCCCCOCCCCCCCOCCCCCCCC...",
                ".......CCCCCCOCCCCOCCOCCCCCC....",
                "........CCCCCCOCCCCOCCCCCCC.....",
                "........CCCCCCCOCCCCOCCCCC......",
                ".........CCCCCCCOOCCCCCCC.......",
                "..........CCCCCCCCCCCCCC........",
                "...........CCCCCCCCCCC..........",
                ".............O....O.............",
                ".............O....O.............",
                "...........OOO...OO.............",
                "..........OOOO..OOO.............",
                "...........OO..OOOO.............",
                "................OO.............."
            ]
            const palette = { C: "#fff5d7", O: "#ff9d25", K: "#050400" }
            const pixel = 1.25
            const wingPhase = (time * 1.4) % 1
            c.save()
            c.translate(48, 0)
            c.scale(-1, 1)
            gooseWing(c, wingSpread, wingPhase, true, palette)
            for (let row = 0; row < rows.length; ++row) {
                for (let col = 0; col < rows[row].length; ++col) {
                    const ink = rows[row][col]
                    if (ink === ".") continue
                    const wing = ink === "O" && row >= 16 && row <= 23
                    let dx = 0
                    let legLift = 0
                    if (row >= 26) {
                        const legDirection = col < 15 ? 1 : -1
                        dx = legDirection * (airborne ? 1 : moving ? step * 0.5 : 0)
                        if(pose === "wade")legLift=Math.max(0,legDirection*step)*0.6
                    }
                    const headDip = row < 14 ? (pose === "eat" ? nibble * 1.5 : pose === "groom" ? 1 : moving ? Math.abs(step) * 0.3 : 0) : 0
                    const dy = headDip + (ink === "O" && row === 8 ? nibble * 0.5 : 0)-legLift
                    const color = wing || (closed && ink === "K") ? palette.C : palette[ink]
                    pixelCell(c, 4 + (col + dx) * pixel, 6 + (row + dy) * pixel, pixel, pixel, color)
                }
            }
            gooseWing(c, wingSpread, wingPhase, false, palette)
            c.save()
            c.globalAlpha *= 1 - wingSpread
            for (let row = 16; row <= 23; ++row)
                for (let col = 0; col < rows[row].length; ++col)
                    if (rows[row][col] === "O")
                        pixelCell(c, 4 + col * pixel, 6 + (row + (pose === "groom" ? -1 : 0)) * pixel, pixel, pixel, palette.O)
            c.restore()
            if (closed) {
                pixelCell(c, 4 + 9 * pixel, 6 + (6 + (pose === "groom" ? 1 : 0)) * pixel, 2 * pixel, 0.75, palette.K)
            }
            c.restore()
        }
        function drawSwimmingFeet(c) {
            if(swimAmount<0.01 || (kind!=="frog" && kind!=="duck")) return
            c.save();c.globalAlpha*=swimAmount*0.4
            const stroke=Math.sin(swimPhase*Math.PI*2)
            if(kind==="frog") {
                const waterPalette={K:"#305b4b",G:"#8bb375"}
                frogLimb(c,[[8,12],[4-2*stroke,15],[2-4*stroke,17],[4-4*stroke,18]],1.5,waterPalette)
                frogLimb(c,[[17,12],[18+2*stroke,15],[20+3*stroke,17]],1.2,waterPalette)
            } else {
                c.translate(48,0);c.scale(-1,1)
                for(let i=0;i<2;i++) {
                    const x=13+i*5, kick=stroke*(i?1:-1)*3
                    goosePatch(c,[[x,24],[x+1,24],[x+1+kick,28],[x+3+kick,29],
                        [x+3+kick,30],[x-1+kick,30],[x-1+kick,28]],"#b6ac69",true)
                }
            }
            c.restore()
        }
        function paintSprite(c) {
            if (!c || width <= 0 || height <= 0) return
            c.setTransform(1, 0, 0, 1, 0, 0)
            c.clearRect(0, 0, width, height)
            c.save()
            c.scale(width / 48, height / 48)
            drawSwimmingFeet(c)
            if(swimAmount>0.01 && (kind==="frog" || kind==="duck")) {
                c.beginPath();c.rect(0,0,48,48-swimAmount*(kind==="frog"?11:13));c.clip()
            }
            const moving = pose === "walk" || pose === "play" || pose === "swim" || pose === "wade"
            const airborne = inAir || pose === "jump" || pose === "held"
            const step = moving ? [0, 1, 2, 1, 0, -1, -2, -1][gaitFrame % 8] : airborne ? 2 : 0
            const blinkPhase = (time + ({ cat: 0.1, parrot: 1.2, hamster: 2.5, fish: 0, frog: 3.1, duck: 4.3 })[kind]) % 5.7
            const blink = kind !== "fish" && (blinkPhase > 5.46 || (blinkPhase > 5.08 && blinkPhase < 5.19))
            const closed = pose === "sleep" || pose === "pet" || pose === "groom" || blink
            const nibble = pose === "eat" ? Math.floor(time * (kind === "hamster" ? 12 : 8)) % 2 : 0
            const wag = Math.round(Math.sin(time * (pose === "pet" ? 7 : moving ? 10 : 3)) * (cheerful ? 1.5 : 0.6))
            const bob = moving && kind !== "fish" && kind !== "frog" ? (Math.abs(step) === 2 ? -1 : 0)*(1-swimAmount) : 0
            const headBob = pose === "eat" ? nibble : pose === "pet" ? Math.round(Math.sin(time * 5)) : 0
            const outline = "#37303b"
            c.translate(0, Math.round(bob * height / 48) * 48 / height)

            if (kind === "cat") {
                box(c, 5, 27 + wag, 12, 6, "#dc8e51")
                box(c, 3, 19 + wag, 6, 12, "#eda466")
                rect(c, 5, 20 + wag, 3, 3, "#ffe3b4")
                oval(c, 12, 26, 24, 17, "#eda466")
                box(c, 15 + step, 39 - (airborne ? 3 : Math.max(0, step)), 7, 7, "#f8d7aa")
                box(c, 28 - step, 39 - (airborne ? 3 : Math.max(0, -step)), 7, 7, "#f8d7aa")
                rect(c, 18, 29, 4, 5, "#cf794a")
                rect(c, 24, 28, 3, 5, "#cf794a")
                c.save()
                c.translate(Math.round(attention * 0.7), headBob)
                const ear = pose === "curious" || time % 8 > 7.65 ? 1 : 0
                box(c, 18 - ear, 10 + ear, 8, 11, "#eda466")
                box(c, 31, 10 - ear, 8, 11, "#eda466")
                rect(c, 20, 12, 4, 5, "#e5a1a0")
                rect(c, 33, 12, 4, 5, "#e5a1a0")
                oval(c, 16, 16, 24, 18, "#eda466")
                rect(c, 26, 17, 3, 4, "#cc7548")
                rect(c, 22, 28, 14, 4, "#ffe5bc")
                eye(c, 22, 22, closed); eye(c, 32, 22, closed)
                rect(c, 28, 27, 3, 2, "#c77880")
                rect(c, 29, 29 + nibble, 1, 2, outline)
                rect(c, 13, 26, 5, 1, outline); rect(c, 38, 26, 5, 1, outline)
                c.restore()
                if (pose === "wash" || pose === "groom") box(c, 31, 27 + wag, 6, 8, "#f8d7aa")
                if (pose === "trick") box(c, 33, 31 - Math.round(stretch * 7), 7, 7, "#f8d7aa")
            } else if (kind === "parrot") {
                box(c, 15 + wag, 34, 6, 11, "#5e9870")
                box(c, 19 + wag, 34, 5, 10, "#77b4aa")
                box(c, 23 + step, 39, 3, 6, "#d3a278")
                box(c, 31 - step, 39, 3, 6, "#d3a278")
                rect(c, 22 + step, 44, 6, 2, outline); rect(c, 30 - step, 44, 6, 2, outline)
                oval(c, 16, 22, 22, 20, "#9bc96f")
                rect(c, 29, 28, 6, 9, "#c4de86")
                const flap = moving || airborne || pose === "trick"
                const wingY = flap ? 20 + Math.round(Math.sin(time * 19) * 6) : pose === "groom" ? 23 : 26
                const wingX = flap ? 7 : 11
                oval(c, wingX, wingY, flap ? 20 : 16, 12, "#e0d775")
                rect(c, wingX + 2, wingY + 5, flap ? 14 : 10, 2, "#afbb64")
                c.save()
                c.translate(pose === "groom" ? -1 : 0,
                    headBob + (pose === "groom" ? 2 : pose === "curious" ? Math.round(Math.sin(time * 5)) : 0))
                oval(c, 22, 12, 18, 19, "#efb16b")
                rect(c, 26, 10, 8, 3, outline); rect(c, 27, 11, 6, 3, "#e9d578")
                rect(c, 30, 17, 7, 8, "#fff2ce")
                eye(c, 31, 18, closed)
                box(c, 37, 23 + nibble, 7, 5, "#d77e6d")
                rect(c, 39, 27 + nibble, 3, 3, outline)
                rect(c, 24, 16, 3, 3, "#f6d487")
                c.restore()
            } else if (kind === "hamster") {
                box(c, 14, 12, 9, 10, "#e7b27b")
                box(c, 30, 12, 9, 10, "#e7b27b")
                rect(c, 16, 14, 5, 4, "#e9a5a1"); rect(c, 32, 14, 5, 4, "#e9a5a1")
                box(c, 16 + step, 40 - (airborne ? 3 : Math.max(0, step)), 8, 6, "#edbbb0")
                box(c, 29 - step, 40 - (airborne ? 3 : Math.max(0, -step)), 8, 6, "#edbbb0")
                oval(c, 11, 18, 31, 26, "#e7b27b")
                oval(c, 16, 29, 23, 14, "#ffe5bd")
                eye(c, 19, 24, closed); eye(c, 31, 24, closed)
                const sniff = pose === "curious" ? Math.round(Math.sin(time * 15)) : 0
                rect(c, 26 + sniff, 29 + nibble, 4, 2, "#be8387")
                rect(c, 27, 31 + nibble, 2, 3, "#fff9df")
                rect(c, 15, 29, 5 + nibble, 3, "#efbcac")
                rect(c, 35 - nibble, 29, 5, 3, "#efbcac")
                const pawsUp = pose === "eat" || pose === "groom" || pose === "trick"
                const pawY = pose === "groom" ? 28 + wag : pose === "trick" ? 29 - Math.round(stretch * 2) : 34 - nibble
                box(c, 13 + (pawsUp ? 5 : 0), pawY, 6, 6, "#edbbb0")
                box(c, 34 - (pawsUp ? 4 : 0), pawY, 6, 6, "#edbbb0")
                rect(c, 10, 27, 5, 1, outline); rect(c, 39, 27, 5, 1, outline)
            } else if (kind === "fish") {
                const tailBeat = Math.round(Math.sin(time * (pose === "sleep" ? 2 : moving || pose === "trick" ? 15 : 6)) * 2)
                box(c, 3 + tailBeat, 20 + Math.abs(tailBeat), 7, 21 - Math.abs(tailBeat) * 2, "#859ac6")
                box(c, 8 + tailBeat, 25, 8, 11, "#a3bfdb")
                box(c, 19, 17 + wag, 11, 8, "#859ac6")
                oval(c, 11, 22, 30, 19, "#9dc9e1")
                rect(c, 17, 25, 14, 2, "#d4e5e6")
                rect(c, 18, 36, 17, 3, "#7aadc9")
                box(c, 21 - wag, 32, 8, 8 + wag, "#aac0db")
                eye(c, 32, 28, closed)
                rect(c, 39, 34 + nibble, 3, pose === "eat" && nibble ? 2 : 1, outline)
                rect(c, 30, 34, 3, 2, "#d5b4c0")
                rect(c, 15, 30, 2, 2, "#82b5d0")
                rect(c, 19, 28, 2, 2, "#82b5d0")
            } else if (kind === "frog") {
                drawFrog(c, moving, airborne, step, closed, nibble)
            } else if (kind === "duck") {
                drawGoose(c, moving, airborne, step, closed, nibble)
            }
            if (pose === "pet" && kind !== "frog" && kind !== "duck") {
                rect(c, kind === "fish" ? 30 : 20, kind === "fish" ? 34 : 28, 3, 2, "#e5a1a0")
            }
            c.restore()
        }
    }

    component SoftButton: Rectangle {
        id: button
        property string label: ""
        property bool highlighted: false
        signal clicked()
        implicitWidth: buttonText.implicitWidth + 16
        implicitHeight: 26
        radius: 8
        color: buttonMouse.pressed ? root.accentPrimary : buttonMouse.containsMouse ? root.bgTrack : "transparent"
        border.width: 1
        border.color: highlighted ? root.accentPrimary : root.textDim
        Behavior on color { ColorAnimation { duration: 150 } }
        opacity: enabled ? 1 : 0.42
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: { if (enabled) clicked() }
        Keys.onReturnPressed: { if (enabled) clicked() }
        Keys.onSpacePressed: { if (enabled) clicked() }
        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            font.pixelSize: 10
            font.bold: true
            color: buttonMouse.pressed ? root.bgPanel : button.highlighted ? root.accentPrimary : root.textDim
        }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: button.activeFocus ? 1 : 0; border.color: root.accentPrimary }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component NeedMeter: Item {
        id: meter
        property string label: ""
        property real value: 0
        implicitWidth: 140
        implicitHeight: 26
        Row {
            width: parent.width
            Text { width: parent.width - 28; text: meter.label; color: root.textDim; font.pixelSize: 11 }
            Text { width: 28; text: Math.round(meter.value); horizontalAlignment: Text.AlignRight; color: meter.value < 25 ? root.danger : root.textMain; font.pixelSize: 11 }
        }
        Rectangle {
            y: 19
            width: parent.width
            height: 6
            radius: 3
            color: root.bgTrack
            Rectangle {
                width: parent.width * root.clamp(meter.value / 100, 0, 1)
                height: parent.height
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: meter.value < 25 ? Qt.darker(root.danger, 1.2) : root.accentSecondary }
                    GradientStop { position: 1.0; color: meter.value < 25 ? root.danger : root.accentPrimary }
                }
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    component CareButton: Rectangle {
        id: care
        property string action: "eat"
        property string label: ""
        property int cooldown: 0
        signal clicked()
        implicitHeight: 30
        radius: 8
        color: careMouse.containsMouse && enabled ? root.accentPrimary : root.bgTrack
        border.width: 1
        border.color: root.accentPrimary
        opacity: enabled ? 1 : 0.43
        scale: careMouse.pressed && enabled ? 0.96 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: { if (enabled) clicked() }
        Keys.onReturnPressed: { if (enabled) clicked() }
        Keys.onSpacePressed: { if (enabled) clicked() }
        Text {
            anchors.centerIn: parent
            text: care.cooldown > 0 ? care.cooldown + " с" : care.label
            color: careMouse.containsMouse && care.enabled ? root.bgPanel : root.textMain
            font.pixelSize: 10
            font.bold: true
        }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: care.activeFocus ? 1 : 0; border.color: root.accentPrimary }
        MouseArea { id: careMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: care.clicked() }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 8
        color: root.bgPanel
        border.width: 3
        border.color: root.borderColor
        opacity: 0
        scale: 0.85
        transformOrigin: Item.TopRight
        enabled: root.expanded
        focus: root.expanded
        Keys.onEscapePressed: {
            if (root.choosing && root.selectedPet !== "") root.choosing = false
            else root.hide()
        }
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 120; easing.type: Easing.InCubic }
            }
            ScriptAction { script: { root.closing = false } }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "🐾"; font.pixelSize: 18; color: root.accentPrimary }
                Text {
                    Layout.fillWidth: true
                    text: root.picking ? "Выбери питомца" : root.currentPetDef.name
                    color: root.textMain
                    font.pixelSize: root.picking ? 16 : 18
                    font.bold: true
                    elide: Text.ElideRight
                }
                SoftButton {
                    visible: root.selectedPet !== ""
                    label: root.picking ? "Назад" : "Сменить"
                    onClicked: { if (root.picking) root.choosing = false; else root.releasePet() }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.separatorColor }

            ColumnLayout {
                visible: root.picking
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: "Корми, играй и заботься. У каждого питомца свой характер и прогресс."
                    color: root.textDim; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 3
                    rowSpacing: 6
                    columnSpacing: 6
                    Repeater {
                        model: root.petDefs
                        delegate: Rectangle {
                            id: choice
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 88
                            Layout.preferredHeight: 118
                            radius: 12
                            color: pickArea.containsMouse ? root.bgTrack : "transparent"
                            border.width: root.selectedPet === modelData.key || activeFocus ? 1 : 0
                            border.color: root.accentPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                            enabled: root.stateReady
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name
                            Accessible.onPressAction: root.choosePet(modelData.key)
                            Keys.onReturnPressed: root.choosePet(modelData.key)
                            Keys.onSpacePressed: root.choosePet(modelData.key)
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 5
                                PetSprite {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 72; height: 72
                                    kind: choice.modelData.key
                                    pose: pickArea.containsMouse || choice.activeFocus ? "curious" : "idle"
                                    time: root.expanded && root.picking ? Math.floor(motion.clock * 18) / 18 + choice.index * 0.7 : 0
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: choice.modelData.name; color: root.textMain; font.pixelSize: 11; font.bold: true }
                                Text { width: parent.width; text: choice.modelData.detail; color: root.textDim; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                            }
                            MouseArea { id: pickArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.choosePet(choice.modelData.key) }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.stateIssue !== "" ? root.stateIssue : root.stateReady ? "Показатели меняются только у выбранного питомца. Остальные отдыхают без потерь." : "Загружаем сохранение…"
                    color: root.stateIssue !== "" ? root.danger : root.textDim; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                visible: !root.picking
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: root.growth + " · день " + root.ageDays; color: root.textDim; font.pixelSize: 10; Layout.fillWidth: true }
                    Text { text: "♥ " + Math.round(root.currentStats.bond) + "  ·  Ур. " + root.level; color: root.accentPrimary; font.pixelSize: 10 }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 17
                    rowSpacing: 8
                    NeedMeter { Layout.fillWidth: true; label: "Сытость"; value: root.currentStats.hunger }
                    NeedMeter { Layout.fillWidth: true; label: "Настроение"; value: root.currentStats.mood }
                    NeedMeter { Layout.fillWidth: true; label: "Энергия"; value: root.currentStats.energy }
                    NeedMeter { Layout.fillWidth: true; label: "Чистота"; value: root.currentStats.hygiene }
                }

                Rectangle {
                    id: habitatFloor
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 300
                    radius: 10
                    clip: true
                    color: root.bgTrack
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.darker(root.isNightTime ? root.habitatDef.nightTop : root.habitatDef.skyTop, root.sleeping ? 1.2 : 1) }
                        GradientStop { position: 1.0; color: Qt.darker(root.isNightTime ? root.habitatDef.nightBottom : root.habitatDef.skyBottom, root.sleeping ? 1.2 : 1) }
                    }
                    onWidthChanged: { if (motion.initialized) root.confineMotion() }
                    onHeightChanged: { if (motion.initialized) root.confineMotion() }
                    HabitatScene { id: habitatScenery }
                    Repeater {
                        model: root.habitatObjects
                        delegate: Item {
                            required property var modelData
                            required property int index
                            x: root.habitatX(index) - width / 2
                            y: root.habitatY(index) - 64
                            width: 72; height: 90
                            enabled: root.stateReady && !root.picking
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.hint
                            Accessible.onPressAction: root.interactWithHabitat(index)
                            Keys.onReturnPressed: root.interactWithHabitat(index)
                            Keys.onSpacePressed: root.interactWithHabitat(index)
                            Rectangle {
                                anchors.fill: parent; radius: 6; color: "transparent"
                                border.width: parent.activeFocus ? 1 : 0; border.color: root.accentPrimary
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 74
                                text: parent.modelData.name
                                color: pickupArea.hoveredHabitat === parent.index ? root.hoverLight : "#e4ead8"
                                font.pixelSize: 9
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -3
                                    color: "#b31f2924"; radius: 2; z: -1
                                }
                            }
                        }
                    }
                    Text {
                        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 14
                        text: root.sleeping ? "Тихий час" : root.habitatDef.title
                        color: "#e4ead8"
                        font.pixelSize: 10
                        Rectangle {
                            anchors.fill: parent; anchors.margins: -4
                            color: "#a6202b2a"; radius: 3; z: -1
                        }
                    }
                    Rectangle {
                        x: motion.posX - width / 2
                        y: motion.groundY - 5
                        width: (49 - Math.min(18, motion.lift * 0.15)) * root.spriteScale
                        height: 9 * root.spriteScale
                        radius: height / 2
                        color: "#000000"
                        opacity: root.clamp(0.23 - motion.lift / 600, 0.06, 0.23)*(1-motion.swim)
                    }
                    Rectangle {
                        visible: root.busy && motion.activity === "play"
                        x: root.toyX - 7
                        y: root.toyY - 14 - motion.toyLift
                        width: 14; height: 14; radius: 7
                        color: root.accentPrimary; border.width: 2; border.color: root.accentSecondary
                        Rectangle { anchors.centerIn: parent; width: 2; height: parent.height - 3; color: root.textMain; rotation: motion.toySpin }
                    }
                    Rectangle {
                        visible: motion.goalLife > 0 && !root.sleeping && !root.busy
                        x: motion.targetX - width / 2; y: motion.targetY - height / 2
                        width: 14 + (1 - motion.goalLife) * 12; height: width * 0.45; radius: height / 2
                        color: "transparent"; border.width: 1; border.color: root.accentPrimary
                        opacity: motion.goalLife * 0.7
                    }

                    Item {
                        id: petStageSprite
                        width: 96; height: 96
                        x: motion.posX - width / 2 + (root.habitatUsing && root.activeHabitatObject.kind === "swing" ? Math.sin(motion.clock * 2.4) * 6 : 0)
                        y: root.screenFoot - height
                        transformOrigin: Item.Bottom
                        scale: root.spriteScale
                        rotation: motion.lean + (root.pose === "shake" ? Math.sin(motion.clock * 36) * 4
                            : root.pose === "trick" && root.selectedPet === "fish" ? Math.sin(root.actionProgress * Math.PI * 4) * 12
                            : root.selectedPet === "duck" && motion.moving ? Math.sin(motion.gait * Math.PI * 2) * 3*(1-motion.swim)
                            : root.habitatUsing && root.activeHabitatObject.kind === "swing" ? Math.sin(motion.clock * 2.4) * 4
                            : root.pose === "pet" ? Math.sin(motion.clock * 3) * 1.5 : 0)
                        transform: Scale {
                            origin.x: 48; origin.y: 96
                            xScale: motion.facing * (1 + motion.squash + root.frogCrouch * 0.075)
                            yScale: 1 - motion.squash - root.frogCrouch * 0.11
                        }
                        PetSprite {
                            id: stageSprite
                            anchors.fill: parent
                            kind: root.selectedPet
                            pose: root.pose
                            time: root.expanded && !root.picking ? Math.floor(motion.clock * 24) / 24 : 0
                            gaitFrame: Math.floor(motion.gait * 8) % 8
                            cheerful: root.currentMood >= 40
                            inAir: motion.lift > 1
                            jumpPhase: Math.round(root.frogJumpPhase * 24) / 24
                            crouchAmount: Math.round(root.frogCrouch * 12) / 12
                            landingAmount: Math.round(motion.squash / 0.17 * 12) / 12
                            swimAmount: Math.round(root.waterClip*48)/48
                            swimPhase: Math.floor(motion.swimGait*48)/48
                            shoreMotion: Math.round(root.shoreMotion*24)/24
                            attention: Math.round(motion.gaze * 2) / 2
                            progress: Math.floor(root.actionProgress * 48) / 48
                            rest: motion.rest
                            opacity: (root.habitatUsing && (root.activeHabitatObject.kind === "burrow" || root.activeHabitatObject.kind === "cave"))
                                || (root.sleepingAtHome && (root.selectedPet==="hamster" || root.selectedPet==="fish"))
                                ? 0.4 : root.sleeping ? 0.82 : 1
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }
                    }
                    SurfaceWake { id: surfaceWake }
                    WaterSplash { id: waterSplash }
                    Rectangle {
                        visible: root.busy && motion.activity === "eat"
                        x: root.clamp(motion.posX + motion.facing * 26 - 12, 4, habitatFloor.width - 28)
                        y: motion.groundY - 12
                        width: 25; height: 11; radius: 4
                        color: root.accentSecondary; border.width: 2; border.color: root.accentPrimary
                        Repeater {
                            model: 6
                            delegate: Rectangle {
                                required property int index
                                visible: root.actionProgress < 1 - index / 7
                                x: 3 + index * 3; y: -2 - index % 2
                                width: root.selectedPet === "cat" ? 4 : 2; height: 3
                                radius: root.selectedPet === "fish" ? 0 : 1
                                color: root.currentPetDef.accent
                            }
                        }
                    }
                    Repeater {
                        model: 7
                        delegate: Rectangle {
                            required property int index
                            visible: root.pose === "wash" && (!root.habitatUsing || root.activeHabitatObject.kind === "bath")
                            x: motion.posX - 35 + (index * 17) % 70 + Math.sin(motion.clock * 3 + index) * 3
                            y: root.screenFoot - 20 - ((motion.clock * 22 + index * 12) % 64)
                            width: 6 + index % 3 * 3; height: width; radius: width / 2
                            color: root.accentSecondary; opacity: 0.65; border.width: 1; border.color: root.textMain
                        }
                    }
                    Repeater {
                        model: 3
                        delegate: Text {
                            required property int index
                            readonly property real phase: (motion.clock * 0.6 + index / 3) % 1
                            visible: root.pose === "pet"
                            x: root.clamp(motion.posX - 24 + index * 19 + Math.sin(phase * 6 + index) * 3, 4, habitatFloor.width - 18)
                            y: root.screenFoot - 53 - phase * 38
                            text: "♥"; font.pixelSize: 9 + index * 2; color: root.accentPrimary
                            opacity: Math.sin(phase * Math.PI) * 0.85
                        }
                    }
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            readonly property real phase: (motion.clock * (root.pose === "trick" ? 0.6 : 0.28) + index / 4) % 1
                            visible: root.selectedPet === "fish" && !root.sleeping && root.pose !== "wash"
                            x: root.clamp(motion.posX + motion.facing * 33 + Math.sin(phase * 8 + index) * 4, 4, habitatFloor.width - 12)
                            y: root.screenFoot - 29 - phase * 58
                            width: 3 + index % 3; height: width; radius: width / 2
                            color: "transparent"; border.width: 1; border.color: root.textDim
                            opacity: Math.sin(phase * Math.PI) * 0.5
                        }
                    }
                    Text {
                        visible: root.pose === "sleep"
                        x: motion.posX + 17
                        y: root.screenFoot - 81 - Math.sin(motion.clock * 2) * 3
                        text: "z Z"; color: root.textDim; font.pixelSize: 17; font.bold: true
                    }
                    Text {
                        visible: root.reactionLife > 0
                        x: root.clamp(motion.posX - width / 2, 4, habitatFloor.width - width - 4)
                        y: Math.max(8, root.screenFoot - 90 - (1.2 - root.reactionLife) * 19)
                        text: root.reaction; color: root.accentPrimary; font.pixelSize: 23
                        opacity: root.clamp(root.reactionLife, 0, 1)
                    }
                    MouseArea {
                        id: pickupArea
                        anchors.fill: parent
                        enabled: root.stateReady && !root.picking
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        pressAndHoldInterval: 550
                        preventStealing: true
                        cursorShape: dragging || draggingToy ? Qt.ClosedHandCursor
                            : (root.busy && motion.activity === "play") || hoveredHabitat >= 0 ? Qt.PointingHandCursor
                            : overPet ? Qt.OpenHandCursor : Qt.ArrowCursor
                        property bool dragging: false
                        property bool draggingToy: false
                        property bool pressOnPet: false
                        property bool consumedPress: false
                        property int pressedHabitat: -1
                        property real startX: 0
                        property real startY: 0
                        property real offsetX: 0
                        property real offsetY: 0
                        property real lastX: 0
                        property real lastY: 0
                        property real lastSample: 0
                        property real throwX: 0
                        property real throwY: 0
                        readonly property bool overPet: containsMouse && Math.abs(mouseX - motion.posX) < 43 * root.spriteScale
                            && mouseY > root.screenFoot - 85 * root.spriteScale && mouseY < root.screenFoot + 2
                        readonly property int hoveredHabitat: containsMouse && !overPet ? root.habitatHit(mouseX, mouseY) : -1
                        function resetPointer() {
                            dragging = false; draggingToy = false; pressOnPet = false
                            consumedPress = true
                            pressedHabitat = -1
                            throwX = 0; throwY = 0
                        }
                        onContainsMouseChanged: root.pointerInside = containsMouse && enabled
                        onEnabledChanged: {
                            if (!enabled) { resetPointer(); root.pointerInside = false }
                        }
                        onPressed: mouse => {
                            if (dragging || draggingToy || motion.pointerDown) return
                            startX = mouse.x; startY = mouse.y
                            dragging = false; throwX = 0; throwY = 0
                            consumedPress = false
                            pressedHabitat = -1
                            if (mouse.button === Qt.RightButton) {
                                consumedPress = true
                                root.showTrick()
                                return
                            }
                            if (root.busy && motion.activity === "play") {
                                consumedPress = true
                                draggingToy = true
                                root.moveToy(mouse.x, mouse.y)
                                return
                            }
                            if (hoveredHabitat >= 0) {
                                consumedPress = true
                                pressedHabitat = hoveredHabitat
                                return
                            }
                            pressOnPet = overPet && !root.sleeping && !root.busy
                            if (!pressOnPet) return
                            motion.pointerDown = true
                            offsetX = motion.posX - mouse.x
                            offsetY = root.screenFoot - mouse.y
                            lastX = motion.posX; lastY = root.screenFoot; lastSample = Date.now()
                        }
                        onPositionChanged: mouse => {
                            root.pointerX = mouse.x
                            if (draggingToy) {
                                root.moveToy(mouse.x, mouse.y)
                                return
                            }
                            if (!pressed || !pressOnPet) return
                            const dx = mouse.x - startX, dy = mouse.y - startY
                            if (!dragging && dx * dx + dy * dy >= 36) {
                                dragging = true
                                motion.held = true
                                motion.activity = "idle"
                                motion.gestureRemaining = 0
                                motion.crouch = 0
                                motion.hopSpeed = 0
                                motion.vx = 0; motion.vy = 0; motion.vz = 0
                            }
                            if (!dragging) return
                            const x = root.clamp(mouse.x + offsetX, root.floorLeft, root.floorRight)
                            const foot = root.clamp(mouse.y + offsetY, 96 * root.spriteScale + 5, root.floorNear)
                            const now = Date.now()
                            const dt = (now - lastSample) / 1000
                            if (dt >= 0.008) {
                                throwX = throwX * 0.35 + root.clamp((x - lastX) / dt, -220, 220) * 0.65
                                throwY = throwY * 0.35 + root.clamp((foot - lastY) / dt, -350, 350) * 0.65
                                lastX = x; lastY = foot; lastSample = now
                            }
                            motion.posX = x
                            motion.groundY = root.clamp(foot + 25, root.floorFar, root.floorNear)
                            motion.lift = Math.max(0, motion.groundY - foot)
                            root.confineMotion()
                        }
                        onPressAndHold: mouse => {
                            if (mouse.button !== Qt.LeftButton || dragging || !pressOnPet) return
                            consumedPress = true
                            pressOnPet = false
                            motion.pointerDown = false
                            root.soothePet()
                        }
                        onReleased: mouse => {
                            if (mouse.button !== Qt.LeftButton) return
                            motion.pointerDown = false
                            if (pressedHabitat >= 0) {
                                const target = pressedHabitat
                                const click = Math.abs(mouse.x-startX)+Math.abs(mouse.y-startY) < 6
                                    && root.habitatHit(mouse.x,mouse.y) === target
                                resetPointer()
                                if (click) root.interactWithHabitat(target)
                                return
                            }
                            if (dragging) {
                                motion.held = false
                                if (Date.now() - lastSample > 100) { throwX = 0; throwY = 0 }
                                motion.vx = throwX * 0.6
                                motion.vy = throwY * 0.10
                                motion.vz = root.clamp(-throwY * 0.45, -140, 180)
                                motion.wait = 1.5
                                root.cuddleAfterHold()
                            } else if (!consumedPress && pressOnPet) root.pet()
                            else if (!consumedPress && Math.abs(mouse.x - startX) + Math.abs(mouse.y - startY) < 6) root.walkTo(mouse.x, mouse.y)
                            resetPointer()
                        }
                        onCanceled: {
                            resetPointer()
                            motion.pointerDown = false; motion.held = false
                            motion.vx = 0; motion.vy = 0; motion.vz = 0
                            motion.wait = 1.2
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    text: root.statusText
                    color: root.stateIssue !== "" ? root.danger : root.textMain; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    CareButton {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        action: "eat"; label: "Кормить"; cooldown: root.cooldownRemaining(action)
                        enabled: !root.sleeping && !root.busy && !motion.held && cooldown === 0
                        onClicked: root.feedPet()
                    }
                    CareButton {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        action: "play"; label: "Играть"; cooldown: root.cooldownRemaining(action)
                        enabled: !root.sleeping && !root.busy && !motion.held && cooldown === 0
                        onClicked: root.playWithPet()
                    }
                    CareButton {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        action: "wash"; label: "Мыть"; cooldown: root.cooldownRemaining(action)
                        enabled: !root.sleeping && !root.busy && !motion.held && cooldown === 0
                        onClicked: root.washPet()
                    }
                    CareButton {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        label: root.sleeping ? "Разбудить" : "Спать"
                        enabled: !root.busy && !motion.held
                        onClicked: root.toggleSleep()
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 4; radius: 2; color: root.bgTrack
                    Rectangle { width: parent.width * (root.currentStats.xp % 40) / 40; height: parent.height; radius: 2; color: root.accentPrimary }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Клик / удержание — ласка · Потяни — на ручки\nПредметы — клик · Пол — идти · ПКМ — трюк"
                    color: root.textDim; font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter; lineHeight: 1.25
                }
            }
        }
    }
}
