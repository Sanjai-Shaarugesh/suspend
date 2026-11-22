import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string backend: "/usr/local/bin/suspend-backend"

    readonly property url boltIcon: Qt.resolvedUrl("thunderbolt-symbolic.svg")
    readonly property url boltOnIcon: Qt.resolvedUrl("suspend-widget-on.svg")

    readonly property var allowedModes:
        ["auto", "systemd", "openrc", "runit", "dinit", "s6", "unknown"]

    readonly property string initMode:
        allowedModes.indexOf(Plasmoid.configuration.initMode) >= 0
            ? Plasmoid.configuration.initMode
            : "auto"

    readonly property int iconScale: Plasmoid.configuration.iconScale || 80

    // An action includes the time the user needs to type a password.
    readonly property int queryTimeoutMs: 15000
    readonly property int actionTimeoutMs: 120000
    // The terminal flow stays open while the user answers prompts.
    readonly property int terminalTimeoutMs: 1800000

    // How long a transient message stays visible.
    readonly property int cancelNoticeMs: 4000
    readonly property int errorNoticeMs: 8000

    property bool isOn: false
    property bool busy: false

    property string initInfo: ""

    // Transient message shown after an ON/OFF or setup attempt.
    property string notice: ""
    property int noticeType: Kirigami.MessageType.Information

    // Persistent message for status/detect problems.
    property string queryError: ""

    // ---------------------------------------------------------------
    // Setup state
    // ---------------------------------------------------------------

    // checking | ok | missing | error
    property string setupState: "checking"
    property string setupError: ""
    property bool setupBusy: false

    property bool missingPkexec: false
    property bool missingFiles: false
    property bool missingAgent: false
    property bool promptFriendly: false
    property string setupPm: ""
    property string setupPkgs: ""

    readonly property bool setupNeeded:
        setupState === "missing" || setupState === "error"

    // The graphical flow needs pkexec AND an authentication agent.
    readonly property bool canInstallGui:
        !missingPkexec && !missingAgent

    readonly property var setupItems: {
        const items = []
        if (missingPkexec)
            items.push("Polkit (pkexec), needed to ask for your password")
        if (missingAgent)
            items.push("A Polkit authentication agent, which shows the "
                       + "password dialog")
        if (missingFiles)
            items.push("Suspend backend, helper and Polkit rules in "
                       + "/usr/local and /usr/share")
        return items
    }

    // Package directory (the folder that contains contents/).
    readonly property string pkgDir: decodeURIComponent(
        Qt.resolvedUrl("../../").toString()
            .replace(/^file:\/\//, "")
            .replace(/\/+$/, ""))

    readonly property string setupScript:
        pkgDir + "/contents/scripts/suspend-setup"

    readonly property string errorMessage:
        setupNeeded ? "Setup required. Click to install."
                    : (notice || queryError)

    // source name -> { kind, started, timeout }
    property var requests: ({})
    property int requestCounter: 0
    property int requestCount: 0

    Plasmoid.status: setupNeeded
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.PassiveStatus
    Plasmoid.icon: isOn ? "suspend-widget-on" : "thunderbolt-symbolic"

    toolTipMainText: "Suspend"
    toolTipSubText: errorMessage !== ""
        ? errorMessage
        : isOn ? "ON: sleep is disabled" : "OFF: sleep is enabled"

    function log(msg) {
        console.log("[suspend-widget] " + msg)
    }

    function showNotice(text, type, durationMs) {
        notice = text
        noticeType = type
        noticeTimer.interval = durationMs
        noticeTimer.restart()
    }

    function clearNotice() {
        noticeTimer.stop()
        notice = ""
    }

    // Single-quote a string for the shell.
    function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function setupCmd(sub) {
        return "bash " + shq(setupScript) + " " + sub + " " + shq(pkgDir)
    }

    // ---------------------------------------------------------------
    // Request bookkeeping
    // ---------------------------------------------------------------

    function hasPending(kind) {
        for (const src in requests) {
            if (requests[src].kind === kind)
                return true
        }
        return false
    }

    function startRequest(kind, command, timeoutMs) {
        // The executable engine identifies a request by its command line,
        // so a unique trailing shell comment keeps every request distinct.
        const id = ++requestCounter
        const source = command + " # req" + id

        requests[source] = {
            kind: kind,
            started: Date.now(),
            timeout: timeoutMs
        }
        requestCount++

        log("start #" + id + " (" + kind + "): " + command)
        runner.connectSource(source)
    }

    function takeRequest(source) {
        const req = requests[source]
        if (req === undefined)
            return undefined

        delete requests[source]
        requestCount--
        return req
    }

    function expireRequest(source) {
        const req = takeRequest(source)
        if (!req)
            return

        runner.disconnectSource(source)
        log("TIMEOUT (" + req.kind + "): " + source)

        if (req.kind === "action") {
            busy = false
            showNotice("The operation timed out.",
                       Kirigami.MessageType.Error, errorNoticeMs)
            refresh()
        } else if (req.kind === "setup-install"
                   || req.kind === "setup-terminal") {
            setupBusy = false
            showNotice("Setup timed out.",
                       Kirigami.MessageType.Error, errorNoticeMs)
            checkSetup()
        } else if (req.kind === "setup-check") {
            setupState = "error"
            setupError = "Setup check did not respond."
        } else {
            queryError = "Backend did not respond (" + req.kind + ")."
        }
    }

    // ---------------------------------------------------------------
    // Setup logic
    // ---------------------------------------------------------------

    function checkSetup() {
        if (!hasPending("setup-check"))
            startRequest("setup-check", setupCmd("check"), queryTimeoutMs)
    }

    function applyCheck(output) {
        let pk = false, fl = false, ag = false, friendly = false
        let pm = "", pkgs = ""

        for (const raw of output.split("\n")) {
            const line = raw.trim()

            if (line === "missing:pkexec")
                pk = true
            else if (line === "missing:files")
                fl = true
            else if (line === "missing:agent")
                ag = true
            else if (line === "prompt:friendly")
                friendly = true
            else if (line.indexOf("pm:") === 0)
                pm = line.slice(3)
            else if (line.indexOf("pkgs:") === 0)
                pkgs = line.slice(5)
        }

        missingPkexec = pk
        missingFiles = fl
        missingAgent = ag
        promptFriendly = friendly
        setupPm = pm
        setupPkgs = pkgs
        setupError = ""

        if (pk || fl || ag) {
            setupState = "missing"
            promptOnce()
        } else {
            setupState = "ok"

            // Prompt again if the files ever go missing or change.
            if (Plasmoid.configuration.setupPrompted)
                Plasmoid.configuration.setupPrompted = false

            refresh()
        }
    }

    // Open the popup the first time setup is found to be incomplete.
    // Plasma ignores "expanded" while the applet is still starting, so the
    // request is retried on a timer. The "prompted" flag is stored only
    // once the popup really opened (see onExpandedChanged), or after the
    // attempts run out, so it never gets lost.
    property bool pendingPrompt: false

    function promptOnce() {
        if (Plasmoid.configuration.setupPrompted || pendingPrompt)
            return

        pendingPrompt = true
        openTimer.tries = 0
        openTimer.restart()
    }

    onExpandedChanged: {
        if (expanded && pendingPrompt) {
            pendingPrompt = false
            openTimer.stop()
            Plasmoid.configuration.setupPrompted = true
        }
    }

    Timer {
        id: openTimer

        property int tries: 0

        interval: 1500
        repeat: true

        onTriggered: {
            if (!root.pendingPrompt) {
                stop()
                return
            }

            if (++tries > 8) {
                // Could not open it; do not keep trying forever.
                stop()
                root.pendingPrompt = false
                Plasmoid.configuration.setupPrompted = true
                return
            }

            root.log("opening setup popup (attempt " + tries + ")")
            root.expanded = true
        }
    }

    function runSetupInstall() {
        if (setupBusy)
            return

        setupBusy = true
        clearNotice()
        startRequest("setup-install", setupCmd("install"), actionTimeoutMs)
    }

    function runSetupTerminal() {
        if (setupBusy)
            return

        setupBusy = true
        clearNotice()
        startRequest("setup-terminal", setupCmd("install-terminal"),
                     terminalTimeoutMs)
    }

    // ---------------------------------------------------------------
    // Command runner
    // ---------------------------------------------------------------

    P5Support.DataSource {
        id: runner

        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            disconnectSource(source)

            const req = root.takeRequest(source)
            if (!req) {
                root.log("ignoring result for unknown/expired source: " + source)
                return
            }

            const output = String(data["stdout"] || "").trim()
            const error = String(data["stderr"] || "").trim()
            const exitCode = data["exit code"] === undefined
                ? 0
                : Number(data["exit code"])

            root.log(req.kind + " finished: exit=" + exitCode
                + " stdout='" + output + "' stderr='" + error + "'")

            if (req.kind === "setup-check") {
                if (exitCode === 0) {
                    root.applyCheck(output)
                } else {
                    root.setupState = "error"
                    root.setupError = error || output
                        || "Setup check failed (exit code " + exitCode + ")"
                    root.promptOnce()
                }
                return
            }

            if (req.kind === "setup-install"
                || req.kind === "setup-terminal") {
                root.setupBusy = false

                // No password dialog possible (pkexec missing, or it found
                // no authentication agent): continue in a terminal instead
                // of showing an error. A wrong password (also exit 127) is
                // NOT retried this way.
                const noDialog = req.kind === "setup-install"
                    && (exitCode === 5
                        || (exitCode === 127
                            && /no authentication agent|controlling terminal/i
                                   .test(error)))

                if (noDialog) {
                    root.runSetupTerminal()
                    root.showNotice(
                        "No password dialog is available. Continuing in a "
                            + "terminal...",
                        Kirigami.MessageType.Information,
                        root.errorNoticeMs)
                } else if (exitCode === 0) {
                    root.showNotice("Setup finished. Checking...",
                                    Kirigami.MessageType.Positive,
                                    root.cancelNoticeMs)
                } else if (exitCode === 126) {
                    root.showNotice("Installation cancelled",
                                    Kirigami.MessageType.Warning,
                                    root.cancelNoticeMs)
                } else if (exitCode === 127) {
                    root.showNotice(
                        "Authentication failed or no authentication agent "
                            + "is running."
                            + (error ? " pkexec said: "
                                       + error.split("\n")[0] : "")
                            + " Try \"Install in terminal\".",
                        Kirigami.MessageType.Error, root.errorNoticeMs)
                } else if (exitCode === 5) {
                    root.showNotice(
                        "pkexec is not installed. Use \"Install in terminal\".",
                        Kirigami.MessageType.Error, root.errorNoticeMs)
                } else if (req.kind === "setup-install" || exitCode === 4) {
                    root.showNotice(
                        error || output
                            || "Setup failed (exit code " + exitCode + ")",
                        Kirigami.MessageType.Error, root.errorNoticeMs)
                }

                // The check decides the truth, whatever the exit code was.
                root.checkSetup()
                return
            }

            if (req.kind === "detect") {
                if (exitCode === 0 && output !== "") {
                    root.initInfo = output
                } else {
                    root.initInfo = "unknown"
                    if (exitCode === 127)
                        root.checkSetup()
                    else
                        root.queryError = error || output
                            || "Could not detect init system"
                }
                return
            }

            if (req.kind === "status") {
                if (exitCode === 0 && (output === "on" || output === "off")) {
                    root.isOn = output === "on"
                    root.queryError = ""
                } else if (exitCode === 127) {
                    // Backend vanished: let the setup check explain why.
                    root.queryError = "Backend not installed."
                    root.checkSetup()
                } else {
                    root.queryError = error || output
                        || "Could not read suspend status"
                }
                return
            }

            // req.kind === "action"
            root.busy = false

            if (exitCode === 0) {
                root.clearNotice()
            } else if (exitCode === 126) {
                // pkexec: the authentication dialog was dismissed.
                root.showNotice("Attempt cancelled",
                                Kirigami.MessageType.Warning,
                                root.cancelNoticeMs)
            } else if (exitCode === 127) {
                // pkexec: not authorized (wrong password / no agent).
                root.showNotice(
                    "Authentication failed or no authentication agent "
                        + "is running.",
                    Kirigami.MessageType.Error, root.errorNoticeMs)
            } else {
                root.showNotice(
                    error || output
                        || "Operation failed (exit code " + exitCode + ")",
                    Kirigami.MessageType.Error, root.errorNoticeMs)
            }

            // Always re-read the real state; never trust the click.
            root.refresh()
        }
    }

    // Fails every request that exceeds its timeout so nothing stays stuck.
    Timer {
        interval: 1000
        repeat: true
        running: root.requestCount > 0

        onTriggered: {
            const now = Date.now()
            for (const src in root.requests) {
                const req = root.requests[src]
                if (now - req.started > req.timeout)
                    root.expireRequest(src)
            }
        }
    }

    Timer {
        id: noticeTimer
        repeat: false
        onTriggered: root.notice = ""
    }

    // ---------------------------------------------------------------
    // Actions
    // ---------------------------------------------------------------

    function refresh() {
        // Never talk to the backend until the setup check says it exists.
        if (busy || setupState !== "ok")
            return

        if (!hasPending("status"))
            startRequest("status",
                         backend + " status " + initMode, queryTimeoutMs)

        if (!hasPending("detect"))
            startRequest("detect",
                         backend + " detect " + initMode, queryTimeoutMs)
    }

    function setSleepDisabled(disable) {
        if (busy || setupState !== "ok")
            return

        busy = true
        clearNotice()

        startRequest("action",
                     backend + " " + (disable ? "on " : "off ") + initMode,
                     actionTimeoutMs)
    }

    function toggleSleep() {
        if (!busy)
            setSleepDisabled(!isOn)
    }

    onInitModeChanged: refresh()

    Plasmoid.onActivated: toggleSleep()

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.isOn
                ? "Enable sleep (turn OFF)"
                : "Disable sleep (turn ON)"

            icon.name: "system-suspend"
            enabled: !root.busy && root.setupState === "ok"

            onTriggered: root.toggleSleep()
        }
    ]

    // Periodic resync. The first tick (triggeredOnStart) runs the setup
    // check. While setup is incomplete it keeps re-checking, so installing
    // from a terminal or with install.sh is picked up without a restart.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            if (root.setupState !== "ok") {
                if (!root.setupBusy)
                    root.checkSetup()
            } else {
                root.refresh()
            }
        }
    }

    // ---------------------------------------------------------------
    // UI
    // ---------------------------------------------------------------

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent

            width: Math.round(
                Math.min(parent.width, parent.height) * root.iconScale / 100)
            height: width

            source: root.isOn ? root.boltOnIcon : root.boltIcon
            isMask: !root.isOn
            color: Kirigami.Theme.textColor

            Kirigami.Icon {
                visible: root.setupNeeded
                source: "dialog-warning"
                width: Math.round(parent.width * 0.5)
                height: width
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
        }
    }

    fullRepresentation: Item {
        id: panel

        // Wide while the setup panel is showing; back to the default
        // width as soon as setup is complete. The width is fixed here and
        // the content below always wraps inside it, so long messages can
        // never push the popup wider than the window.
        readonly property real wantedWidth: Kirigami.Units.gridUnit
            * (root.setupNeeded ? 30 : 16)

        // Real bottom edge of the visible content, so the popup is exactly
        // as tall as what it shows and shrinks again when parts disappear.
        readonly property real wantedHeight: Math.ceil(
            content.childrenRect.y + content.childrenRect.height
            + Kirigami.Units.largeSpacing)

        implicitWidth: wantedWidth
        implicitHeight: wantedHeight

        Layout.minimumWidth: wantedWidth
        Layout.preferredWidth: wantedWidth
        Layout.maximumWidth: wantedWidth
        Layout.minimumHeight: wantedHeight
        Layout.preferredHeight: wantedHeight
        Layout.maximumHeight: wantedHeight

        ColumnLayout {
            id: content

            width: panel.width

            spacing: Kirigami.Units.largeSpacing

            // ---- Header (always visible) ----
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: root.isOn ? root.boltOnIcon : root.boltIcon
                    isMask: !root.isOn
                    color: Kirigami.Theme.textColor

                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true

                    QQC2.Label {
                        text: "Suspend"
                        font.bold: true
                    }

                    QQC2.Label {
                        text: root.setupState === "checking"
                            ? "Checking setup..."
                            : root.setupNeeded
                                ? "Setup required"
                                : root.isOn
                                    ? "ON: sleep disabled"
                                    : "OFF: sleep enabled"
                        opacity: 0.7
                    }

                    QQC2.Label {
                        visible: root.initInfo !== "" && root.setupState === "ok"
                        text: "Init system: " + root.initInfo
                        opacity: 0.6
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }

                QQC2.Switch {
                    id: sleepSwitch

                    visible: root.setupState === "ok"
                    checked: root.isOn
                    enabled: !root.busy

                    onToggled: {
                        const wanted = checked

                        // Restore the binding so the switch always shows the real
                        // backend state (snaps back if authentication is cancelled).
                        checked = Qt.binding(() => root.isOn)

                        root.setSleepDisabled(wanted)
                    }
                }
            }

            // ---- Setup panel ----
            ColumnLayout {
                visible: root.setupNeeded
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.InlineMessage {
                    visible: true
                    Layout.fillWidth: true
                    type: root.setupState === "error"
                        ? Kirigami.MessageType.Error
                        : Kirigami.MessageType.Warning
                    text: root.setupState === "error"
                        ? root.setupError
                        : "Suspend widget needs access to install the "
                            + "necessary packages. Nothing is changed until "
                            + "you press Install and enter your password."
                }

                QQC2.Label {
                    visible: root.setupItems.length > 0
                    text: "Missing:"
                    font.bold: true
                }

                Repeater {
                    model: root.setupItems

                    QQC2.Label {
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        wrapMode: Text.WordWrap
                        text: "\u2022 " + modelData
                    }
                }

                QQC2.Label {
                    visible: root.setupPkgs !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: "Packages (" + root.setupPm + "): " + root.setupPkgs
                }

                QQC2.Label {
                    visible: root.canInstallGui && !root.promptFriendly
                             && root.setupState === "missing"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: "The first time, your system shows its standard "
                        + "password dialog, which may mention a program path. "
                        + "That is this setup. Later updates show a clearer "
                        + "message."
                }

                QQC2.Label {
                    visible: !root.canInstallGui && root.setupState === "missing"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: "A graphical password prompt is not available. "
                        + "\"Install in terminal\" opens a terminal and uses "
                        + "sudo, doas or su."
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        text: "Install"
                        icon.name: "system-software-install"
                        highlighted: root.canInstallGui
                        enabled: root.canInstallGui && !root.setupBusy
                                 && root.setupState === "missing"
                        onClicked: root.runSetupInstall()
                    }

                    QQC2.Button {
                        text: "Install in terminal"
                        icon.name: "utilities-terminal"
                        highlighted: !root.canInstallGui
                        enabled: !root.setupBusy
                        onClicked: root.runSetupTerminal()
                    }

                    Item { Layout.fillWidth: true }

                    QQC2.BusyIndicator {
                        running: root.setupBusy
                        visible: root.setupBusy
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    }

                    QQC2.Button {
                        text: "Check again"
                        icon.name: "view-refresh"
                        flat: true
                        enabled: !root.setupBusy
                        onClicked: root.checkSetup()
                    }
                }
            }

            // ---- Messages ----
            Kirigami.InlineMessage {
                visible: root.notice !== ""
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing

                type: root.noticeType
                text: root.notice
            }

            Kirigami.InlineMessage {
                visible: root.queryError !== "" && !root.setupNeeded
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing

                type: Kirigami.MessageType.Error
                text: root.queryError
            }
        }
    }
}
