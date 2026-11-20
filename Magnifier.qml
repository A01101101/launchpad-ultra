// The looking glass at the start of the search bar, drawn in the style the
// settings pick. It is a 16 by 16 drawing; scale it to size.
import QtQuick

Item {
  id: glass

  // classic, fine, bold, filled, square, pixel, arrow, dot or off.
  property string style: "classic"
  property color color: "white"

  width: 16
  height: 16

  readonly property bool ringed: style === "classic" || style === "fine" || style === "bold" || style === "filled" || style === "square"
  readonly property real stroke: style === "bold" ? 2.6 : style === "fine" ? 1 : 1.5

  // The lens.
  Rectangle {
    visible: glass.ringed
    width: 12
    height: 12
    radius: glass.style === "square" ? 2 : 6
    color: glass.style === "filled" ? Qt.rgba(glass.color.r, glass.color.g, glass.color.b, 0.35) : "transparent"
    border.width: glass.stroke
    border.color: glass.color
  }
  // The handle.
  Rectangle {
    visible: glass.ringed
    x: glass.style === "square" ? 10.5 : 9.5
    y: glass.style === "square" ? 12 : 11.5 - (glass.stroke - 1.5) / 2
    width: 6
    height: glass.stroke
    radius: 1
    color: glass.color
    rotation: 45
    transformOrigin: Item.Left
  }

  // Pixel art: one square per lit cell of an 8 by 8 grid.
  Repeater {
    model: glass.style === "pixel" ? [1, 2, 3, 8, 12, 16, 20, 24, 28, 33, 34, 35, 45, 54, 63] : []
    delegate: Rectangle {
      required property int modelData
      x: (modelData % 8) * 2
      y: Math.floor(modelData / 8) * 2
      width: 2
      height: 2
      color: glass.color
    }
  }

  // An arrow in place of a glass.
  Text {
    visible: glass.style === "arrow"
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: "→"
    color: glass.color
    font.pixelSize: 17
  }

  // Or just a dot.
  Rectangle {
    visible: glass.style === "dot"
    anchors.centerIn: parent
    width: 8
    height: 8
    radius: 4
    color: glass.color
  }
}
