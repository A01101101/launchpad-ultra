// Launchpad: a fullscreen frosted overlay with a search pill, a sliding paged
// grid of six columns by four rows holding every installed app, and page dots.
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
  property var apps: []
  property int page: 0
  property string launchingId: ""

  readonly property int cols: 6
  readonly property int rows: 4
  readonly property int pageSize: cols * rows
  readonly property int pageCount: Math.ceil(apps.length / pageSize)
  readonly property string query: searchInput.text.trim()

  onQueryChanged: {
    page = 0
    rebuild()
  }

  // ---- What the shell calls ------------------------------------------------

  function open(payloadJson) {
    searchInput.clear()
    page = 0
    launchingId = ""
    if (appLibrary) appLibrary.refreshIcons()
    rebuild()
    opened = true
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function close() {
    opened = false
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

  // ---- Apps ----------------------------------------------------------------

  // The shell's own app list: the same apps, search and hidden entries as the
  // Omarchy launcher.
  function rebuild() {
    var found = appLibrary ? appLibrary.sortedEntries(query) : []
    apps = found.map(function(row) { return row.entry })
    goToPage(page)
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

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  OverlayWindow {
    id: panel
    shown: root.opened
    // Hyprland can blur the desktop behind this namespace; see the README.
    WlrLayershell.namespace: "launchpad"

    // ---- Backdrop: a dark tint over the desktop ----------------------------
    // The tint stays above 0.3 so a blur rule with ignore_alpha = 0.3 applies.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(12 / 255, 14 / 255, 22 / 255, 0.34)
    }

    // Clicking empty space dismisses the launcher.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
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
    Timer { id: wheelPause; interval: 320 }

    // ---- Search pill -------------------------------------------------------
    Rectangle {
      id: searchPill
      readonly property bool filled: searchInput.text !== ""
      anchors.top: parent.top
      anchors.topMargin: 36
      anchors.horizontalCenter: parent.horizontalCenter
      width: filled ? 440 : 340
      height: 38
      radius: height / 2
      color: Qt.rgba(1, 1, 1, filled ? 0.26 : 0.16)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, filled ? 0.45 : 0.22)

      Behavior on width {
        NumberAnimation { duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }
      Behavior on color { ColorAnimation { duration: Style.duration(180) } }

      // Swallow clicks so they don't dismiss the launcher.
      MouseArea { anchors.fill: parent }

      // Magnifier glyph.
      Item {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        opacity: 0.7
        Rectangle {
          width: 12; height: 12; radius: 6
          color: "transparent"
          border.width: 1.5
          border.color: "white"
        }
        Rectangle {
          x: 9.5; y: 11.5
          width: 6; height: 1.5; radius: 1
          color: "white"
          rotation: 45
          transformOrigin: Item.Left
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: searchInput
        verticalAlignment: Text.AlignVCenter
        text: strings.t("search.placeholder")
        color: Qt.rgba(1, 1, 1, 0.6)
        font.family: Style.font.family
        font.pixelSize: 14
        visible: !searchPill.filled
      }

      // Always focused, so typing anywhere searches.
      TextInput {
        id: searchInput
        anchors.fill: parent
        anchors.leftMargin: 38
        anchors.rightMargin: 36
        verticalAlignment: TextInput.AlignVCenter
        color: "white"
        selectionColor: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: 14
        clip: true
        focus: true

        // Arrows and PageUp/PageDown change page, Enter opens the first
        // match, Escape clears the search and then hides the launcher.
        Keys.onPressed: function(event) {
          var key = Util.readingKey(event)
          if (key === Qt.Key_Right || key === Qt.Key_PageDown) {
            root.goToPage(root.page + 1)
          } else if (key === Qt.Key_Left || key === Qt.Key_PageUp) {
            root.goToPage(root.page - 1)
          } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (root.query !== "" && root.apps.length > 0) root.openApp(root.apps[0])
          } else if (key === Qt.Key_Escape) {
            if (text !== "") clear()
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
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        radius: 9
        color: Qt.rgba(1, 1, 1, 0.25)
        visible: searchPill.filled
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "✕"
          color: "white"
          font.pixelSize: 10
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: searchInput.clear()
        }
      }
    }

    // ---- Pages -------------------------------------------------------------
    Item {
      id: viewport
      anchors.top: searchPill.bottom
      anchors.bottom: dots.top
      anchors.topMargin: 16
      anchors.bottomMargin: 22
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width - 96, 1360)
      clip: true

      readonly property real gridWidth: width - 40
      readonly property real gridHeight: Math.min(height - 20, 680)
      readonly property real cellWidth: (gridWidth - (root.cols - 1) * 24) / root.cols
      readonly property real cellHeight: (gridHeight - (root.rows - 1) * 32) / root.rows

      Row {
        id: slider
        height: parent.height
        // Pages run the other way in a right-to-left layout.
        x: (Commons.I18n.rightToLeft ? root.page - (root.pageCount - 1) : -root.page) * viewport.width
        // No animation while hidden, so it reopens already on page one.
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
                columnSpacing: 24
                rowSpacing: 32

                Repeater {
                  model: root.apps.slice(pageSlide.index * root.pageSize,
                                         (pageSlide.index + 1) * root.pageSize)

                  delegate: Item {
                    id: cell
                    required property var modelData
                    readonly property bool launching: root.launchingId === modelData.id
                    width: viewport.cellWidth
                    height: viewport.cellHeight

                    Column {
                      id: appItem
                      anchors.centerIn: parent
                      width: Math.max(116, cell.width - 8)
                      spacing: 8

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
                        width: 86
                        height: 86
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
                          sourceSize.width: 192
                          sourceSize.height: 192
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
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: "white"
                        font.family: Style.font.family
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.8)
                        text: root.appLibrary ? root.appLibrary.entryName(cell.modelData) : ""
                      }
                    }

                    MouseArea {
                      id: hit
                      anchors.fill: appItem
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openApp(cell.modelData)
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
        spacing: 12
        visible: root.apps.length === 0
        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          text: "⌕"
          color: Qt.rgba(1, 1, 1, 0.6)
          font.pixelSize: 48
        }
        Text {
          textFormat: Text.PlainText
          text: strings.t("search.empty")
          color: Qt.rgba(1, 1, 1, 0.6)
          font.family: Style.font.family
          font.pixelSize: 16
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
      color: Qt.rgba(1, 1, 1, arrowHit.containsMouse ? 0.25 : 0.12)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.2)
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
          color: "white"
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
      x: 20
      direction: -1
      visible: root.page + step >= 0 && root.page + step < root.pageCount
      onClicked: root.goToPage(root.page + step)
    }
    NavArrow {
      readonly property int step: Commons.I18n.rightToLeft ? -1 : 1
      x: parent.width - width - 20
      direction: 1
      visible: root.page + step >= 0 && root.page + step < root.pageCount
      onClicked: root.goToPage(root.page + step)
    }

    // ---- Page dots: the active one stretches into a glowing pill -----------
    Row {
      id: dots
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 48
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
            color: dot.active ? "white" : Qt.rgba(1, 1, 1, dotHit.containsMouse ? 0.75 : 0.38)
            scale: !dot.active && dotHit.containsMouse ? 1.25 : 1
            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
            layer.enabled: dot.active
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: "white"
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
}
