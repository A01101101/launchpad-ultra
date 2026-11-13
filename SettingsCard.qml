// The settings card shown beside the grid, which redraws as each setting
// changes, so the grid itself is the preview. Launchpad's own settings come
// first, then the dock's.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BorderSurface {
  id: card

  required property var store
  required property var catalog
  // The dock this plugin provides, or null when it is not running.
  property var dock: null
  // The most height the card may take; past it the settings scroll.
  property real maxHeight: 600
  signal closeRequested()

  readonly property color ink: Commons.Color.popups.text
  readonly property bool paged: store.scrollStyle === "pages"

  width: Style.space(400)
  height: Math.min(maxHeight, content.implicitHeight + contentTopInset + contentBottomInset)
  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
  padding: Style.spacing.panelPadding

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
      fillColor: Commons.Color.accent
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
    ButtonGroup {
      options: choiceRow.options
      value: choiceRow.value
      foreground: card.ink
      background: Commons.Color.popups.background
      focusable: false
      onChanged: function(value) { choiceRow.picked(value) }
    }
  }

  // A pick-one row bound to one of Launchpad's own settings.
  component SettingChoice: ChoiceRow {
    property string key: ""
    value: card.store.values[key]
    onPicked: function(value) { card.store.set(key, value) }
  }

  Flickable {
    id: scroller
    x: card.contentLeftInset
    y: card.contentTopInset
    width: card.width - card.contentLeftInset - card.contentRightInset
    height: card.height - card.contentTopInset - card.contentBottomInset
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: content
      width: scroller.width
      spacing: Style.spacing.xxl

      Item {
        width: parent.width
        height: Math.max(heading.implicitHeight, closeButton.implicitHeight)
        Label {
          id: heading
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - closeButton.width - Style.spacing.lg
          text: card.catalog.t("settings.title")
          font.pixelSize: Style.font.heading
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

      PanelSectionHeader { text: card.catalog.t("settings.layout"); foreground: card.ink }
      SliderRow { label: card.catalog.t("settings.columns"); key: "columns"; minimum: 4; maximum: 10 }
      SliderRow { label: card.catalog.t("settings.rows"); key: "rows"; minimum: 2; maximum: 6 }
      SliderRow { label: card.catalog.t("settings.iconSize"); key: "iconSize"; minimum: 56; maximum: 128; step: 2 }
      SettingSwitch { label: card.catalog.t("settings.showNames"); key: "showNames" }

      PanelSectionHeader { text: card.catalog.t("settings.search"); foreground: card.ink }
      SliderRow {
        label: card.catalog.t("settings.searchSize")
        key: "searchSize"
        minimum: 60
        maximum: 180
        step: 5
        format: function(value) { return card.catalog.t("settings.percent").arg(Commons.I18n.formatNumber(value, 0)) }
      }
      SliderRow {
        label: card.catalog.t("settings.searchBorder")
        key: "searchBorder"
        minimum: 0
        maximum: 6
        format: function(value) { return value < 1 ? card.catalog.t("settings.none") : Commons.I18n.formatNumber(value, 0) }
      }
      SettingSwitch { label: card.catalog.t("settings.sortBox"); key: "sortBox" }
      SettingChoice {
        label: card.catalog.t("settings.sortBy")
        key: "sortBy"
        options: [card.option("alpha", "sort.alpha"), card.option("used", "sort.used")]
      }

      PanelSectionHeader { text: card.catalog.t("settings.pages"); foreground: card.ink }
      SettingChoice {
        label: card.catalog.t("settings.scrollStyle")
        key: "scrollStyle"
        options: [card.option("pages", "settings.scrollStyle.pages"), card.option("smooth", "settings.scrollStyle.smooth")]
      }
      SliderRow { label: card.catalog.t("settings.scrollSensitivity"); key: "scrollSensitivity"; minimum: 1; maximum: 5 }
      Label {
        visible: !card.paged
        width: parent.width
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        opacity: 0.7
        text: card.catalog.t("settings.pagesOnly")
      }
      SettingChoice {
        label: card.catalog.t("settings.slideFrom")
        key: "slideFrom"
        available: card.paged
        options: [card.option("right", "settings.side.right"), card.option("left", "settings.side.left"),
                  card.option("bottom", "settings.side.bottom"), card.option("top", "settings.side.top")]
      }
      SettingChoice {
        label: card.catalog.t("settings.indicator")
        key: "indicator"
        available: card.paged
        options: [card.option("pill", "settings.indicator.pill"), card.option("dots", "settings.indicator.dots"),
                  card.option("numbers", "settings.indicator.numbers"), card.option("off", "settings.off")]
      }
      SettingChoice {
        label: card.catalog.t("settings.arrows")
        key: "arrows"
        available: card.paged
        options: [card.option("round", "settings.arrows.round"), card.option("chevron", "settings.arrows.chevron"),
                  card.option("edge", "settings.arrows.edge"), card.option("off", "settings.off")]
      }
      SettingChoice {
        label: card.catalog.t("settings.emptyClick")
        key: "emptyClick"
        available: card.paged
        options: [card.option("close", "settings.emptyClick.close"), card.option("page", "settings.emptyClick.page")]
      }

      PanelSectionHeader { text: card.catalog.t("settings.appearance"); foreground: card.ink }
      SliderRow {
        label: card.catalog.t("settings.backdrop")
        key: "backdrop"
        minimum: 0.31
        maximum: 0.9
        step: 0.01
        integer: false
        format: function(value) { return card.catalog.t("settings.percent").arg(Commons.I18n.formatNumber(Math.round(value * 100), 0)) }
      }
      SettingSwitch { label: card.catalog.t("settings.followTheme"); key: "followTheme" }

      PanelSectionHeader { text: card.catalog.t("settings.behaviour"); foreground: card.ink }
      SettingSwitch { label: card.catalog.t("settings.rememberPage"); key: "rememberPage" }

      // The dock's position and auto-hide are Omarchy's own dock settings,
      // the ones `omarchy dock` changes.
      PanelSectionHeader { visible: !!card.dock; text: card.catalog.t("settings.dock"); foreground: card.ink }
      ChoiceRow {
        visible: !!card.dock
        label: card.catalog.t("settings.dockPosition")
        value: card.dock ? card.dock.position : ""
        options: [card.option("top", "dock.positionTop"), card.option("bottom", "dock.positionBottom"),
                  card.option("left", "dock.positionLeft"), card.option("right", "dock.positionRight")]
        onPicked: function(value) { card.dock.setPosition(value) }
      }
      SwitchRow {
        visible: !!card.dock
        label: card.catalog.t("dock.autoHide")
        checked: !!card.dock && card.dock.autohide
        onToggled: function(on) { card.dock.setAutohide(on) }
      }
      SliderRow {
        visible: !!card.dock
        label: card.catalog.t("settings.dockIconSize")
        key: "dockIconSize"
        minimum: 24
        maximum: 64
        step: 2
      }

      Button {
        text: card.catalog.t("settings.reset")
        bordered: true
        foreground: card.ink
        opacity: card.store.isDefault ? 0.5 : 1
        onClicked: card.store.reset()
      }
    }
  }
}
