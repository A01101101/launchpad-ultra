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
    // The settings cog in the corner. Off: settings open from the dock's menu.
    showGear: { value: false },
    rememberPage: { value: false },
    // "pages" turns whole pages; "smooth" is one long grid that scrolls.
    scrollStyle: { value: "pages", options: ["pages", "smooth"] },
    // The side the next page comes in from.
    slideFrom: { value: "right", options: ["right", "left", "bottom", "top"] },
    indicator: { value: "pill", options: ["pill", "dots", "numbers", "off"] },
    arrows: { value: "round", options: ["round", "chevron", "edge", "off"] },
    // A click on empty space closes Launchpad or turns the page.
    emptyClick: { value: "close", options: ["close", "page"] },
    scrollSensitivity: { value: 3, min: 1, max: 5 },
    dockIconSize: { value: 36, min: 24, max: 64 },
    // The search bar's size, in percent, and its border in pixels (0 is none).
    searchSize: { value: 100, min: 60, max: 240 },
    searchBorder: { value: 1, min: 0, max: 6 },
    // The whole screen's theme: frosted glass, or a retro green LCD.
    theme: { value: "glass", options: ["glass", "lcd"] },
    // The LCD's colors, and how far its icons' shadows fall, in pixels (0 is
    // no shadow).
    lcdTint: { value: "green", options: ["green", "amber", "blue", "grey", "violet", "paper", "night"] },
    lcdShadow: { value: 3, min: 0, max: 12 },
    // The search bar's look, caret, and underline (for the plain look).
    // Past the first three: viewfinder corners, giant capitals over a rule,
    // a neo-brutalist block, labelled paper, and a glowing aurora ring.
    searchLook: { value: "glass", options: ["glass", "plain", "win98", "frame", "headline", "brutal", "paper", "aurora"] },
    // The looking glass in the search bar: its drawing, color and size in
    // percent.
    glassStyle: { value: "classic", options: ["classic", "fine", "bold", "filled", "square", "pixel", "arrow", "dot", "off"] },
    glassSize: { value: 100, min: 60, max: 200 },
    searchUnderline: { value: true },
    searchCaret: { value: "line", options: ["line", "block", "underscore"] },
    searchBlink: { value: true },
    // Holds the search bar and its placeholder still: no corners closing in,
    // no press, no turning ring, no fading lines or bobbing marks.
    searchCalm: { value: false },
    // What the empty bar says: the word, rotating lines, a confused face, your own words, or
    // the yellow LCD's easter egg.
    searchPrompt: { value: "plain", options: ["plain", "quips", "confused", "custom", "pika"] },
    // The words the "custom" placeholder shows, up to 60 characters.
    searchCustom: { value: "", maxLength: 60 },
    // Where the bar sits: a preset, or "custom" at searchX / searchY (the
    // bar's centre as a fraction of the screen), set by dragging it.
    searchPlace: { value: "top", options: ["top", "center", "bottom", "custom"] },
    searchX: { value: 0.5, min: 0, max: 1 },
    searchY: { value: 0.06, min: 0, max: 1 },
    // Whether the settings card floats, and where: its centre as a fraction
    // of the screen.
    cardPopped: { value: false },
    cardX: { value: 0.5, min: 0, max: 1 },
    cardY: { value: 0.5, min: 0, max: 1 },
    // Whether the sort box shows beside the search bar, and the order chosen.
    sortBox: { value: false },
    sortBy: { value: "alpha", options: ["alpha", "used"] }
  })

  // What is in effect now, defaults filled in.
  property var values: root.withDefaults({})

  readonly property int columns: values.columns
  readonly property int rows: values.rows
  readonly property int iconSize: values.iconSize
  readonly property bool showNames: values.showNames
  readonly property real backdrop: values.backdrop
  readonly property bool followTheme: values.followTheme
  readonly property bool showGear: values.showGear
  readonly property bool rememberPage: values.rememberPage
  readonly property string scrollStyle: values.scrollStyle
  readonly property string slideFrom: values.slideFrom
  readonly property string indicator: values.indicator
  readonly property string arrows: values.arrows
  readonly property string emptyClick: values.emptyClick
  readonly property int scrollSensitivity: values.scrollSensitivity
  readonly property int dockIconSize: values.dockIconSize
  readonly property int searchSize: values.searchSize
  readonly property int searchBorder: values.searchBorder
  readonly property string theme: values.theme
  readonly property string lcdTint: values.lcdTint
  readonly property int lcdShadow: values.lcdShadow
  // Each LCD tint: the screen's color and the ink drawn on it.
  readonly property var lcdTints: ({
    green: { screen: "#a9bb8f", ink: "#1c2713" },
    amber: { screen: "#e3b04b", ink: "#2e1c05" },
    blue: { screen: "#a3c6d9", ink: "#10232f" },
    grey: { screen: "#c6cabd", ink: "#1f221c" },
    violet: { screen: "#bcaedb", ink: "#201733" },
    paper: { screen: "#e8e6dc", ink: "#1b1b19" },
    night: { screen: "#111a0d", ink: "#9ed46c" }
  })
  readonly property color lcdScreen: lcdTints[lcdTint].screen
  readonly property color lcdInk: lcdTints[lcdTint].ink
  readonly property string searchLook: values.searchLook
  readonly property string glassStyle: values.glassStyle
  readonly property int glassSize: values.glassSize
  // The looking glass's fixed colors. "ink" and "accent" follow the screen.
  readonly property bool searchUnderline: values.searchUnderline
  readonly property string searchCaret: values.searchCaret
  readonly property bool searchBlink: values.searchBlink
  readonly property bool searchCalm: values.searchCalm
  readonly property string searchPrompt: values.searchPrompt
  readonly property string searchCustom: values.searchCustom
  // The easter egg plays only on the yellow (amber) LCD, and only when its
  // clip is in easter/ beside the plugin; the clip is not part of the repo.
  readonly property url pikaSource: Qt.resolvedUrl("easter/pika.mp4")
  property bool pikaAvailable: false
  readonly property bool pikaOffered: pikaAvailable && theme === "lcd" && lcdTint === "amber"
  readonly property string searchPromptShown: searchPrompt === "pika" && !pikaOffered ? "plain" : searchPrompt
  readonly property string searchPlace: values.searchPlace
  readonly property real searchX: values.searchX
  readonly property real searchY: values.searchY
  readonly property bool sortBox: values.sortBox
  readonly property string sortBy: values.sortBy

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
      if (rule.options && rule.options.indexOf(value) === -1) value = rule.value
      if (typeof value === "string" && rule.maxLength) value = value.slice(0, rule.maxLength)
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
    // The looks that were redrawn keep their place in a saved file.
    var renamed = { hairline: "frame", band: "brutal", split: "aurora" }
    if (stored && renamed[stored.searchLook]) stored.searchLook = renamed[stored.searchLook]
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
    path: String(root.pikaSource).replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: root.pikaAvailable = true
    onLoadFailed: root.pikaAvailable = false
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
