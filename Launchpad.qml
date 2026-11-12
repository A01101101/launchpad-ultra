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

  // Colors: a dark glass with white ink by default, or the theme's own
  // background and text when "follow theme" is on.
  readonly property color ink: settings.followTheme ? Commons.Color.foreground : "white"
  readonly property color shade: settings.followTheme ? Commons.Color.background : Qt.rgba(12 / 255, 14 / 255, 22 / 255, 1)
  function inkAlpha(opacity) { return Util.alpha(root.ink, opacity) }

  onQueryChanged: {
    page = 0
    selectedIndex = 0
    cursorActive = false
    menuEntry = null
    rebuild()
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
    if (appLibrary) appLibrary.refreshIcons()
    rebuild()
    goToPage(startPage)
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
  function rebuild() {
    var found = appLibrary ? appLibrary.sortedEntries(query) : []
    apps = found.map(function(row) { return row.entry })
    selectedIndex = Math.max(0, Math.min(selectedIndex, apps.length - 1))
    goToPage(page)
  }

  // Moves the keyboard's app, turning the page to keep it in view.
  function select(delta) {
    if (apps.length === 0) return
    selectedIndex = cursorActive ? Math.max(0, Math.min(apps.length - 1, selectedIndex + delta))
                                 : page * pageSize
    cursorActive = true
    goToPage(Math.floor(selectedIndex / pageSize))
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
    appLibrary.launch(entry.id, appLibrary.entryName(entry))
    closeTimer.start()
  }

  Timer { id: closeTimer; interval: Style.duration(200); onTriggered: root.dismiss() }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.rebuild() }
  }

  LauncherSettings { id: settings }
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

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
        anchors.fill: parent
        color: Util.alpha(root.shade, settings.backdrop)
      }

      // Clicking empty space dismisses the launcher.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
          if (root.menuEntry) root.menuEntry = null
          else root.dismiss()
        }
      }

      // Mouse wheel and touchpad swipes turn one page per gesture.
      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          if (wheelPause.running) return
          var dx = event.angleDelta.x, dy = event.angleDelta.y
          var d = Math.abs(dx) > Math.abs(dy) ? dx : dy
          if (Math.abs(d) < 25) return
          root.goToPage(root.page + (d < 0 ? 1 : -1))
          wheelPause.start()
        }
      }
      // One page turn per gesture, however long the swipe keeps scrolling.
      Timer { id: wheelPause; interval: 320 }

      // ---- Search pill -------------------------------------------------------
      Rectangle {
        id: searchPill
        readonly property bool filled: searchInput.text !== ""
        anchors.top: parent.top
        anchors.topMargin: Style.space(36)
        anchors.horizontalCenter: viewport.horizontalCenter
        width: Style.space(filled ? 440 : 340)
        height: Style.space(38)
        radius: height / 2
        color: root.inkAlpha(filled ? 0.26 : 0.16)
        border.width: 1
        border.color: root.inkAlpha(filled ? 0.45 : 0.22)

        Behavior on width {
          NumberAnimation { duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }
        Behavior on color { ColorAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        // Swallow clicks so they don't dismiss the launcher.
        MouseArea { anchors.fill: parent }

        // Magnifier glyph.
        Item {
          x: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: 16
          height: 16
          opacity: 0.7
          Rectangle {
            width: 12; height: 12; radius: 6
            color: "transparent"
            border.width: 1.5
            border.color: root.ink
          }
          Rectangle {
            x: 9.5; y: 11.5
            width: 6; height: 1.5; radius: 1
            color: root.ink
            rotation: 45
            transformOrigin: Item.Left
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: searchInput
          verticalAlignment: Text.AlignVCenter
          text: strings.t("search.placeholder")
          color: root.inkAlpha(0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          visible: !searchPill.filled
        }

        // Always focused, so typing anywhere searches.
        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: Style.space(38)
          anchors.rightMargin: Style.space(36)
          verticalAlignment: TextInput.AlignVCenter
          color: root.ink
          selectionColor: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          clip: true
          focus: true

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
            if (key === Qt.Key_PageDown) {
              root.cursorActive = false
              root.goToPage(root.page + 1)
            } else if (key === Qt.Key_PageUp) {
              root.cursorActive = false
              root.goToPage(root.page - 1)
            } else if (key === Qt.Key_Right) {
              if (root.cursorActive) root.select(1)
              else root.goToPage(root.page + 1)
            } else if (key === Qt.Key_Left) {
              if (root.cursorActive) root.select(-1)
              else root.goToPage(root.page - 1)
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
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          height: width
          radius: width / 2
          color: root.inkAlpha(0.25)
          visible: searchPill.filled
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "✕"
            color: root.ink
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: searchInput.clear()
          }
        }
      }

      // ---- Settings button, in the top corner --------------------------------
      Rectangle {
        id: gear
        anchors.top: parent.top
        anchors.topMargin: Style.space(36)
        x: parent.width - width - Style.space(20)
        width: Style.space(38)
        height: width
        radius: width / 2
        visible: !root.settingsOpen
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

      // ---- Pages -------------------------------------------------------------
      Item {
        id: viewport
        anchors.top: searchPill.bottom
        anchors.bottom: dots.top
        anchors.topMargin: Style.space(16)
        anchors.bottomMargin: Style.space(22)
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

        Row {
          id: slider
          height: parent.height
          // Pages run the other way in a right-to-left layout.
          x: (Commons.I18n.rightToLeft ? root.page - (root.pageCount - 1) : -root.page) * viewport.width
          // No animation while hidden, so it reopens already on its page.
          Behavior on x {
            enabled: root.opened
            NumberAnimation { duration: Style.duration(280); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }

          Repeater {
            model: root.pageCount

            // One page of the grid. Only the current page and its neighbours
            // are built, so a long app list costs no more than a short one.
            delegate: Item {
              id: pageSlide
              required property int index
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

                    delegate: Item {
                      id: cell
                      required property var modelData
                      required property int index
                      readonly property int appIndex: pageSlide.index * root.pageSize + index
                      readonly property bool launching: root.launchingId === modelData.id
                      // A press that moves is a drag toward the dock, not a click.
                      property bool moved: false
                      property point pressPoint
                      width: viewport.cellWidth
                      height: viewport.cellHeight

                      // Where the keyboard is.
                      Rectangle {
                        anchors.fill: appItem
                        anchors.margins: -Style.space(8)
                        radius: Style.cornerRadius
                        visible: root.cursorActive && cell.appIndex === root.selectedIndex
                        color: root.inkAlpha(0.14)
                        border.width: 1
                        border.color: root.inkAlpha(0.3)
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
                            source: root.appLibrary ? root.appLibrary.iconSource(cell.modelData.icon) : ""
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
                            shadowEnabled: true
                            shadowColor: "black"
                            shadowOpacity: hit.containsMouse ? 0.55 : 0.45
                            shadowBlur: hit.containsMouse ? 0.75 : 0.55
                            shadowVerticalOffset: hit.containsMouse ? 14 : 8
                          }
                        }

                        Text {
                          textFormat: Text.PlainText
                          visible: settings.showNames
                          width: parent.width
                          horizontalAlignment: Text.AlignHCenter
                          elide: Text.ElideRight
                          color: root.ink
                          font.family: Style.font.family
                          font.pixelSize: root.labelSize
                          font.weight: Font.Medium
                          style: Text.Raised
                          styleColor: Util.alpha(root.shade, 0.8)
                          text: root.appLibrary ? root.appLibrary.entryName(cell.modelData) : ""
                        }
                      }

                      MouseArea {
                        id: hit
                        anchors.fill: appItem
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onContainsMouseChanged: if (containsMouse && !root.dragging) root.selectedIndex = cell.appIndex
                        onPressed: function(event) {
                          cell.moved = false
                          cell.pressPoint = Qt.point(event.x, event.y)
                        }
                        onPositionChanged: function(event) {
                          if (!(pressedButtons & Qt.LeftButton)) return
                          if (!cell.moved && Math.hypot(event.x - cell.pressPoint.x, event.y - cell.pressPoint.y) > Style.space(4)) cell.moved = true
                          if (cell.moved) root.dragTo(cell.modelData, hit.mapToItem(panel.contentItem, event.x, event.y))
                        }
                        onReleased: function(event) {
                          if (root.dragging && event.button === Qt.LeftButton) root.dropDrag()
                        }
                        onCanceled: if (root.dragging) root.dismiss()
                        onClicked: function(event) {
                          if (cell.moved) return
                          if (event.button === Qt.RightButton) {
                            root.openMenu(cell.modelData, hit.mapToItem(panel.contentItem, event.x, event.y))
                            return
                          }
                          root.menuEntry = null
                          root.openApp(cell.modelData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // Shown when the search matches nothing.
        Column {
          anchors.centerIn: parent
          spacing: Style.space(12)
          visible: root.apps.length === 0
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "⌕"
            color: root.inkAlpha(0.6)
            font.pixelSize: Style.font.displayLarge * 1.7
          }
          Text {
            textFormat: Text.PlainText
            text: strings.t("search.empty")
            color: root.inkAlpha(0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
          }
        }
      }

      // ---- Previous / next arrows --------------------------------------------
      // `direction` is where the arrow sits and points: -1 left, 1 right.
      component NavArrow: Rectangle {
        id: arrow
        property int direction: 1
        signal clicked()
        width: 46
        height: 46
        radius: 23
        anchors.verticalCenter: parent.verticalCenter
        color: root.inkAlpha(arrowHit.containsMouse ? 0.25 : 0.12)
        border.width: 1
        border.color: root.inkAlpha(0.2)
        opacity: arrowHit.containsMouse ? 1 : 0.55
        scale: arrowHit.containsMouse ? 1.1 : 1
        Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        // Chevron: two strokes meeting at a point. Kept out of the mirroring a
        // right-to-left layout applies, since the arrow itself is placed by side.
        Repeater {
          model: [-45, 45]
          Rectangle {
            required property int modelData
            LayoutMirroring.enabled: false
            x: 23 + arrow.direction * 4 - (arrow.direction > 0 ? width : 0)
            y: 22
            width: 10
            height: 2.5
            radius: 1.25
            color: root.ink
            rotation: modelData
            transformOrigin: arrow.direction > 0 ? Item.Right : Item.Left
          }
        }

        MouseArea {
          id: arrowHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: arrow.clicked()
        }
      }

      // Placed by x rather than anchors so each arrow stays on the side it
      // points to in every language; which page it turns to follows the layout.
      NavArrow {
        readonly property int step: Commons.I18n.rightToLeft ? 1 : -1
        x: Style.space(20)
        direction: -1
        visible: root.page + step >= 0 && root.page + step < root.pageCount
        onClicked: root.goToPage(root.page + step)
      }
      NavArrow {
        readonly property int step: Commons.I18n.rightToLeft ? -1 : 1
        x: parent.width - panel.reserve - width - Style.space(20)
        direction: 1
        visible: root.page + step >= 0 && root.page + step < root.pageCount
        onClicked: root.goToPage(root.page + step)
      }

      // ---- Page dots: the active one stretches into a glowing pill -----------
      Row {
        id: dots
        anchors.horizontalCenter: viewport.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(48)
        height: 8
        spacing: 10

        Repeater {
          model: root.pageCount
          delegate: Item {
            id: dot
            required property int index
            readonly property bool active: index === root.page
            width: active ? 22 : 8
            height: 8
            Behavior on width {
              NumberAnimation { duration: Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
            }

            Rectangle {
              anchors.fill: parent
              radius: 4
              color: dot.active ? root.ink : root.inkAlpha(dotHit.containsMouse ? 0.75 : 0.38)
              scale: !dot.active && dotHit.containsMouse ? 1.25 : 1
              Behavior on color { ColorAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
              layer.enabled: dot.active
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

      // ---- Settings card, down the side the gear sits on ---------------------
      SettingsCard {
        id: settingsCard
        visible: root.settingsOpen
        // By x, like the grid beside it, so the two never swap sides.
        x: parent.width - width - Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        store: settings
        catalog: strings
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
