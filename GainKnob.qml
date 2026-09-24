import QtQuick
import QtQuick.Shapes
import qs.Commons

// A gain knob drawn the way the Scarlett front panel reads: an outer arc for
// the gain position and an inner "halo" that lights with the live input level,
// warming towards the theme's urgent colour as the signal nears clipping.
//
// Drag up/down (or sideways), scroll, or use the arrow keys through the panel.
// The value is the raw ALSA integer; the caller supplies the dB mapping.
Item {
  id: root

  property int value: 0
  property int minimum: 0
  property int maximum: 70
  property real dbMin: 0
  property real dbMax: 69
  property real levelDb: -120        // live input level, dBFS
  property bool busy: false          // autogain is listening
  property bool linked: false
  property bool interactive: true

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal moved(int value)
  signal released()

  readonly property real range: Math.max(1, maximum - minimum)
  readonly property int shownValue: dragging ? dragValue : value
  readonly property real progress: Math.max(0, Math.min(1, (shownValue - minimum) / range))
  readonly property real db: dbMin + progress * (dbMax - dbMin)
  readonly property real levelFraction: {
    var floor = -60
    if (levelDb <= floor) return 0
    if (levelDb >= 0) return 1
    return Math.pow((levelDb - floor) / -floor, 1.6)
  }
  readonly property color haloColor: {
    if (levelDb > -1) return urgent
    if (levelDb > -6) return Qt.tint(accent, Util.alpha(urgent, 0.55))
    return accent
  }

  property bool dragging: false
  property int dragValue: value
  property real _startY: 0
  property real _startX: 0
  property int _startValue: 0
  property real _wheelAcc: 0

  readonly property real sweep: 270
  readonly property real startAngle: 135      // degrees, clockwise from 3 o'clock
  readonly property real stroke: Math.max(3, Math.round(width * 0.055))
  readonly property real haloStroke: Math.max(3, Math.round(width * 0.075))

  implicitWidth: Style.space(92)
  implicitHeight: implicitWidth

  Shape {
    id: shape
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real rOuter: width / 2 - root.stroke / 2
    readonly property real rHalo: rOuter - root.stroke - root.haloStroke / 2 - Style.space(3)

    // Gain track
    ShapePath {
      strokeColor: Util.alpha(root.foreground, 0.14)
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: shape.cx; centerY: shape.cy
        radiusX: shape.rOuter; radiusY: shape.rOuter
        startAngle: root.startAngle
        sweepAngle: root.sweep
      }
    }

    // Gain value
    ShapePath {
      strokeColor: root.interactive ? root.foreground : Util.alpha(root.foreground, 0.4)
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: shape.cx; centerY: shape.cy
        radiusX: shape.rOuter; radiusY: shape.rOuter
        startAngle: root.startAngle
        sweepAngle: Math.max(0.5, root.sweep * root.progress)
      }
    }

    // Halo track
    ShapePath {
      strokeColor: Util.alpha(root.foreground, 0.07)
      strokeWidth: root.haloStroke
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: shape.cx; centerY: shape.cy
        radiusX: shape.rHalo; radiusY: shape.rHalo
        startAngle: 0
        sweepAngle: 360
      }
    }

    // Halo level — grows symmetrically from the bottom, like the hardware ring
    ShapePath {
      strokeColor: root.haloColor
      strokeWidth: root.haloStroke
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: shape.cx; centerY: shape.cy
        radiusX: shape.rHalo; radiusY: shape.rHalo
        startAngle: 90 - 180 * root.levelFraction
        sweepAngle: 360 * root.levelFraction
      }
    }
  }

  // Busy pulse while autogain listens
  Rectangle {
    anchors.centerIn: parent
    width: shape.rHalo * 2 + root.haloStroke
    height: width
    radius: width / 2
    color: "transparent"
    border.width: root.haloStroke
    border.color: root.accent
    visible: root.busy
    opacity: 0
    SequentialAnimation on opacity {
      running: root.busy
      loops: Animation.Infinite
      NumberAnimation { from: 0.1; to: 0.85; duration: 650; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.85; to: 0.1; duration: 650; easing.type: Easing.InOutSine }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: root.busy ? "AUTO" : Math.round(root.db).toString()
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.busy ? Style.font.subtitle : Style.font.displayLarge
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: root.busy ? "listening" : "dB"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    preventStealing: true

    onPressed: function(mouse) {
      root._startY = mouse.y
      root._startX = mouse.x
      root._startValue = root.value
      root.dragValue = root.value
      root.dragging = true
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      // ~2.2 px per dB: the full 69 dB range fits in one comfortable drag.
      var delta = ((root._startY - mouse.y) + (mouse.x - root._startX) * 0.6) / 2.2
      var next = Math.max(root.minimum, Math.min(root.maximum, Math.round(root._startValue + delta)))
      if (next !== root.dragValue) {
        root.dragValue = next
        root.moved(next)
      }
    }
    onReleased: {
      root.dragging = false
      root.released()
    }
    onCanceled: root.dragging = false
    onWheel: function(wheel) {
      var w = Util.wheelSteps(root._wheelAcc, wheel.angleDelta.y || wheel.angleDelta.x)
      root._wheelAcc = w.remainder
      if (w.steps === 0) return
      var next = Math.max(root.minimum, Math.min(root.maximum, root.value + w.steps))
      if (next !== root.value) root.moved(next)
    }
  }
}
