import QtQuick
import QtQuick.Layouts
import "../Palette.js" as P

// One chat or mail row: avatar, title + time, optional subject, preview text.
Rectangle {
  id: root

  property string title: ""
  property string meta: ""
  property string subject: ""
  property string preview: ""
  property bool unread: true
  property color avatarColor: P.chatAvatar
  property color avatarTextColor: P.chatAvatarText
  property string fontFamily: "monospace"

  implicitHeight: content.implicitHeight + 28
  color: P.item
  radius: P.itemRadius

  RowLayout {
    id: content
    anchors.fill: parent
    anchors.margins: 14
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    spacing: 16

    Rectangle {
      Layout.alignment: Qt.AlignTop
      Layout.preferredWidth: 44
      Layout.preferredHeight: 44
      radius: 22
      color: root.avatarColor
      Text {
        anchors.centerIn: parent
        text: P.initials(root.title)
        color: root.avatarTextColor
        font.family: root.fontFamily
        font.pixelSize: 16
        font.bold: true
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: 3

      RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
          Layout.fillWidth: true
          text: root.title
          color: root.unread ? P.textStrong : P.textSoft
          font.family: root.fontFamily
          font.pixelSize: 18
          font.weight: Font.Medium
          elide: Text.ElideRight
        }
        Text {
          text: root.meta
          color: P.textMuted
          font.family: root.fontFamily
          font.pixelSize: 14
        }
      }
      Text {
        Layout.fillWidth: true
        visible: root.subject !== ""
        text: root.subject
        color: "#c3cbd8"
        font.family: root.fontFamily
        font.pixelSize: 16
        font.weight: Font.Medium
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        visible: root.preview !== ""
        text: root.preview
        color: P.textSoft
        font.family: root.fontFamily
        font.pixelSize: 15
        lineHeight: 1.3
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
  }
}
