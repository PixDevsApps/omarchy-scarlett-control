import QtQuick
import qs.Ui
import qs.Commons

// Compact toggle chip for the front-panel style buttons (Inst, Air, Auto,
// Safe, 48V, Link). Same state tokens as the shell's Button so it reads as
// part of the theme, plus a small secondary line for multi-state controls
// (Air: Presence / Drive) and a warn tint for things like live 48V.
BorderSurface {
  id: root

  property string text: ""
  property string sub: ""
  property string tooltip: ""
  property bool checked: false
  property bool warn: false
  property bool available: true
  property bool led: true             // front-panel style status light
  property color ledColor: warn ? urgent : accent
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property bool hot: mouse.containsMouse && available
  readonly property color tone: warn && checked ? urgent : foreground

  implicitHeight: Math.max(Style.spacing.controlHeight, labelRow.implicitHeight + subLabel.implicitHeight * (sub !== "" ? 1 : 0) + Style.space(8))
  implicitWidth: Math.max(labelRow.implicitWidth, subLabel.implicitWidth) + Style.space(16)
  radius: Style.cornerRadius
  opacity: available ? 1 : 0.4

  color: mouse.pressed && available ? Style.pressedFillFor(tone, accent)
    : hot ? Style.hoverFillFor(tone, accent)
    : checked ? Style.selectedFillFor(tone, accent)
    : Style.normalFillFor(foreground, accent)
  borderSpec: hot ? Border.controlSpec("hover-cursor", tone, accent)
    : checked ? Border.controlSpec("selected", tone, accent)
    : Border.controlSpec("normal", foreground, accent)

  Behavior on color { ColorAnimation { duration: 120 } }

  Column {
    anchors.centerIn: parent
    spacing: 0

    Row {
      id: labelRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(6)

      Rectangle {
        visible: root.led
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(5, Style.space(6))
        height: width
        radius: width / 2
        color: root.checked ? root.ledColor : Util.alpha(root.foreground, 0.22)
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        id: label
        textFormat: Text.PlainText
        text: root.text
        color: root.checked ? Style.selectedStateColor(root.tone, root.accent) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        font.letterSpacing: 0.6
      }
    }

    Text {
      id: subLabel
      visible: root.sub !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: root.sub
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Style.font.caption - 1)
      font.bold: true
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ForbiddenCursor
    onClicked: if (root.available) root.clicked()
  }

  PanelToolTip {
    visible: mouse.containsMouse && root.tooltip !== ""
    text: root.tooltip
    fontFamily: root.fontFamily
  }
}
