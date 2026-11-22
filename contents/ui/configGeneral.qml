import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_initMode: "auto"
    property int cfg_iconScale: 80

    readonly property var modes: [
        { value: "auto", label: "Automatic (detect)" },
        { value: "systemd", label: "systemd" },
        { value: "openrc", label: "OpenRC / elogind" },
        { value: "runit", label: "runit / elogind" },
        { value: "dinit", label: "dinit / elogind" },
        { value: "s6", label: "s6 / elogind" }
    ]

    function syncCombo() {
        const selected = cfg_initMode || "auto"
        for (let i = 0; i < modes.length; ++i) {
            if (modes[i].value === selected) {
                combo.currentIndex = i
                return
            }
        }
        combo.currentIndex = 0
    }

    Component.onCompleted: syncCombo()
    onCfg_initModeChanged: syncCombo()

    QQC2.ComboBox {
        id: combo
        Kirigami.FormData.label: "Init system:"
        textRole: "label"
        model: page.modes
        onActivated: page.cfg_initMode = page.modes[currentIndex].value
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: "systemd masks its sleep targets. OpenRC, runit, dinit and s6 use a Polkit rule with elogind to deny sleep requests."
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Icon size (%):"
        from: 50
        to: 100
        stepSize: 5
        value: page.cfg_iconScale
        onValueModified: page.cfg_iconScale = value
    }
}
