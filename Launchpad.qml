// Launchpad: a fullscreen frosted overlay with a search pill, a sliding paged
// grid holding every installed app, and page dots. Its settings open in a card
// beside the grid.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  // Set by the shell when it loads the plugin.
  property var shell: null
  property var manifest: null
  readonly property var appLibrary: shell ? shell.appLibrary : null

  property bool opened: false
  property bool settingsOpen: false
  property var apps: []
  property int page: 0
  // The page last browsed without a search, for the "remember page" setting.
  property int browsedPage: 0
  property string launchingId: ""

  // The dock this plugin also provides: apps can be dragged onto it or kept
  // in it from an app's menu.
  property var service: null
  readonly property var dock: service || (shell && manifest ? shell.serviceFor(manifest.id) : null)

  // The app the keyboard is on. It only shows once the keyboard has moved it.
  property int selectedIndex: 0
  property bool cursorActive: false
  // While an app is dragged out toward the dock, everything but its icon
  // steps aside so the dock shows through.
  property bool dragging: false
  property var dragEntry: null
  property point dragPoint
  // The app whose menu is open, and where it opened.
  property var menuEntry: null
  property point menuPoint
  // The app waiting on the user to confirm uninstalling it.
  property var uninstallEntry: null

  readonly property int cols: settings.columns
  readonly property int rows: settings.rows
  readonly property int pageSize: cols * rows
  readonly property int pageCount: Math.ceil(apps.length / pageSize)
  readonly property string query: searchInput.text.trim()

  // Sizes follow the shell's spacing and font scale.
  readonly property int iconSize: Style.space(settings.iconSize)
  readonly property int labelSize: Style.font.subtitle
  readonly property int labelGap: Style.space(8)
  readonly property int labelRoom: settings.showNames ? labelSize * 1.5 + labelGap : 0

  // How pages turn. `hSign` and `vSign` are +1 when the next page lies to
  // the right or below, -1 when it lies to the left or above; a right-to-left
  // layout flips the horizontal one.
  readonly property bool paged: settings.scrollStyle === "pages"
  readonly property bool horizontal: settings.slideFrom === "right" || settings.slideFrom === "left"
  readonly property int hSign: (settings.slideFrom === "left" ? -1 : 1) * (Commons.I18n.rightToLeft ? -1 : 1)
  readonly property int vSign: settings.slideFrom === "top" ? -1 : 1

  // Scroll sensitivity, 1 to 5: how far the wheel must turn for a page, and
  // how far a notch or a touchpad pixel scrolls the smooth grid.
  readonly property int wheelThreshold: [80, 50, 25, 12, 5][settings.scrollSensitivity - 1]
  readonly property int wheelNotch: [40, 70, 110, 160, 220][settings.scrollSensitivity - 1]
  readonly property real wheelGain: [0.4, 0.7, 1, 1.5, 2.2][settings.scrollSensitivity - 1]
  // Where the smooth grid is scrolling to.
  property real smoothTarget: 0
  onPagedChanged: scrollTo(0)

  // Colors: a dark glass with white ink by default, or the theme's own
  // background and text when "follow theme" is on.
  // The LCD theme swaps both for a green screen with dark ink.
  readonly property bool lcd: settings.theme === "lcd"
  readonly property color ink: lcd ? settings.lcdInk : (settings.followTheme ? Commons.Color.foreground : "white")
  readonly property color shade: lcd ? settings.lcdScreen : (settings.followTheme ? Commons.Color.background : Qt.rgba(12 / 255, 14 / 255, 22 / 255, 1))
  function inkAlpha(opacity) { return Util.alpha(root.ink, opacity) }

  onQueryChanged: {
    page = 0
    selectedIndex = 0
    cursorActive = false
    menuEntry = null
    rebuild()
    scrollTo(0)
  }
  onPageChanged: if (query === "") browsedPage = page
  onPageSizeChanged: goToPage(page)

  // ---- What the shell calls ------------------------------------------------

  // The payload may ask for a view: { "view": "settings" } opens the settings
  // card along with the grid.
  function open(payloadJson) {
    var payload = {}
    try {
      payload = JSON.parse(String(payloadJson || "{}")) || {}
    } catch (e) {
      payload = {}
    }
    var startPage = settings.rememberPage ? browsedPage : 0
    searchInput.clear()
    launchingId = ""
    selectedIndex = 0
    cursorActive = false
    settingsOpen = payload.view === "settings"
    // { "view": "settings", "tab": "search" } opens the card on that tab.
    if (settingsOpen && ["grid", "pages", "search", "theme"].indexOf(payload.tab) !== -1) settingsCard.tab = payload.tab
    if (appLibrary) appLibrary.refreshIcons()
    rebuild()
    goToPage(startPage)
    scrollTo(0)
    opened = true
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function close() {
    if (dragging && dock) dock.endExternalDrag()
    opened = false
    settingsOpen = false
    dragging = false
    dragEntry = null
    menuEntry = null
    uninstallEntry = null
    closeTimer.stop()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "launchpad")
  }

  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }

  // Changes settings from outside, e.g.
  //   omarchy-shell shell call launchpad configure '{"columns": 8}'
  function configure(payloadJson) {
    var changes = {}
    try {
      changes = JSON.parse(String(payloadJson || "{}")) || {}
    } catch (e) {
      return
    }
    for (var key in changes)
      if (key in settings.spec) settings.preview(key, changes[key])
    settings.save()
  }

  // ---- Apps ----------------------------------------------------------------

  // The shell's own app list: the same apps, search and hidden entries as the
  // Omarchy launcher.
  // A search keeps the shell's own ranking. Otherwise the apps come by name,
  // or most opened first with names breaking ties, as the sort setting says.
  function rebuild() {
    var found = appLibrary ? appLibrary.sortedEntries(query) : []
    var entries = found.map(function(row) { return row.entry })
    if (query === "" && settings.sortBy === "used") {
      var rank = {}
      for (var i = 0; i < entries.length; i++) rank[entries[i].id] = i
      entries.sort(function(a, b) {
        return (usage.count(b.id) - usage.count(a.id)) || (rank[a.id] - rank[b.id])
      })
    }
    apps = entries
    selectedIndex = Math.max(0, Math.min(selectedIndex, apps.length - 1))
    goToPage(page)
  }

  function scrollTo(y) {
    var most = Math.max(0, smoothGrid.contentHeight - smoothGrid.height)
    smoothTarget = Math.max(0, Math.min(most, y))
    smoothGrid.contentY = smoothTarget
  }

  function scrollBy(pixels) {
    scrollTo(smoothTarget + pixels)
  }

  // Moves the keyboard's app, turning the page or scrolling to keep it in
  // view. It starts from the first app showing.
  function select(delta) {
    if (apps.length === 0) return
    var first = paged ? page * pageSize : Math.floor(smoothTarget / smoothGrid.cellHeight) * cols
    selectedIndex = cursorActive ? Math.max(0, Math.min(apps.length - 1, selectedIndex + delta))
                                 : Math.min(apps.length - 1, first)
    cursorActive = true
    if (paged) {
      goToPage(Math.floor(selectedIndex / pageSize))
      return
    }
    var top = Math.floor(selectedIndex / cols) * smoothGrid.cellHeight
    if (top < smoothTarget) scrollTo(top)
    else if (top + smoothGrid.cellHeight > smoothTarget + smoothGrid.height) scrollTo(top + smoothGrid.cellHeight - smoothGrid.height)
  }

  // ---- Dragging an app onto the dock ---------------------------------------

  function dragTo(entry, point) {
    if (!dragging) {
      menuEntry = null
      dragEntry = entry
      dragging = true
    }
    dragPoint = point
    if (dock) dock.moveExternalDrag(panel.screen, point.x, point.y)
  }

  function dropDrag() {
    var entry = dragEntry
    if (entry && dock) dock.dropExternalDrag(panel.screen, dragPoint.x, dragPoint.y, String(entry.id || ""))
    dismiss()
  }

  // ---- An app's menu and uninstalling --------------------------------------

  function openMenu(entry, point) {
    menuEntry = entry
    menuPoint = point
  }

  function requestUninstall(entry) {
    if (!entry) return
    menuEntry = null
    uninstallConfirm.selectedIndex = 1
    uninstallEntry = entry
  }

  function confirmUninstall() {
    var entry = uninstallEntry
    uninstallEntry = null
    dismiss()
    if (entry && appLibrary) appLibrary.remove(entry.id, appLibrary.entryName(entry))
  }

  function goToPage(p) {
    page = Math.max(0, Math.min(p, pageCount - 1))
  }

  // Starts an app and hides the launcher once its icon has zoomed away.
  function openApp(entry) {
    if (!entry || !appLibrary || launchingId !== "") return
    launchingId = entry.id
    usage.record(entry.id)
    appLibrary.launch(entry.id, appLibrary.entryName(entry))
    closeTimer.start()
  }

  Timer { id: closeTimer; interval: Style.duration(200); onTriggered: root.dismiss() }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.rebuild() }
  }

  LauncherSettings { id: settings }
  UsageStore { id: usage }
  // The order follows the setting at once. Counts are read when Launchpad
  // opens, so apps do not shuffle while it is open.
  readonly property string sortBy: settings.sortBy
  onSortByChanged: rebuild()
  // The search bar's size setting, as a factor.
  readonly property real searchScale: settings.searchSize / 100
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // A click on any other screen closes Launchpad too: while it is open, each
  // of the other screens wears an invisible sheet that takes the click.
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: catcher
      required property var modelData
      screen: modelData
      visible: root.opened && !!panel.targetScreen && modelData.name !== panel.targetScreen.name
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "launchpad-outside"
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.dismiss()
      }
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    // Hyprland can blur the desktop behind this namespace; see the README.
    WlrLayershell.namespace: "launchpad"

    // Room the settings card takes from the grid while it is open.
    readonly property int reserve: root.settingsOpen ? settingsCard.width + Style.space(40) : 0

    // Everything but a dragged icon and the menus. It fades out while an app
    // is dragged toward the dock, and still holds the pointer.
    Item {
      id: stage
      anchors.fill: parent
      opacity: root.dragging ? 0 : 1
      Behavior on opacity {
        id: stageFade
        NumberAnimation { duration: Style.duration(stageFade.targetValue > 0 ? 150 : 100); easing.type: Easing.OutCubic }
      }

      // ---- Backdrop: a tint over the desktop ---------------------------------
      // The tint stays above 0.3 so a blur rule with ignore_alpha = 0.3 applies.
      Rectangle {
        id: backdrop
        anchors.fill: parent
        // Lighter through the middle, deeper toward the top and bottom, so the
        // grid sits in a pool of light and the edges recede. The LCD is a
        // nearly solid screen.
        readonly property real mid: root.lcd ? 1 : settings.backdrop
        readonly property real edge: root.lcd ? 1 : Math.min(0.96, settings.backdrop + 0.16)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(root.shade, backdrop.edge) }
          GradientStop { position: 0.28; color: Util.alpha(root.shade, backdrop.mid) }
          GradientStop { position: 0.72; color: Util.alpha(root.shade, backdrop.mid) }
          GradientStop { position: 1.0; color: Util.alpha(root.shade, backdrop.edge) }
        }
      }

      // The LCD's pixel grid: a faint dark line between every four-pixel dot,
      // tiled over the whole screen.
      Image {
        anchors.fill: parent
        visible: root.lcd
        fillMode: Image.Tile
        smooth: false
        sourceSize: Qt.size(4, 4)
        source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'>"
                + "<path d='M0 0h4v1h-4zM0 1h1v3h-1z' fill='%23" + settings.lcdTints[settings.lcdTint].ink.slice(1)
                + "' fill-opacity='0.11'/></svg>"
      }
      // The glass over it: darker into the corners, the way a lit LCD falls off.
      Rectangle {
        anchors.fill: parent
        visible: root.lcd
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(root.ink, 0.16) }
          GradientStop { position: 0.12; color: Util.alpha(root.ink, 0.0) }
          GradientStop { position: 0.88; color: Util.alpha(root.ink, 0.0) }
          GradientStop { position: 1.0; color: Util.alpha(root.ink, 0.2) }
        }
      }

      // A click on empty space closes the launcher, or turns the page toward
      // the side clicked when the settings say so. A right-click always closes.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(event) {
          if (root.menuEntry) {
            root.menuEntry = null
          } else if (root.paged && settings.emptyClick === "page" && event.button === Qt.LeftButton) {
            var forward = root.horizontal ? event.x >= viewport.x + viewport.width / 2
                                          : event.y >= viewport.y + viewport.height / 2
            root.goToPage(root.page + (forward ? 1 : -1) * (root.horizontal ? root.hSign : root.vSign))
          } else {
            root.dismiss()
          }
        }
      }

      // Mouse wheel and touchpad swipes turn one page per gesture, or scroll
      // the smooth grid. Over the settings card they scroll the card instead.
      WheelHandler {
        id: wheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var at = wheel.point.position
          if (root.settingsOpen && at.x >= settingsCard.x && at.x <= settingsCard.x + settingsCard.width
              && at.y >= settingsCard.y && at.y <= settingsCard.y + settingsCard.height) return
          var dx = event.angleDelta.x, dy = event.angleDelta.y
          var d = Math.abs(dx) > Math.abs(dy) ? dx : dy
          if (!root.paged) {
            var pixels = event.pixelDelta.y !== 0 ? event.pixelDelta.y * root.wheelGain : d / 120 * root.wheelNotch
            root.scrollBy(-pixels)
            return
          }
          if (wheelPause.running) return
          if (Math.abs(d) < root.wheelThreshold) return
          root.goToPage(root.page + (d < 0 ? 1 : -1))
          wheelPause.start()
        }
      }
      // One page turn per gesture, however long the swipe keeps scrolling.
      Timer { id: wheelPause; interval: 320 }

      // ---- Search pill -------------------------------------------------------
      // Its look, caret, size and place all come from the settings. With the
      // card open and "Move and resize" switched on, it can be dragged to move
      // and resized by its corner.
      Rectangle {
        id: searchPill
        readonly property bool filled: searchInput.text !== ""
        readonly property string look: root.lcd ? "lcd" : settings.searchLook
        readonly property bool lcd: look === "lcd"
        readonly property bool win98: look === "win98"
        readonly property bool plain: look === "plain"
        // A thin outlined pill with a light italic prompt.
        readonly property bool hairline: look === "hairline"
        // Giant bold capitals set straight on the screen, over a thin rule.
        readonly property bool headline: look === "headline"
        // A solid band of the accent color with serif type.
        readonly property bool band: look === "band"
        // A sheet of warm paper with a small label above it.
        readonly property bool paper: look === "paper"
        // A fine-bordered field joined to a solid accent button.
        readonly property bool split: look === "split"
        // Looks that end in an arrow.
        readonly property bool arrowed: headline || band || split
        readonly property color pillInk: win98 ? "#000000" : paper ? "#1d1b16" : band ? root.shade : root.ink
        readonly property string face: lcd ? "monospace" : win98 ? "Tahoma" : band ? "Noto Serif" : Style.font.family
        readonly property real fontPx: headline ? Math.round(height * 0.78)
                                       : Math.round(Style.font.title * searchPill.fit * (win98 ? 0.92 : band ? 1.08 : 1))
        // The room the paper look's label takes above the field.
        readonly property real headRoom: paper ? Math.round(Style.space(20) * Math.max(0.8, Math.min(1.5, fit))) : 0
        // The split look's button, and the room any arrow takes at the end.
        readonly property real tailRoom: split ? height : arrowed ? Style.space(34) * fit : 0
        // The looking glass's color.
        readonly property color glassInk: root.lcd || settings.glassTint === "ink" ? pillInk
                                          : settings.glassTint === "accent" ? (band ? pillInk : Commons.Color.accent)
                                          : settings.tints[settings.glassTint]
        readonly property bool lit: filled || searchInput.activeFocus
        // The size setting is a wish: the bar shrinks to whatever fits around
        // its centre, so it is never cut off by the screen's edges (or runs
        // under the sort box), and grows back when there is room.
        readonly property real centerX: settings.searchPlace === "custom"
                                        ? settings.searchX * parent.width
                                        : viewport.x + viewport.width / 2
        readonly property real fitMargin: Style.space(16)
        readonly property real roomX: Math.min(centerX - fitMargin,
                                               parent.width - centerX - fitMargin
                                               - (settings.sortBox ? sortBox.width + Style.space(12) : 0))
        readonly property real roomY: (settings.searchPlace === "custom"
                                       ? Math.min(settings.searchY, 1 - settings.searchY) * parent.height
                                       : parent.height / 2) - fitMargin
        readonly property real fit: Math.max(0.35, Math.min(root.searchScale,
                                                            2 * roomX / Style.space(440),
                                                            2 * roomY / Style.space(38)))
        width: Math.round(Style.space(filled && settings.searchGrow ? 440 : 340) * searchPill.fit)
        height: Math.round(Style.space(38) * searchPill.fit)
        // A preset, or wherever it was dragged to.
        x: settings.searchPlace === "custom"
           ? Math.max(0, Math.min(parent.width - width, settings.searchX * parent.width - width / 2))
           : viewport.x + (viewport.width - width) / 2
        y: settings.searchPlace === "custom"
           ? Math.max(headRoom, Math.min(parent.height - height, settings.searchY * parent.height - height / 2))
           : settings.searchPlace === "center" ? (parent.height - height) / 2
           : settings.searchPlace === "bottom" ? parent.height - Style.space(96) - height
           : Style.space(36) + headRoom
        radius: lcd ? Math.round(Style.space(3) * searchPill.fit)
                : paper ? Math.round(Style.space(5) * searchPill.fit)
                : (look === "glass" || hairline) ? height / 2
                : 0
        color: lcd ? Util.alpha(root.ink, lit ? 0.12 : 0.06)
               : look === "glass" ? root.inkAlpha(filled ? 0.22 : 0.13)
               : band ? Commons.Color.accent
               : paper ? "#ece8dd"
               : "transparent"
        border.width: (look === "glass" || lcd) ? settings.searchBorder
                      : (hairline || split) ? Math.max(1, settings.searchBorder)
                      : 0
        border.color: lcd ? Util.alpha(root.ink, 0.85)
                      : (hairline || split) ? root.inkAlpha(lit ? 0.9 : 0.5)
                      : root.inkAlpha(lit ? 0.5 : 0.24)
        Behavior on border.color { ColorAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        // Windows 98: a raised grey frame around a sunken white field.
        Item {
          visible: searchPill.win98
          anchors.fill: parent
          anchors.margins: -Style.space(5)
          Rectangle { anchors.fill: parent; color: "#000000" }
          Rectangle { width: parent.width - 1; height: parent.height - 1; color: "#dfdfdf" }
          Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height - 2; color: "#808080" }
          Rectangle { x: 1; y: 1; width: parent.width - 3; height: parent.height - 3; color: "#ffffff" }
          Rectangle { x: 2; y: 2; width: parent.width - 4; height: parent.height - 4; color: "#c0c0c0" }
        }
        Item {
          visible: searchPill.win98
          anchors.fill: parent
          Rectangle { anchors.fill: parent; color: "#ffffff" }
          Rectangle { width: parent.width - 1; height: parent.height - 1; color: "#808080" }
          Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height - 2; color: "#dfdfdf" }
          Rectangle { x: 1; y: 1; width: parent.width - 3; height: parent.height - 3; color: "#000000" }
          Rectangle { x: 2; y: 2; width: parent.width - 4; height: parent.height - 4; color: "#ffffff" }
        }

        // The plain look is just text, with or without a line under it; the
        // headline always sits on a thin rule.
        Rectangle {
          visible: (searchPill.plain && settings.searchUnderline) || searchPill.headline
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: searchPill.headline ? -Style.space(6) * searchPill.fit : 0
          height: searchPill.headline ? 1 : 2
          color: Util.alpha(root.ink, searchPill.lit ? 0.9 : 0.5)
        }

        // A soft sheen along the top edge, the way light catches glass.
        Rectangle {
          visible: searchPill.look === "glass"
          anchors.fill: parent
          radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: root.inkAlpha(0.16) }
            GradientStop { position: 0.5; color: root.inkAlpha(0.0) }
          }
        }

        // Paper: a small spaced-out label above the sheet.
        Text {
          visible: searchPill.paper
          textFormat: Text.PlainText
          x: Style.space(2)
          y: -searchPill.headRoom
          width: parent.width
          height: searchPill.headRoom
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: strings.t("search.prompt").toUpperCase()
          color: root.inkAlpha(0.75)
          font.family: Style.font.family
          font.letterSpacing: 1.5
          font.pixelSize: Math.round(searchPill.headRoom * 0.52)
        }

        // Split: the accent button the field is joined to.
        Rectangle {
          visible: searchPill.split
          anchors.right: parent.right
          width: searchPill.tailRoom
          height: parent.height
          color: Commons.Color.accent
        }
        // The arrow the headline, band and split looks end in. It opens the
        // first match, like Enter.
        Text {
          visible: searchPill.arrowed
          textFormat: Text.PlainText
          anchors.right: parent.right
          width: searchPill.tailRoom
          height: parent.height
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: "→"
          color: searchPill.split ? root.shade : searchPill.pillInk
          opacity: searchPill.filled || searchPill.split ? 1 : 0.6
          font.pixelSize: Math.round(Style.font.title * 1.2 * searchPill.fit)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.query !== "" && root.apps.length > 0) root.openApp(root.apps[0])
          }
        }

        Behavior on width {
          NumberAnimation { duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }
        Behavior on color { ColorAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        // Swallow clicks so they don't dismiss the launcher.
        MouseArea { anchors.fill: parent }

        // Right-click the search bar for its settings: the card opens on the
        // Search tab, or closes again if it is already there.
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: {
            if (root.settingsOpen && settingsCard.tab === "search") {
              root.settingsOpen = false
            } else {
              settingsCard.tab = "search"
              root.settingsOpen = true
            }
          }
        }

        // The looking glass, in the style, color and size the settings pick.
        Magnifier {
          id: magnifier
          visible: settings.glassStyle !== "off"
          x: Style.space(12) * searchPill.fit
          anchors.verticalCenter: parent.verticalCenter
          transformOrigin: Item.Left
          scale: searchPill.fit * settings.glassSize / 100
          style: settings.glassStyle
          color: searchPill.glassInk
          opacity: settings.glassTint === "ink" || root.lcd ? 0.7 : 1
        }

        // The word, rotating lines, the head scratcher, or the yellow LCD's
        // easter egg, as the settings pick.
        SearchPrompt {
          anchors.fill: searchInput
          anchors.leftMargin: caret.width + 3
          visible: !searchPill.filled
          mode: settings.searchPromptShown
          catalog: strings
          pikaSource: settings.pikaSource
          upper: searchPill.lcd
          ink: Util.alpha(searchPill.pillInk, 0.6)
          family: searchPill.face
          bold: searchPill.headline
          italic: searchPill.hairline || searchPill.band
          weight: searchPill.hairline ? Font.Light : searchPill.headline ? Font.Bold : Font.Normal
          capitalization: searchPill.headline ? Font.AllUppercase : Font.MixedCase
          pixelSize: searchPill.fontPx
        }

        // Always focused, so typing anywhere searches.
        TextInput {
          id: searchInput
          anchors.fill: parent
          // The text starts after the looking glass, however big it is.
          anchors.leftMargin: settings.glassStyle === "off" ? Style.space(16) * searchPill.fit
                              : (Style.space(12) + 16 * settings.glassSize / 100 + Style.space(10)) * searchPill.fit
          anchors.rightMargin: Style.space(36) * searchPill.fit + searchPill.tailRoom
          verticalAlignment: TextInput.AlignVCenter
          color: searchPill.pillInk
          selectionColor: searchPill.lcd ? Util.alpha(root.ink, 0.35) : searchPill.win98 ? "#000080"
                          : searchPill.band ? searchPill.pillInk : Commons.Color.accent
          selectedTextColor: searchPill.win98 ? "#ffffff" : searchPill.band ? Commons.Color.accent : searchPill.pillInk
          font.family: searchPill.face
          font.capitalization: searchPill.lcd || searchPill.headline ? Font.AllUppercase : Font.MixedCase
          font.bold: searchPill.headline
          font.pixelSize: searchPill.fontPx
          clip: true
          focus: true
          // The caret is drawn below, in the shape the settings pick.
          cursorDelegate: Item { width: 0; height: 0 }

          Rectangle {
            id: caret
            visible: searchInput.activeFocus
            readonly property real glyph: Math.round(searchInput.font.pixelSize * 0.58)
            readonly property real lineHeight: searchInput.cursorRectangle.height
            x: searchInput.cursorRectangle.x
            y: settings.searchCaret === "underscore" ? searchInput.cursorRectangle.y + lineHeight * 0.86
               : settings.searchCaret === "block" ? searchInput.cursorRectangle.y + lineHeight * 0.12
               : searchInput.cursorRectangle.y
            width: settings.searchCaret === "line" ? Math.max(1.5, searchInput.font.pixelSize * 0.09) : glyph
            height: settings.searchCaret === "underscore" ? Math.max(2, searchInput.font.pixelSize * 0.12)
                    : settings.searchCaret === "block" ? lineHeight * 0.76 : lineHeight
            color: searchPill.pillInk
            // Blinks unless the settings say solid, and stays lit while typing.
            Timer {
              id: blink
              running: caret.visible && settings.searchBlink
              repeat: true
              interval: 530
              onTriggered: caret.opacity = caret.opacity > 0.5 ? 0 : 1
              onRunningChanged: if (!running) caret.opacity = 1
            }
            Connections {
              target: searchInput
              function onTextChanged() { caret.opacity = 1; blink.restart() }
              function onCursorPositionChanged() { caret.opacity = 1; blink.restart() }
            }
          }

          // Arrows and PageUp/PageDown change page, Enter opens the first
          // match, Escape backs out one step at a time: the search, then the
          // settings card, then the launcher.
          //
          // Up and Down put the keyboard on an app. From then on the arrows
          // move between apps, Enter opens that one and Delete uninstalls it.
          Keys.onPressed: function(event) {
            if (root.uninstallEntry) {
              uninstallConfirm.handleKey(event)
              event.accepted = true
              return
            }
            var key = Util.readingKey(event)
            if (key === Qt.Key_PageDown || key === Qt.Key_PageUp) {
              var ahead = key === Qt.Key_PageDown ? 1 : -1
              root.cursorActive = false
              if (root.paged) root.goToPage(root.page + ahead)
              else root.scrollBy(ahead * smoothGrid.height * 0.9)
            } else if (key === Qt.Key_Right || key === Qt.Key_Left) {
              var onward = key === Qt.Key_Right ? 1 : -1
              // With no app selected, the arrows turn toward the page on that
              // side when pages run left and right, and otherwise step through.
              if (root.cursorActive || !root.paged) root.select(onward)
              else if (root.horizontal) root.goToPage(root.page + (event.key === Qt.Key_Right ? 1 : -1) * root.hSign)
              else root.goToPage(root.page + onward)
            } else if (key === Qt.Key_Down) {
              root.select(root.cols)
            } else if (key === Qt.Key_Up) {
              root.select(-root.cols)
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
              if (root.cursorActive) root.openApp(root.apps[root.selectedIndex])
              else if (root.query !== "" && root.apps.length > 0) root.openApp(root.apps[0])
            } else if (key === Qt.Key_Delete && root.cursorActive) {
              root.requestUninstall(root.apps[root.selectedIndex])
            } else if (key === Qt.Key_Escape) {
              if (root.menuEntry) root.menuEntry = null
              else if (text !== "") clear()
              else if (root.settingsOpen) root.settingsOpen = false
              else root.dismiss()
            } else {
              return
            }
            event.accepted = true
          }
        }

        // Clear button.
        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10) * searchPill.fit + searchPill.tailRoom
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(Style.space(18) * searchPill.fit)
          height: width
          radius: searchPill.win98 ? 0 : width / 2
          color: searchPill.win98 ? "#c0c0c0" : searchPill.hairline ? "transparent" : Util.alpha(searchPill.pillInk, 0.2)
          border.width: searchPill.win98 || searchPill.hairline ? 1 : 0
          border.color: searchPill.win98 ? "#000000" : searchPill.pillInk
          visible: searchPill.filled
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "✕"
            color: searchPill.pillInk
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: searchInput.clear()
          }
        }

        // ---- Edit mode: with the card open and Move and resize switched on ---------------------
        Rectangle {
          visible: root.settingsOpen && settings.searchArrange
          anchors.fill: parent
          anchors.margins: -Style.space(5)
          radius: searchPill.radius > 0 ? searchPill.radius + Style.space(5) : 0
          color: "transparent"
          border.width: 1
          border.color: root.lcd ? root.ink : Commons.Color.accent
        }
        // Drag anywhere on the bar to move it.
        MouseArea {
          id: moveArea
          visible: root.settingsOpen && settings.searchArrange
          enabled: root.settingsOpen && settings.searchArrange
          anchors.fill: parent
          cursorShape: Qt.SizeAllCursor
          property point grab
          property real startX
          property real startY
          onPressed: function(mouse) {
            grab = mapToItem(stage, mouse.x, mouse.y)
            startX = searchPill.x
            startY = searchPill.y
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var at = mapToItem(stage, mouse.x, mouse.y)
            var nx = Math.max(0, Math.min(stage.width - searchPill.width, startX + at.x - grab.x))
            var ny = Math.max(0, Math.min(stage.height - searchPill.height, startY + at.y - grab.y))
            // Snaps to the middle of the screen.
            if (Math.abs(nx + searchPill.width / 2 - stage.width / 2) < Style.space(12)) nx = (stage.width - searchPill.width) / 2
            settings.preview("searchPlace", "custom")
            settings.preview("searchX", (nx + searchPill.width / 2) / stage.width)
            settings.preview("searchY", (ny + searchPill.height / 2) / stage.height)
          }
          onReleased: settings.save()
        }
        // Drag the corner to resize it.
        Rectangle {
          visible: root.settingsOpen && settings.searchArrange
          width: Style.space(12)
          height: width
          radius: 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 1
          color: root.lcd ? root.ink : Commons.Color.accent
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            cursorShape: Qt.SizeFDiagCursor
            property real grabX
            property real startSize
            property real startWidth
            onPressed: function(mouse) {
              grabX = mapToItem(stage, mouse.x, mouse.y).x
              startSize = Math.round(searchPill.fit * 100)
              startWidth = searchPill.width
            }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              var dx = mapToItem(stage, mouse.x, mouse.y).x - grabX
              settings.preview("searchSize", Math.round(startSize * (startWidth + dx) / startWidth))
            }
            onReleased: settings.save()
          }
        }
      }

      // ---- Sort box, beside the search bar when the settings ask for it ------
      Rectangle {
        id: sortBox
        visible: settings.sortBox
        anchors.verticalCenter: searchPill.verticalCenter
        // By x so it stays on the far side of the bar in every language.
        x: searchPill.x + searchPill.width + Style.space(12)
        width: sortRow.width + Style.space(8)
        height: Style.space(38)
        radius: height / 2
        color: root.inkAlpha(0.16)
        border.width: settings.searchBorder
        border.color: root.inkAlpha(0.22)

        // Swallow clicks so they don't dismiss the launcher.
        MouseArea { anchors.fill: parent }

        Row {
          id: sortRow
          anchors.centerIn: parent
          spacing: Style.space(2)

          Repeater {
            model: ["alpha", "used"]
            delegate: Rectangle {
              id: sortChoice
              required property string modelData
              readonly property bool chosen: settings.sortBy === modelData
              width: sortLabel.implicitWidth + Style.space(24)
              height: sortBox.height - Style.space(8)
              radius: height / 2
              color: chosen ? root.inkAlpha(0.3) : sortHit.containsMouse ? root.inkAlpha(0.12) : "transparent"
              Behavior on color { ColorAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

              Text {
                id: sortLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: sortChoice.modelData === "used" ? strings.t("sort.used") : strings.t("sort.alpha")
                color: root.inkAlpha(sortChoice.chosen ? 1 : 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: sortHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: settings.set("sortBy", sortChoice.modelData)
              }
            }
          }
        }
      }

      // ---- Settings button, in the top corner --------------------------------
      Rectangle {
        id: gear
        // Hidden unless the settings ask for it; the dock's menu opens settings too.
        anchors.top: parent.top
        anchors.topMargin: Style.space(36)
        x: parent.width - width - Style.space(20)
        width: Style.space(38)
        height: width
        radius: width / 2
        visible: settings.showGear && !root.settingsOpen
        color: root.inkAlpha(gearHit.containsMouse ? 0.25 : 0.12)
        border.width: 1
        border.color: root.inkAlpha(0.2)
        opacity: gearHit.containsMouse ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "⚙"
          color: root.ink
          font.pixelSize: Style.font.heading
        }
        MouseArea {
          id: gearHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.settingsOpen = true
        }
      }

      // ---- The grid -----------------------------------------------------------
      Item {
        id: viewport
        // The grid keeps its place wherever the search bar is dragged to.
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: settings.searchPlace === "top" ? searchPill.height + searchPill.headRoom + Style.space(52) : Style.space(60)
        anchors.bottomMargin: Style.space(78) + (settings.searchPlace === "bottom" ? searchPill.height + searchPill.headRoom + Style.space(20) : 0)
        // Centered in what the settings card leaves free. Placed by x so it
        // stays clear of the card in a right-to-left layout too.
        x: Math.round((parent.width - panel.reserve - width) / 2)
        width: Math.min(parent.width - panel.reserve - Style.space(96),
                        root.cols * (root.iconSize + Style.space(134)) + Style.space(40))
        clip: true

        readonly property int columnGap: Style.space(24)
        readonly property int rowGap: Style.space(32)
        readonly property real gridWidth: width - Style.space(40)
        readonly property real gridHeight: Math.min(height - Style.space(20),
                                                    root.rows * (root.iconSize + root.labelRoom + Style.space(62)))
        readonly property real cellWidth: (gridWidth - (root.cols - 1) * columnGap) / root.cols
        readonly property real cellHeight: (gridHeight - (root.rows - 1) * rowGap) / root.rows
        // Icons shrink rather than overlap when the screen cannot fit them.
        readonly property real iconDraw: Math.max(Style.space(24),
          Math.min(root.iconSize, cellWidth - Style.space(8), cellHeight - root.labelRoom - Style.space(8)))

        // Paged: one slide per page, laid out along the axis the pages turn on,
        // so the next page comes in from the side the settings name.
        Item {
          id: slider
          visible: root.paged
          width: parent.width
          height: parent.height
          x: root.horizontal ? -root.hSign * root.page * viewport.width : 0
          y: root.horizontal ? 0 : -root.vSign * root.page * viewport.height
          // No animation while hidden, so it reopens already on its page.
          Behavior on x {
            enabled: root.opened
            NumberAnimation { duration: Style.duration(280); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }
          Behavior on y {
            enabled: root.opened
            NumberAnimation { duration: Style.duration(280); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }

          Repeater {
            model: root.paged ? root.pageCount : 0

            // One page of the grid. Only the current page and its neighbours
            // are built, so a long app list costs no more than a short one.
            delegate: Item {
              id: pageSlide
              required property int index
              x: root.horizontal ? root.hSign * index * viewport.width : 0
              y: root.horizontal ? 0 : root.vSign * index * viewport.height
              width: viewport.width
              height: viewport.height

              Loader {
                anchors.centerIn: parent
                active: Math.abs(pageSlide.index - root.page) <= 1
                sourceComponent: Grid {
                  columns: root.cols
                  columnSpacing: viewport.columnGap
                  rowSpacing: viewport.rowGap

                  Repeater {
                    model: root.apps.slice(pageSlide.index * root.pageSize,
                                           (pageSlide.index + 1) * root.pageSize)

                    delegate: AppCell {
                      required property var modelData
                      required property int index
                      entry: modelData
                      appIndex: pageSlide.index * root.pageSize + index
                      live: pageSlide.index === root.page
                    }
                  }
                }
              }
            }
          }
        }

        // Smooth: every app on one grid that scrolls like a web page. The
        // wheel drives it through root.scrollBy(), which the sensitivity
        // setting scales.
        GridView {
          id: smoothGrid
          visible: !root.paged
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.cols * cellWidth
          height: parent.height
          cellWidth: viewport.cellWidth + viewport.columnGap
          cellHeight: viewport.cellHeight + viewport.rowGap
          model: root.paged ? [] : root.apps
          interactive: false
          boundsBehavior: Flickable.StopAtBounds
          cacheBuffer: Math.max(0, height)

          Behavior on contentY {
            enabled: root.opened
            NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
          }

          delegate: Item {
            id: smoothCell
            required property var modelData
            required property int index
            width: smoothGrid.cellWidth
            height: smoothGrid.cellHeight

            AppCell {
              anchors.centerIn: parent
              entry: smoothCell.modelData
              appIndex: smoothCell.index
            }
          }
        }

        // Shown when the search matches nothing: a shrug and a quip, a new
        // one each time the matches run out.
        Column {
          id: nothingFound
          anchors.centerIn: parent
          width: parent.width - Style.space(40)
          spacing: Style.space(16)
          visible: root.apps.length === 0
          property int pick: 0
          // The search as typed, cut short so a long one cannot fill the screen.
          readonly property string asked: root.query.length > 24 ? root.query.slice(0, 24) + "…" : root.query
          readonly property var quips: [strings.t("search.empty.1"), strings.t("search.empty.2"), strings.t("search.empty.3"),
                                        strings.t("search.empty.4"), strings.t("search.empty.5"), strings.t("search.empty.6"),
                                        strings.t("search.empty.7"), strings.t("search.empty.8")]
          onVisibleChanged: if (visible) pick = Math.floor(Math.random() * quips.length)
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "¯\\_( ͡° ͜ʖ ͡°)_/¯"
            color: root.inkAlpha(0.8)
            font.family: "Noto Sans"
            font.pixelSize: Style.font.displayLarge * 1.3
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: nothingFound.quips[nothingFound.pick].replace("%1", nothingFound.asked)
            color: root.inkAlpha(0.7)
            font.family: root.lcd ? "monospace" : Style.font.family
            font.pixelSize: Style.font.heading
          }
        }
      }

      // ---- One app: its icon and name --------------------------------------
      component AppCell: Item {
        id: cell
        // The app, where it falls among all the apps, and whether it takes
        // the pointer: a page out of view is built but must not.
        property var entry: null
        property int appIndex: 0
        property bool live: true
        readonly property bool launching: !!entry && root.launchingId === entry.id
        // A press that moves is a drag toward the dock, not a click.
        property bool moved: false
        property point pressPoint
        width: viewport.cellWidth
        height: viewport.cellHeight

        // Where the keyboard is.
        Rectangle {
          anchors.fill: appItem
          anchors.margins: -Style.space(8)
          radius: Style.cornerRadius * 1.5
          visible: root.cursorActive && cell.appIndex === root.selectedIndex
          gradient: Gradient {
            GradientStop { position: 0.0; color: root.inkAlpha(0.2) }
            GradientStop { position: 1.0; color: root.inkAlpha(0.08) }
          }
          border.width: 1
          border.color: root.inkAlpha(0.34)
        }

        Column {
          id: appItem
          anchors.centerIn: parent
          width: Math.max(viewport.iconDraw, cell.width - Style.space(8))
          spacing: root.labelGap

          // The icon zooms toward the viewer and fades as its app starts.
          scale: cell.launching ? 1.22 : 1
          opacity: cell.launching ? 0 : 1
          Behavior on scale {
            enabled: root.opened
            NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }
          Behavior on opacity {
            enabled: root.opened
            NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
          }

          Item {
            id: iconBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: viewport.iconDraw
            height: viewport.iconDraw
            scale: hit.pressed ? 0.96 : hit.containsMouse ? 1.1 : 1
            Behavior on scale {
              NumberAnimation {
                duration: Style.duration(hit.pressed ? 80 : 180)
                easing.type: Easing.Bezier
                easing.bezierCurve: Style.easeOut
              }
            }

            Image {
              id: icon
              anchors.fill: parent
              source: root.appLibrary ? root.appLibrary.iconSource(cell.entry.icon) : ""
              sourceSize.width: 256
              sourceSize.height: 256
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              mipmap: true
              visible: false
              // An app whose own icon file is missing still gets a tile.
              onStatusChanged: if (status === Image.Error)
                source = Quickshell.iconPath("application-x-executable", true)
            }
            MultiEffect {
              anchors.fill: icon
              source: icon
              // On the LCD the icons are drawn in the screen's own two tones:
              // white becomes the screen's green and black stays dark, with
              // the hard offset shadow LCD pixels cast on the glass behind.
              contrast: root.lcd ? 0.35 : 0
              brightness: root.lcd ? -0.06 : 0
              colorization: root.lcd ? 1 : 0
              // Tinted with whichever of the screen and ink is lighter, so a
              // dark screen gets light icons rather than invisible ones.
              colorizationColor: root.ink.hslLightness > root.shade.hslLightness ? root.ink : root.shade
              shadowEnabled: !root.lcd || settings.lcdShadow > 0
              shadowColor: root.lcd ? root.ink : "black"
              shadowOpacity: root.lcd ? 0.28 : hit.containsMouse ? 0.55 : 0.45
              shadowBlur: root.lcd ? 0 : hit.containsMouse ? 0.75 : 0.55
              shadowHorizontalOffset: root.lcd ? settings.lcdShadow : 0
              shadowVerticalOffset: root.lcd ? settings.lcdShadow : hit.containsMouse ? 14 : 8
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: settings.showNames
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: root.ink
            font.family: root.lcd ? "monospace" : Style.font.family
            font.pixelSize: root.labelSize
            font.weight: root.lcd ? Font.Bold : Font.Medium
            font.capitalization: root.lcd ? Font.AllUppercase : Font.MixedCase
            style: root.lcd ? Text.Normal : Text.Raised
            styleColor: Util.alpha(root.shade, 0.8)
            text: root.appLibrary ? root.appLibrary.entryName(cell.entry) : ""
          }
        }

        MouseArea {
          id: hit
          anchors.fill: appItem
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          enabled: cell.live
          onPressed: function(event) {
            cell.moved = false
            cell.pressPoint = Qt.point(event.x, event.y)
          }
          // The keyboard's app follows the pointer when the pointer
          // moves, not when a page slides under it.
          onPositionChanged: function(event) {
            if (!pressedButtons && !root.dragging) root.selectedIndex = cell.appIndex
            if (!(pressedButtons & Qt.LeftButton)) return
            if (!cell.moved && Math.hypot(event.x - cell.pressPoint.x, event.y - cell.pressPoint.y) > Style.space(4)) cell.moved = true
            if (cell.moved) root.dragTo(cell.entry, hit.mapToItem(panel.contentItem, event.x, event.y))
          }
          onReleased: function(event) {
            if (root.dragging && event.button === Qt.LeftButton) root.dropDrag()
          }
          onCanceled: if (root.dragging) root.dismiss()
          onClicked: function(event) {
            if (cell.moved) return
            if (event.button === Qt.RightButton) {
              root.openMenu(cell.entry, hit.mapToItem(panel.contentItem, event.x, event.y))
              return
            }
            root.menuEntry = null
            root.openApp(cell.entry)
          }
        }
      }

      // ---- Page arrows ---------------------------------------------------------
      // One per side; the two on the axis the pages turn on show. `side` is
      // where the arrow sits and points.
      component NavArrow: Item {
        id: arrow
        property string side: "right"
        readonly property bool alongX: side === "left" || side === "right"
        readonly property int step: side === "left" ? -root.hSign : side === "right" ? root.hSign
                                  : side === "top" ? -root.vSign : root.vSign
        readonly property int target: root.page + step
        // "edge" is a bar of color flush against the screen's edge, the
        // length of its side, that widens under the pointer to show a long
        // arrow; "chevron" has no backing.
        readonly property bool edge: settings.arrows === "edge"
        readonly property bool plain: settings.arrows === "chevron"
        readonly property int knob: Style.space(46)
        // The edge bar: the strip it takes under the pointer, and at rest.
        readonly property int reach: alongX ? Style.space(64) : Style.space(30)
        readonly property int rest: Style.space(8)
        readonly property color barColor: root.lcd ? root.ink : Commons.Color.accent

        visible: root.paged && settings.arrows !== "off" && alongX === root.horizontal
                 && target >= 0 && target < root.pageCount
        width: !edge ? knob : alongX ? reach : parent.width - panel.reserve
        height: !edge ? knob : alongX ? parent.height : reach
        // By x rather than anchors so each arrow stays on the side it points
        // to in every language.
        x: edge ? (side === "right" ? parent.width - panel.reserve - width : 0)
         : side === "left" ? Style.space(20)
         : side === "right" ? parent.width - panel.reserve - width - Style.space(20)
         : viewport.x + (viewport.width - width) / 2
        y: edge ? (side === "bottom" ? parent.height - height : 0)
         : side === "top" ? viewport.y
         : side === "bottom" ? viewport.y + viewport.height - height
         : viewport.y + (viewport.height - height) / 2
        opacity: edge || arrowHit.containsMouse ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        // The edge bar, growing in from its side of the screen.
        Rectangle {
          id: bar
          visible: arrow.edge
          readonly property real thick: arrowHit.containsMouse ? arrow.reach : arrow.rest
          width: arrow.alongX ? thick : parent.width
          height: arrow.alongX ? parent.height : thick
          x: arrow.side === "right" ? parent.width - width : 0
          y: arrow.side === "bottom" ? parent.height - height : 0
          color: Util.alpha(arrow.barColor, arrowHit.containsMouse ? 1 : 0.6)
          Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

          // A long thin arrow, drawn pointing right and turned to face the
          // bar's side, with the page it leads to written beside it.
          Item {
            anchors.centerIn: parent
            width: Style.space(34)
            height: Style.space(18)
            opacity: arrowHit.containsMouse ? 1 : 0
            rotation: arrow.side === "bottom" ? 90 : arrow.side === "left" ? 180 : arrow.side === "top" ? 270 : 0
            scale: arrow.alongX ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
            Rectangle { y: parent.height / 2 - 1; width: parent.width; height: 2; color: root.shade }
            Repeater {
              model: [40, -40]
              Rectangle {
                required property int modelData
                x: parent.width - width
                y: parent.height / 2 - 1
                width: Style.space(13)
                height: 2
                color: root.shade
                rotation: modelData
                transformOrigin: Item.Right
              }
            }
          }
          Text {
            visible: arrow.alongX
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + Style.space(22)
            opacity: arrowHit.containsMouse ? 1 : 0
            text: Commons.I18n.formatNumber(arrow.target + 1, 0)
            color: root.shade
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.body
            Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
          }
        }

        Rectangle {
          anchors.fill: parent
          visible: !arrow.plain && !arrow.edge
          radius: width / 2
          color: root.inkAlpha(arrowHit.containsMouse ? 0.25 : 0.12)
          border.width: 1
          border.color: root.inkAlpha(0.2)
          scale: arrowHit.containsMouse ? 1.1 : 1
          Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
        }

        // Chevron: two strokes meeting at a point, drawn pointing right and
        // turned to face the arrow's side.
        Item {
          visible: !arrow.edge
          anchors.centerIn: parent
          width: 12
          height: 12
          scale: arrow.plain ? 1.8 : 1
          rotation: arrow.side === "bottom" ? 90 : arrow.side === "left" ? 180 : arrow.side === "top" ? 270 : 0

          Repeater {
            model: [45, -45]
            Rectangle {
              required property int modelData
              x: 1
              y: 4.75
              width: 10
              height: 2.5
              radius: 1.25
              color: root.ink
              rotation: modelData
              transformOrigin: Item.Right
            }
          }
        }

        MouseArea {
          id: arrowHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.goToPage(arrow.target)
        }
      }

      NavArrow { side: "left" }
      NavArrow { side: "right" }
      NavArrow { side: "top" }
      NavArrow { side: "bottom" }

      // ---- Page indicator ------------------------------------------------------
      // A row under the grid, or a column beside it when pages turn up and
      // down. "pill" stretches the current page's dot into a glowing pill,
      // "dots" keeps them all round, "numbers" writes "2 / 4".
      Item {
        id: dots
        readonly property bool numbers: settings.indicator === "numbers"
        readonly property bool pill: settings.indicator === "pill"
        readonly property bool sideways: !root.horizontal && !numbers

        visible: root.paged && settings.indicator !== "off"
        width: numbers ? count.implicitWidth : marks.width
        height: numbers ? count.implicitHeight : marks.height
        x: sideways ? parent.width - panel.reserve - width - Style.space(34)
                    : viewport.x + (viewport.width - width) / 2
        y: sideways ? viewport.y + (viewport.height - height) / 2
                    : parent.height - Style.space(48) - height

        Text {
          id: count
          visible: dots.numbers
          textFormat: Text.PlainText
          text: strings.t("pages.count").arg(Commons.I18n.formatNumber(root.page + 1, 0))
                                        .arg(Commons.I18n.formatNumber(Math.max(1, root.pageCount), 0))
          color: root.inkAlpha(0.8)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Grid {
          id: marks
          visible: !dots.numbers
          columns: dots.sideways ? 1 : Math.max(1, root.pageCount)
          spacing: 10

          Repeater {
            model: dots.numbers ? 0 : root.pageCount
            delegate: Item {
              id: dot
              required property int index
              readonly property bool active: index === root.page
              readonly property int along: active && dots.pill ? 22 : 8
              width: dots.sideways ? 8 : along
              height: dots.sideways ? along : 8
              Behavior on width {
                NumberAnimation { duration: Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
              }
              Behavior on height {
                NumberAnimation { duration: Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
              }

              Rectangle {
                anchors.fill: parent
                radius: 4
                color: dot.active ? root.ink : root.inkAlpha(dotHit.containsMouse ? 0.75 : 0.38)
                scale: !dot.active && dotHit.containsMouse ? 1.25 : 1
                Behavior on color { ColorAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
                layer.enabled: dot.active && dots.pill
                layer.effect: MultiEffect {
                  shadowEnabled: true
                  shadowColor: root.ink
                  shadowOpacity: 0.75
                  shadowBlur: 0.5
                }
              }
              MouseArea {
                id: dotHit
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToPage(dot.index)
              }
            }
          }
        }
      }

      // ---- Settings card, down the side the gear sits on ---------------------
      SettingsCard {
        id: settingsCard
        visible: root.settingsOpen
        // By x, like the grid beside it, so the two never swap sides.
        x: parent.width - width - Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        store: settings
        catalog: strings
        ink: root.ink
        shade: root.shade
        lcd: root.lcd
        maxHeight: parent.height - Style.space(80)
        onCloseRequested: root.settingsOpen = false
      }
    }

    // The dragged app's icon, under the pointer.
    Image {
      visible: root.dragging && !!root.dragEntry
      x: root.dragPoint.x - width / 2
      y: root.dragPoint.y - height / 2
      width: viewport.iconDraw
      height: viewport.iconDraw
      sourceSize: Qt.size(256, 256)
      source: root.dragEntry && root.appLibrary ? root.appLibrary.iconSource(root.dragEntry.icon) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    // Right-click on an app: open it, keep it in the dock or take it out, or
    // uninstall it.
    BorderSurface {
      id: menu

      readonly property var entry: root.menuEntry
      readonly property bool pinned: !!entry && !!root.dock && root.dock.isPinned(String(entry.id || ""))

      visible: !!entry && !root.dragging
      width: Math.max(Style.space(160), menuColumn.implicitWidth) + padding * 2
      height: menuColumn.implicitHeight + padding * 2
      // Opens along the reading direction from the pointer.
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(root.menuPoint.x, panel.width - width - Style.gapsOut)
      y: Math.min(root.menuPoint.y, panel.height - height - Style.gapsOut)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm

      Column {
        id: menuColumn
        x: menu.contentLeftInset
        y: menu.contentTopInset
        width: menu.width - menu.contentLeftInset - menu.contentRightInset

        MenuRow {
          text: strings.t("dock.open")
          onTriggered: {
            var entry = menu.entry
            root.menuEntry = null
            root.openApp(entry)
          }
        }

        MenuRow {
          visible: !!root.dock
          text: menu.pinned ? strings.t("dock.removeFromDock") : strings.t("dock.keepInDock")
          onTriggered: {
            if (root.dock && menu.entry) root.dock.setPinned(String(menu.entry.id || ""), !menu.pinned)
            root.menuEntry = null
          }
        }

        MenuRow {
          text: strings.t("dock.uninstall")
          onTriggered: root.requestUninstall(menu.entry)
        }
      }
    }

    component MenuRow: Rectangle {
      id: row

      property string text: ""
      signal triggered()

      width: parent ? parent.width : 0
      height: visible ? Style.spacing.popupRowHeight : 0
      radius: Style.cornerRadius
      color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.controlPaddingX
        textFormat: Text.PlainText
        text: row.text
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.triggered()
      }
    }

    // Asks before uninstalling. The dialog draws the app's name as plain text.
    ConfirmDialog {
      id: uninstallConfirm

      anchors.fill: parent
      opened: !!root.uninstallEntry
      z: 10
      message: strings.t("common.uninstallConfirm").arg(root.uninstallEntry && root.appLibrary ? root.appLibrary.entryName(root.uninstallEntry) : "")
      confirmText: strings.t("common.uninstall")
      background: Commons.Color.popups.background
      foreground: Commons.Color.popups.text
      onCanceled: root.uninstallEntry = null
      onConfirmed: root.confirmUninstall()
    }
  }
}
