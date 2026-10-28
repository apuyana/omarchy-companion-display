import QtQuick
import QtQuick.Layouts
import "../Palette.js" as P

RowLayout {
  id: root

  property string glyph: ""
  property color glyphColor: P.textMuted
  property string label: ""
  property string detail: ""
  property string fontFamily: "monospace"
  // Clear-all button: shown while showClear (e.g. the card is hovered) and
  // there is something to clear. The first click arms it, a second click
  // within three seconds clears.
  property bool clearable: false
  property bool showClear: false
  property bool armed: false

  signal cleared()

  spacing: 10

  Timer {
    id: disarm
    interval: 3000
    onTriggered: root.armed = false
  }

  Text {
    textFormat: Text.PlainText
    text: root.glyph
    color: root.glyphColor
    font.family: root.fontFamily
    font.pixelSize: 18
  }
  Text {
    textFormat: Text.PlainText
    text: root.label.toUpperCase()
    color: P.textMuted
    font.family: root.fontFamily
    font.pixelSize: 14
    font.letterSpacing: 1.2
  }
  Item { Layout.fillWidth: true }
  Text {
    textFormat: Text.PlainText
    text: root.detail
    color: P.textMuted
    font.family: root.fontFamily
    font.pixelSize: 15
  }
  Rectangle {
    visible: root.clearable && (root.showClear || root.armed)
    Layout.preferredWidth: root.armed ? armedLabel.implicitWidth + 20 : 28
    Layout.preferredHeight: 28
    radius: 14
    color: root.armed || clearMouse.containsMouse ? P.track : "transparent"
    Text {
      textFormat: Text.PlainText
      id: armedLabel
      anchors.centerIn: parent
      text: root.armed ? "Clear all?" : "\u{F00E2}"
      color: root.armed ? P.amber : clearMouse.containsMouse ? P.textStrong : P.textMuted
      font.family: root.fontFamily
      font.pixelSize: root.armed ? 14 : 16
    }
    MouseArea {
      id: clearMouse
      anchors.fill: parent
      anchors.margins: -6
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (root.armed) {
          disarm.stop()
          root.armed = false
          root.cleared()
        } else {
          root.armed = true
          disarm.restart()
        }
      }
    }
  }
}
