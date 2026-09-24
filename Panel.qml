import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Scarlett control center: bar icon + popup panel.
//
// All hardware access goes through ./scarlett-ctl, a small long-running helper
// that owns the ALSA control handle (so knob turns on the device show up here
// instantly) and applies PipeWire clock settings. The panel only renders the
// snapshots it streams and sends one-line commands back.
Panel {
  id: root
  moduleName: "io.github.pixdevsapps.scarlett-control"
  ipcTarget: "scarlett-control"

  // ---------------------------------------------------------------- state

  property bool connected: false
  property string deviceName: ""
  property string serial: ""
  property string usbid: ""
  property var controls: ({})
  property var meterValues: []
  property var clock: ({})
  property string lastError: ""
  property bool rateSwitching: false
  property bool deviceExpanded: false

  // Firmware: `firmware` is the daemon's latest report; fwStage drives the
  // banner ("" | confirm | running | rebooting | done | failed).
  property var firmware: ({})
  property string fwStage: ""
  property var fwProgress: ({})
  property string fwMessage: ""
  property int fwFrom: 0
  property int fwTo: 0
  property bool fwDismissed: false
  readonly property bool updateAvailable: firmware.updateAvailable === true

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool metering: opened && connected && meterValues.length > 0
  readonly property var meterIndex: Model.meterMap(controls)

  readonly property string clockMode: clock.mode || "fixed"
  readonly property int configuredRate: clock.rate || 0
  readonly property int activeRate: clock.activeRate || 0
  readonly property int displayRate: activeRate || configuredRate
  readonly property bool quadRate: Model.isQuadRate(displayRate)
  readonly property var supportedRates: clock.supported && clock.supported.length ? clock.supported : Model.RATES
  readonly property int effectiveQuantum: clock.forceQuantum || clock.quantum || 0

  readonly property int directMonitor: Model.value(controls, "Direct Monitor", 0)
  readonly property bool phantom: Model.bool(controls, "Line In 1-2 Phantom Power")
  readonly property bool linked: Model.bool(controls, "Line In 1 Link") || Model.bool(controls, "Line In 2 Link")
  readonly property bool locked: Model.item(controls, "Sync Status") !== "Unlocked"

  readonly property string title: {
    var n = deviceName.replace(/^Focusrite\s+/i, "")
    var m = n.match(/^(Scarlett\s+\S+)/i)
    return m ? m[1] : (n || "Scarlett")
  }
  readonly property string generation: {
    var m = deviceName.match(/(\d+(st|nd|rd|th)\s+Gen)/i)
    return m ? m[1] : ""
  }

  // ---------------------------------------------------------------- backend

  readonly property string ctlPath: decodeURIComponent(String(Qt.resolvedUrl("scarlett-ctl")).replace(/^file:\/\//, ""))

  function send(line) {
    if (backend.running) backend.write(line + "\n")
  }

  function setControl(name, value) {
    var c = Model.ctl(controls, name)
    if (!c || !c.rw) return
    send("set " + c.numid + " " + Math.round(Number(value)))
    // Optimistic local echo so chips flip instantly; the device's own change
    // event replaces this snapshot a few milliseconds later.
    var next = Object.assign({}, controls)
    var copy = Object.assign({}, c)
    copy.values = c.type === "bool" ? [!!value] : [Math.round(Number(value))]
    next[name] = copy
    controls = next
  }

  function setControls(names, value) {
    for (var i = 0; i < names.length; i++) setControl(names[i], value)
  }

  function setRate(rate) {
    rateSwitching = true
    rateTimeout.restart()
    send("rate " + rate)
  }

  function setBuffer(q) {
    send("buffer " + (q > 0 ? q : "auto"))
  }

  function startFirmwareUpdate() {
    fwFrom = firmware.current || 0
    fwTo = firmware.latest || 0
    fwProgress = { label: "Saving settings", percent: 0 }
    fwStage = "running"
    send("firmware-update")
  }

  function dismissFirmware() {
    if (fwStage === "" && updateAvailable) fwDismissed = true
    fwStage = ""
    fwMessage = ""
  }

  function handle(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.type === "meters") {
      meterValues = msg.v || []
    } else if (msg.type === "state") {
      controls = msg.controls || {}
    } else if (msg.type === "clock") {
      clock = msg
      rateSwitching = false
    } else if (msg.type === "device") {
      connected = !!msg.connected
      if (connected) {
        deviceName = msg.name || ""
        serial = msg.serial || ""
        usbid = msg.usbid || ""
        if (opened) send("meters on")
      } else {
        controls = {}
        meterValues = []
        if (fwStage === "running") fwStage = "rebooting"
      }
    } else if (msg.type === "firmware") {
      firmware = msg
    } else if (msg.type === "fwprogress") {
      fwStage = "running"
      fwProgress = msg
      if (msg.from) { fwFrom = msg.from; fwTo = msg.to }
    } else if (msg.type === "fwresult") {
      if (msg.stage === "flashed") {
        fwStage = "rebooting"
      } else if (msg.stage === "failed") {
        fwStage = "failed"
        fwMessage = msg.message || ""
      } else if (msg.stage === "restored") {
        fwStage = "done"
        fwMessage = "Now running firmware " + (firmware.current || fwTo) + "."
          + (msg.restored ? " " + msg.restored + " settings restored" + (msg.failed ? ", " + msg.failed + " could not be restored." : ".") : "")
      }
    } else if (msg.type === "error") {
      if (fwStage === "running" && /^firmware-update/.test(msg.message || "")) {
        fwStage = "failed"
        fwMessage = String(msg.message).replace(/^firmware-update:\s*/, "")
      }
      lastError = msg.message || ""
      errorTimer.restart()
      console.warn("scarlett-ctl:", lastError)
    }
  }

  function meterDbAt(idx) {
    if (idx === undefined || idx < 0 || idx >= meterValues.length) return -120
    return Model.meterDb(meterValues[idx])
  }

  function inputDb(channel) {
    return meterDbAt(meterIndex["Analogue " + channel])
  }

  function monitorRaw(channel) {
    var cells = Model.monitorCells(controls, directMonitor, channel)
    return cells.length ? Model.value(controls, cells[0], 0) : 0
  }

  onOpenedChanged: {
    send(opened ? "meters on" : "meters off")
    if (opened && fwStage === "") send("firmware")
  }

  // New images arrive with system updates (package scarlett2-firmware), so
  // look again now and then even if the panel is never opened.
  Timer {
    interval: 4 * 60 * 60 * 1000
    running: root.connected
    repeat: true
    onTriggered: if (root.fwStage === "") root.send("firmware")
  }

  Process {
    id: backend
    command: ["python3", root.ctlPath, "daemon"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) { root.handle(data) }
    }
    stderr: SplitParser {
      onRead: function(data) { console.warn("scarlett-ctl:", data) }
    }
    onExited: function(code) {
      root.connected = false
      restartTimer.start()
    }
  }

  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: backend.running = true
  }

  Timer {
    id: rateTimeout
    interval: 4000
    onTriggered: root.rateSwitching = false
  }

  // A finished update's banner clears itself; failures stay until dismissed.
  onFwStageChanged: if (fwStage === "done") fwDoneTimer.restart()
  Timer {
    id: fwDoneTimer
    interval: 20000
    onTriggered: if (root.fwStage === "done") root.fwStage = ""
  }

  Timer {
    id: errorTimer
    interval: 6000
    onTriggered: root.lastError = ""
  }

  // ---------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.connected
      ? root.title + " · " + Model.formatRateLong(root.displayRate) + (root.clockMode === "auto" ? " (auto)" : "")
        + (root.updateAvailable ? " · firmware " + root.firmware.latest + " available" : "")
      : "Scarlett not connected"
    iconComponent: Component {
      DeviceGlyph {
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        dim: !root.connected
        badge: root.updateAvailable || root.fwStage === "running" || root.fwStage === "rebooting"
        badgePulse: root.fwStage === "running" || root.fwStage === "rebooting"
      }
    }
    onPressed: function(b) { root.toggle() }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var n = parseInt(t)
        if (n >= 1 && n <= root.supportedRates.length) root.setRate(root.supportedRates[n - 1])
        else if (t === "a" || t === "A") root.setRate(root.clockMode === "auto" ? (root.displayRate || 48000) : "auto")
        else if (t === "m" || t === "M") root.setControl("Direct Monitor", (root.directMonitor + 1) % 3)
        else if (t === "p" || t === "P") root.setControl("Line In 1-2 Phantom Power", root.phantom ? 0 : 1)
        else if (t === "d" || t === "D") root.deviceExpanded = !root.deviceExpanded
        else if (t === "u" || t === "U") {
          if (root.fwStage === "confirm") root.startFirmwareUpdate()
          else if (root.updateAvailable && (root.fwStage === "" || root.fwStage === "failed")) root.fwStage = "confirm"
        }
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scroll.availableWidth
          spacing: Style.space(14)

          // ---------------- hero
          PanelHero {
            width: parent.width
            foreground: root.fg
            fontFamily: root.fontFamily
            title: root.connected ? root.title : "Scarlett"
            detail: root.connected && root.displayRate ? Model.formatRateLong(root.displayRate) : ""
            meta: {
              if (!root.connected) return "Not connected"
              var parts = []
              if (root.generation) parts.push(root.generation)
              parts.push(root.clockMode === "auto" ? "Rate follows apps" : "Fixed rate")
              if (!root.locked) parts.push("Clock unlocked")
              else if (root.activeRate) parts.push("Streaming")
              else parts.push("Idle")
              return parts.join(" · ")
            }
            iconComponent: Component {
              DeviceGlyph {
                width: Style.space(40)
                height: Style.space(40)
                foreground: root.fg
                dim: !root.connected
                level1: root.metering ? Model.meterFraction(root.inputDb(1)) : 0
                level2: root.metering ? Model.meterFraction(root.inputDb(2)) : 0
              }
            }
          }

          FirmwareCard {
            width: parent.width
            panel: root
          }

          // ---------------- not connected
          Text {
            visible: !root.connected
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Plug in your Focusrite Scarlett over USB. Controls appear here as soon as the interface is detected."
            color: Qt.darker(root.fg, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---------------- sample rate
          PanelSeparator { visible: root.connected; foreground: root.fg }

          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(rateHeader.implicitHeight, followRow.implicitHeight)

              PanelSectionHeader {
                id: rateHeader
                text: "SAMPLE RATE"
                foreground: root.fg
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: followRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Follow apps"
                  color: Qt.darker(root.fg, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                ToggleSwitch {
                  id: followSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  trackHeight: Math.max(14, Style.space(16))
                  cursorPad: Style.space(3)
                  checked: root.clockMode === "auto"
                  busy: root.rateSwitching
                  foreground: root.fg
                  onToggled: root.setRate(checked ? (root.displayRate || 48000) : "auto")

                  PanelToolTip {
                    visible: followSwitch.containsMouse
                    text: followSwitch.checked
                      ? "Lock the interface to one rate"
                      : "Let PipeWire switch to each app's native rate when the device is idle"
                    fontFamily: root.fontFamily
                  }
                }
              }
            }

            Row {
              id: rateRow
              width: parent.width
              spacing: Style.space(6)
              readonly property real chipWidth: (width - spacing * (root.supportedRates.length - 1)) / root.supportedRates.length

              Repeater {
                model: root.supportedRates

                Button {
                  required property var modelData
                  required property int index
                  width: rateRow.chipWidth
                  text: Model.formatRate(modelData)
                  bordered: true
                  selected: root.clockMode === "fixed" && root.configuredRate === modelData
                  active: root.clockMode === "auto" && root.activeRate === modelData
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  horizontalPadding: 0
                  tooltipText: (index + 1) + " · " + Model.formatRateLong(modelData)
                    + (Model.isQuadRate(modelData) ? " — Clip Safe and Air Drive are off at this rate" : "")
                  onClicked: root.setRate(modelData)
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              color: Qt.darker(root.fg, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: {
                if (root.rateSwitching) return "Switching…"
                if (root.clockMode === "auto")
                  return root.activeRate
                    ? "Following the playing app · running at " + Model.formatRateLong(root.activeRate)
                    : "Follows the first app that opens the device · currently idle"
                var t = "Locked at " + Model.formatRateLong(root.configuredRate) + " · other rates are resampled"
                if (root.quadRate) t += " · Clip Safe and Air Drive unavailable"
                return t
              }
            }

            // Buffer size
            Item {
              width: parent.width
              implicitHeight: bufferHeader.implicitHeight
              PanelSectionHeader {
                id: bufferHeader
                text: "BUFFER"
                foreground: root.fg
                fontFamily: root.fontFamily
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: bufferHeader.verticalCenter
                textFormat: Text.PlainText
                text: root.effectiveQuantum
                  ? root.effectiveQuantum + " samples · " + Model.latencyMs(root.effectiveQuantum, root.displayRate || 48000)
                  : ""
                color: Qt.darker(root.fg, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Row {
              id: bufferRow
              width: parent.width
              spacing: Style.space(6)
              readonly property var options: [0].concat(Model.QUANTA)
              readonly property real chipWidth: (width - spacing * (options.length - 1)) / options.length

              Repeater {
                model: bufferRow.options

                Button {
                  required property var modelData
                  width: bufferRow.chipWidth
                  text: modelData === 0 ? "Auto" : String(modelData)
                  bordered: true
                  selected: (root.clock.forceQuantum || 0) === modelData
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  horizontalPadding: 0
                  tooltipText: modelData === 0
                    ? "Let PipeWire pick the buffer size per app"
                    : modelData + " samples ≈ " + Model.latencyMs(modelData, root.displayRate || 48000) + " per buffer"
                  onClicked: root.setBuffer(modelData)
                }
              }
            }
          }

          // ---------------- inputs
          PanelSeparator { visible: root.connected; foreground: root.fg }

          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(inputsHeader.implicitHeight, inputChips.implicitHeight)

              PanelSectionHeader {
                id: inputsHeader
                text: "INPUTS"
                foreground: root.fg
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: inputChips
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Chip {
                  text: "LINK"
                  checked: root.linked
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  available: Model.has(root.controls, "Line In 1 Link")
                  tooltip: root.linked
                    ? "Inputs linked as a stereo pair — click to split"
                    : "Link inputs 1 and 2 as a stereo pair (gain, Air, Safe, Inst)"
                  onClicked: root.setControl("Line In 1 Link", root.linked ? 0 : 1)
                }

                Chip {
                  text: "48V"
                  checked: root.phantom
                  warn: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  available: Model.has(root.controls, "Line In 1-2 Phantom Power")
                  tooltip: root.phantom
                    ? "Phantom power is ON for both XLR inputs"
                    : "Phantom power for condenser mics (both XLR inputs). Press P"
                  onClicked: root.setControl("Line In 1-2 Phantom Power", root.phantom ? 0 : 1)
                }
              }
            }

            Row {
              id: stripRow
              width: parent.width
              spacing: Style.space(10)

              Repeater {
                model: [1, 2]
                InputStrip {
                  required property var modelData
                  width: (stripRow.width - stripRow.spacing) / 2
                  panel: root
                  channel: modelData
                }
              }
            }
          }

          // ---------------- direct monitor
          PanelSeparator { visible: root.connected && Model.has(root.controls, "Direct Monitor"); foreground: root.fg }

          Column {
            visible: root.connected && Model.has(root.controls, "Direct Monitor")
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(dmHeader.implicitHeight, dmGroup.implicitHeight)

              PanelSectionHeader {
                id: dmHeader
                text: "DIRECT MONITOR"
                foreground: root.fg
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: dmGroup
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Repeater {
                  model: ["Off", "Mono", "Stereo"]
                  Button {
                    required property var modelData
                    required property int index
                    text: modelData
                    bordered: true
                    selected: root.directMonitor === index
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    verticalPadding: Style.space(3)
                    tooltipText: index === 0 ? "Hear only computer playback"
                      : index === 1 ? "Both inputs in the centre of your headphones (M)"
                      : "Input 1 left, input 2 right (M)"
                    onClicked: root.setControl("Direct Monitor", index)
                  }
                }
              }
            }

            Text {
              visible: root.directMonitor === 0
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Hear your inputs with zero latency, blended with computer playback."
              color: Qt.darker(root.fg, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.directMonitor > 0 ? [
                { key: "in1", label: "Input 1", meter: "Analogue 1" },
                { key: "in2", label: "Input 2", meter: "Analogue 2" },
                { key: "playback", label: "Playback", meter: "PCM 1" }
              ] : []

              Item {
                id: faderRow
                required property var modelData
                readonly property var cells: Model.monitorCells(root.controls, root.directMonitor, modelData.key)
                readonly property var cell: cells.length ? Model.ctl(root.controls, cells[0]) : null
                readonly property int raw: root.monitorRaw(modelData.key)
                width: column.width
                implicitHeight: Math.max(faderLabel.implicitHeight, fader.implicitHeight)

                Text {
                  id: faderLabel
                  width: Style.space(64)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: faderRow.modelData.label
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                PanelSlider {
                  id: fader
                  bar: root.bar
                  anchors.left: faderLabel.right
                  anchors.right: faderValue.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  minimum: faderRow.cell ? faderRow.cell.min : 0
                  maximum: faderRow.cell ? faderRow.cell.max : 184
                  step: 2
                  integer: true
                  value: faderRow.raw
                  tickCount: 0
                  onMoved: function(v) { root.setControls(faderRow.cells, v) }
                  onRightClicked: root.setControls(faderRow.cells, faderRow.raw > 0 ? 0 : 160)
                }

                Text {
                  id: faderValue
                  width: Style.space(58)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: Model.formatDb(Model.toDb(faderRow.cell, fader.dragging ? fader.liveValue : faderRow.raw), true)
                  color: Qt.darker(root.fg, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          // ---------------- output meters
          PanelSeparator { visible: root.connected; foreground: root.fg }

          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "OUTPUT"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Repeater {
              model: [{ label: "L", key: "out1" }, { label: "R", key: "out2" }]
              Row {
                required property var modelData
                width: column.width
                spacing: Style.space(8)
                readonly property real db: root.meterDbAt(root.meterIndex[modelData.key])

                Text {
                  id: chLabel
                  width: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: parent.modelData.label
                  color: Qt.darker(root.fg, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                LevelMeter {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - chLabel.width - dbLabel.width - parent.spacing * 2
                  db: parent.db
                  active: root.metering
                  foreground: root.fg
                }
                Text {
                  id: dbLabel
                  width: Style.space(52)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: parent.db > -60 ? Math.round(parent.db) + " dBFS" : "—"
                  color: Qt.darker(root.fg, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---------------- device (collapsible)
          PanelSeparator { visible: root.connected; foreground: root.fg }

          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: deviceHeader.implicitHeight + Style.space(4)

              PanelSectionHeader {
                id: deviceHeader
                text: "DEVICE"
                foreground: root.fg
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.deviceExpanded ? "Hide ▴" : "Show ▾"
                color: Qt.darker(root.fg, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.deviceExpanded = !root.deviceExpanded
              }
            }

            Column {
              visible: root.deviceExpanded
              width: parent.width
              spacing: Style.space(10)

              SettingRow {
                label: "Firmware"
                Row {
                  spacing: Style.space(8)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: {
                      var f = root.firmware
                      if (!f.current) return "—"
                      if (!f.tool) return f.current + " · updater not installed"
                      if (f.updateAvailable) return f.current + " · " + f.latest + " available"
                      return f.current + " · up to date"
                    }
                    color: root.updateAvailable ? root.fg : Qt.darker(root.fg, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Button {
                    text: root.updateAvailable ? "Update…" : "Check"
                    bordered: true
                    selected: root.updateAvailable
                    enabled: root.fwStage !== "running" && root.fwStage !== "rebooting"
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    verticalPadding: Style.space(3)
                    tooltipText: root.firmware.tool
                      ? "Looks in /usr/lib/firmware/scarlett2 (package scarlett2-firmware — update it with your system updates)"
                      : "Install the AUR packages scarlett2 and scarlett2-firmware to enable updates"
                    onClicked: {
                      if (root.updateAvailable) { root.fwDismissed = false; root.fwStage = "confirm" }
                      else root.send("firmware")
                    }
                  }
                }
              }

              SettingRow {
                label: "Front panel"
                visible: Model.has(root.controls, "Front Panel Brightness")
                Row {
                  spacing: Style.space(4)
                  Repeater {
                    model: Model.ctl(root.controls, "Front Panel Brightness") ? Model.ctl(root.controls, "Front Panel Brightness").items : []
                    Button {
                      required property var modelData
                      required property int index
                      text: modelData
                      bordered: true
                      selected: Model.value(root.controls, "Front Panel Brightness", -1) === index
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      verticalPadding: Style.space(3)
                      onClicked: root.setControl("Front Panel Brightness", index)
                    }
                  }
                }
              }

              SettingRow {
                label: "Panel sleep"
                visible: Model.has(root.controls, "Front Panel Sleep Time")
                Row {
                  spacing: Style.space(4)
                  Repeater {
                    model: [{ v: 60, t: "1m" }, { v: 300, t: "5m" }, { v: 600, t: "10m" }, { v: 1800, t: "30m" }, { v: 3600, t: "1h" }]
                    Button {
                      required property var modelData
                      text: modelData.t
                      bordered: true
                      selected: Model.value(root.controls, "Front Panel Sleep Time", -1) === modelData.v
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      verticalPadding: Style.space(3)
                      tooltipText: "Dim the front panel after " + modelData.t + " of inactivity"
                      onClicked: root.setControl("Front Panel Sleep Time", modelData.v)
                    }
                  }
                }
              }

              Repeater {
                model: [
                  { name: "Autogain Mean Target", label: "Auto mean" },
                  { name: "Autogain Peak Target", label: "Auto peak" }
                ]
                SettingRow {
                  id: targetRow
                  required property var modelData
                  readonly property var c: Model.ctl(root.controls, modelData.name)
                  label: modelData.label
                  visible: !!c
                  Row {
                    spacing: Style.space(8)
                    PanelSlider {
                      id: targetSlider
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(170)
                      bar: root.bar
                      minimum: targetRow.c ? targetRow.c.min : -30
                      maximum: targetRow.c ? targetRow.c.max : 0
                      step: 1
                      integer: true
                      value: targetRow.c ? targetRow.c.values[0] : 0
                      onReleased: function(v) { root.setControl(targetRow.modelData.name, v) }
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(50)
                      horizontalAlignment: Text.AlignRight
                      textFormat: Text.PlainText
                      text: Math.round(targetSlider.dragging ? targetSlider.liveValue : targetSlider.value) + " dBFS"
                      color: Qt.darker(root.fg, 1.3)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: Qt.darker(root.fg, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                text: {
                  var parts = []
                  if (root.serial) parts.push("Serial " + root.serial)
                  if (root.usbid) parts.push("USB " + root.usbid)
                  parts.push(root.locked ? "Clock locked" : "Clock unlocked")
                  return parts.join("  ·  ")
                }
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.lastError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // Label on the left, control on the right.
  component SettingRow: Item {
    id: settingRow
    property string label: ""
    default property alias content: holder.children
    width: column.width
    implicitHeight: Math.max(rowLabel.implicitHeight, holder.childrenRect.height)

    Text {
      id: rowLabel
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: settingRow.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      id: holder
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }
}
