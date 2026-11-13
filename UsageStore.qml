// How often each app has been opened from Launchpad or its dock, for the
// "most used" order. Kept in ~/.local/state/omarchy/launchpad-usage.json.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property string path: Quickshell.env("HOME") + "/.local/state/omarchy/launchpad-usage.json"
  // Desktop id -> times opened.
  property var counts: ({})

  function count(desktopId) {
    return counts[String(desktopId || "")] || 0
  }

  function record(desktopId) {
    var id = String(desktopId || "")
    if (!id) return
    var next = {}
    for (var key in counts) next[key] = counts[key]
    next[id] = (next[id] || 0) + 1
    counts = next
    file.setText(JSON.stringify(counts) + "\n")
  }

  // Only whole, positive counts under sane ids are kept, so a damaged or
  // hand-edited file cannot upset the sort.
  function load(raw) {
    var stored = {}
    try {
      stored = JSON.parse(String(raw || "{}"))
    } catch (e) {
      stored = {}
    }
    var out = {}
    var kept = 0
    if (stored && typeof stored === "object" && !Array.isArray(stored)) {
      for (var key in stored) {
        var value = stored[key]
        if (kept >= 2000 || key.length > 200) continue
        if (typeof value !== "number" || !isFinite(value) || value < 1) continue
        out[key] = Math.min(1000000, Math.floor(value))
        kept++
      }
    }
    counts = out
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
