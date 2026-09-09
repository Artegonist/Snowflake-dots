import QtQuick
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root

    //------------------------------- WINDOW SETUP ----------------------
    visible: false
    focusable: true
    WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool expanded: false
    property bool closing: false

    function show() {
        root.closing = false
        if (!root.visible)
            root.visible = true
        focusGrab.active = true
        root.mask = null
        root.expanded = true
        root.refreshAll()
        Qt.callLater(function() {
            if (!root.expanded)
                return
            if (root.passwordRetry && root.wifiEnabled) {
                const retry = root.passwordRetry
                root.passwordRetry = null
                root.promptPassword(retry.ssid, retry.profile)
            } else if (root.passwordPromptVisible) {
                passwordField.forceActiveFocus()
            } else {
                card.forceActiveFocus()
            }
        })
    }

    function hide() {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.expanded = false
        root.cancelPassword()
    }

    function toggle() {
        if (root.expanded && !root.closing)
            hide()
        else
            show()
    }

    Region {
        id: emptyRegion
        x: 0
        y: 0
        width: 0
        height: 0
    }

    anchors {
        top: true
        right: true
    }

    margins {
        top: 30
        right: 53
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 380
    implicitHeight: 540

    //------------------------------- THEME COLORS ----------------------
    readonly property color accentPrimary:   "#5fa77c"
    readonly property color accentSecondary: "#446b56"
    readonly property color bgPanelWaybar:   "#1b241c"
    readonly property color bgPanel:         "#1c211e"
    readonly property color bgTrack:         "#2a322d"
    readonly property color bgInput:         "#1e2d26"
    readonly property color textMain:        "#eef3ef"
    readonly property color textDim:         "#8fa196"
    readonly property color textWaybar:      "#a8c3a0"
    readonly property color workspaceActive: "#6e8f72"
    readonly property color hoverLight:      "#b7d3a8"
    readonly property color hoverSelect:     "#b4dcc3"
    readonly property color inputTextColor:  "#e8f0ec"
    readonly property color accentText:      "#cdd6f4"

    readonly property color borderColor: accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)

    //------------------------------- STATE ----------------------
    property bool wifiEnabled: true
    readonly property bool scanning: scanProc.pending || scanProc.running
    readonly property bool busy: connectProc.pending || connectProc.running
                                || passwordUpdateProc.pending || passwordUpdateProc.running
                                || disconnectProc.pending || disconnectProc.running
                                || forgetProc.pending || forgetProc.running
                                || radioToggleProc.pending || radioToggleProc.running
    readonly property bool disconnecting: disconnectProc.pending || disconnectProc.running
                                         || ((radioToggleProc.pending || radioToggleProc.running) && !radioToggleProc.turnOn)
                                         || ((forgetProc.pending || forgetProc.running) && root.activeUuid !== ""
                                             && forgetProc.targetUuids.indexOf(root.activeUuid) !== -1)
    property string ipAddress: "—"
    property string activeSsid: ""
    property string activeIface: ""
    property string activeUuid: ""
    property string wifiIface: ""
    property var networks: []
    readonly property var availableNetworks: root.networks.filter(function(n) { return n.ssid !== root.activeSsid })
    property var knownConnections: []
    property string connectingSsid: ""
    property string errorText: ""
    property string statusErrorText: ""
    property bool passwordPromptVisible: false
    property string pendingSsid: ""
    property var pendingProfile: null
    property var attemptProfile: null
    property bool attemptNeedsPassword: false
    property string attemptIface: ""
    property var passwordRetry: null

    property int pollInterval: 5000
    property int backgroundPollInterval: 30000
    property int connectingPollInterval: 1000
    property int scanInterval: 30000
    property int profilesInterval: 60000
    property int connectTimeout: 35
    property int commandTimeout: 5
    property int scanTimeout: 15

    property int stateEpoch: 0
    property double lastProfilesRefresh: 0
    property double lastScan: 0
    property bool profilesDirty: true
    property bool cachedScanPending: false
    property var deviceSnapshot: []
    property int deviceSnapshotEpoch: -1
    readonly property var nmcliEnvironment: ({ LC_ALL: "C", LANG: "C", NO_COLOR: "1", PAGER: "" })

    ListModel { id: networkModel }

    onAvailableNetworksChanged: root.syncNetworkModel()

    //------------------------------- FUNCTIONS ----------------------
    function queueRefresh() {
        if (!eventRefreshTimer.running)
            eventRefreshTimer.start()
    }

    function refreshAll() {
        root.refreshRadioState()
        root.refreshActiveConnection()
        if (root.expanded && !root.busy) {
            root.refreshKnownConnections()
            root.scanNetworks(false)
        }
    }

    function refreshRadioState() {
        radioStateProc.start(["-t", "-f", "WIFI", "radio"], root.commandTimeout)
    }

    function refreshActiveConnection() {
        activeConnProc.start(["-t", "-e", "no", "-m", "multiline", "-f",
            "GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.CON-UUID,IP4.ADDRESS,IP6.ADDRESS",
            "device", "show"], root.commandTimeout)
    }

    function refreshIp() { root.refreshActiveConnection() }

    function refreshKnownConnections() {
        if (knownConnProc.pending || knownConnProc.running || profileDetailsProc.pending || profileDetailsProc.running || root.busy)
            return
        const elapsed = Date.now() - root.lastProfilesRefresh
        if (!root.profilesDirty && elapsed >= 0 && elapsed < Math.max(5000, root.profilesInterval))
            return
        if (knownConnProc.start(["-t", "-f", "UUID,TYPE", "connection", "show"], root.commandTimeout))
            root.profilesDirty = false
    }

    function scanNetworks(force, automatic) {
        const rescan = force === undefined || force === true
        const manual = rescan && automatic !== true
        if (!root.wifiEnabled || !root.expanded || root.busy || root.passwordPromptVisible || root.scanning)
            return
        const args = ["-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY,DEVICE", "device", "wifi", "list",
                      "--rescan", rescan ? "yes" : "no"]
        if (root.wifiIface !== "")
            args.push("ifname", root.wifiIface)
        scanProc.requestIface = root.wifiIface
        scanProc.manual = manual
        if (scanProc.start(args, root.scanTimeout)) {
            root.cachedScanPending = false
            if (rescan)
                root.lastScan = Date.now()
            if (manual) {
                root.errorText = ""
            }
        }
    }

    function toggleRadio() {
        return root.setRadioEnabled(!root.wifiEnabled)
    }

    function setRadioEnabled(enabled) {
        const turnOn = enabled === true
        if (radioToggleProc.pending || radioToggleProc.running || (turnOn && root.busy))
            return false
        if (!turnOn) {
            connectProc.cancel()
            passwordUpdateProc.cancel()
            scanProc.cancel()
            root.connectingSsid = ""
            root.attemptProfile = null
            root.attemptNeedsPassword = false
            root.attemptIface = ""
        }
        root.cancelPassword()
        root.errorText = ""
        root.stateEpoch++
        radioToggleProc.turnOn = turnOn
        return radioToggleProc.start(["radio", "wifi", turnOn ? "on" : "off"], root.commandTimeout)
    }

    function profileForSsid(ssid) {
        for (const profile of root.knownConnections) {
            if (profile.ssid === ssid && (!profile.iface || !root.wifiIface || profile.iface === root.wifiIface))
                return profile
        }
        return null
    }

    function networkForSsid(ssid) {
        for (const network of root.networks) {
            if (network.ssid === ssid)
                return network
        }
        return null
    }

    function promptPassword(ssid, profile) {
        root.pendingSsid = ssid
        root.pendingProfile = profile
        passwordField.text = ""
        root.passwordPromptVisible = true
        Qt.callLater(function() {
            if (root.expanded && root.passwordPromptVisible)
                passwordField.forceActiveFocus()
        })
    }

    function connectTo(ssid, secure, known) {
        if (root.busy || !root.wifiEnabled || !ssid || root.passwordPromptVisible)
            return
        const profile = root.profileForSsid(ssid)
        const network = root.networkForSsid(ssid)
        const needsPassword = network ? network.needsPassword : secure
        root.errorText = ""
        root.passwordRetry = null
        if (!profile && network && /802\.1X|EAP/i.test(network.security)) {
            root.errorText = "Для этой сети сначала настройте профиль 802.1X в NetworkManager"
            return
        }
        if (needsPassword && !profile) {
            root.promptPassword(ssid, null)
            return
        }
        root.beginConnection(ssid, profile, needsPassword, "")
    }

    function beginConnection(ssid, profile, needsPassword, password) {
        root.stateEpoch++
        root.errorText = ""
        root.connectingSsid = ssid
        root.attemptProfile = profile
        root.attemptNeedsPassword = needsPassword
        root.attemptIface = root.wifiIface
        if (password.length > 0 && profile) {
            let secretProperty = "802-11-wireless-security.psk"
            if (profile.keyMgmt === "none")
                secretProperty = "802-11-wireless-security.wep-key" + profile.wepKeyIndex
            else if (profile.keyMgmt === "wpa-eap" || profile.keyMgmt === "ieee8021x" || profile.keyMgmt === "wpa-eap-suite-b-192")
                secretProperty = "802-1x.password"
            passwordUpdateProc.start(["connection", "modify", "uuid", profile.uuid, secretProperty, password], root.commandTimeout, true)
            return
        }
        const args = profile ? ["connection", "up", "uuid", profile.uuid]
                             : ["device", "wifi", "connect", ssid]
        if (root.attemptIface !== "")
            args.push("ifname", root.attemptIface)
        if (password.length > 0)
            args.push("password", password)
        connectProc.start(args, root.connectTimeout, password.length > 0)
    }

    function connectWithPassword() {
        if (root.busy || !root.wifiEnabled || !root.passwordPromptVisible || !root.pendingSsid || passwordField.text.length === 0)
            return
        const ssid = root.pendingSsid
        const profile = root.pendingProfile || root.profileForSsid(ssid)
        const password = passwordField.text
        root.cancelPassword()
        root.beginConnection(ssid, profile, true, password)
    }

    function cancelPassword() {
        root.passwordPromptVisible = false
        root.pendingSsid = ""
        root.pendingProfile = null
        root.passwordRetry = null
        passwordField.text = ""
        if (root.expanded)
            card.forceActiveFocus()
    }

    function passwordFailure(exitCode, message) {
        const error = message.toLowerCase()
        if (/not authorized|permission|not permitted|insufficient privileges|not running|not (?:be )?found|not available|unavailable|no network with|no wi-fi device|no wifi device|no suitable device|no such device|ip configuration|dhcp|firmware|rfkill|unmanaged|networking is disabled|radio.*disabled/.test(error))
            return false
        if (/secrets were required|no secrets|authentication failed|wrong password|incorrect password|invalid.*password|invalid.*psk|password.*invalid|psk.*invalid|802-11-wireless-security\.(psk|wep-key)|802-1x\.password/.test(error))
            return true
        return exitCode === 3 || exitCode === 4
    }

    function operationError(exitCode, message, fallback) {
        if (exitCode === 127)
            return "Не удалось запустить nmcli"
        if (exitCode === 8 || /networkmanager is not running/i.test(message))
            return "NetworkManager не запущен"
        if (/not authorized|permission|not permitted|insufficient privileges/i.test(message))
            return "Недостаточно прав для изменения сетевого подключения"
        if (exitCode === 3 || exitCode === 124)
            return "Превышено время ожидания операции"
        return fallback
    }

    function setStatusError(message) {
        const previous = root.statusErrorText
        root.statusErrorText = message
        if (previous !== "" && root.errorText === previous)
            root.errorText = message
        else if (message !== "" && !root.busy && !root.passwordPromptVisible && root.errorText === "")
            root.errorText = message
    }

    function finishConnection(exitCode, exitStatus, message) {
        const failed = exitCode !== 0 || exitStatus !== 0
        const ssid = root.connectingSsid
        const profile = root.attemptProfile
        const askAgain = failed && exitStatus === 0 && root.attemptNeedsPassword
                         && root.wifiEnabled && root.passwordFailure(exitCode, message)
        root.errorText = failed ? root.operationError(exitCode, message, "Не удалось подключиться к сети") : ""
        root.connectingSsid = ""
        root.attemptProfile = null
        root.attemptNeedsPassword = false
        root.attemptIface = ""
        root.stateEpoch++
        root.profilesDirty = true
        if (askAgain && ssid) {
            root.errorText = "Не удалось подключиться. Проверьте пароль сети"
            if (root.expanded && !root.closing)
                root.promptPassword(ssid, profile)
            else
                root.passwordRetry = { ssid: ssid, profile: profile }
        }
        root.queueRefresh()
    }

    function disconnectActive() {
        if (root.activeIface === "" || root.busy)
            return
        root.cancelPassword()
        root.errorText = ""
        root.stateEpoch++
        disconnectProc.start(["device", "disconnect", root.activeIface], 10)
    }

    function forgetActive() {
        if (root.activeUuid === "" || root.busy)
            return false
        return root.forgetConnections([root.activeUuid])
    }

    function forgetNetwork(ssid) {
        if (!ssid || ssid === root.activeSsid || root.busy || root.passwordPromptVisible)
            return false
        const activeUuids = root.deviceSnapshot.filter(function(device) {
            return parseInt(device["GENERAL.STATE"], 10) === 100
        }).map(function(device) { return device["GENERAL.CON-UUID"] })
        const uuids = []
        for (const profile of root.knownConnections) {
            if (profile.ssid === ssid && profile.uuid && profile.uuid !== root.activeUuid
                && activeUuids.indexOf(profile.uuid) === -1
                && (!profile.iface || !root.wifiIface || profile.iface === root.wifiIface)
                && uuids.indexOf(profile.uuid) === -1)
                uuids.push(profile.uuid)
        }
        if (uuids.length === 0)
            return false
        return root.forgetConnections(uuids)
    }

    function forgetConnections(uuids) {
        if (root.busy || !uuids || uuids.length === 0)
            return false
        root.cancelPassword()
        root.errorText = ""
        root.stateEpoch++
        const args = ["connection", "delete"]
        for (const uuid of uuids)
            args.push("uuid", uuid)
        forgetProc.targetUuids = uuids.slice()
        return forgetProc.start(args, 10)
    }

    function finishAction(exitCode, exitStatus, message, fallback) {
        root.errorText = exitCode !== 0 || exitStatus !== 0 ? root.operationError(exitCode, message, fallback) : ""
        root.stateEpoch++
        root.profilesDirty = true
        root.queueRefresh()
    }

    function splitEscaped(line) {
        const result = []
        let current = ""
        for (let i = 0; i < line.length; i++) {
            if (line.charCodeAt(i) === 92 && i + 1 < line.length) {
                current += line[i + 1]
                i++
            } else if (line[i] === ":") {
                result.push(current)
                current = ""
            } else {
                current += line[i]
            }
        }
        result.push(current)
        return result
    }

    function parseRecords(text, firstKey) {
        const records = []
        let record = null
        for (const line of text.split("\n")) {
            const separator = line.indexOf(":")
            if (separator === -1)
                continue
            const key = line.slice(0, separator)
            if (key === firstKey) {
                record = Object.create(null)
                records.push(record)
            }
            if (record)
                record[key] = line.slice(separator + 1)
        }
        return records
    }

    function parseKnownConnections(text) {
        const profiles = []
        for (const record of root.parseRecords(text, "connection.id")) {
            const uuid = record["connection.uuid"] || ""
            const ssid = record["802-11-wireless.ssid"] || ""
            if (!uuid || !ssid)
                continue
            const iface = record["connection.interface-name"] || ""
            const keyMgmt = record["802-11-wireless-security.key-mgmt"] || ""
            profiles.push({ uuid: uuid, ssid: ssid, name: record["connection.id"],
                iface: iface === "--" ? "" : iface, keyMgmt: keyMgmt === "--" ? "" : keyMgmt,
                wepKeyIndex: Math.max(0, Math.min(3, parseInt(record["802-11-wireless-security.wep-tx-keyidx"], 10) || 0)) })
        }
        return profiles
    }

    function parseNetworks(text) {
        const indexBySsid = Object.create(null)
        const list = []
        for (const line of text.split("\n")) {
            const parts = root.splitEscaped(line)
            if (parts.length < 4 || !parts[1])
                continue
            const ssid = parts[1]
            const security = parts[3]
            const secure = security !== "" && security !== "--"
            const item = { ssid: ssid, signal: Math.max(0, Math.min(100, parseInt(parts[2], 10) || 0)),
                security: security, secure: secure, needsPassword: secure && !/^OWE(?:\s|$)/i.test(security),
                active: parts[0] === "yes", iface: parts[4] || "", known: root.profileForSsid(ssid) !== null }
            if (indexBySsid[ssid] !== undefined) {
                const index = indexBySsid[ssid]
                const previous = list[index]
                if ((item.active && !previous.active) || (item.active === previous.active && item.signal > previous.signal))
                    list[index] = item
            } else {
                indexBySsid[ssid] = list.length
                list.push(item)
            }
        }
        list.sort(function(a, b) {
            if (a.active !== b.active)
                return a.active ? -1 : 1
            return b.signal - a.signal || (a.ssid < b.ssid ? -1 : a.ssid > b.ssid ? 1 : 0)
        })
        return list
    }

    function setNetworks(list) {
        if (JSON.stringify(root.networks) !== JSON.stringify(list))
            root.networks = list
    }

    function syncNetworkModel() {
        if (!networkModel)
            return
        const list = root.availableNetworks
        const roles = ["ssid", "signal", "security", "secure", "needsPassword", "active", "iface", "known"]
        for (let i = 0; i < list.length; i++) {
            const network = list[i]
            let existing = -1
            for (let j = i; j < networkModel.count; j++) {
                if (networkModel.get(j).ssid === network.ssid) {
                    existing = j
                    break
                }
            }
            if (existing === -1) {
                networkModel.insert(i, network)
            } else {
                if (existing !== i)
                    networkModel.move(existing, i, 1)
                for (const role of roles) {
                    if (networkModel.get(i)[role] !== network[role])
                        networkModel.setProperty(i, role, network[role])
                }
            }
        }
        if (networkModel.count > list.length)
            networkModel.remove(list.length, networkModel.count - list.length)
    }

    function updateNetworkProfiles() {
        const list = root.networks.map(function(network) {
            return { ssid: network.ssid, signal: network.signal, security: network.security,
                secure: network.secure, needsPassword: network.needsPassword,
                active: root.wifiEnabled && root.activeIface !== "" && network.ssid === root.activeSsid,
                iface: network.iface, known: root.profileForSsid(network.ssid) !== null }
        })
        root.setNetworks(list)
    }

    function applyDeviceSnapshot() {
        if (root.wifiEnabled && root.deviceSnapshotEpoch !== root.stateEpoch)
            return
        let chosen = null
        for (const device of root.deviceSnapshot) {
            if (device["GENERAL.TYPE"] !== "wifi")
                continue
            const connected = parseInt(device["GENERAL.STATE"], 10) === 100
            if (!chosen || (connected && parseInt(chosen["GENERAL.STATE"], 10) !== 100)
                || (connected === (parseInt(chosen["GENERAL.STATE"], 10) === 100) && device["GENERAL.DEVICE"] === root.wifiIface))
                chosen = device
        }
        const iface = chosen ? chosen["GENERAL.DEVICE"] : ""
        if (root.wifiIface !== iface) {
            root.wifiIface = iface
            root.setNetworks([])
            root.cachedScanPending = true
        }
        if (!root.wifiEnabled || !chosen || parseInt(chosen["GENERAL.STATE"], 10) !== 100) {
            root.activeIface = ""
            root.activeUuid = ""
            root.activeSsid = ""
            root.ipAddress = "—"
            root.updateNetworkProfiles()
            return
        }
        root.activeIface = iface
        const uuid = chosen["GENERAL.CON-UUID"] || ""
        root.activeUuid = uuid === "--" ? "" : uuid
        let ssid = ""
        for (const profile of root.knownConnections) {
            if (profile.uuid === root.activeUuid) {
                ssid = profile.ssid
                break
            }
        }
        if (!ssid) {
            for (const network of root.networks) {
                if (network.active && network.iface === iface) {
                    ssid = network.ssid
                    break
                }
            }
        }
        root.activeSsid = ssid || chosen["GENERAL.CONNECTION"] || ""
        const ipv4 = chosen["IP4.ADDRESS[1]"] || ""
        const ipv6 = chosen["IP6.ADDRESS[1]"] || ""
        const address = ipv4 !== "--" && ipv4 !== "" ? ipv4 : ipv6
        root.ipAddress = address && address !== "--" ? address.split("/")[0] : "—"
        root.updateNetworkProfiles()
    }

    function wifiIcon(signal) {
        if (signal >= 75) return "󰤨"
        if (signal >= 50) return "󰤥"
        if (signal >= 25) return "󰤢"
        return "󰤟"
    }

    //------------------------------- PROCESSES ----------------------
    component NmcliProcess: Process {
        id: job
        property bool pending: false
        property bool timedOut: false
        property bool eraseCommand: false
        property bool startedSuccessfully: false
        property int epoch: 0
        property int requestId: 0
        property int waitSeconds: 5
        property string output: ""
        property string errors: ""
        signal completed(int exitCode, int exitStatus)
        environment: root.nmcliEnvironment
        stdout: StdioCollector { onStreamFinished: job.output = text }
        stderr: StdioCollector { onStreamFinished: job.errors = text }
        property Timer watchdog: Timer {
            interval: (job.waitSeconds + 5) * 1000
            onTriggered: {
                job.timedOut = true
                job.signal(9)
                job.finish(124, 1, job.requestId)
            }
        }
        function start(args, seconds, secret) {
            if (pending || running)
                return false
            output = ""
            errors = ""
            timedOut = false
            startedSuccessfully = false
            eraseCommand = secret === true
            waitSeconds = Math.max(1, Math.min(300, Math.floor(Number(seconds)) || 5))
            epoch = root.stateEpoch
            requestId++
            command = ["nmcli", "--colors", "no", "--wait", String(waitSeconds)].concat(args)
            pending = true
            watchdog.restart()
            running = true
            return true
        }
        function finish(exitCode, exitStatus, ticket) {
            if (!pending || requestId !== ticket)
                return
            watchdog.stop()
            command = []
            pending = false
            completed(exitCode, exitStatus)
        }
        function cancel() {
            if (!pending && !running)
                return
            watchdog.stop()
            pending = false
            requestId++
            command = []
            if (running)
                signal(9)
        }
        onStarted: {
            startedSuccessfully = true
            if (eraseCommand) {
                command = []
                eraseCommand = false
            }
        }
        onExited: function(exitCode, exitStatus) {
            const ticket = requestId
            Qt.callLater(function() { job.finish(exitCode, exitStatus, ticket) })
        }
        onRunningChanged: {
            if (!running && pending && !startedSuccessfully) {
                const ticket = requestId
                Qt.callLater(function() {
                    if (!job.running && !job.startedSuccessfully)
                        job.finish(127, 1, ticket)
                })
            }
        }
    }

    NmcliProcess {
        id: radioStateProc
        onCompleted: function(exitCode, exitStatus) {
            if (epoch !== root.stateEpoch) { root.queueRefresh(); return }
            if (exitCode !== 0 || exitStatus !== 0)
                return
            const state = output.trim()
            if (state !== "enabled" && state !== "disabled")
                return
            const wasEnabled = root.wifiEnabled
            root.wifiEnabled = state === "enabled"
            if (wasEnabled !== root.wifiEnabled)
                root.stateEpoch++
            if (!root.wifiEnabled) {
                root.cancelPassword()
                root.setNetworks([])
                root.applyDeviceSnapshot()
            } else if (!wasEnabled) {
                root.lastScan = 0
                root.cachedScanPending = true
                root.queueRefresh()
            }
        }
    }

    NmcliProcess {
        id: radioToggleProc
        property bool turnOn: false
        onCompleted: function(exitCode, exitStatus) {
            if (exitCode === 0 && exitStatus === 0) {
                root.wifiEnabled = turnOn
                root.lastScan = 0
                root.setNetworks([])
                root.applyDeviceSnapshot()
            }
            root.finishAction(exitCode, exitStatus, errors, "Не удалось переключить Wi-Fi")
        }
    }

    NmcliProcess {
        id: activeConnProc
        onCompleted: function(exitCode, exitStatus) {
            if (epoch !== root.stateEpoch) { root.queueRefresh(); return }
            if (exitCode !== 0 || exitStatus !== 0) {
                if (exitCode === 8 || exitCode === 127) {
                    root.profilesDirty = true
                    root.deviceSnapshot = []
                    root.deviceSnapshotEpoch = root.stateEpoch
                    root.setNetworks([])
                    root.applyDeviceSnapshot()
                }
                root.setStatusError(root.operationError(exitCode, errors, "Не удалось получить состояние Wi-Fi"))
                return
            }
            root.setStatusError("")
            root.deviceSnapshot = root.parseRecords(output, "GENERAL.DEVICE")
            root.deviceSnapshotEpoch = root.stateEpoch
            root.applyDeviceSnapshot()
            if (root.cachedScanPending)
                root.scanNetworks(false)
        }
    }

    NmcliProcess {
        id: knownConnProc
        onCompleted: function(exitCode, exitStatus) {
            if (epoch !== root.stateEpoch) { root.profilesDirty = true; root.queueRefresh(); return }
            if (exitCode !== 0 || exitStatus !== 0) {
                root.profilesDirty = true
                return
            }
            const args = ["-t", "-e", "no", "-m", "multiline", "-f",
                "connection.id,connection.uuid,connection.interface-name,802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.wep-tx-keyidx",
                "connection", "show"]
            let count = 0
            for (const line of output.split("\n")) {
                const parts = root.splitEscaped(line)
                if (parts.length >= 2 && (parts[1] === "802-11-wireless" || parts[1] === "wifi")) {
                    args.push("uuid", parts[0])
                    count++
                }
            }
            if (count === 0) {
                root.knownConnections = []
                root.lastProfilesRefresh = Date.now()
                root.updateNetworkProfiles()
            } else if (!profileDetailsProc.start(args, root.commandTimeout)) {
                root.profilesDirty = true
            }
        }
    }

    NmcliProcess {
        id: profileDetailsProc
        onCompleted: function(exitCode, exitStatus) {
            if (epoch !== root.stateEpoch) { root.profilesDirty = true; root.queueRefresh(); return }
            if (exitCode !== 0 || exitStatus !== 0) {
                root.profilesDirty = true
                return
            }
            root.knownConnections = root.parseKnownConnections(output)
            root.lastProfilesRefresh = Date.now()
            root.updateNetworkProfiles()
            root.applyDeviceSnapshot()
        }
    }

    NmcliProcess {
        id: scanProc
        property string requestIface: ""
        property bool manual: false
        onCompleted: function(exitCode, exitStatus) {
            if (epoch !== root.stateEpoch || !root.wifiEnabled || requestIface !== root.wifiIface) {
                root.cachedScanPending = true
                root.queueRefresh()
                return
            }
            if (exitCode === 0 && exitStatus === 0) {
                root.setNetworks(root.parseNetworks(output))
                root.applyDeviceSnapshot()
            } else if (manual && !root.busy && !root.passwordPromptVisible) {
                root.errorText = root.operationError(exitCode, errors, "Не удалось обновить список сетей")
            }
        }
    }

    NmcliProcess {
        id: passwordUpdateProc
        onCompleted: function(exitCode, exitStatus) {
            if (exitCode !== 0 || exitStatus !== 0) {
                root.finishConnection(exitCode, exitStatus, errors + "\n" + output)
                return
            }
            const args = ["connection", "up", "uuid", root.attemptProfile.uuid]
            if (root.attemptIface !== "")
                args.push("ifname", root.attemptIface)
            connectProc.start(args, root.connectTimeout)
        }
    }

    NmcliProcess {
        id: connectProc
        onCompleted: function(exitCode, exitStatus) {
            root.finishConnection(exitCode, exitStatus, errors + "\n" + output)
        }
    }

    NmcliProcess {
        id: disconnectProc
        onCompleted: function(exitCode, exitStatus) {
            root.finishAction(exitCode, exitStatus, errors, "Не удалось отключиться от сети")
        }
    }

    NmcliProcess {
        id: forgetProc
        property var targetUuids: []
        onCompleted: function(exitCode, exitStatus) {
            if (exitCode === 0 && exitStatus === 0) {
                const forgotten = targetUuids
                root.knownConnections = root.knownConnections.filter(function(profile) {
                    return forgotten.indexOf(profile.uuid) === -1
                })
                root.updateNetworkProfiles()
            }
            targetUuids = []
            root.finishAction(exitCode, exitStatus, errors, "Не удалось удалить сохранённое подключение")
        }
    }

    Process {
        id: monitorProc
        command: ["nmcli", "--colors", "no", "monitor"]
        environment: root.nmcliEnvironment
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                if (data.toLowerCase().indexOf("connection") !== -1)
                    root.profilesDirty = true
                root.queueRefresh()
            }
        }
        stderr: StdioCollector {}
    }

    //------------------------------- LIFECYCLE / TIMERS ----------------------
    Component.onCompleted: {
        root.syncNetworkModel()
        monitorProc.running = root.expanded
        root.refreshAll()
    }

    onExpandedChanged: {
        monitorProc.running = root.expanded
        if (!root.expanded)
            toggleMouseArea.cancelPress()
    }

    Timer {
        id: eventRefreshTimer
        interval: 250
        onTriggered: root.refreshAll()
    }

    Timer {
        interval: Math.max(500, root.busy ? root.connectingPollInterval
                                        : root.expanded ? root.pollInterval : root.backgroundPollInterval)
        running: true
        repeat: true
        onTriggered: root.refreshAll()
    }

    Timer {
        interval: 1000
        running: root.expanded && root.wifiEnabled && !root.busy && !root.passwordPromptVisible
        repeat: true
        onTriggered: {
            const elapsed = Date.now() - root.lastScan
            if (elapsed < 0 || elapsed >= Math.max(10000, root.scanInterval))
                root.scanNetworks(true, true)
        }
    }

    Timer {
        interval: 5000
        running: root.expanded && !monitorProc.running
        repeat: true
        onTriggered: monitorProc.running = true
    }


    //------------------------------- FOCUS ----------------------
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.hide()
    }

    onVisibleChanged: {
        if (visible && !root.expanded)
            root.expanded = true
    }

    //------------------------------- LAYOUT ----------------------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 8
        color: root.bgPanel
        border.width: 3
        border.color: root.borderColor

        transformOrigin: Item.Top

        opacity: 0
        scale: 0.85

        focus: true
        Keys.onEscapePressed: root.hide()

        //------------------------------- ANIMATIONS ----------------------
        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    topSection.opacity = 0
                    topSectionTranslate.y = -12
                    networkList.opacity = 0
                    networkListTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

                SequentialAnimation {
                    PauseAnimation { duration: 35 }
                    ParallelAnimation {
                        NumberAnimation { target: topSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: topSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation { target: networkList; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: networkListTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 110; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: root.closing = false
            }
        }

        Connections {
            target: root
            function onExpandedChanged() {
                closeAnim.stop()
                openAnim.stop()
                if (root.expanded)
                    openAnim.start()
                else
                    closeAnim.start()
            }
        }

        //------------------------------- MAIN CONTENT ----------------------
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            visible: root.wifiEnabled

            //------------------------------- HEADER / TOP SECTION ----------------------
            ColumnLayout {
                id: topSection
                Layout.fillWidth: true
                spacing: 14
                opacity: 0

                transform: Translate {
                    id: topSectionTranslate
                    y: -12
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: root.wifiEnabled ? "󰖩" : "󰖪"
                        font.pixelSize: 20
                        color: root.accentPrimary
                    }

                    Text {
                        text: root.wifiEnabled ? (root.activeSsid !== "" ? root.activeSsid : "Wi-Fi") : "Wi-Fi выключен"
                        color: root.textMain
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.maximumWidth: 170
                    }

                    Item { Layout.fillWidth: true }

                    Item {
                        width: 44
                        height: 24
                    }
                }

                //------------------------------- CONNECTION INFO ----------------------
                Rectangle {
                    id: connectionInfo
                    Layout.fillWidth: true
                    visible: root.wifiEnabled
                    clip: true
                    implicitHeight: connectionColumn.implicitHeight + 20
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: root.accentPrimary
                    property real changeOpacity: 1
                    property real changeScale: 1
                    property real disconnectionOpacity: 1
                    opacity: changeOpacity * disconnectionOpacity
                    scale: changeScale
                    transformOrigin: Item.Center

                    ParallelAnimation {
                        id: connectionStateAnim
                        NumberAnimation {
                            target: connectionInfo
                            property: "changeOpacity"
                            from: 0.6
                            to: 1
                            duration: 240
                            easing.type: Easing.OutCubic
                        }
                        SequentialAnimation {
                            NumberAnimation {
                                target: connectionInfo
                                property: "changeScale"
                                from: 0.94
                                to: 1.025
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: connectionInfo
                                property: "changeScale"
                                to: 1
                                duration: 190
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.6
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onActiveUuidChanged() {
                            if (root.expanded && root.wifiEnabled)
                                connectionStateAnim.restart()
                        }
                    }

                    SequentialAnimation {
                        id: disconnectPulse
                        running: root.disconnecting
                        loops: Animation.Infinite
                        NumberAnimation {
                            target: connectionInfo
                            property: "disconnectionOpacity"
                            to: 0.5
                            duration: 480
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            target: connectionInfo
                            property: "disconnectionOpacity"
                            to: 1
                            duration: 480
                            easing.type: Easing.InOutSine
                        }
                        onRunningChanged: {
                            if (!running)
                                disconnectSettle.restart()
                        }
                    }

                    NumberAnimation {
                        id: disconnectSettle
                        target: connectionInfo
                        property: "disconnectionOpacity"
                        to: 1
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                    ColumnLayout {
                        id: connectionColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        readonly property real actionButtonWidth: Math.max(forgetLabel.implicitWidth, disconnectLabel.implicitWidth) + 20

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "󰩟"
                                font.pixelSize: 13
                                color: root.accentPrimary
                            }

                            Text {
                                text: "IP: " + root.ipAddress
                                color: root.textMain
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: root.activeSsid !== ""

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                implicitWidth: connectionColumn.actionButtonWidth
                                height: 28
                                radius: 10
                                color: forgetArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                       : forgetArea.containsMouse ? root.accentSecondary : root.accentPrimary
                                scale: forgetArea.pressed ? 0.95 : 1.0

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                Text {
                                    id: forgetLabel
                                    anchors.centerIn: parent
                                    text: "Забыть"
                                    color: root.bgPanel
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: forgetArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.forgetActive()
                                }
                            }

                            Rectangle {
                                implicitWidth: connectionColumn.actionButtonWidth
                                height: 28
                                radius: 10
                                color: disconnectArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                       : disconnectArea.containsMouse ? root.accentSecondary : root.accentPrimary
                                scale: disconnectArea.pressed ? 0.95 : 1.0

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                Text {
                                    id: disconnectLabel
                                    anchors.centerIn: parent
                                    text: "Отключить"
                                    color: root.bgPanel
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: disconnectArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.disconnectActive()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.separatorColor
                    visible: root.wifiEnabled
                }

                //------------------------------- NETWORK LIST HEADER ----------------------
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.wifiEnabled

                    Text {
                        text: "Доступные сети"
                        color: root.textDim
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: refreshButton
                        width: 30
                        height: 30
                        radius: 15
                        color: refreshArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                               : refreshArea.containsMouse ? root.accentSecondary : root.accentPrimary
                        scale: refreshArea.pressed ? 0.88 : 1.0

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                        Text {
                            id: refreshIcon
                            anchors.centerIn: parent
                            text: "󰑐"
                            font.pixelSize: 14
                            color: root.bgPanel

                            RotationAnimation on rotation {
                                running: root.scanning
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scanNetworks()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.errorText !== ""
                    text: root.errorText
                    color: root.accentText
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            //------------------------------- NETWORK LIST ----------------------
            Flickable {
                id: networkList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: root.wifiEnabled
                contentHeight: networkColumn.height
                boundsBehavior: Flickable.StopAtBounds
                opacity: 0

                transform: Translate {
                    id: networkListTranslate
                    y: -12
                }

                ColumnLayout {
                    id: networkColumn
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: networkModel

                        delegate: Rectangle {
                            id: networkRow
                            required property var model
                            readonly property var modelData: model
                            readonly property bool isActive: modelData.active === true
                            property bool wasActive: false
                            Layout.fillWidth: true
                            height: 48
                            radius: 12
                            color: modelData.active ? root.workspaceActive
                                   : netArea.containsMouse ? root.bgTrack : "transparent"
                            scale: netArea.pressed ? 0.98 : 1.0
                            transformOrigin: Item.Center

                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            onIsActiveChanged: {
                                if (isActive && !wasActive)
                                    connectSuccessBounce.restart()
                                wasActive = isActive
                            }

                            SequentialAnimation {
                                id: connectSuccessBounce
                                NumberAnimation { target: networkRow; property: "scale"; to: 1.035; duration: 130; easing.type: Easing.OutCubic }
                                NumberAnimation { target: networkRow; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                            }

                            RowLayout {
                                z: 1
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    id: networkSignalIcon
                                    text: root.wifiIcon(modelData.signal)
                                    font.pixelSize: 16
                                    color: modelData.active ? root.bgPanel : root.accentPrimary
                                    transformOrigin: Item.Center
                                    readonly property bool connectingThis: root.expanded && root.connectingSsid === modelData.ssid

                                    SequentialAnimation on opacity {
                                        running: networkSignalIcon.connectingThis
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.35; duration: 420; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.35; to: 1; duration: 420; easing.type: Easing.InOutSine }
                                        onRunningChanged: {
                                            if (!running)
                                                networkSignalIcon.opacity = 1
                                        }
                                    }

                                    SequentialAnimation on scale {
                                        running: networkSignalIcon.connectingThis
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 1.22; duration: 420; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1.22; to: 1; duration: 420; easing.type: Easing.InOutSine }
                                        onRunningChanged: {
                                            if (!running)
                                                networkSignalIcon.scale = 1
                                        }
                                    }
                                }

                                Text {
                                    text: modelData.ssid
                                    color: modelData.active ? root.bgPanel : root.textMain
                                    font.pixelSize: 13
                                    font.bold: modelData.active
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    id: forgetNetworkButton
                                    visible: modelData.known && !modelData.active
                                    enabled: !root.busy && !root.passwordPromptVisible
                                    implicitWidth: forgetNetworkLabel.implicitWidth + 14
                                    height: 24
                                    radius: 8
                                    color: forgetNetworkArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                           : forgetNetworkArea.containsMouse ? root.accentSecondary : root.accentPrimary
                                    opacity: enabled ? 1 : 0.55
                                    scale: forgetNetworkArea.pressed ? 0.95 : 1

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                    Text {
                                        id: forgetNetworkLabel
                                        anchors.centerIn: parent
                                        text: "Забыть"
                                        color: root.bgPanel
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: forgetNetworkArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        property string pressedSsid: ""

                                        onPressed: pressedSsid = modelData.ssid
                                        onCanceled: pressedSsid = ""
                                        onClicked: {
                                            const ssid = pressedSsid
                                            pressedSsid = ""
                                            if (ssid && ssid === modelData.ssid)
                                                root.forgetNetwork(ssid)
                                        }
                                    }
                                }

                                Text {
                                    visible: root.connectingSsid === modelData.ssid
                                    text: "…"
                                    font.pixelSize: 14
                                    color: root.accentPrimary
                                }

                                Text {
                                    visible: modelData.secure
                                    text: "󰌾"
                                    font.pixelSize: 12
                                    color: modelData.active ? root.bgPanel : root.textDim
                                }
                            }

                            MouseArea {
                                id: netArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                property string pressedSsid: ""

                                onPressed: pressedSsid = modelData.ssid
                                onCanceled: pressedSsid = ""
                                onClicked: function(mouse) {
                                    const ssid = pressedSsid
                                    pressedSsid = ""
                                    if (!ssid || ssid !== modelData.ssid)
                                        return
                                    if (mouse.button === Qt.RightButton) {
                                        root.forgetNetwork(ssid)
                                        return
                                    }
                                    if (mouse.button !== Qt.LeftButton || modelData.active)
                                        return
                                    root.connectTo(ssid, modelData.secure, modelData.known === true)
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        visible: root.availableNetworks.length === 0 && !root.scanning
                        text: "Сети не найдены"
                        color: root.textDim
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        //------------------------------- WIFI TOGGLE BUTTON ----------------------
        Rectangle {
            id: wifiToggleButton
            z: 20
            clip: true
            color: toggleMouseArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                   : toggleMouseArea.containsMouse ? root.accentSecondary
                   : root.accentPrimary

            scale: toggleMouseArea.pressed ? 0.9 : 1.0

            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            state: root.wifiEnabled ? "small" : "big"

            states: [
                State {
                    name: "big"
                    AnchorChanges {
                        target: wifiToggleButton
                        anchors.top: undefined
                        anchors.right: undefined
                        anchors.horizontalCenter: card.horizontalCenter
                        anchors.verticalCenter: card.verticalCenter
                    }
                    PropertyChanges {
                        target: wifiToggleButton
                        width: 120
                        height: 120
                        radius: 28
                    }
                },
                State {
                    name: "small"
                    AnchorChanges {
                        target: wifiToggleButton
                        anchors.horizontalCenter: undefined
                        anchors.verticalCenter: undefined
                        anchors.top: card.top
                        anchors.right: card.right
                    }
                    PropertyChanges {
                        target: wifiToggleButton
                        width: 36
                        height: 36
                        radius: 10
                        anchors.topMargin: 24
                        anchors.rightMargin: 24
                    }
                }
            ]

            transitions: Transition {
                AnchorAnimation { duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { properties: "width,height,radius"; duration: 260; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: holdFill
                visible: root.wifiEnabled
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Qt.rgba(0, 0, 0, 0.28)
                height: 0
            }

            NumberAnimation {
                id: holdFillAnim
                target: holdFill
                property: "height"
                from: 0
                to: wifiToggleButton.height
                duration: toggleMouseArea.pressAndHoldInterval
                easing.type: Easing.Linear
            }

            NumberAnimation {
                id: holdResetAnim
                target: holdFill
                property: "height"
                to: 0
                duration: 140
                easing.type: Easing.OutCubic
            }

            Text {
                anchors.centerIn: parent
                text: "󰖪"
                color: root.bgPanel
                font.pixelSize: 42
                opacity: wifiToggleButton.state === "big" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            Text {
                anchors.centerIn: parent
                text: "󰖩"
                color: root.bgPanel
                font.pixelSize: 17
                opacity: wifiToggleButton.state === "small" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: toggleMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                pressAndHoldInterval: 650
                property bool enabledOnPress: false
                property bool holdArmed: false
                property bool pressHandled: true

                function resetFill() {
                    holdFillAnim.stop()
                    holdResetAnim.restart()
                }

                function cancelPress() {
                    holdArmed = false
                    pressHandled = true
                    resetFill()
                }

                onPressed: {
                    enabledOnPress = root.wifiEnabled
                    pressHandled = !root.expanded || root.closing || radioToggleProc.pending || radioToggleProc.running
                    holdArmed = enabledOnPress && !pressHandled
                    holdFillAnim.stop()
                    holdResetAnim.stop()
                    holdFill.height = 0
                    if (!enabledOnPress && !pressHandled) {
                        pressHandled = true
                        root.setRadioEnabled(true)
                    } else if (holdArmed) {
                        holdFillAnim.restart()
                    }
                }

                onReleased: {
                    holdArmed = false
                    resetFill()
                }

                onCanceled: cancelPress()
                onExited: {
                    if (pressed)
                        cancelPress()
                }

                onClicked: pressHandled = true

                onPressAndHold: {
                    if (!holdArmed || pressHandled || !pressed || !containsMouse || !root.expanded || root.closing)
                        return
                    holdArmed = false
                    pressHandled = true
                    resetFill()
                    root.setRadioEnabled(false)
                }
            }
        }

        //------------------------------- PASSWORD PROMPT ----------------------
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.55)
            visible: root.passwordPromptVisible

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                width: parent.width - 40
                anchors.centerIn: parent
                radius: 18
                color: root.bgPanel
                border.width: 2
                border.color: root.accentPrimary
                height: promptColumn.height + 32

                ColumnLayout {
                    id: promptColumn
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 12

                    Text {
                        text: root.pendingSsid
                        color: root.textMain
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 12
                        color: root.bgInput
                        border.width: 1
                        border.color: passwordField.activeFocus ? root.accentPrimary : root.separatorColor

                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.inputTextColor
                            font.pixelSize: 13
                            echoMode: TextInput.Password
                            clip: true
                            Keys.onReturnPressed: root.connectWithPassword()
                            Keys.onEnterPressed: root.connectWithPassword()
                            Keys.onEscapePressed: root.cancelPassword()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: cancelArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                   : cancelArea.containsMouse ? root.accentSecondary : root.accentPrimary
                            scale: cancelArea.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "Отмена"
                                color: root.bgPanel
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: cancelArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelPassword()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: connectArea.pressed ? Qt.darker(root.accentPrimary, 1.15)
                                   : connectArea.containsMouse ? root.accentSecondary : root.accentPrimary
                            opacity: passwordField.text.length > 0 ? 1.0 : 0.5
                            scale: connectArea.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "Подключить"
                                color: root.bgPanel
                                font.pixelSize: 12
                                font.bold: true
                            }

                            MouseArea {
                                id: connectArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: passwordField.text.length > 0
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectWithPassword()
                            }
                        }
                    }
                }
            }
        }
    }
}
