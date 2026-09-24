import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model

// One preamp channel: gain knob with level halo, meter, and the front-panel
// buttons. Clicking the card makes it the hardware's selected input, so the
// physical gain knob and buttons follow what you are looking at.
BorderSurface {
  id: root

  required property var panel
  required property int channel          // 1 or 2

  readonly property var controls: panel.controls
  readonly property string prefix: "Line In " + channel + " "
  readonly property var gainCtl: Model.ctl(controls, prefix + "Gain")
  readonly property bool selectedInput: Model.value(controls, "Input Select", 0) === channel - 1
  readonly property bool inst: Model.item(controls, prefix + "Level") === "Inst"
  readonly property int airIndex: Model.value(controls, prefix + "Air", 0)
  readonly property bool autogain: Model.bool(controls, prefix + "Autogain")
  readonly property string autogainStatus: Model.item(controls, prefix + "Autogain Status")
  readonly property bool safe: Model.bool(controls, prefix + "Safe")
  readonly property bool linked: Model.bool(controls, prefix + "Link")
  readonly property bool quad: panel.quadRate
  readonly property real levelDb: panel.inputDb(channel)

  readonly property color fg: panel.fg

  radius: Style.cornerRadius
  color: selectedInput ? Style.selectedFillFor(fg, Color.accent) : Style.normalFillFor(fg, Color.accent)
  borderSpec: selectedInput ? Border.controlSpec("selected", fg, Color.accent) : Border.controlSpec("normal", fg, Color.accent)
  implicitHeight: content.implicitHeight + Style.space(24)

  Behavior on color { ColorAnimation { duration: 120 } }

  MouseArea {
    anchors.fill: parent
    cursorShape: root.selectedInput ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: if (!root.selectedInput) root.panel.setControl("Input Select", root.channel - 1)
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(12)
    spacing: Style.space(10)

    Item {
      width: parent.width
      implicitHeight: title.implicitHeight

      Text {
        id: title
        textFormat: Text.PlainText
        text: "INPUT " + root.channel
        color: root.fg
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: title.verticalCenter
        textFormat: Text.PlainText
        text: root.inst ? "INST" : "MIC · LINE"
        color: Qt.darker(root.fg, 1.4)
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }
    }

    GainKnob {
      id: knob
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width * 0.62, Style.space(96))
      height: width
      value: root.gainCtl ? root.gainCtl.values[0] : 0
      minimum: root.gainCtl ? root.gainCtl.min : 0
      maximum: root.gainCtl ? root.gainCtl.max : 70
      dbMin: root.gainCtl && root.gainCtl.dbMin !== undefined ? root.gainCtl.dbMin : 0
      dbMax: root.gainCtl && root.gainCtl.dbMax !== undefined ? root.gainCtl.dbMax : 69
      levelDb: root.levelDb
      busy: root.autogain
      interactive: !!root.gainCtl && !root.autogain
      foreground: root.fg
      fontFamily: root.panel.fontFamily
      onMoved: function(v) {
        root.panel.setControl(root.prefix + "Gain", v)
        if (!root.selectedInput) root.panel.setControl("Input Select", root.channel - 1)
      }
    }

    LevelMeter {
      width: parent.width
      db: root.levelDb
      active: root.panel.metering
      foreground: root.fg
    }

    Grid {
      id: chips
      width: parent.width
      columns: 2
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(6)
      readonly property real cellWidth: (width - columnSpacing) / 2

      Chip {
        width: chips.cellWidth
        text: "INST"
        checked: root.inst
        fontFamily: root.panel.fontFamily
        foreground: root.fg
        tooltip: root.inst
          ? "Instrument level (hi-Z) on the front jack — click for line level"
          : "Switch the front jack to instrument level for guitar or bass"
        onClicked: root.panel.setControl(root.prefix + "Level", root.inst ? 0 : 1)
      }

      Chip {
        width: chips.cellWidth
        text: "AIR"
        sub: root.airIndex === 1 ? "PRESENCE" : (root.airIndex === 2 ? "+ DRIVE" : "")
        checked: root.airIndex > 0
        // Presence lights like the other buttons; Drive warms towards urgent,
        // echoing the hardware's green → amber Air LED.
        ledColor: root.airIndex === 2 ? Qt.tint(Color.accent, Util.alpha(Color.urgent, 0.6)) : Color.accent
        fontFamily: root.panel.fontFamily
        foreground: root.fg
        tooltip: root.quad
          ? "Air Presence. Drive is unavailable at 176.4/192 kHz"
          : "Cycle Air: Off → Presence → Presence + Harmonic Drive"
        onClicked: {
          var next = (root.airIndex + 1) % 3
          if (next === 2 && root.quad) next = 0
          root.panel.setControl(root.prefix + "Air", next)
        }
      }

      Chip {
        width: chips.cellWidth
        text: "AUTO"
        checked: root.autogain
        fontFamily: root.panel.fontFamily
        foreground: root.fg
        available: Model.has(root.controls, root.prefix + "Autogain")
        tooltip: root.autogain
          ? "Listening for 10 seconds — click to cancel"
          : "Auto Gain: play or sing at performance level for 10 seconds"
        onClicked: root.panel.setControl(root.prefix + "Autogain", root.autogain ? 0 : 1)
      }

      Chip {
        width: chips.cellWidth
        text: "SAFE"
        checked: root.safe && !root.quad
        available: !root.quad && Model.has(root.controls, root.prefix + "Safe")
        fontFamily: root.panel.fontFamily
        foreground: root.fg
        tooltip: root.quad
          ? "Clip Safe is unavailable at 176.4/192 kHz"
          : "Clip Safe: pulls the gain down before the signal clips"
        onClicked: root.panel.setControl(root.prefix + "Safe", root.safe ? 0 : 1)
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Model.AUTOGAIN_TEXT[root.autogainStatus] || ""
      visible: text !== "" && !root.autogain
      color: /^Fail/.test(root.autogainStatus) ? Color.urgent : Qt.darker(root.fg, 1.3)
      font.family: root.panel.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
