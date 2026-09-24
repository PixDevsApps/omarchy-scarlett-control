import QtQuick
import qs.Ui
import qs.Commons

// Firmware update banner. Only visible when there is something to say: an
// update is available, the user is confirming, an update is running, or one
// just finished. Walks through: available → confirm → running → rebooting →
// done / failed.
BorderSurface {
  id: root

  required property var panel

  readonly property var fw: panel.firmware
  readonly property string stage: panel.fwStage
  readonly property color fg: panel.fg
  readonly property bool busy: stage === "running" || stage === "rebooting"
  readonly property bool failed: stage === "failed"
  readonly property color tone: failed ? Color.urgent : Color.accent

  onBusyChanged: if (!busy) statusDot.opacity = 1
  visible: stage !== "" || (fw.updateAvailable === true && !panel.fwDismissed)
  radius: Style.cornerRadius
  color: Util.alpha(tone, 0.10)
  borderSpec: Border.controlSpec("selected", tone, Color.accent)
  implicitHeight: body.implicitHeight + Style.space(24)

  function versionText() {
    var from = panel.fwFrom || fw.current
    var to = panel.fwTo || fw.latest
    return from && to ? from + " → " + to : ""
  }

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    // Title row
    Item {
      width: parent.width
      implicitHeight: Math.max(titleText.implicitHeight, closeBtn.implicitHeight)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Rectangle {
          id: statusDot
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(6, Style.space(7))
          height: width
          radius: width / 2
          color: root.tone
          SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.25; duration: 600 }
            NumberAnimation { from: 0.25; to: 1; duration: 600 }
          }
        }

        Text {
          id: titleText
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.panel.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          text: {
            switch (root.stage) {
            case "confirm": return "Update firmware?"
            case "running": return "Updating firmware…"
            case "rebooting": return "Restarting interface…"
            case "done": return "Firmware updated"
            case "failed": return "Firmware update failed"
            default: return "Firmware update available"
            }
          }
        }
      }

      Text {
        anchors.right: closeBtn.visible ? closeBtn.left : parent.right
        anchors.rightMargin: closeBtn.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.versionText()
        color: Qt.darker(root.fg, 1.3)
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        id: closeBtn
        visible: !root.busy && root.stage !== "confirm"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "✕"
        color: Qt.darker(root.fg, 1.4)
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.body
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          cursorShape: Qt.PointingHandCursor
          onClicked: root.panel.dismissFirmware()
        }
      }
    }

    // Explanation
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      color: root.failed ? Color.urgent : Qt.darker(root.fg, 1.25)
      font.family: root.panel.fontFamily
      font.pixelSize: Style.font.caption
      text: {
        switch (root.stage) {
        case "confirm":
          return "Takes about a minute. The interface is reset to factory settings while it updates; "
            + "your current settings are saved first and put back automatically. "
            + "Audio stops until it restarts — don't unplug it."
        case "running":
          return (root.panel.fwProgress.label || "Working") + " · don't unplug the interface"
        case "rebooting":
          return "Waiting for the interface to come back, then restoring your settings."
        case "done":
          return root.panel.fwMessage
        case "failed":
          return root.panel.fwMessage || "The updater reported an error."
        default:
          return "Focusrite firmware " + (root.fw.latest || "") + " is available for your interface."
        }
      }
    }

    // Progress
    Item {
      visible: root.busy
      width: parent.width
      implicitHeight: Math.max(5, Style.space(6))

      Rectangle {
        anchors.fill: parent
        radius: Math.min(height / 2, Style.cornerRadius)
        color: Util.alpha(root.fg, 0.12)
      }
      Rectangle {
        height: parent.height
        radius: Math.min(height / 2, Style.cornerRadius)
        color: Color.accent
        width: root.stage === "rebooting" ? parent.width : parent.width * (root.panel.fwProgress.percent || 0) / 100
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      }
    }

    // Actions
    Row {
      visible: root.stage === "" || root.stage === "confirm" || root.stage === "failed"
      anchors.right: parent.right
      spacing: Style.space(6)

      Button {
        visible: root.stage === "confirm"
        text: "Cancel"
        bordered: true
        foreground: root.fg
        fontFamily: root.panel.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: root.panel.fwStage = ""
      }
      Button {
        text: root.stage === "confirm" ? "Update now" : (root.failed ? "Try again" : "Update…")
        bordered: true
        selected: true
        foreground: root.fg
        fontFamily: root.panel.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: {
          if (root.stage === "confirm") root.panel.startFirmwareUpdate()
          else root.panel.fwStage = "confirm"
        }
      }
    }
  }
}
