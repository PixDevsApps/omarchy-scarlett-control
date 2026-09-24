import QtQuick
import qs.Commons

// Horizontal peak meter with a short peak-hold tick. `db` is dBFS; colours
// come from the theme (accent → urgent) so the meter follows theme switches.
Item {
  id: root

  property real db: -120
  property bool active: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent

  property real peakDb: -120
  readonly property real fraction: frac(db)
  readonly property real peakFraction: frac(peakDb)

  function frac(d) {
    var floor = -60
    if (d <= floor) return 0
    if (d >= 0) return 1
    return Math.pow((d - floor) / -floor, 1.6)
  }

  function colorFor(d) {
    if (d > -1) return urgent
    if (d > -6) return Qt.tint(accent, Util.alpha(urgent, 0.55))
    return accent
  }

  onDbChanged: {
    if (db >= peakDb) {
      peakDb = db
      holdTimer.restart()
    }
  }

  Timer {
    id: holdTimer
    interval: 1200
    onTriggered: decay.start()
  }

  Timer {
    id: decay
    interval: 40
    repeat: true
    onTriggered: {
      root.peakDb = Math.max(root.db, root.peakDb - 1.5)
      if (root.peakDb <= root.db) stop()
    }
  }

  implicitHeight: Math.max(4, Style.space(5))
  implicitWidth: Style.space(160)
  opacity: active ? 1 : 0.35

  Rectangle {
    anchors.fill: parent
    radius: Math.min(height / 2, Style.cornerRadius)
    color: Util.alpha(root.foreground, 0.1)
  }

  Rectangle {
    height: parent.height
    width: parent.width * root.fraction
    radius: Math.min(height / 2, Style.cornerRadius)
    color: root.colorFor(root.db)
  }

  Rectangle {
    visible: root.peakFraction > 0.01
    width: Math.max(2, Style.space(2))
    height: parent.height
    x: Math.min(parent.width - width, parent.width * root.peakFraction)
    color: root.colorFor(root.peakDb)
  }
}
