import QtQuick
import QtMultimedia
import qs.Commons

// What the empty search bar shows in place of typed text, as the settings
// pick: the plain word, a line that changes every few seconds, a little
// figure scratching his head, or (on the yellow LCD only) a clip.
Item {
  id: prompt

  property string mode: "plain"
  property var catalog: null
  property color ink: "black"
  property string family: Style.font.family
  property real pixelSize: Style.font.title
  property bool bold: false
  property bool italic: false
  property int weight: Font.Normal
  property int capitalization: Font.MixedCase
  // The LCD shouts everything.
  property bool upper: false
  property url pikaSource

  readonly property var quipKeys: ["search.quip1", "search.quip2", "search.quip3", "search.quip4",
                                   "search.quip5", "search.quip6", "search.quip7", "search.quip8"]
  property int quip: 0

  function say(key) {
    var text = prompt.catalog ? prompt.catalog.t(key) : key
    return prompt.upper ? text.toUpperCase() : text
  }

  // A fresh line each time the bar comes up empty, then one every few seconds.
  onVisibleChanged: if (visible && mode === "quips") quip = Math.floor(Math.random() * quipKeys.length)

  Timer {
    running: prompt.visible && prompt.mode === "quips"
    repeat: true
    interval: 3200
    onTriggered: {
      if (Style.reduceMotion) prompt.quip = (prompt.quip + 1) % prompt.quipKeys.length
      else swap.restart()
    }
  }

  SequentialAnimation {
    id: swap
    NumberAnimation { target: line; property: "opacity"; to: 0; duration: Style.duration(120); easing.type: Easing.OutCubic }
    ScriptAction { script: prompt.quip = (prompt.quip + 1) % prompt.quipKeys.length }
    NumberAnimation { target: line; property: "opacity"; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: Math.round(prompt.pixelSize * 0.3)

    // ---- The head scratcher, drawn on a 24-unit grid in the bar's ink -----
    Item {
      id: thinker
      visible: prompt.mode === "thinker"
      readonly property real u: Math.round(prompt.pixelSize * 1.25) / 24
      width: 24 * u
      height: 24 * u
      anchors.verticalCenter: parent.verticalCenter

      // Shoulders.
      Rectangle { x: 3 * thinker.u; y: 16 * thinker.u; width: 14 * thinker.u; height: 8 * thinker.u; radius: 4 * thinker.u; color: prompt.ink }
      // Head.
      Rectangle { id: head; x: 4 * thinker.u; y: 3 * thinker.u; width: 11 * thinker.u; height: 11 * thinker.u; radius: width / 2; color: prompt.ink }
      // Eyes glancing up, and a puzzled mouth, cut out of the head.
      Rectangle { x: 7.5 * thinker.u; y: 6.5 * thinker.u; width: 1.8 * thinker.u; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.9) }
      Rectangle { x: 10.5 * thinker.u; y: 6.5 * thinker.u; width: 1.8 * thinker.u; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.9) }
      Rectangle { x: 8 * thinker.u; y: 10.8 * thinker.u; width: 3.5 * thinker.u; height: 0.9 * thinker.u; radius: height / 2; rotation: -12; color: Qt.rgba(1, 1, 1, 0.9) }

      // The arm, raised from the shoulder to the top of the head, rocking
      // back and forth as it scratches.
      Item {
        id: arm
        x: 15 * thinker.u
        y: 3.5 * thinker.u
        width: 2.4 * thinker.u
        height: 13 * thinker.u
        transformOrigin: Item.Bottom
        rotation: -8

        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 2 * thinker.u; width: parent.width; height: parent.height - 2 * thinker.u; radius: width / 2; color: prompt.ink }
        // The hand.
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 0; width: 3.6 * thinker.u; height: width; radius: width / 2; color: prompt.ink }

        SequentialAnimation on rotation {
          running: thinker.visible && prompt.visible && !Style.reduceMotion
          loops: Animation.Infinite
          // Four quick scratches, then a pause to think.
          SequentialAnimation {
            loops: 4
            NumberAnimation { to: -20; duration: Style.duration(110); easing.type: Easing.OutCubic }
            NumberAnimation { to: -8; duration: Style.duration(110); easing.type: Easing.OutCubic }
          }
          PauseAnimation { duration: Style.duration(900) }
        }
      }

      // A question mark that bobs above him.
      Text {
        textFormat: Text.PlainText
        x: 18.5 * thinker.u
        y: -3 * thinker.u
        text: "?"
        color: prompt.ink
        font.family: prompt.family
        font.bold: true
        font.pixelSize: Math.round(9 * thinker.u)

        SequentialAnimation on opacity {
          running: thinker.visible && prompt.visible && !Style.reduceMotion
          loops: Animation.Infinite
          NumberAnimation { to: 0.25; duration: Style.duration(260); easing.type: Easing.OutCubic }
          NumberAnimation { to: 1; duration: Style.duration(260); easing.type: Easing.OutCubic }
          PauseAnimation { duration: Style.duration(500) }
        }
      }
    }

    // ---- The easter egg: a looping clip, yellow LCD only -----------------
    Video {
      id: pika
      visible: prompt.mode === "pika"
      height: Math.round(prompt.pixelSize * 1.5)
      width: height
      anchors.verticalCenter: parent.verticalCenter
      source: visible && prompt.visible ? prompt.pikaSource : ""
      loops: MediaPlayer.Infinite
      muted: true
      autoPlay: true
      fillMode: VideoOutput.PreserveAspectFit
    }

    Text {
      id: line
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - (thinker.visible ? thinker.width + parent.spacing : 0) - (pika.visible ? pika.width + parent.spacing : 0)
      text: prompt.mode === "quips" ? prompt.say(prompt.quipKeys[prompt.quip])
            : prompt.mode === "thinker" ? prompt.say("search.thinking")
            : prompt.say("search.placeholder")
      color: prompt.ink
      font.family: prompt.family
      font.bold: prompt.bold
      font.italic: prompt.italic
      font.weight: prompt.weight
      font.capitalization: prompt.capitalization
      font.pixelSize: prompt.pixelSize
      elide: Text.ElideRight
    }
  }
}
