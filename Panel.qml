import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Commons
import "components"
import "Palette.js" as P

// Companion display: a full-screen, always-on dashboard on a secondary
// monitor. Lives on the Bottom layer, so any window opened on that monitor
// still covers it.
Item {
  id: root

  property string omarchyPath: ""
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string fontFamily: Style.font.family

  // ------------------------------------------------------------ config

  property var config: ({})
  readonly property string screenName: config.screen || "HDMI-A-1"
  readonly property int idleSeconds: config.idleSeconds || 300
  readonly property bool privacy: config.privacy === true
  function moduleOn(name) {
    var m = config.modules || {}
    return m[name] !== false
  }

  FileView {
    id: configFile
    path: root.home + "/.config/omarchy/companion-display.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.config = JSON.parse(text()) } catch (e) { root.config = {} }
      feed.send("refresh")
    }
    onLoadFailed: root.config = {}
  }

  // -------------------------------------------------------------- feed

  property var feedState: ({ phone: {}, chats: [], mail: [], mailNew: 0, apps: [] })
  // Phone sections hide themselves on machines without a paired KDE Connect device.
  readonly property bool hasPhone: !!(feedState.phone && feedState.phone.name)

  function applyFeed(line) {
    var next
    try { next = JSON.parse(line) } catch (e) { return }
    var prev = root.feedState
    root.feedState = next
    if (root.signature(next) !== root.signature(prev)
        || root.appsTotal(next) > root.appsTotal(prev)
        || (root.busyCount(prev) > 0 && root.busyCount(next) === 0))
      root.markActivity()
  }

  // Wake-up rules besides new chats and mail: a new notification from any
  // other phone app, and Claude Code going from working to all sessions done.
  function appsTotal(s) {
    var a = s.apps || [], n = 0
    for (var i = 0; i < a.length; i++) n += a[i].count
    return n
  }
  function busyCount(s) {
    var c = s.claude || [], n = 0
    for (var i = 0; i < c.length; i++) if (c[i].status === "busy") n++
    return n
  }

  // Something new arrived: newest chat/mail time or counts changed.
  function signature(s) {
    var chats = s.chats || [], mail = s.mail || []
    return [chats.length, chats.length ? chats[0].ts : 0, mail.length ? mail[0].ts : 0, s.mailNew || 0].join("|")
  }

  Process {
    id: feed
    command: ["python3", root.pluginDir + "/bin/companion-feed"]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: data => root.applyFeed(data) }
    onExited: feedRestart.start()
    function send(cmd) { if (running) write(cmd + "\n") }
  }
  Timer { id: feedRestart; interval: 5000; onTriggered: feed.running = true }

  // ------------------------------------------------------- open apps

  // Focus the app's window if it is already open, otherwise launch it.
  Process { id: opener }
  function openApp(args) {
    opener.command = args
    opener.running = true
  }
  // Commands run when a section is clicked; override them under "launch" in
  // the config. An empty list disables the click.
  readonly property var defaultLaunch: ({
    chats: ["omarchy-launch-or-focus-webapp", "web.whatsapp.com", "https://web.whatsapp.com/"],
    player: ["omarchy-launch-or-focus", "^spotify$", "spotify"],
    claude: ["omarchy-launch-or-focus", "^com.anthropic.Claude$", "claude-desktop"],
    mail: [root.pluginDir + "/bin/open-default-app", "x-scheme-handler/mailto"]
  })
  function launch(name) {
    var custom = root.config.launch || {}
    var cmd = custom[name] !== undefined ? custom[name] : root.defaultLaunch[name]
    if (cmd && cmd.length) openApp(cmd)
  }
  function openWhatsApp() { launch("chats") }
  function openSpotify() { launch("player") }
  function openClaude() { launch("claude") }
  // Opening the mail app (the system default mail client unless configured)
  // also marks every mail as seen.
  function openMail() { feed.send("seen"); launch("mail") }

  // ------------------------------------------------------------ claude

  property var claude: null
  FileView {
    path: root.home + "/.local/state/omarchy/agents/usage/claude.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.claude = JSON.parse(text()) } catch (e) { root.claude = null } }
  }
  function claudeWorking() {
    var list = root.feedState.claude || [], n = 0
    for (var i = 0; i < list.length; i++) if (list[i].status === "busy") n++
    return n
  }
  // A session that went idle in the last few minutes has just finished and
  // is waiting for you.
  readonly property int claudeDoneWindow: (root.config.claude && root.config.claude.doneMinutes ? root.config.claude.doneMinutes : 15) * 60
  function claudeState(sess) {
    var age = clockTick.now.getTime() / 1000 - sess.since
    if (sess.status === "busy") return { label: "working", color: P.green, age: age }
    if (sess.status === "idle" && age < root.claudeDoneWindow) return { label: "done", color: P.blue, age: age }
    if (sess.status === "idle") return { label: "idle", color: P.textMuted, age: age }
    return { label: "waiting", color: P.amber, age: age }
  }
  function ago(seconds) {
    if (seconds < 60) return "now"
    if (seconds < 3600) return Math.floor(seconds / 60) + "m"
    if (seconds < 86400) return Math.floor(seconds / 3600) + "h"
    return Math.floor(seconds / 86400) + "d"
  }
  function claudeLimit(i) {
    var l = root.claude && root.claude.limits ? root.claude.limits[i] : null
    return l ? Math.round(l.percent * 100) : -1
  }

  // Take tasks in turns from each status (blocked, in review, in progress) so
  // a long list of one kind does not hide the others.
  function pickIssues(issues, max) {
    var groups = {}, order = []
    for (var i = 0; i < issues.length; i++) {
      var st = issues[i].status
      if (!groups[st]) { groups[st] = []; order.push(st) }
      groups[st].push(issues[i])
    }
    var picked = []
    for (var round = 0; picked.length < max; round++) {
      var added = false
      for (var j = 0; j < order.length && picked.length < max; j++) {
        if (round < groups[order[j]].length) { picked.push(groups[order[j]][round]); added = true }
      }
      if (!added) break
    }
    var rank = {}
    for (var k = 0; k < order.length; k++) rank[order[k]] = k
    return picked.sort(function (a, b) { return rank[a.status] - rank[b.status] })
  }

  // ------------------------------------------------------------- media

  readonly property var player: {
    var list = Mpris.players ? Mpris.players.values : []
    var titled = null
    for (var i = 0; i < list.length; i++) {
      if (list[i].isPlaying) return list[i]
      if (!titled && list[i].trackTitle) titled = list[i]
    }
    return titled
  }
  property bool playerExpanded: false
  property bool claudeExpanded: false

  // Lyrics button (lines with a music note) that opens and closes the lyrics.
  component LyricsToggle: Text {
    text: "\u{F0CB8}"
    color: root.lyricsOpen ? P.green : P.textMuted
    font.family: root.fontFamily
    font.pixelSize: 22
    MouseArea { anchors.fill: parent; anchors.margins: -12; cursorShape: Qt.PointingHandCursor; onClicked: root.lyricsOpen = !root.lyricsOpen }
  }
  // Start expanded when the config asks for it (re-applied on config changes).
  onConfigChanged: claudeExpanded = !!(config.claude && config.claude.expanded)

  Timer {
    // Faster ticks while synced lyrics follow the song.
    interval: root.lyricsOpen ? 250 : 1000
    repeat: true
    running: !!root.player && root.player.isPlaying
    onTriggered: root.player.positionChanged()
  }

  // ------------------------------------------------------------ lyrics

  // Lyrics open as a panel above the compact player, or in place of the
  // album art in the expanded player. Fetched from LRCLIB only while open.
  property bool lyricsOpen: false
  property var lyrics: null
  readonly property string trackKey: root.player && root.player.trackTitle
    ? (root.player.trackArtist || "") + "\n" + root.player.trackTitle : ""
  property string lyricsKey: ""
  onTrackKeyChanged: fetchLyrics()
  onLyricsOpenChanged: fetchLyrics()

  function fetchLyrics() {
    if (!root.lyricsOpen || root.lyricsKey === root.trackKey) return
    root.lyricsKey = root.trackKey
    if (!root.trackKey) { root.lyrics = null; return }
    root.lyrics = { loading: true }
    lyricsProc.running = false
    lyricsProc.command = ["python3", root.pluginDir + "/bin/companion-lyrics",
      root.player.trackArtist || "", root.player.trackTitle,
      root.player.trackAlbum || "", String(Math.round(root.player.length || 0))]
    lyricsProc.running = true
  }

  Process {
    id: lyricsProc
    stdout: StdioCollector {
      onStreamFinished: {
        var r
        try { r = JSON.parse(text) } catch (e) { return }
        // Drop answers for a song that already ended.
        if (r.track && r.track.join("\n") === root.lyricsKey) root.lyrics = r
      }
    }
  }

  // Last synced line whose time has come; a small lead feels in step.
  readonly property int lyricsLine: {
    var l = root.lyrics && root.lyrics.synced
    if (!l || !l.length || !root.player) return -1
    var pos = root.player.position + 0.3, idx = -1
    for (var i = 0; i < l.length && l[i].t <= pos; i++) idx = i
    return idx
  }

  // ------------------------------------------------- idle + burn-in care

  property real lastActivity: Date.now()
  property bool idle: false
  function markActivity() { lastActivity = Date.now(); idle = false }

  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.idle = (Date.now() - root.lastActivity) > root.idleSeconds * 1000
  }

  // Small, slow shift of the whole layout so no edge stays on the same pixels.
  property int shiftX: 0
  property int shiftY: 0
  Timer {
    interval: 10 * 60 * 1000
    repeat: true
    running: true
    onTriggered: { root.shiftX = Math.round(Math.random() * 12 - 6); root.shiftY = Math.round(Math.random() * 12 - 6) }
  }

  // ------------------------------------------------------------ bar cover

  // The Omarchy bar shows on every monitor. With hideBar, a black strip on the
  // Overlay layer covers it on this monitor only, so nothing bright stays lit.
  readonly property bool hideBar: config.hideBar === true
  property string barPosition: "top"
  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.barPosition = (JSON.parse(text()).bar || {}).position || "top" } catch (e) {}
    }
  }

  PanelWindow {
    id: barCover
    readonly property bool horizontal: root.barPosition === "top" || root.barPosition === "bottom"
    // The main window sits beside the bar's exclusive zone, so the gap between
    // it and the screen edge is exactly the bar's thickness.
    readonly property int thickness: !root.targetScreen ? 0 : (horizontal
      ? root.targetScreen.height - window.height
      : root.targetScreen.width - window.width)
    screen: root.targetScreen
    visible: root.hideBar && root.targetScreen !== null && thickness > 0
    color: P.idleBackground
    anchors {
      top: root.barPosition !== "bottom"
      bottom: root.barPosition !== "top"
      left: root.barPosition !== "right"
      right: root.barPosition !== "left"
    }
    implicitHeight: horizontal ? thickness : 0
    implicitWidth: horizontal ? 0 : thickness
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-companion-display-bar-cover"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  }

  // ------------------------------------------------------------ window

  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === root.screenName) return screens[i]
    return null
  }

  PanelWindow {
    id: window
    screen: root.targetScreen
    visible: root.targetScreen !== null
    color: root.idle ? P.idleBackground : P.background
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "omarchy-companion-display"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onPositionChanged: root.markActivity()
    }

    // ------------------------------------------------------ active view
    ColumnLayout {
      id: active
      visible: !root.idle
      anchors.fill: parent
      anchors.margins: 32
      anchors.leftMargin: 32 + root.shiftX
      anchors.rightMargin: 32 - root.shiftX
      anchors.topMargin: 24 + root.shiftY
      anchors.bottomMargin: 32 - root.shiftY
      spacing: P.gap

      // Clock, mail count, other phone notifications
      RowLayout {
        Layout.fillWidth: true
        visible: !root.playerExpanded && (root.moduleOn("clock") || root.moduleOn("mail") || root.moduleOn("apps"))
        spacing: P.gap

        Card {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.preferredHeight: 120
          visible: root.moduleOn("clock")
          ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 28
            spacing: 6
            Text {
              id: clock
              color: "#d4d4d8"
              font.family: root.fontFamily
              font.pixelSize: 54
              font.weight: Font.Medium
              text: Qt.formatTime(clockTick.now, "HH:mm")
            }
            Text {
              color: P.textMuted
              font.family: root.fontFamily
              font.pixelSize: 16
              text: {
                var d = clockTick.now.toLocaleDateString(Qt.locale(root.config.locale || "en_US"), root.config.dateFormat || "dddd, MMMM d")
                return d.charAt(0).toUpperCase() + d.slice(1)
              }
            }
          }
          Timer {
            id: clockTick
            property date now: new Date()
            interval: 15000
            repeat: true
            running: true
            onTriggered: now = new Date()
          }
        }

        Card {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.preferredHeight: 120
          visible: root.moduleOn("mail")
          RowLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 28
            spacing: 22
            Text { text: ""; color: P.blue; font.family: root.fontFamily; font.pixelSize: 36 }
            ColumnLayout {
              spacing: 4
              Text {
                text: root.feedState.mailNew || 0
                color: P.textStrong
                font.family: root.fontFamily
                font.pixelSize: 50
                font.weight: Font.DemiBold
              }
              Text { text: "new emails"; color: P.textMuted; font.family: root.fontFamily; font.pixelSize: 16 }
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openMail()
          }
        }

        // Other phone notifications, counted per app
        Card {
          id: appsCard
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.preferredHeight: 120
          visible: root.moduleOn("apps") && root.hasPhone
          readonly property var apps: root.feedState.apps || []
          readonly property int total: {
            var n = 0
            for (var i = 0; i < apps.length; i++) n += apps[i].count
            return n
          }
          RowLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 28
            anchors.rightMargin: 20
            spacing: 22
            Text { text: "\uF10B"; color: P.textMuted; font.family: root.fontFamily; font.pixelSize: 36 }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 4
              Text {
                text: appsCard.total
                color: P.textStrong
                font.family: root.fontFamily
                font.pixelSize: 50
                font.weight: Font.DemiBold
              }
              Text {
                Layout.fillWidth: true
                text: {
                  var a = appsCard.apps
                  if (!a.length) return "phone notifications"
                  return a.map(function (x) { return x.count > 1 ? x.app + " " + x.count : x.app }).join(" · ")
                }
                color: P.textMuted
                font.family: root.fontFamily
                font.pixelSize: 16
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      // Paperclip tasks
      Card {
        id: paperclipCard
        readonly property var pc: root.feedState.paperclip
        Layout.fillWidth: true
        Layout.preferredHeight: paperclipBody.implicitHeight + 44
        visible: !root.playerExpanded && root.moduleOn("paperclip") && pc !== null && pc !== undefined
        ColumnLayout {
          id: paperclipBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: P.pad
          anchors.topMargin: 22
          spacing: 16

          SectionHeader {
            Layout.fillWidth: true
            fontFamily: root.fontFamily
            glyph: ""
            glyphColor: P.amber
            label: "Paperclip" + (root.config.paperclip && root.config.paperclip.name ? " · " + root.config.paperclip.name : "")
            detail: {
              var pc = paperclipCard.pc
              if (!pc || !pc.ok) return ""
              var parts = []
              if (pc.agentsBusy) parts.push(pc.agentsBusy + " working")
              parts.push(pc.agentsIdle + " idle")
              if (pc.agentsPaused) parts.push(pc.agentsPaused + " paused")
              if (pc.agentsError) parts.push(pc.agentsError + " failing")
              return parts.join(" · ")
            }
          }

          Text {
            visible: !!paperclipCard.pc && !paperclipCard.pc.ok
            text: paperclipCard.pc ? (paperclipCard.pc.error || "") : ""
            color: P.textSoft
            font.family: root.fontFamily
            font.pixelSize: 16
          }

          GridLayout {
            Layout.fillWidth: true
            visible: !!paperclipCard.pc && paperclipCard.pc.ok
            columns: 4
            columnSpacing: 12
            Repeater {
              model: {
                var pc = paperclipCard.pc || {}
                return [
                  { value: pc.blocked || 0, label: "blocked", color: P.amber },
                  { value: pc.inReview || 0, label: "in review", color: P.blue },
                  { value: pc.inProgress || 0, label: "in progress", color: P.text },
                  { value: pc.approvals || 0, label: "approvals", color: (pc.approvals || 0) > 0 ? P.amber : P.text }
                ]
              }
              Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 72
                radius: 12
                color: P.item
                ColumnLayout {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  spacing: 0
                  Text { text: modelData.value; color: modelData.color; font.family: root.fontFamily; font.pixelSize: 30; font.weight: Font.DemiBold }
                  Text { text: modelData.label; color: P.textMuted; font.family: root.fontFamily; font.pixelSize: 14 }
                }
              }
            }
          }

          Repeater {
            model: paperclipCard.pc && paperclipCard.pc.ok ? root.pickIssues(paperclipCard.pc.issues, root.config.paperclip && root.config.paperclip.maxIssues ? root.config.paperclip.maxIssues : 4) : []
            Rectangle {
              id: issueRow
              required property var modelData
              Layout.fillWidth: true
              Layout.leftMargin: -10
              Layout.rightMargin: -10
              implicitHeight: issueContent.implicitHeight + 12
              radius: 10
              color: issueMouse.containsMouse ? P.item : "transparent"
              MouseArea {
                id: issueMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !!issueRow.modelData.url
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["xdg-open", issueRow.modelData.url])
              }
              RowLayout {
                id: issueContent
                readonly property var modelData: issueRow.modelData
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 14
                Text {
                  Layout.preferredWidth: 96
                  text: modelData.identifier
                  color: modelData.status === "blocked" ? P.amber : (modelData.status === "in_review" ? P.blue : P.textSoft)
                  font.family: root.fontFamily
                  font.pixelSize: 16
                }
                Text {
                  Layout.fillWidth: true
                  text: modelData.title
                  color: P.text
                  font.family: root.fontFamily
                  font.pixelSize: 16
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.assignee
                  color: P.textMuted
                  font.family: root.fontFamily
                  font.pixelSize: 15
                }
              }
            }
          }
        }
      }

      // Chats from the phone
      Card {
        id: chatsCard
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: chatsCol.implicitHeight + 22 + P.pad
        Layout.maximumHeight: chatsCol.implicitHeight + 22 + P.pad
        Layout.minimumHeight: 0
        visible: !root.playerExpanded && root.moduleOn("chats") && root.hasPhone
        clip: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openWhatsApp()
        }
        ColumnLayout {
          id: chatsCol
          anchors.fill: parent
          anchors.margins: P.pad
          anchors.topMargin: 22
          spacing: 12
          SectionHeader {
            Layout.fillWidth: true
            fontFamily: root.fontFamily
            glyph: ""
            glyphColor: P.green
            label: "Chats · " + (root.feedState.phone.name || "phone") + (root.feedState.phone.reachable === false ? " (offline)" : "")
            detail: {
              var c = root.feedState.chats || [], n = 0
              for (var i = 0; i < c.length; i++) n += c[i].count
              return c.length ? c.length + (c.length === 1 ? " chat · " : " chats · ") + n + (n === 1 ? " message" : " messages") : "no messages"
            }
          }
          Repeater {
            model: root.feedState.chats || []
            MessageItem {
              required property var modelData
              Layout.fillWidth: true
              fontFamily: root.fontFamily
              title: modelData.title
              meta: P.timeLabel(modelData.ts) + (modelData.count > 1 ? " · " + modelData.count : "")
              preview: root.privacy ? "" : modelData.text
              dismissable: (modelData.keys || []).length > 0
              onDismissed: feed.send("dismiss " + modelData.keys.join(" "))
            }
          }
          Item { Layout.fillHeight: true }
        }
      }

      // Mail
      Card {
        id: mailCard
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: mailCol.implicitHeight + 22 + P.pad
        Layout.maximumHeight: mailCol.implicitHeight + 22 + P.pad
        Layout.minimumHeight: 0
        visible: !root.playerExpanded && root.moduleOn("mail")
        clip: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openMail()
        }
        ColumnLayout {
          id: mailCol
          anchors.fill: parent
          anchors.margins: P.pad
          anchors.topMargin: 22
          spacing: 12
          SectionHeader {
            Layout.fillWidth: true
            fontFamily: root.fontFamily
            glyph: ""
            glyphColor: P.blue
            label: "Mail"
            detail: (root.feedState.mail || []).length ? (root.feedState.mailNew || 0) + " new" : "no mail"
          }
          Repeater {
            model: root.feedState.mail || []
            MessageItem {
              required property var modelData
              readonly property var parts: P.splitMail(modelData.body)
              Layout.fillWidth: true
              fontFamily: root.fontFamily
              avatarColor: P.mailAvatar
              avatarTextColor: P.mailAvatarText
              unread: modelData.new
              title: modelData.summary
              meta: P.timeLabel(modelData.ts) + (modelData.source === "phone" ? " · " + modelData.app : "")
              subject: parts.subject
              preview: root.privacy ? "" : parts.preview
              dismissable: (modelData.keys || []).length > 0
              onDismissed: feed.send("dismiss " + modelData.keys.join(" "))
            }
          }
          Item { Layout.fillHeight: true }
        }
      }

      // Pushes the bottom rows down when chats/mail are short
      Item { Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 0; visible: !root.playerExpanded }

      // Claude Code: one-line counter, expands upward to list every session
      Card {
        id: claudeCard
        readonly property var sessions: root.feedState.claude || []
        readonly property var counts: {
          var c = { working: 0, done: 0, waiting: 0, idle: 0 }
          for (var i = 0; i < sessions.length; i++) {
            var st = root.claudeState(sessions[i]).label
            c[st] = (c[st] || 0) + 1
          }
          return c
        }
        Layout.fillWidth: true
        Layout.preferredHeight: claudeBody.implicitHeight + 32
        visible: !root.playerExpanded && root.moduleOn("claude") && (sessions.length > 0 || root.claude !== null)

        ColumnLayout {
          id: claudeBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: 24
          anchors.rightMargin: 18
          anchors.topMargin: 16
          spacing: 10

          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 14
            Text { text: "\u{F06A9}"; color: P.amber; font.family: root.fontFamily; font.pixelSize: 20 }
            Repeater {
              model: [
                { key: "working", color: P.green },
                { key: "done", color: P.blue },
                { key: "waiting", color: P.amber },
                { key: "idle", color: P.textMuted }
              ]
              RowLayout {
                required property var modelData
                readonly property int n: claudeCard.counts[modelData.key] || 0
                visible: n > 0 || modelData.key === "working"
                spacing: 8
                Rectangle { Layout.preferredWidth: 10; Layout.preferredHeight: 10; radius: 5; color: modelData.color }
                Text {
                  text: parent.n + " " + modelData.key
                  color: modelData.key === "idle" ? P.textMuted : P.text
                  font.family: root.fontFamily
                  font.pixelSize: 16
                }
              }
            }
            Item { Layout.fillWidth: true }
            Text {
              color: P.textMuted
              font.family: root.fontFamily
              font.pixelSize: 15
              text: {
                var parts = []
                var s = root.claudeLimit(0), w = root.claudeLimit(1)
                if (s >= 0) parts.push("5h " + s + "%")
                if (w >= 0) parts.push("week " + w + "%")
                return parts.join(" · ")
              }
            }
            Text {
              text: root.claudeExpanded ? "\u{F0140}" : "\u{F0143}"
              color: P.textMuted
              font.family: root.fontFamily
              font.pixelSize: 22
            }
          }

          Repeater {
            model: root.claudeExpanded ? claudeCard.sessions : []
            RowLayout {
              required property var modelData
              readonly property var state: root.claudeState(modelData)
              Layout.fillWidth: true
              spacing: 14
              Rectangle {
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                radius: 5
                color: parent.state.color
              }
              Text {
                Layout.fillWidth: true
                text: modelData.name
                color: parent.state.label === "idle" ? P.textSoft : P.text
                font.family: root.fontFamily
                font.pixelSize: 16
                elide: Text.ElideRight
              }
              Text {
                Layout.maximumWidth: 220
                text: modelData.project
                color: P.textMuted
                font.family: root.fontFamily
                font.pixelSize: 15
                elide: Text.ElideRight
              }
              Text {
                Layout.preferredWidth: 110
                horizontalAlignment: Text.AlignRight
                text: parent.state.label + " · " + root.ago(parent.state.age)
                color: parent.state.color
                font.family: root.fontFamily
                font.pixelSize: 15
              }
            }
          }

          Text {
            visible: root.claudeExpanded && claudeCard.sessions.length === 0
            text: "No open sessions"
            color: P.textSoft
            font.family: root.fontFamily
            font.pixelSize: 16
          }
        }

        // The counter row toggles the list.
        MouseArea {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 64
          cursorShape: Qt.PointingHandCursor
          onClicked: root.claudeExpanded = !root.claudeExpanded
        }

        // The Claude icon opens Claude Desktop.
        MouseArea {
          anchors.left: parent.left
          anchors.top: parent.top
          width: 60
          height: 64
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openClaude()
          Rectangle {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 4
            width: 40
            height: 40
            radius: 20
            // Drawn over the icon, so only a ring.
            color: "transparent"
            border.width: parent.containsMouse ? 1 : 0
            border.color: P.textMuted
          }
        }
      }

      // Expanded player: summary row on top, big player below
      RowLayout {
        Layout.fillWidth: true
        visible: root.playerExpanded
        spacing: 16
        Repeater {
          model: [
            { value: Qt.formatTime(clockTick.now, "HH:mm"), label: "time", color: "#d4d4d8" },
            { value: String(root.feedState.mailNew || 0), label: "emails", color: P.blue },
            { value: String((root.feedState.chats || []).length), label: "chats", color: P.green },
            { value: String(root.claudeWorking()), label: "Claude working", color: P.amber }
          ]
          Card {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            ColumnLayout {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 20
              spacing: 2
              Text { text: modelData.value; color: modelData.color; font.family: root.fontFamily; font.pixelSize: 30 }
              Text { text: modelData.label; color: P.textMuted; font.family: root.fontFamily; font.pixelSize: 14 }
            }
          }
        }
      }

      Card {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.playerExpanded
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 36
          spacing: 28
          RowLayout {
            Layout.fillWidth: true
            SectionHeader {
              Layout.fillWidth: true
              fontFamily: root.fontFamily
              glyph: ""
              glyphColor: P.green
              label: root.player ? (root.player.identity || "Player") : "Player"
            }
            LyricsToggle { }
            Text {
              text: "\u{F0294}"
              color: P.textMuted
              font.family: root.fontFamily
              font.pixelSize: 22
              MouseArea { anchors.fill: parent; anchors.margins: -12; cursorShape: Qt.PointingHandCursor; onClicked: root.playerExpanded = false }
            }
          }
          Item { Layout.fillHeight: true; visible: !root.lyricsOpen }
          AlbumArt {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.lyricsOpen ? 160 : Math.min(600, parent.width)
            Layout.preferredHeight: Layout.preferredWidth
            radius: 18
            fontFamily: root.fontFamily
            source: root.player ? root.player.trackArtUrl : ""
          }
          ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.player ? (root.player.trackTitle || "") : "Nothing playing"
              color: P.textStrong
              font.family: root.fontFamily
              font.pixelSize: 32
              font.weight: Font.DemiBold
            }
            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.player ? [root.player.trackArtist, root.player.trackAlbum].filter(function (x) { return !!x }).join(" · ") : ""
              color: P.textMuted
              font.family: root.fontFamily
              font.pixelSize: 19
            }
          }
          LyricsView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.lyricsOpen
            lyrics: root.lyrics
            currentLine: root.lyricsLine
            size: 1.15
            fontFamily: root.fontFamily
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            ProgressLine {
              Layout.fillWidth: true
              implicitHeight: 6
              value: root.player && root.player.length > 0 ? root.player.position / root.player.length : 0
            }
            RowLayout {
              Layout.fillWidth: true
              Text { text: P.duration(root.player ? root.player.position : 0); color: P.textMuted; font.family: root.fontFamily; font.pixelSize: 14 }
              Item { Layout.fillWidth: true }
              Text { text: P.duration(root.player ? root.player.length : 0); color: P.textMuted; font.family: root.fontFamily; font.pixelSize: 14 }
            }
          }
          PlayerControls {
            Layout.alignment: Qt.AlignHCenter
            player: root.player
            size: 1.4
            fontFamily: root.fontFamily
          }
        }
      }

      // Lyrics panel above the compact player, about a third of the screen
      Card {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(window.height / 3)
        visible: !root.playerExpanded && root.moduleOn("player") && root.lyricsOpen
        LyricsView {
          anchors.fill: parent
          anchors.margins: 24
          lyrics: root.lyrics
          currentLine: root.lyricsLine
          fontFamily: root.fontFamily
        }
      }

      // Compact player, always at the very bottom
      Card {
        Layout.fillWidth: true
        Layout.preferredHeight: 92
        visible: !root.playerExpanded && root.moduleOn("player")
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openSpotify()
        }
        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          spacing: 18
          AlbumArt {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            fontFamily: root.fontFamily
            source: root.player ? root.player.trackArtUrl : ""
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Text {
                text: root.player ? (root.player.trackTitle || "") : "Nothing playing"
                color: P.textStrong
                font.family: root.fontFamily
                font.pixelSize: 18
                font.weight: Font.Medium
                elide: Text.ElideRight
                Layout.maximumWidth: 380
              }
              Text {
                Layout.fillWidth: true
                text: root.player ? (root.player.trackArtist || "") : ""
                color: P.textMuted
                font.family: root.fontFamily
                font.pixelSize: 16
                elide: Text.ElideRight
              }
            }
            ProgressLine {
              Layout.fillWidth: true
              value: root.player && root.player.length > 0 ? root.player.position / root.player.length : 0
            }
          }
          PlayerControls {
            player: root.player
            fontFamily: root.fontFamily
          }
          LyricsToggle { }
          Text {
            text: "\u{F0293}"
            color: P.textMuted
            font.family: root.fontFamily
            font.pixelSize: 22
            MouseArea { anchors.fill: parent; anchors.margins: -12; cursorShape: Qt.PointingHandCursor; onClicked: root.playerExpanded = true }
          }
        }
      }
    }

    // -------------------------------------------------------- idle view
    Item {
      id: idleView
      anchors.fill: parent
      visible: root.idle

      Column {
        id: idleBlock
        spacing: 14
        x: (idleView.width - width) / 2
        y: (idleView.height - height) / 2

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Qt.formatTime(clockTick.now, "HH:mm")
          color: P.idleText
          font.family: root.fontFamily
          font.pixelSize: 72
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          color: P.idleTextSoft
          font.family: root.fontFamily
          font.pixelSize: 17
          text: {
            var parts = []
            if (root.feedState.mailNew) parts.push("Mail " + root.feedState.mailNew)
            var chats = (root.feedState.chats || []).length
            if (chats) parts.push("Chats " + chats)
            var working = root.claudeWorking()
            if (working) parts.push("Claude " + working + " working")
            if (root.player && root.player.isPlaying)
              parts.push((root.player.trackTitle || "") + (root.player.trackArtist ? " — " + root.player.trackArtist : ""))
            return parts.join("   ")
          }
        }
      }

      // Move the block every few minutes.
      Timer {
        interval: 3 * 60 * 1000
        repeat: true
        running: root.idle
        triggeredOnStart: true
        onTriggered: {
          idleBlock.x = Math.random() * Math.max(0, idleView.width - idleBlock.width - 80) + 40
          idleBlock.y = Math.random() * Math.max(0, idleView.height - idleBlock.height - 80) + 40
        }
      }
    }
  }
}
