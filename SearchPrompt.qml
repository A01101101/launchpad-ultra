import QtQuick
import QtMultimedia
import qs.Commons

// What the empty search bar shows in place of typed text, as the settings
// pick: the plain word, a line that changes every few seconds, or (on the
// yellow LCD only) a clip.
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
      width: parent.width - (pika.visible ? pika.width + parent.spacing : 0)
      text: prompt.mode === "quips" ? prompt.say(prompt.quipKeys[prompt.quip])
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
