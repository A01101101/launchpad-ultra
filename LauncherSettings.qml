// Launchpad's settings, kept in ~/.config/omarchy/launchpad.json. Editing the
// file by hand works too: it is re-read whenever it changes.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/launchpad.json"

  // Each setting's default and, for numbers, the range it is held to.
  readonly property var spec: ({
    columns: { value: 6, min: 4, max: 10 },
    rows: { value: 4, min: 2, max: 6 },
    iconSize: { value: 86, min: 56, max: 128 },
    showNames: { value: true },
    backdrop: { value: 0.34, min: 0.31, max: 0.9 },
    followTheme: { value: false },
    rememberPage: { value: false }
  })

  // What is in effect now, defaults filled in.
  property var values: root.withDefaults({})

  readonly property int columns: values.columns
  readonly property int rows: values.rows
  readonly property int iconSize: values.iconSize
  readonly property bool showNames: values.showNames
  readonly property real backdrop: values.backdrop
  readonly property bool followTheme: values.followTheme
  readonly property bool rememberPage: values.rememberPage

  readonly property bool isDefault: {
    for (var key in spec) if (values[key] !== spec[key].value) return false
    return true
  }

  // Anything missing, of the wrong type or out of range falls back or is
  // clamped, so a hand-edited file cannot break the grid.
  function withDefaults(stored) {
    var out = {}
    for (var key in spec) {
      var rule = spec[key]
      var value = stored ? stored[key] : undefined
      if (typeof value !== typeof rule.value || (typeof value === "number" && !isFinite(value))) value = rule.value
      if (typeof value === "number") {
        value = Math.max(rule.min, Math.min(rule.max, value))
        if (Math.round(rule.value) === rule.value) value = Math.round(value)
      }
      out[key] = value
    }
    return out
  }

  function load(raw) {
    var stored = {}
    try {
      stored = JSON.parse(String(raw || "{}"))
    } catch (e) {
      stored = {}
    }
    values = withDefaults(stored)
  }

  // Changes a setting for now, without saving: what a slider does mid-drag.
  function preview(key, value) {
    var next = {}
    for (var k in values) next[k] = values[k]
    next[key] = value
    values = withDefaults(next)
  }

  function save() {
    file.setText(JSON.stringify(values, null, 2) + "\n")
  }

  function set(key, value) {
    preview(key, value)
    save()
  }

  function reset() {
    values = withDefaults({})
    save()
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("{}")
    onFileChanged: reload()
  }
}
