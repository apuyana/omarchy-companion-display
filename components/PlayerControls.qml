import QtQuick
import QtQuick.Layouts
import "../Palette.js" as P

// Previous / play-pause / next for an MPRIS player.
RowLayout {
  id: root

  property var player: null
  property real size: 1
  property string fontFamily: "monospace"

  spacing: 6 * size

  component RoundButton: Rectangle {
    id: btn
    property string glyph: ""
    property bool primary: false
    property bool enabledState: true
    signal clicked()
    implicitWidth: (primary ? 56 : 46) * root.size
    implicitHeight: implicitWidth
    radius: implicitWidth / 2
    color: primary ? "#d0d0d4" : (mouse.containsMouse ? P.item : "transparent")
    opacity: enabledState ? 1 : 0.35
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: btn.glyph
      color: btn.primary ? P.background : "#a8a8b0"
      font.family: root.fontFamily
      font.pixelSize: (btn.primary ? 24 : 22) * root.size
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.enabledState
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  RoundButton {
    glyph: "\u{F04AE}"
    enabledState: !!root.player && root.player.canGoPrevious
    onClicked: root.player.previous()
  }
  RoundButton {
    primary: true
    glyph: root.player && root.player.isPlaying ? "\u{F03E4}" : "\u{F040A}"
    enabledState: !!root.player && root.player.canTogglePlaying
    onClicked: root.player.togglePlaying()
  }
  RoundButton {
    glyph: "\u{F04AD}"
    enabledState: !!root.player && root.player.canGoNext
    onClicked: root.player.next()
  }
}
