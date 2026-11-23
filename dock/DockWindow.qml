import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

// One screen's dock. It stays mapped and only hides its contents, so switching
// to a floating workspace does not wait on a fresh layer surface. While hidden the
// mask is empty and clicks fall through to the windows below.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  property var dock: null

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  readonly property bool shown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
  // With auto-hide on, the dock waits off screen until the pointer reaches its
  // edge, and stays while the pointer, a menu, or a drag still needs it. A
  // maximized window hides the dock the same way, so it can still be called up.
  readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
  property bool revealed: false
  readonly property bool menuOpen: menuItem !== null || settingsMenu
  readonly property bool tucked: autohide && !(revealed || menuOpen || dragging || insertIndex >= 0 || (!!dock && dock.moveActive))
  readonly property bool contentShown: shown && !tucked

  readonly property int gap: Style.spacing.xs
  readonly property int iconSize: Math.round((dock ? dock.iconSize : 36) * Style.fontScale)
  // Each app has a square slot with its icon in the middle, and the slots run
  // straight to the edge of the dock.
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  // A pinned app that is not running is drawn faded.
  readonly property real idleOpacity: 0.7
  // Room inward of the dock for its menus: the tallest, the apps button's,
  // has six rows.
  readonly property int popupRoom: Style.spacing.popupRowHeight * 6 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2 + gap * 2
  // Icons pop away from the screen edge.
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  // How a launching app bounces, from Launchpad's settings: "rubber",
  // "jelly", or "off".
  readonly property string bounceStyle: dock ? dock.bounceStyle : "rubber"

  // Rubber: a launching app's bounce, worked out as a rubber ball under gravity: a
  // crouch, a hop, then rebounds that die away, and a rest. Each flight is a
  // parabola, h = 4H·u(1 − u). A rebound leaves with the fraction `rebound`
  // of the speed it landed with, so with gravity unchanged it rises rebound²
  // as high and stays up rebound as long. Squash and stretch keep the icon's
  // area (across · along = 1), and every phase starts where the last one
  // ended, so nothing jumps.
  readonly property real bounceHeight: iconSize * 1.0
  readonly property real rebound: 0.45
  readonly property int bounceRebounds: 2
  // How far the icon stretches along its flight at full speed, how hard it
  // squashes landing from the full hop, and how deep it crouches first.
  readonly property real bounceStretch: 0.18
  readonly property real bounceSquash: 0.3
  readonly property real bounceCrouch: 0.22
  // How far it leans, in degrees, over the main hop: into the jump going up,
  // the other way coming down, upright again on landing.
  readonly property real bounceLean: 7
  // Phase lengths in units of the main hop's flight time, and that time.
  readonly property real bounceCrouchUnits: 0.2
  readonly property real bounceContactUnits: 0.14
  readonly property real bounceRestUnits: 0.25
  readonly property int bounceFlightMs: 240
  readonly property var bouncePhases: {
    // [kind, length, height, stretch, squash] for each phase in turn.
    var phases = [["crouch", bounceCrouchUnits, 0, bounceStretch, bounceCrouch]]
    for (var i = 0; i <= bounceRebounds; i++) {
      var e = Math.pow(rebound, i)
      phases.push(["flight", e, bounceHeight * e * e, bounceStretch * e, 0])
      phases.push(["land", bounceContactUnits * e, 0, bounceStretch * e, bounceSquash * e])
    }
    phases.push(["rest", bounceRestUnits, 0, 0, 0])
    return phases
  }
  readonly property real bounceUnits: bouncePhases.reduce(function(sum, phase) { return sum + phase[1] }, 0)

  // Where the bounce is at t, 0 to 1 through one cycle: how far the icon is
  // off the dock, how much it is stretched (above 1) or squashed (below)
  // along the hop, and how far it leans.
  function rubberAt(t) {
    var x = t * bounceUnits
    var phases = bouncePhases
    for (var i = 0; i < phases.length; i++) {
      var phase = phases[i]
      if (x >= phase[1] && i < phases.length - 1) { x -= phase[1]; continue }
      var u = Math.min(1, x / phase[1])
      if (phase[0] === "flight") {
        return {
          hop: 4 * phase[2] * u * (1 - u),
          along: 1 + phase[3] * Math.abs(1 - 2 * u),
          lean: i === 1 ? bounceLean * Math.sin(2 * Math.PI * u) : 0
        }
      }
      if (phase[0] === "rest") return { hop: 0, along: 1, lean: 0 }
      // On the dock: from the stretch it came in with to the one it leaves
      // with, dipping into a squash halfway.
      var into = phase[0] === "crouch" ? 0 : phase[3]
      var next = phases[i + 1][0] === "flight" ? phases[i + 1][3] : 0
      return { hop: 0, along: 1 + into * (1 - u) + next * u - phase[4] * Math.sin(Math.PI * u), lean: 0 }
    }
    return { hop: 0, along: 1, lean: 0 }
  }

  // Jelly: a crouch, one big stretchy hop on the same parabola, and on
  // landing a wobble that dies away. The wobble is a damped spring,
  // x(t) = e^(−ζωt)·(x₀·cos ω_d t + v·sin ω_d t) with ω_d = ω√(1 − ζ²):
  // it lands still stretched (x₀) and splats (v). It ends on a zero of the
  // spring, so the icon is at rest exactly when the wobble stops. The icon
  // rocks side to side as it settles, over a whole number of half swings,
  // so it is upright then too.
  readonly property real jellyHeight: iconSize * 0.8
  readonly property real jellyStretch: 0.26
  readonly property real jellyCrouch: 0.18
  readonly property real jellySplat: 0.4
  readonly property real jellyLean: 6
  // The spring: its natural frequency in hertz and its damping ratio.
  readonly property real jellyHz: 7
  readonly property real jellyDamping: 0.18
  readonly property int jellyCrouchMs: 50
  readonly property int jellyFlightMs: 250
  readonly property int jellyRestMs: 60
  // Wobble at least this long, then stop on the spring's next zero.
  readonly property int jellyWobbleMinMs: 320
  readonly property real jellyOmega: 2 * Math.PI * jellyHz
  readonly property real jellyOmegaD: jellyOmega * Math.sqrt(1 - jellyDamping * jellyDamping)
  readonly property real jellyWobbleMs: {
    // x(t) = 0 where tan(ω_d t) = −x₀ / v.
    var first = Math.atan(jellyStretch / jellySplat)
    var minimum = jellyWobbleMinMs / 1000
    var n = Math.max(0, Math.ceil((minimum * jellyOmegaD - first) / Math.PI))
    return (first + n * Math.PI) / jellyOmegaD * 1000
  }
  readonly property real jellyCycleMs: jellyCrouchMs + jellyFlightMs + jellyWobbleMs + jellyRestMs

  function jellyAt(t) {
    var ms = t * jellyCycleMs
    if (ms < jellyCrouchMs) {
      var c = ms / jellyCrouchMs
      return { hop: 0, along: 1 + jellyStretch * c - jellyCrouch * Math.sin(Math.PI * c), lean: 0 }
    }
    ms -= jellyCrouchMs
    if (ms < jellyFlightMs) {
      var u = ms / jellyFlightMs
      return { hop: 4 * jellyHeight * u * (1 - u), along: 1 + jellyStretch * Math.abs(1 - 2 * u), lean: 0 }
    }
    ms -= jellyFlightMs
    if (ms < jellyWobbleMs) {
      var s = ms / 1000
      var decay = Math.exp(-jellyDamping * jellyOmega * s)
      var x = decay * (jellyStretch * Math.cos(jellyOmegaD * s) - jellySplat * Math.sin(jellyOmegaD * s))
      var lean = jellyLean * decay * Math.sin(3 * Math.PI * ms / jellyWobbleMs)
      return { hop: 0, along: 1 + x, lean: lean }
    }
    return { hop: 0, along: 1, lean: 0 }
  }

  // Where the chosen bounce is at t, 0 to 1 through one cycle.
  function bounceAt(t) {
    return bounceStyle === "jelly" ? jellyAt(t) : rubberAt(t)
  }
  readonly property real bounceCycleMs: bounceStyle === "jelly" ? jellyCycleMs : bounceFlightMs * bounceUnits

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  // How far the dragged app has been pulled across the dock, toward or away
  // from its edge. The icon follows the pointer both ways, like a dragged bar
  // widget.
  property real dragCross: 0
  readonly property bool dragging: dragIndex >= 0
  // True once a kept app has been pulled far enough off the dock that letting
  // go takes it out, the way a widget dragged off the bar is removed. Its
  // room closes meanwhile, as though it were gone already.
  property bool removeArmed: false
  readonly property real removeDistance: window.slotSize * 0.75 + Style.spaceReal(24)
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var point = Qt.point(screenX - at.x - body.x, screenY - at.y - body.y)
    var reach = window.slotSize
    var along = window.vertical ? point.y : point.x
    var across = window.vertical ? point.x : point.y
    var length = window.vertical ? body.height : body.width
    var depth = window.vertical ? body.width : body.height
    var near = along >= -window.slotSize && along <= length + window.slotSize && across >= -reach && across <= depth + reach
    if (window.shown && window.autohide && near) window.revealed = true
    window.insertIndex = window.shown && near ? window.slotIndexAt(point) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // The slot a point along the dock falls before, counting from the first app.
  function slotIndexAt(point) {
    var along = window.vertical ? point.y : point.x
    var first = window.slotSize
    var count = window.dock ? window.dock.itemModel.count : 0
    return Math.max(0, Math.min(count, Math.round((along - first) / window.slotSize)))
  }
  property var menuItem: null
  property Item menuSlot: null
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false

  onWorkspaceIdChanged: if (dock) dock.readMode(workspaceId)
  onShownChanged: {
    if (shown) return
    closeMenu()
    window.revealed = false
  }
  Component.onCompleted: if (dock) dock.readMode(workspaceId)

  function openMenu(item, slot) {
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot) {
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
    window.dragCross = 0
    window.removeArmed = false
  }

  function closeMenu() {
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // Places the menu inward of the dock, centered on a slot.
  function popupX(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    if (window.position === "left") return body.x + body.width + window.gap
    if (window.position === "right") return body.x - window.gap - popup.width
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    if (window.position === "top") return body.y + body.height + window.gap
    if (window.position === "bottom") return body.y - window.gap - popup.height
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, without reserving one of its own:
  // floating windows go where they are put.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  // The surface spans its screen, clear past the icons, the way the bar's
  // does, and a drag only toggles its input region. While the dock is being
  // moved or an app slid along it, the whole surface takes input, so the
  // pointer never leaves the dock however far it goes: a pointer that strays
  // onto another surface is pulled off mid-drag by Hyprland, ending the
  // gesture with a synthesized release. Growing the surface for the drag
  // instead would flash a stale, stretched frame.
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  readonly property bool gestureActive: window.dragging || (!!window.dock && window.dock.moveActive && !!window.dock.moveScreen && window.dock.moveScreen.name === window.screen.name)

  mask: window.gestureActive ? null : idleMask

  Region {
    id: idleMask
    item: window.contentShown ? body : null

    Region { item: window.shown && window.autohide ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back. Like
  // macOS, it runs the whole length of the edge, not just under the icons.
  Item {
    id: edgeTrigger

    // Two pixels: the pointer stops at the screen's edge, so that is enough to
    // hit, and it takes clicks from as little of the windows below as it can.
    readonly property int depth: 2

    x: window.position === "right" ? window.width - depth : 0
    y: window.position === "bottom" ? window.height - depth : 0
    width: window.vertical ? depth : window.width
    height: window.vertical ? window.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  Item {
    id: body

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along x from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    width: slots.implicitWidth
    height: slots.implicitHeight
    // How far the dock is tucked past its edge. Auto-hide slides it, but only
    // while the dock is on screen: arriving on a floating workspace shows it
    // where it belongs at once.
    property real tuck: window.tucked ? window.slotSize + window.gap : 0

    // Tucking away is quicker than coming back. A gentler curve than
    // Style.easeOut, which crosses the short slide in a frame or two.
    Behavior on tuck {
      id: tuckMotion
      enabled: window.shown
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 120 : 180)
        easing.type: Easing.OutCubic
      }
    }

    x: window.position === "left" ? window.gap - tuck
      : window.position === "right" ? window.width - width - window.gap + tuck
      : Math.round((window.width - width) / 2)
    y: window.position === "top" ? window.gap - tuck
      : window.position === "bottom" ? window.height - height - window.gap + tuck
      : Math.round((window.height - height) / 2)
    // Switching between tiled and floating workspaces shows and hides the dock
    // at once, with nothing to watch in between. Hidden by opacity rather than
    // visibility, so the icons keep their textures and are drawn on the first
    // frame back instead of being uploaded again.
    opacity: window.shown ? 1 : 0

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered && window.autohide) hideTimer.restart()
      // Only a real move clears it: the release itself reports the pointer too.
      onPointChanged: {
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      anchors.centerIn: parent
      columns: window.vertical ? 1 : appRepeater.count + 1

      AppsSlot {}

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null

        delegate: AppSlot {}
      }
    }
  }

  component Slot: Item {
    id: slot

    // Only the dragged icon is lifted while a drag is on; none of the others
    // pop as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse

    // Held with the left button, any slot takes the dock with it to another
    // screen edge, the way holding the bar, or a widget on it, moves the bar.
    property bool moving: false

    function screenPoint(event) {
      var scene = mouse.mapToItem(window.contentItem, event.x, event.y)
      var origin = window.origin()
      return { x: origin.x + scene.x, y: origin.y + scene.y }
    }

    function startMove(event) {
      if (moving || !window.dock) return
      moving = true
      window.closeMenu()
      window.dock.beginMove(window.screen)
      window.dock.updateMove(screenPoint(event))
    }

    width: window.slotSize
    height: window.slotSize

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }
  }

  component AppsSlot: Slot {
    id: appsSlot

    property real displayedShift: window.insertIndex >= 0 ? -window.slotSize / 2 : 0

    Behavior on displayedShift {
      enabled: window.animateShifts
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    transform: Translate {
      x: window.vertical ? 0 : appsSlot.displayedShift
      y: window.vertical ? appsSlot.displayedShift : 0
    }

    // Held or dragged with the left button, the apps button moves the dock,
    // the way empty bar space moves the bar.
    property bool suppressClick: false
    property point pressedAt

    mouse.pressAndHoldInterval: 200
    mouse.cursorShape: moving ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    mouse.onPressed: function(event) {
      moving = false
      suppressClick = false
      pressedAt = Qt.point(event.x, event.y)
    }

    mouse.onPressAndHold: function(event) {
      if (appsSlot.mouse.pressedButtons & Qt.LeftButton) startMove(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(event.buttons & Qt.LeftButton)) return
      if (!moving) {
        if (Math.abs(event.x - pressedAt.x) + Math.abs(event.y - pressedAt.y) < Style.space(4)) return
        startMove(event)
        return
      }
      window.dock.updateMove(screenPoint(event))
    }

    mouse.onReleased: function(event) {
      if (!moving) return
      moving = false
      suppressClick = true
      window.dock.finishMove()
    }

    mouse.onCanceled: {
      moving = false
      suppressClick = false
      if (window.dock) window.dock.clearMove()
    }

    mouse.onClicked: function(event) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openSettingsMenu(appsSlot)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.openApps()
    }

    // A grid of app squares reads as "all apps" in any icon theme. Drawn
    // rather than taken from a font, so its edges stay crisp on the
    // transparent dock and it fills its slot like the app icons beside it.
    Item {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      scale: appsSlot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Grid {
        readonly property int square: Math.round(window.iconSize * 0.22)

        anchors.centerIn: parent
        columns: 3
        spacing: Math.round(window.iconSize * 0.1)

        Repeater {
          model: 9

          delegate: Rectangle {
            width: parent.square
            height: parent.square
            radius: Math.max(1, Math.round(parent.square * 0.2))
            color: Commons.Color.bar.text
          }
        }
      }
    }
  }

  component AppSlot: Slot {
    id: appSlot

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    // How far through one bounce a launching app is, 0 to 1.
    property real bounceT: 0
    readonly property var bounce: launching && window.bounceStyle !== "off" ? window.bounceAt(bounceT) : ({ hop: 0, along: 1, lean: 0 })
    readonly property real hop: bounce.hop

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    z: lifted ? 1 : 0

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Reading the pointer through a slot that moves with it would
    // feed each move back into the next.
    function bodyPoint(event) {
      return appSlot.mapToItem(body, event.x, event.y)
    }

    // Held still for a long moment, an app moves the whole dock; one that
    // starts sliding first is reordered or pulled off instead. The wait is
    // long so a short pause before dragging still reorders.
    mouse.pressAndHoldInterval: 600
    mouse.cursorShape: appSlot.moving ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    mouse.onPressed: function(event) {
      appSlot.dragged = false
      appSlot.moving = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
    }

    mouse.onPressAndHold: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton) || window.dragging || appSlot.dragged) return
      appSlot.startMove(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      if (appSlot.moving) {
        window.dock.updateMove(appSlot.screenPoint(event))
        return
      }
      var point = appSlot.bodyPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // A press that wanders is a drag in the making, not a click.
      if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > Style.space(4)) appSlot.dragged = true
      var cross = window.vertical ? point.x - appSlot.pressPoint.x : point.y - appSlot.pressPoint.y
      if (!window.dragging) {
        if (Math.hypot(delta, cross) < Style.space(6)) return
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      window.dragCross = cross
      // Only a kept app can be taken out; a running one that is not kept
      // stays while its windows do, so pulling it off does nothing.
      window.removeArmed = !!appSlot.modelData && appSlot.modelData.pinned && Math.abs(cross) >= window.removeDistance
      window.dropIndex = window.removeArmed ? appRepeater.count - 1
        : DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
    }

    mouse.onReleased: function(event) {
      if (appSlot.moving) {
        appSlot.moving = false
        appSlot.dragged = true
        window.dock.finishMove()
        return
      }
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
      var from = window.dragIndex
      var to = window.dropIndex
      var remove = window.removeArmed
      appSlot.dragged = true
      window.endDrag()
      if (remove) window.dock.setPinned(appSlot.key, false)
      else window.dock.moveItem(from, to)
    }

    mouse.onCanceled: {
      if (appSlot.moving) {
        appSlot.moving = false
        if (window.dock) window.dock.clearMove()
      }
      if (appSlot.lifted) window.endDrag()
    }

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
      else window.dock.activate(appSlot.modelData)
    }

    // Running apps are drawn in full and pinned ones that are not running
    // faded. One that is starting bounces, like the macOS dock, in full, the
    // way the settings choose.
    Image {
      id: appIcon
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      opacity: (appSlot.lifted && window.removeArmed ? 0.55 : 1) * (appSlot.launching || appSlot.windowCount > 0 ? 1 : window.idleOpacity)
      // The hop points away from the screen edge the dock sits on.
      readonly property real hopX: window.position === "left" ? appSlot.hop : window.position === "right" ? -appSlot.hop : 0
      readonly property real hopY: window.position === "top" ? appSlot.hop : window.position === "bottom" ? -appSlot.hop : 0
      transform: [
        // Squashed and stretched about the edge it lands on, so it stays
        // planted on the dock.
        Scale {
          origin.x: window.position === "right" ? appIcon.width : window.position === "left" ? 0 : appIcon.width / 2
          origin.y: window.position === "bottom" ? appIcon.height : window.position === "top" ? 0 : appIcon.height / 2
          xScale: window.vertical ? appSlot.bounce.along : 1 / appSlot.bounce.along
          yScale: window.vertical ? 1 / appSlot.bounce.along : appSlot.bounce.along
        },
        // Leans about the same planted edge.
        Rotation {
          origin.x: window.position === "right" ? appIcon.width : window.position === "left" ? 0 : appIcon.width / 2
          origin.y: window.position === "bottom" ? appIcon.height : window.position === "top" ? 0 : appIcon.height / 2
          angle: appSlot.bounce.lean
        },
        Translate {
          x: (window.vertical ? (appSlot.lifted ? window.dragCross : 0) : appSlot.displayedShift) + appIcon.hopX
          y: (window.vertical ? appSlot.displayedShift : (appSlot.lifted ? window.dragCross : 0)) + appIcon.hopY
        }
      ]
      scale: appSlot.lifted && window.removeArmed ? 0.82 : appSlot.lifted || appSlot.hovered ? 1.15 : 1

      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    // With animations off it holds still rather than spinning through
    // zero-length steps.
    // Time runs evenly; window.bounceAt gives the motion its shape.
    NumberAnimation {
      target: appSlot
      property: "bounceT"
      from: 0
      to: 1
      running: appSlot.launching && window.bounceStyle !== "off" && !Style.reduceMotion
      loops: Animation.Infinite
      duration: Style.duration(Math.round(window.bounceCycleMs))
      onRunningChanged: if (!running) appSlot.bounceT = 0
    }
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu)
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", strings.t("dock.positionTop")], ["bottom", strings.t("dock.positionBottom")], ["left", strings.t("dock.positionLeft")], ["right", strings.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: window.dock.setPosition(modelData[0])
        }
      }

      MenuRow {
        visible: window.settingsMenu
        text: strings.t("dock.autoHide")
        checked: window.autohide
        onTriggered: window.dock.setAutohide(!window.autohide)
      }

      MenuRow {
        visible: window.settingsMenu
        text: strings.t("dock.launchpadSettings")
        onTriggered: window.dock.openLauncherSettings()
      }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: strings.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.hasEntry
        text: menu.item && menu.item.pinned ? strings.t("dock.removeFromDock") : strings.t("dock.keepInDock")
        onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
      }

      MenuRow {
        visible: menu.running
        text: strings.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
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

    Text {
      visible: row.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
