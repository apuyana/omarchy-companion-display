.pragma library

// Fixed dark palette, independent of the Omarchy theme: the companion display
// is on all day, so it never uses white or bright fills that burn in.
var background = "#0a0a0b"
var card = "#121214"
var cardBorder = "#1f1f23"
var item = "#17171a"
var track = "#24242a"

var textStrong = "#dcdce0"
var text = "#c8c8cc"
var textSoft = "#9a9aa2"
var textMuted = "#8a8a92"

var green = "#5fb98a"
var blue = "#8fb4ec"
var amber = "#e0a458"

var chatAvatar = "#23262b"
var chatAvatarText = "#b8c4d0"
var mailAvatar = "#1f2633"
var mailAvatarText = "#a9c2ea"

// Idle mode: pure black and dim grey only.
var idleBackground = "#000000"
var idleText = "#808086"
var idleTextSoft = "#75757b"

var radius = 20
var itemRadius = 14
var pad = 26
var gap = 20

function initials(name) {
  var words = String(name || "").replace(/[^A-Za-z0-9À-ɏ ]/g, " ").trim().split(/\s+/)
  if (words.length === 0 || words[0] === "") return "?"
  var out = words[0].charAt(0)
  if (words.length > 1) out += words[1].charAt(0)
  return out.toUpperCase()
}

function timeLabel(ts) {
  if (!ts) return ""
  var d = new Date(ts * 1000)
  var now = new Date()
  var pad2 = function (n) { return n < 10 ? "0" + n : "" + n }
  if (d.toDateString() === now.toDateString())
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  return pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1)
}

function duration(seconds) {
  if (!seconds || seconds < 0) return "0:00"
  var s = Math.floor(seconds)
  var m = Math.floor(s / 60)
  s = s % 60
  return m + ":" + (s < 10 ? "0" + s : s)
}

// Mail notifications put the sender in the summary and "subject\npreview" in
// the body; split them the same way for desktop and phone sources.
function splitMail(body) {
  var lines = String(body || "").split(/\r?\n/).filter(function (l) { return l.trim() !== "" })
  return { subject: lines.length ? lines[0] : "", preview: lines.slice(1).join(" ") }
}
