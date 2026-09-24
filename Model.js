.pragma library

// Pure helpers for the Scarlett panel. Everything here works on the control
// snapshot scarlett-ctl emits: { "<short name>": { numid, type, min, max,
// dbMin, dbMax, items, values, rw } }. Nothing assumes a fixed numid, so the
// same code keeps working if a firmware update renumbers the controls.

var RATES = [44100, 48000, 88200, 96000, 176400, 192000]
var QUANTA = [64, 128, 256, 512, 1024]

// Autogain status items -> short human text. "Root" is the device's idle
// value (never run since power-on), so it reads as nothing at all.
var AUTOGAIN_TEXT = {
  "Running": "Listening…",
  "Success": "Gain set",
  "SuccessDRover": "Gain set · wide dynamics",
  "WarnMinGainLimit": "Set at minimum gain",
  "FailDRunder": "Too quiet — try again",
  "FailMaxGainLimit": "Needs more than max gain",
  "FailClipped": "Signal clipped",
  "Cancelled": "Cancelled",
  "Root": "",
  "Invalid": ""
}

function has(controls, name) {
  return !!(controls && controls[name])
}

function ctl(controls, name) {
  return controls ? controls[name] || null : null
}

function value(controls, name, fallback) {
  var c = ctl(controls, name)
  if (!c || !c.values || c.values.length === 0) return fallback
  return c.values[0]
}

function bool(controls, name) {
  return value(controls, name, false) === true
}

function item(controls, name) {
  var c = ctl(controls, name)
  if (!c || !c.items || !c.values) return ""
  return c.items[c.values[0]] || ""
}

function numid(controls, name) {
  var c = ctl(controls, name)
  return c ? c.numid : -1
}

// Raw integer -> dB using the control's own TLV range (linear scales only,
// which is what the Scarlett driver publishes).
function toDb(c, raw) {
  if (!c || c.dbMin === undefined || c.max === c.min) return raw
  return c.dbMin + (raw - c.min) * (c.dbMax - c.dbMin) / (c.max - c.min)
}

function fromDb(c, db) {
  if (!c || c.dbMin === undefined || c.dbMax === c.dbMin) return Math.round(db)
  var raw = c.min + (db - c.dbMin) * (c.max - c.min) / (c.dbMax - c.dbMin)
  return Math.max(c.min, Math.min(c.max, Math.round(raw)))
}

function formatDb(db, withSign) {
  if (db <= -79.5) return "−∞"
  var rounded = Math.round(db * 2) / 2
  var text = (Math.abs(rounded - Math.round(rounded)) < 0.01 ? Math.round(rounded).toString() : rounded.toFixed(1))
  if (withSign && rounded > 0) text = "+" + text
  return text.replace("-", "−") + " dB"
}

function formatRate(hz) {
  if (!hz) return "—"
  var k = hz / 1000
  return (Math.round(k) === k ? k.toString() : k.toFixed(1))
}

function formatRateLong(hz) {
  return hz ? formatRate(hz) + " kHz" : "—"
}

function isQuadRate(hz) {
  return hz >= 176400
}

function latencyMs(quantum, rate) {
  if (!quantum || !rate) return ""
  var ms = quantum / rate * 1000
  return (ms < 10 ? ms.toFixed(1) : Math.round(ms).toString()) + " ms"
}

// ---- metering ------------------------------------------------------------

// The Level Meter control is one value per routing *destination*, in the
// order the driver enumerates them: analogue outputs, mixer inputs, DSP
// inputs, then PCM capture channels. Each destination's routing enum names the
// source it carries, which is how "Analogue 1" is found without hardcoding.
function meterSinks(controls) {
  var groups = [/^Analogue Output \d+$/, /^Mixer Input \d+$/, /^DSP Input \d+$/, /^PCM \d+$/]
  var names = controls ? Object.keys(controls) : []
  var sinks = []
  for (var g = 0; g < groups.length; g++) {
    var group = []
    for (var i = 0; i < names.length; i++)
      if (groups[g].test(names[i]) && controls[names[i]].type === "enum") group.push(names[i])
    group.sort(function(a, b) { return controls[a].numid - controls[b].numid })
    for (var j = 0; j < group.length; j++)
      sinks.push({ name: group[j], source: item(controls, group[j]) })
  }
  return sinks
}

// { "Analogue 1": index, "PCM 1": index, "out1": 0, "out2": 1 }
function meterMap(controls) {
  var sinks = meterSinks(controls)
  var map = {}
  var outs = 0
  for (var i = 0; i < sinks.length; i++) {
    var s = sinks[i]
    if (/^Analogue Output/.test(s.name)) map["out" + (++outs)] = i
    if (s.source && map[s.source] === undefined) map[s.source] = i
  }
  return map
}

// 12-bit linear amplitude -> dBFS.
function meterDb(raw) {
  if (!raw || raw <= 0) return -120
  return 20 * Math.log(raw / 4095) / Math.LN10
}

// dBFS -> 0..1 for drawing. The bottom of the scale is -60 dBFS, with a
// gentle curve so the musically useful top 20 dB gets most of the length.
function meterFraction(db) {
  var floor = -60
  if (db <= floor) return 0
  if (db >= 0) return 1
  var x = (db - floor) / -floor
  return Math.pow(x, 1.6)
}

// ---- direct monitor ------------------------------------------------------

// Which mixer inputs ("Mixer Input 0N") carry a given source family. The
// direct-monitor mixes address mixer inputs by number, so the routing is read
// rather than assumed (on the 2i2: 01/02 = PCM 1/2, 03/04 = DSP 1/2).
function mixerInputFor(controls, sources) {
  for (var n = 1; n <= 8; n++) {
    var name = "Mixer Input " + (n < 10 ? "0" + n : n)
    if (!has(controls, name)) break
    if (sources.indexOf(item(controls, name)) >= 0) return n
  }
  return 0
}

function pad2(n) {
  return n < 10 ? "0" + n : "" + n
}

// The cells ("Monitor M Mix X Input NN") a direct-monitor channel owns in the
// given mode. Mono (Monitor 1) centres both inputs; Stereo (Monitor 2) pans
// input 1 left and input 2 right. Playback is always L->A, R->B.
function monitorCells(controls, mode, channel) {
  var mon = mode === 1 ? "Monitor 1" : "Monitor 2"
  var in1 = mixerInputFor(controls, ["DSP 1", "Analogue 1"])
  var in2 = mixerInputFor(controls, ["DSP 2", "Analogue 2"])
  var pl = mixerInputFor(controls, ["PCM 1"])
  var pr = mixerInputFor(controls, ["PCM 2"])
  var cells = []
  function add(mix, input) {
    if (!input) return
    var name = mon + " Mix " + mix + " Input " + pad2(input)
    if (has(controls, name)) cells.push(name)
  }
  if (channel === "in1") {
    add("A", in1)
    if (mode === 1) add("B", in1)
  } else if (channel === "in2") {
    if (mode === 1) add("A", in2)
    add("B", in2)
  } else if (channel === "playback") {
    add("A", pl)
    add("B", pr)
  }
  return cells
}
