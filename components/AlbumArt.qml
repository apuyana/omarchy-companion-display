import QtQuick
import "../Palette.js" as P

Rectangle {
  id: root

  property string source: ""
  property string fontFamily: "monospace"

  color: "#1a1a1e"
  radius: 10
  clip: true

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    visible: art.status !== Image.Ready
    text: "\u{F075A}"
    color: "#5c5c64"
    font.family: root.fontFamily
    font.pixelSize: Math.max(18, root.width * 0.3)
  }

  Image {
    id: art
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: root.width * 2
    sourceSize.height: root.height * 2
  }
}
