// The settings card shown beside the grid, which redraws as each setting
// changes, so the grid itself is the preview. It wears the same glass (or LCD)
// as Launchpad and keeps one size on every tab.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Rectangle {
  id: card

  required property var store
  required property var catalog
  // The look of Launchpad itself, so the card is part of the same screen.
  property color ink: "white"
  property color shade: "black"
  property bool lcd: false
  // The most height the card may take.
  property real maxHeight: 600
  signal closeRequested()
  // Whether the search bar can be dragged and resized; Launchpad holds it
  // and turns it off whenever the settings open.
  property bool arrange: false
  signal arrangeToggled(bool on)
  // Popped out, the card floats wherever it is dragged by its title row;
  // docked, it sits down the side of the screen.
  property bool poppedOut: false
  signal popToggled()
  signal dragStarted()
  signal dragMoved(real dx, real dy)
  signal dragFinished()

  readonly property bool paged: store.scrollStyle === "pages"

  // The card keeps one size on every tab; only the settings inside scroll.
  readonly property real inset: Style.space(20)
  width: Style.space(380)
  height: Math.min(maxHeight, Style.space(580))
  radius: lcd ? 3 : Style.cornerRadius * 1.5
  color: Util.alpha(shade, lcd ? 1 : 0.82)
  border.width: lcd ? 2 : 1
  border.color: Util.alpha(ink, lcd ? 0.85 : 0.22)

  // The tab showing.
  property string tab: "grid"
  readonly property var tabs: [option("grid", "settings.tab.grid"), option("pages", "settings.pages"),
                               option("search", "settings.tab.search"), option("theme", "settings.tab.theme")]

  function option(value, key) {
    return { value: value, label: card.catalog.t(key) }
  }

  // Clicks on the card stay on the card.
  MouseArea { anchors.fill: parent }

  component Label: Text {
    textFormat: Text.PlainText
    color: card.ink
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  // A wrapping row of pick-one chips. The chosen chip is tinted with the
  // accent on glass and inverted on the LCD, so it reads on either screen.
  component Chips: Flow {
    id: chips
    property var options: []
    property string value: ""
    signal changed(string value)

    spacing: Style.spacing.sm

    Repeater {
      model: chips.options
      delegate: Rectangle {
        id: chip
        required property var modelData
        readonly property bool chosen: chips.value === modelData.value
        readonly property color tint: card.lcd ? card.ink : Commons.Color.accent
        width: chipLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
        height: chipLabel.implicitHeight + 2 * Style.spacing.controlPaddingY
        radius: card.lcd ? 2 : Style.cornerRadius
        color: chosen ? (card.lcd ? card.ink : Util.alpha(tint, 0.22))
               : chipHit.containsMouse ? Util.alpha(card.ink, 0.12) : Util.alpha(card.shade, card.lcd ? 0 : 0.5)
        border.width: 1
        border.color: chosen ? tint : Util.alpha(card.ink, card.lcd ? 0.7 : 0.3)
        Label {
          id: chipLabel
          anchors.centerIn: parent
          elide: Text.ElideNone
          text: chip.modelData.label
          color: chip.chosen ? (card.lcd ? card.shade : chip.tint) : card.ink
          font.bold: chip.chosen
        }
        MouseArea {
          id: chipHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: chips.changed(chip.modelData.value)
        }
      }
    }
  }

  // A named slider with its current value at the end of the title line.
  component SliderRow: Column {
    id: sliderRow
    property string label: ""
    property string key: ""
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property bool integer: true
    // How the value reads, e.g. "6" or "34%".
    property var format: function(value) { return Commons.I18n.formatNumber(value, 0) }

    width: parent.width
    spacing: Style.spacing.xs

    Item {
      width: parent.width
      height: title.implicitHeight
      Label { id: title; text: sliderRow.label; width: parent.width - amount.implicitWidth - Style.spacing.lg }
      Label {
        id: amount
        anchors.right: parent.right
        opacity: 0.7
        text: sliderRow.format(slider.liveValue)
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      integer: sliderRow.integer
      value: card.store.values[sliderRow.key]
      trackColor: Util.alpha(card.ink, 0.2)
      fillColor: card.lcd ? card.ink : Commons.Color.accent
      knobColor: card.ink
      onMoved: function(value) { card.store.preview(sliderRow.key, value) }
      onReleased: function(value) { card.store.set(sliderRow.key, value) }
    }
  }

  // A named on/off switch; the whole row takes the click.
  component SwitchRow: Item {
    id: switchRow
    property string label: ""
    property bool checked: false
    signal toggled(bool on)

    width: parent.width
    height: Math.max(title.implicitHeight, toggle.implicitHeight)

    Label {
      id: title
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - toggle.width - Style.spacing.lg
      text: switchRow.label
    }
    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      interactive: false
      foreground: card.ink
      accent: card.lcd ? card.ink : Commons.Color.accent
      checked: switchRow.checked
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: switchRow.toggled(!switchRow.checked)
    }
  }

  // A switch bound to one of Launchpad's own settings.
  component SettingSwitch: SwitchRow {
    property string key: ""
    checked: card.store.values[key] === true
    onToggled: function(on) { card.store.set(key, on) }
  }

  // A named pick-one row. `available: false` greys it out, for a choice that
  // means nothing with the other settings as they are.
  component ChoiceRow: Column {
    id: choiceRow
    property string label: ""
    property var options: []
    property string value: ""
    property bool available: true
    signal picked(string value)

    width: parent.width
    spacing: Style.spacing.sm
    opacity: available ? 1 : 0.4
    enabled: available

    Label { text: choiceRow.label; width: parent.width }
    Chips {
      width: parent.width
      options: choiceRow.options
      value: choiceRow.value
      onChanged: function(value) { choiceRow.picked(value) }
    }
  }

  // A pick-one row bound to one of Launchpad's own settings.
  component SettingChoice: ChoiceRow {
    property string key: ""
    value: card.store.values[key]
    onPicked: function(value) { card.store.set(key, value) }
  }

  // A pick-one setting with more choices than fit on one line: named chips
  // that wrap.
  component ChipChoice: Column {
    id: chipChoice
    property string label: ""
    property string key: ""
    property var options: []

    width: parent.width
    spacing: Style.spacing.sm

    Label { text: chipChoice.label; width: parent.width }
    Chips {
      width: parent.width
      options: chipChoice.options
      value: card.store.values[chipChoice.key]
      onChanged: function(value) { card.store.set(chipChoice.key, value) }
    }
  }

  // A square tile in a row of picks: the chosen one wears a ring.
  component Tile: Rectangle {
    id: tile
    property bool chosen: false
    signal picked()
    width: Style.space(40)
    height: width
    radius: Style.cornerRadius
    color: Util.alpha(card.ink, chosen ? 0.18 : tileHit.containsMouse ? 0.1 : 0.04)
    border.width: chosen ? 2 : 1
    border.color: chosen ? (card.lcd ? card.ink : Commons.Color.accent) : Util.alpha(card.ink, 0.22)
    MouseArea {
      id: tileHit
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.picked()
    }
  }

  // ---- Pinned: title and tabs --------------------------------------------
  Column {
    id: pinned
    x: card.inset
    y: card.inset
    width: card.width - 2 * card.inset
    spacing: Style.spacing.lg

    Item {
      width: parent.width
      height: Math.max(heading.implicitHeight, closeButton.implicitHeight)
      // Popped out, the title row is the handle the card is dragged by.
      MouseArea {
        anchors.fill: parent
        enabled: card.poppedOut
        cursorShape: card.poppedOut ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
        property point grab
        onPressed: function(mouse) {
          grab = mapToItem(card.parent, mouse.x, mouse.y)
          card.dragStarted()
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var at = mapToItem(card.parent, mouse.x, mouse.y)
          card.dragMoved(at.x - grab.x, at.y - grab.y)
        }
        onReleased: card.dragFinished()
      }
      Label {
        id: heading
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - closeButton.width - popButton.width - 2 * Style.spacing.lg
        text: card.catalog.t("settings.title")
        font.pixelSize: Style.font.heading
      }
      // Pops the card out to float, or docks it back. Nerd Font glyphs:
      // an arrow out of a box, and arrows pulling in.
      Button {
        id: popButton
        anchors.right: closeButton.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        text: card.poppedOut ? "\uf066" : "\uf08e"
        foreground: card.ink
        onClicked: card.popToggled()
      }
      Button {
        id: closeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "✕"
        foreground: card.ink
        onClicked: card.closeRequested()
      }
    }

    Chips {
      width: parent.width
      options: card.tabs
      value: card.tab
      onChanged: function(value) { card.tab = value }
    }
  }

  // ---- Pinned: reset ------------------------------------------------------
  Button {
    id: resetButton
    anchors.left: parent.left
    anchors.leftMargin: card.inset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: card.inset
    text: card.catalog.t("settings.reset")
    bordered: true
    foreground: card.ink
    opacity: card.store.isDefault ? 0.5 : 1
    onClicked: card.store.reset()
  }

  // ---- A scrollbar beside the settings, once they run past the card -------
  // Drag the thumb, or click the track to jump there; the wheel scrolls too.
  Item {
    id: scrollTrack
    readonly property bool needed: scroller.contentHeight > scroller.height + 1
    visible: needed
    x: scroller.x + scroller.width + Math.round((card.inset - width) / 2)
    y: scroller.y
    width: Style.space(6)
    height: scroller.height

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Util.alpha(card.ink, card.lcd ? 0.18 : 0.1)
    }
    Rectangle {
      id: thumb
      readonly property real span: Math.max(Style.space(28), scrollTrack.height * scroller.height / Math.max(1, scroller.contentHeight))
      readonly property real travel: scrollTrack.height - span
      readonly property real reach: Math.max(1, scroller.contentHeight - scroller.height)
      width: parent.width
      height: span
      y: travel * Math.max(0, Math.min(1, scroller.contentY / reach))
      radius: width / 2
      color: Util.alpha(card.ink, trackMouse.pressed || trackMouse.containsMouse ? 0.7 : 0.4)
    }
    MouseArea {
      id: trackMouse
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      property real grabOffset: 0
      function scrollTo(pointerY) {
        var top = Math.max(0, Math.min(thumb.travel, pointerY - grabOffset))
        scroller.contentY = thumb.travel > 0 ? top / thumb.travel * thumb.reach : 0
      }
      onPressed: function(mouse) {
        var onThumb = mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height
        grabOffset = onThumb ? mouse.y - thumb.y : thumb.height / 2
        scrollTo(mouse.y)
      }
      onPositionChanged: function(mouse) { if (pressed) scrollTo(mouse.y) }
    }
  }

  // ---- The tab's settings, the only part that scrolls --------------------
  Flickable {
    id: scroller
    x: card.inset
    anchors.top: pinned.bottom
    anchors.topMargin: Style.spacing.xl
    anchors.bottom: resetButton.top
    anchors.bottomMargin: Style.spacing.lg
    width: card.width - 2 * card.inset
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    // Each tab starts at its top.
    Connections { target: card; function onTabChanged() { scroller.contentY = 0 } }

    Column {
      id: content
      width: scroller.width
      spacing: Style.spacing.xxl

      // ---- Grid: what is shown and in what order -------------------------
      Column {
        visible: card.tab === "grid"
        width: parent.width
        spacing: Style.spacing.xxl

        PanelSectionHeader { text: card.catalog.t("settings.layout"); foreground: card.ink }
        SliderRow { label: card.catalog.t("settings.columns"); key: "columns"; minimum: 4; maximum: 10 }
        SliderRow { label: card.catalog.t("settings.rows"); key: "rows"; minimum: 2; maximum: 6 }
        SliderRow { label: card.catalog.t("settings.iconSize"); key: "iconSize"; minimum: 56; maximum: 128; step: 2 }
        SettingSwitch { label: card.catalog.t("settings.showNames"); key: "showNames" }

        PanelSectionHeader { text: card.catalog.t("settings.behaviour"); foreground: card.ink }
        SettingChoice {
          label: card.catalog.t("settings.sortBy")
          key: "sortBy"
          options: [card.option("alpha", "sort.alpha"), card.option("used", "sort.used")]
        }
        SettingSwitch { label: card.catalog.t("settings.sortBox"); key: "sortBox" }
        SettingSwitch { label: card.catalog.t("settings.rememberPage"); key: "rememberPage" }
        SettingChoice {
          label: card.catalog.t("settings.dockBounce")
          key: "dockBounce"
          options: [card.option("rubber", "settings.dockBounce.rubber"), card.option("jelly", "settings.dockBounce.jelly"),
                    card.option("off", "settings.off")]
        }
      }

      // ---- Pages: how the grid moves ---------------------------------------
      Column {
        visible: card.tab === "pages"
        width: parent.width
        spacing: Style.spacing.xxl

        SettingChoice {
          label: card.catalog.t("settings.scrollStyle")
          key: "scrollStyle"
          options: [card.option("pages", "settings.scrollStyle.pages"), card.option("smooth", "settings.scrollStyle.smooth")]
        }
        SliderRow { label: card.catalog.t("settings.scrollSensitivity"); key: "scrollSensitivity"; minimum: 1; maximum: 5 }
        // Smooth scrolling has no pages, so their settings step out of the way.
        Label {
          visible: !card.paged
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.7
          text: card.catalog.t("settings.pagesOnly")
        }
        SettingChoice {
          visible: card.paged
          label: card.catalog.t("settings.slideFrom")
          key: "slideFrom"
          options: [card.option("right", "settings.side.right"), card.option("left", "settings.side.left"),
                    card.option("bottom", "settings.side.bottom"), card.option("top", "settings.side.top")]
        }
        SettingChoice {
          visible: card.paged
          label: card.catalog.t("settings.indicator")
          key: "indicator"
          options: [card.option("pill", "settings.indicator.pill"), card.option("dots", "settings.indicator.dots"),
                    card.option("numbers", "settings.indicator.numbers"), card.option("off", "settings.off")]
        }
        SettingChoice {
          visible: card.paged
          label: card.catalog.t("settings.arrows")
          key: "arrows"
          options: [card.option("round", "settings.arrows.round"), card.option("chevron", "settings.arrows.chevron"),
                    card.option("edge", "settings.arrows.edge"), card.option("off", "settings.off")]
        }
        SettingChoice {
          visible: card.paged
          label: card.catalog.t("settings.emptyClick")
          key: "emptyClick"
          options: [card.option("close", "settings.emptyClick.close"), card.option("page", "settings.emptyClick.page")]
        }
        Label {
          visible: card.paged && card.store.emptyClick === "page"
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.7
          text: card.catalog.t("settings.emptyClick.pageHint")
        }
      }

      // ---- Search: the bar's look, caret, place and size -------------------
      Column {
        visible: card.tab === "search"
        width: parent.width
        spacing: Style.spacing.xxl

        SwitchRow {
          label: card.catalog.t("settings.searchArrange")
          checked: card.arrange
          onToggled: function(on) { card.arrangeToggled(on) }
        }
        Label {
          visible: card.arrange
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.7
          text: card.catalog.t("settings.searchHint")
        }
        SettingSwitch { label: card.catalog.t("settings.searchCalm"); key: "searchCalm" }
        ChipChoice {
          label: card.catalog.t("settings.searchPrompt")
          key: "searchPrompt"
          options: [card.option("plain", "settings.prompt.plain"), card.option("quips", "settings.prompt.quips"),
                    card.option("confused", "settings.prompt.confused"), card.option("custom", "settings.prompt.custom")]
                   .concat(card.store.pikaOffered ? [card.option("pika", "settings.prompt.pika")] : [])
        }
        // The custom placeholder's words, saved as they are typed.
        TextField {
          visible: card.store.searchPrompt === "custom"
          width: parent.width
          text: card.store.searchCustom
          maximumLength: 60
          placeholderText: card.catalog.t("settings.prompt.customHint")
          foreground: card.ink
          onTextEdited: card.store.preview("searchCustom", text)
          onEditingFinished: card.store.save()
          // Keys typed here stay here rather than reaching the search bar.
          Keys.onEscapePressed: function(event) { focus = false; event.accepted = true }
        }
        ChipChoice {
          visible: !card.lcd
          label: card.catalog.t("settings.searchLook")
          key: "searchLook"
          options: [card.option("glass", "settings.searchLook.glass"), card.option("plain", "settings.searchLook.plain"),
                    card.option("win98", "settings.searchLook.win98"), card.option("frame", "settings.searchLook.frame"),
                    card.option("headline", "settings.searchLook.headline"), card.option("brutal", "settings.searchLook.brutal"),
                    card.option("aurora", "settings.searchLook.aurora")]
        }
        Label {
          visible: card.lcd
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          opacity: 0.7
          text: card.catalog.t("settings.searchLcd")
        }
        SettingSwitch {
          visible: !card.lcd && card.store.searchLook === "plain"
          label: card.catalog.t("settings.searchUnderline")
          key: "searchUnderline"
        }
        SettingChoice {
          label: card.catalog.t("settings.searchCaret")
          key: "searchCaret"
          options: [card.option("line", "settings.caret.line"), card.option("block", "settings.caret.block"),
                    card.option("underscore", "settings.caret.underscore")]
        }
        SettingSwitch { label: card.catalog.t("settings.searchBlink"); key: "searchBlink" }
        SettingChoice {
          label: card.catalog.t("settings.searchPlace")
          key: "searchPlace"
          options: [card.option("top", "settings.place.top"), card.option("bottom", "settings.place.bottom"),
                    card.option("custom", "settings.place.custom")]
        }
        SliderRow {
          label: card.catalog.t("settings.searchSize")
          key: "searchSize"
          minimum: 60
          maximum: 240
          step: 5
          format: function(value) { return card.catalog.t("settings.percent").arg(Commons.I18n.formatNumber(value, 0)) }
        }
        SliderRow {
          visible: card.lcd || ["glass", "frame", "aurora"].indexOf(card.store.searchLook) !== -1
          label: card.catalog.t("settings.searchBorder")
          key: "searchBorder"
          minimum: 0
          maximum: 6
          format: function(value) { return value < 1 ? card.catalog.t("settings.none") : Commons.I18n.formatNumber(value, 0) }
        }

        // The looking glass: each tile shows the drawing it picks.
        PanelSectionHeader { text: card.catalog.t("settings.glass"); foreground: card.ink }
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Label { text: card.catalog.t("settings.glassStyle"); width: parent.width }
          Flow {
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: card.store.spec.glassStyle.options
              delegate: Tile {
                id: styleTile
                required property string modelData
                chosen: card.store.glassStyle === modelData
                onPicked: card.store.set("glassStyle", modelData)
                Magnifier {
                  visible: styleTile.modelData !== "off"
                  anchors.centerIn: parent
                  scale: 1.25
                  style: styleTile.modelData
                  color: card.ink
                }
                Label {
                  visible: styleTile.modelData === "off"
                  anchors.centerIn: parent
                  opacity: 0.7
                  font.pixelSize: Style.font.caption
                  text: card.catalog.t("settings.off")
                }
              }
            }
          }
        }
        SliderRow {
          label: card.catalog.t("settings.glassSize")
          key: "glassSize"
          minimum: 60
          maximum: 200
          step: 5
          format: function(value) { return card.catalog.t("settings.percent").arg(Commons.I18n.formatNumber(value, 0)) }
        }
      }

      // ---- Theme: the whole screen ----------------------------------------
      Column {
        visible: card.tab === "theme"
        width: parent.width
        spacing: Style.spacing.xxl

        SettingChoice {
          label: card.catalog.t("settings.theme")
          key: "theme"
          options: [card.option("glass", "settings.theme.glass"), card.option("lcd", "settings.theme.lcd")]
        }
        // The LCD's tint: each tile is that screen with a dot of its ink.
        Column {
          visible: card.lcd
          width: parent.width
          spacing: Style.spacing.sm
          Label { text: card.catalog.t("settings.lcdTint"); width: parent.width }
          Flow {
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: card.store.spec.lcdTint.options
              delegate: Tile {
                id: lcdTile
                required property string modelData
                chosen: card.store.lcdTint === modelData
                onPicked: card.store.set("lcdTint", modelData)
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Style.space(5)
                  radius: 2
                  color: card.store.lcdTints[lcdTile.modelData].screen
                  border.width: 1
                  border.color: card.store.lcdTints[lcdTile.modelData].ink
                  Rectangle {
                    anchors.centerIn: parent
                    width: Style.space(10)
                    height: width
                    color: card.store.lcdTints[lcdTile.modelData].ink
                  }
                }
              }
            }
          }
        }
        SliderRow {
          visible: card.lcd
          label: card.catalog.t("settings.lcdShadow")
          key: "lcdShadow"
          minimum: 0
          maximum: 12
          format: function(value) { return value < 1 ? card.catalog.t("settings.none") : Commons.I18n.formatNumber(value, 0) }
        }
        SettingSwitch { visible: !card.lcd; label: card.catalog.t("settings.followTheme"); key: "followTheme" }
        SliderRow {
          visible: !card.lcd
          label: card.catalog.t("settings.backdrop")
          key: "backdrop"
          minimum: 0.31
          maximum: 0.9
          step: 0.01
          integer: false
          format: function(value) { return card.catalog.t("settings.percent").arg(Commons.I18n.formatNumber(Math.round(value * 100), 0)) }
        }
        SettingSwitch { label: card.catalog.t("settings.showGear"); key: "showGear" }
      }
    }
  }
}
