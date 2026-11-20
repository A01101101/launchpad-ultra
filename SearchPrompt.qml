import QtQuick
import QtMultimedia
import qs.Commons

// What the empty search bar shows in place of typed text, as the settings
// pick: the plain word, a line that changes every few seconds, a confused
// face with question marks rising as it thinks, the user's own words, or (on
// the yellow LCD only) a clip.
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
  // The user's own words, for the "custom" mode.
  property string customText: ""
  // Reduce movement: everything holds still.
  property bool calm: false
  readonly property bool still: calm || Style.reduceMotion

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
      if (prompt.still) prompt.quip = (prompt.quip + 1) % prompt.quipKeys.length
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

    // ---- The confused face: a crooked mouth, one brow up, head tilting ---
    Item {
      id: face
      visible: prompt.mode === "confused"
      readonly property real d: Math.round(prompt.pixelSize * 1.15)
      readonly property bool moving: visible && prompt.visible && !prompt.still
      width: d * 1.6
      height: d
      anchors.verticalCenter: parent.verticalCenter

      Canvas {
        id: faceArt
        width: face.d
        height: face.d
        transformOrigin: Item.Bottom
        property color ink: prompt.ink
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
          var c = getContext("2d")
          var d = width
          var line = Math.max(1.5, d * 0.08)
          c.reset()
          c.strokeStyle = ink
          c.fillStyle = ink
          c.lineWidth = line
          c.lineCap = "round"
          c.lineJoin = "round"
          // Head.
          c.beginPath()
          c.arc(d / 2, d / 2, d / 2 - line, 0, Math.PI * 2)
          c.stroke()
          // Eyes.
          c.beginPath(); c.arc(d * 0.35, d * 0.42, d * 0.06, 0, Math.PI * 2); c.fill()
          c.beginPath(); c.arc(d * 0.65, d * 0.42, d * 0.06, 0, Math.PI * 2); c.fill()
          // One brow flat, one raised.
          c.beginPath(); c.moveTo(d * 0.25, d * 0.28); c.lineTo(d * 0.43, d * 0.28); c.stroke()
          c.beginPath(); c.moveTo(d * 0.57, d * 0.27); c.lineTo(d * 0.74, d * 0.19); c.stroke()
          // A wobbly, unsure mouth.
          c.beginPath()
          c.moveTo(d * 0.30, d * 0.70)
          c.bezierCurveTo(d * 0.40, d * 0.62, d * 0.48, d * 0.76, d * 0.58, d * 0.68)
          c.quadraticCurveTo(d * 0.65, d * 0.63, d * 0.71, d * 0.66)
          c.stroke()
        }

        // The head tips one way, then the other, as he puzzles it out.
        SequentialAnimation on rotation {
          running: face.moving
          loops: Animation.Infinite
          onRunningChanged: if (!running) faceArt.rotation = 0
          NumberAnimation { to: -10; duration: Style.duration(600); easing.type: Easing.InOutSine }
          PauseAnimation { duration: Style.duration(500) }
          NumberAnimation { to: 8; duration: Style.duration(700); easing.type: Easing.InOutSine }
          PauseAnimation { duration: Style.duration(400) }
          NumberAnimation { to: 0; duration: Style.duration(400); easing.type: Easing.InOutSine }
        }
      }

      // Question marks that rise off his head one after another and fade.
      Repeater {
        model: 3
        delegate: Text {
          id: mark
          required property int index
          textFormat: Text.PlainText
          text: "?"
          color: prompt.ink
          font.family: prompt.family
          font.bold: true
          font.pixelSize: Math.round(face.d * (0.45 + 0.1 * index))
          x: face.d * (0.92 + 0.18 * index)
          readonly property real restY: face.d * 0.25
          y: restY
          opacity: face.moving ? 0 : (index === 1 ? 1 : 0)

          SequentialAnimation {
            running: face.moving
            loops: Animation.Infinite
            PauseAnimation { duration: Style.duration(mark.index * 450) }
            ParallelAnimation {
              NumberAnimation { target: mark; property: "y"; from: mark.restY; to: -face.d * 0.25; duration: Style.duration(1100); easing.type: Easing.OutCubic }
              SequentialAnimation {
                NumberAnimation { target: mark; property: "opacity"; from: 0; to: 1; duration: Style.duration(250); easing.type: Easing.OutCubic }
                PauseAnimation { duration: Style.duration(450) }
                NumberAnimation { target: mark; property: "opacity"; to: 0; duration: Style.duration(400); easing.type: Easing.OutCubic }
              }
            }
            PauseAnimation { duration: Style.duration((2 - mark.index) * 450 + 300) }
          }
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
      width: parent.width - (pika.visible ? pika.width + parent.spacing : 0) - (face.visible ? face.width + parent.spacing : 0)
      text: prompt.mode === "quips" ? prompt.say(prompt.quipKeys[prompt.quip])
            : prompt.mode === "confused" ? prompt.say("search.thinking")
            : prompt.mode === "custom" && prompt.customText.trim() !== ""
              ? (prompt.upper ? prompt.customText.toUpperCase() : prompt.customText)
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
