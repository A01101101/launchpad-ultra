// The settings card shown beside the grid, which redraws as each setting
// changes, so the grid itself is the preview.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BorderSurface {
  id: card

  required property var store
  required property var catalog
  signal closeRequested()

  readonly property color ink: Commons.Color.popups.text

  width: Style.space(340)
  height: content.implicitHeight + contentTopInset + contentBottomInset
  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
  padding: Style.spacing.panelPadding

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
    property string key: ""

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
      checked: card.store.values[switchRow.key] === true
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: card.store.set(switchRow.key, !toggle.checked)
    }
  }

  Column {
    id: content
    x: card.contentLeftInset
    y: card.contentTopInset
    width: card.width - card.contentLeftInset - card.contentRightInset
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
    SwitchRow { label: card.catalog.t("settings.showNames"); key: "showNames" }

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
    SwitchRow { label: card.catalog.t("settings.followTheme"); key: "followTheme" }

    PanelSectionHeader { text: card.catalog.t("settings.behaviour"); foreground: card.ink }
    SwitchRow { label: card.catalog.t("settings.rememberPage"); key: "rememberPage" }

    Button {
      text: card.catalog.t("settings.reset")
      bordered: true
      foreground: card.ink
      opacity: card.store.isDefault ? 0.5 : 1
      onClicked: card.store.reset()
    }
  }
}
