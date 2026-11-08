import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import "info.js" as Info

KCM.SimpleKCM {
    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            source: Qt.resolvedUrl("suspend-widget-on.svg")
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
        }
        QQC2.Label {
            text: "suspend"
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
            Layout.alignment: Qt.AlignHCenter
        }
        QQC2.Label {
            text: "Version " + Plasmoid.metaData.version
            opacity: 0.7
            Layout.alignment: Qt.AlignHCenter
        }
        QQC2.Label {
            text: "Sleep ON/OFF switch for the Plasma panel"
            Layout.alignment: Qt.AlignHCenter
        }
        QQC2.Label {
            text: "Created by " + Info.author
            Layout.alignment: Qt.AlignHCenter
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            QQC2.Button {
                text: "Creator"
                icon.name: "user-identity"
                onClicked: Qt.openUrlExternally(Info.authorUrl)
            }
            QQC2.Button {
                text: "GitHub repo"
                icon.name: "vcs-normal"
                onClicked: Qt.openUrlExternally(Info.repoUrl)
            }
            QQC2.Button {
                text: "Report a bug"
                icon.name: "tools-report-bug"
                onClicked: Qt.openUrlExternally(Info.repoUrl + "/issues")
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label {
            text: "If this saved you some trouble, you can buy me a coffee."
            Layout.alignment: Qt.AlignHCenter
        }

        Image {
            source: Qt.resolvedUrl("coffee-button.svg")
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            Layout.preferredHeight: 49
            fillMode: Image.PreserveAspectFit
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(Info.donateUrl)
            }
        }

        Image {
            id: qr
            source: Qt.resolvedUrl("donate-qr.svg")
            visible: status === Image.Ready
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 150
            Layout.preferredHeight: 150
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(300, 300)
        }
        QQC2.Label {
            visible: qr.visible
            text: "Scan to donate"
            opacity: 0.7
            Layout.alignment: Qt.AlignHCenter
        }

        QQC2.Button {
            text: "Other ways to donate"
            icon.name: "emblem-favorite"
            Layout.alignment: Qt.AlignHCenter
            onClicked: Qt.openUrlExternally(Info.donateAltUrl)
        }
    }
}
