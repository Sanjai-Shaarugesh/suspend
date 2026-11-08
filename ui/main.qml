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
    readonly property string initMode: Plasmoid.configuration.initMode
    readonly property int iconScale: Plasmoid.configuration.iconScale

    property bool isOn: false
    property bool busy: false
    property string initInfo: ""
    signal synced()

    // passive keeps it in the tray's hidden popup
    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.icon: isOn ? "suspend-widget-on" : "thunderbolt-symbolic"
    toolTipMainText: "Suspend"
    toolTipSubText: isOn ? "ON: sleep is disabled" : "OFF: sleep is enabled"

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            var out = (data["stdout"] || "").trim()
            if (source.indexOf(" status") >= 0) {
                root.isOn = (out === "on")
                root.synced()
            } else if (source.indexOf(" detect") >= 0) {
                root.initInfo = out
            } else {
                root.busy = false
                root.refresh()
            }
        }
    }

    function refresh() {
        runner.connectSource(backend + " status " + initMode)
        runner.connectSource(backend + " detect " + initMode)
    }

    function setSleepDisabled(disable) {
        busy = true
        runner.connectSource(backend + (disable ? " on " : " off ") + initMode)
    }

    function toggleSleep() {
        if (!busy) setSleepDisabled(!isOn)
    }

    onInitModeChanged: refresh()

    Plasmoid.onActivated: toggleSleep()

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.isOn ? "Enable sleep (turn OFF)" : "Disable sleep (turn ON)"
            icon.name: "system-suspend"
            onTriggered: root.toggleSleep()
        }
    ]

    // polling catches changes made from a terminal
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.busy) root.refresh()
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(Math.min(parent.width, parent.height) * root.iconScale / 100)
            height: width
            source: root.isOn ? root.boltOnIcon : root.boltIcon
            isMask: !root.isOn    // the green one keeps its own colour
            color: Kirigami.Theme.textColor
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: root.isOn ? root.boltOnIcon : root.boltIcon
                isMask: !root.isOn
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                QQC2.Label { text: "Suspend"; font.bold: true }
                QQC2.Label {
                    text: root.isOn ? "ON: sleep disabled" : "OFF: sleep enabled"
                    opacity: 0.7
                }
                QQC2.Label {
                    visible: root.initInfo !== ""
                    text: "Init: " + root.initInfo
                    opacity: 0.5
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            QQC2.Switch {
                id: sw
                checked: root.isOn
                enabled: !root.busy
                onToggled: root.setSleepDisabled(checked)
                Connections {
                    target: root
                    function onSynced() { sw.checked = root.isOn }
                }
            }
        }
    }
}
