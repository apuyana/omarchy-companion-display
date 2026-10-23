import QtQuick
import "../Palette.js" as P

Rectangle {
  id: root

  property real value: 0
  property color fill: P.green

  implicitHeight: 4
  radius: height / 2
  color: P.track
  clip: true

  Rectangle {
    width: parent.width * Math.max(0, Math.min(1, root.value))
    height: parent.height
    radius: parent.radius
    color: root.fill
  }
}
