import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_initMode
    property string cfg_initModeDefault
    property int cfg_iconScale
    property int cfg_iconScaleDefault

    readonly property var modes: [
        { v: "auto",    t: "Automatic (detect)" },
        { v: "systemd", t: "systemd" },
        { v: "openrc",  t: "OpenRC" },
        { v: "runit",   t: "runit" },
        { v: "dinit",   t: "dinit" },
        { v: "s6",      t: "s6" }
    ]

    // cfg_initMode is filled in after the combo exists
    function syncCombo() {
        var v = cfg_initMode === "" ? "auto" : cfg_initMode
        for (var i = 0; i < modes.length; i++) {
            if (modes[i].v === v) { combo.currentIndex = i; return }
        }
        combo.currentIndex = 0
    }
    onCfg_initModeChanged: syncCombo()
    Component.onCompleted: syncCombo()

    QQC2.ComboBox {
        id: combo
        Kirigami.FormData.label: "Init system:"
        model: page.modes.map(function (m) { return m.t })
        onActivated: page.cfg_initMode = page.modes[currentIndex].v
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "systemd masks the sleep targets. OpenRC, runit, dinit and s6 use the elogind sleep.conf.d drop-in."
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
