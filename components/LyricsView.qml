import QtQuick
import "../Palette.js" as P

// Lyrics for the current track. Synced lyrics keep the current line centered
// and highlighted; plain lyrics are shown as a scrollable list.
Item {
  id: root

  // Result of bin/companion-lyrics, or { loading: true }, or null.
  property var lyrics: null
  property int currentLine: -1
  property real size: 1
  property string fontFamily: "monospace"

  readonly property bool synced: !!(lyrics && lyrics.synced && lyrics.synced.length)
  readonly property var lines: !lyrics ? [] : (synced ? lyrics.synced : (lyrics.plain || []))
  readonly property string status: {
    if (!lyrics) return "Nothing playing"
    if (lyrics.loading) return "Searching lyrics…"
    if (lyrics.error) return "Lyrics unavailable right now"
    if (lyrics.instrumental) return "Instrumental"
    if (!lyrics.found || lines.length === 0) return "No lyrics found"
    return ""
  }

  clip: true

  // Glide to each new line while the song plays.
  onCurrentLineChanged: list.currentIndex = synced ? currentLine : -1
  function jumpToCurrent() {
    list.currentIndex = synced ? currentLine : -1
    if (list.currentIndex >= 0) list.positionViewAtIndex(list.currentIndex, ListView.Center)
    else list.positionViewAtBeginning()
  }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    visible: root.status !== ""
    text: root.status
    color: P.textMuted
    font.family: root.fontFamily
    font.pixelSize: 18 * root.size
  }

  ListView {
    id: list
    anchors.fill: parent
    visible: root.status === ""
    model: root.lines
    spacing: 14 * root.size
    currentIndex: -1
    // Keep the current line in the middle while the song plays.
    highlightRangeMode: root.synced && root.currentLine >= 0 ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
    preferredHighlightBegin: height / 2 - 24 * root.size
    preferredHighlightEnd: height / 2 + 24 * root.size
    highlightMoveDuration: 450
    interactive: !root.synced
    header: Item { height: root.synced ? list.height / 2 - 24 * root.size : 0 }
    footer: Item { height: root.synced ? list.height / 2 : 0 }
    // Jump straight to the current line when lyrics load or the view is
    // resized; ListView resets currentIndex on a new model, so set it here.
    onModelChanged: Qt.callLater(root.jumpToCurrent)
    onHeightChanged: Qt.callLater(root.jumpToCurrent)

    delegate: Text {
      textFormat: Text.PlainText
      required property var modelData
      required property int index
      readonly property bool current: root.synced && index === root.currentLine
      width: list.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.synced ? (modelData.text || "♪") : modelData
      color: current ? P.textStrong : (root.synced && index < root.currentLine ? "#5c5c64" : P.textSoft)
      font.family: root.fontFamily
      font.pixelSize: (current ? 26 : 21) * root.size
      font.weight: current ? Font.DemiBold : Font.Normal
      Behavior on color { ColorAnimation { duration: 250 } }
    }
  }

  // Fade the edges so lines scroll in and out softly.
  Rectangle {
    visible: list.visible
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: 40 * root.size
    gradient: Gradient {
      GradientStop { position: 0; color: P.card }
      GradientStop { position: 1; color: "transparent" }
    }
  }
  Rectangle {
    visible: list.visible
    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
    height: 40 * root.size
    gradient: Gradient {
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 1; color: P.card }
    }
  }
}
