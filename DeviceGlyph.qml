import QtQuick
import qs.Commons

// Line drawing of the 2i2 front panel: a body with two gain halos and the big
// monitor knob. Scales from a 16 px bar icon up to the panel hero, and the two
// halos can light with the live input levels (0..1) like the hardware does.
Item {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property real level1: 0
  property real level2: 0
  property bool dim: false
  property bool badge: false          // e.g. firmware update available
  property bool badgePulse: false

  readonly property real line: Math.max(1, Math.round(width / 14))

  implicitWidth: 16
  implicitHeight: 16
  opacity: dim ? 0.45 : 1

  Rectangle {
    id: body
    anchors.centerIn: parent
    width: parent.width
    height: Math.round(parent.width * 0.62)
    radius: Math.max(1, Math.round(height * 0.22))
    color: "transparent"
    border.width: root.line
    border.color: root.foreground

    readonly property real halo: Math.round(height * 0.44)

    Row {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Math.round(body.height * 0.2)
      spacing: Math.max(1, Math.round(body.height * 0.14))

      Repeater {
        model: 2
        Rectangle {
          required property int index
          readonly property real lvl: index === 0 ? root.level1 : root.level2
          width: body.halo
          height: width
          radius: width / 2
          color: lvl > 0.02 ? Util.alpha(root.accent, 0.25 + 0.75 * lvl) : "transparent"
          border.width: root.line
          border.color: lvl > 0.02 ? root.accent : root.foreground
          Behavior on color { ColorAnimation { duration: 80 } }
        }
      }
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Math.round(body.height * 0.2)
      width: Math.round(body.height * 0.56)
      height: width
      radius: width / 2
      color: root.foreground
    }
  }

  onBadgePulseChanged: if (!badgePulse) badgeDot.opacity = 1

  Rectangle {
    id: badgeDot
    visible: root.badge
    width: Math.max(4, Math.round(root.width * 0.34))
    height: width
    radius: width / 2
    x: root.width - width * 0.8
    y: (root.height - body.height) / 2 - height * 0.45
    color: root.accent
    border.width: Math.max(1, Math.round(width * 0.2))
    border.color: Color.bar.background
    SequentialAnimation on opacity {
      running: root.badgePulse
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.3; duration: 600 }
      NumberAnimation { from: 0.3; to: 1; duration: 600 }
    }
  }
}
