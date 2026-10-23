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

  spacing: 10

  Text {
    text: root.glyph
    color: root.glyphColor
    font.family: root.fontFamily
    font.pixelSize: 18
  }
  Text {
    text: root.label.toUpperCase()
    color: P.textMuted
    font.family: root.fontFamily
    font.pixelSize: 14
    font.letterSpacing: 1.2
  }
  Item { Layout.fillWidth: true }
  Text {
    text: root.detail
    color: P.textMuted
    font.family: root.fontFamily
    font.pixelSize: 15
  }
}
