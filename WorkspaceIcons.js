// Pure helpers for the workspace icons widget: which windows belong to a
// workspace, which app got there first, and how a /proc stat line is read.
// No QML or Qt here, so the ordering rules can be reasoned about on their own.

// Rank of a window that appeared while the shell was running sits above every
// seeded rank, so a new window never claims a workspace opened before it.
var NEW_WINDOW_BASE = 1e15
// A window that was already there before its process start time was read.
var UNKNOWN_BASE = 1e12

// Workspace a minimized window came from, as omarchy-hyprland-window-minimize
// tags it before moving it to special:minimized.
function minimizedOrigin(tags) {
  if (!tags) return null
  for (var i = 0; i < tags.length; i++) {
    var match = /^omarchy-minimized-from-([1-9][0-9]*)$/.exec(String(tags[i] || ""))
    if (match) return parseInt(match[1], 10)
  }
  return null
}

// starttime is field 22 of /proc/<pid>/stat, counted in clock ticks since boot.
// The command name in field 2 may hold spaces and parentheses, so the fields
// are counted from the last closing parenthesis instead of split from the top.
function parseStartTime(raw) {
  var text = String(raw || "")
  var close = text.lastIndexOf(")")
  if (close < 0) return NaN
  var fields = text.slice(close + 1).replace(/^\s+/, "").split(/\s+/)
  var ticks = Number(fields[19])
  return isFinite(ticks) ? ticks : NaN
}

// Names a desktop entry may hide behind: the app id, its class, and lowercase
// forms. A TUI launched as org.omarchy.nvim keeps its icon under nvim.
function appIdCandidates(appId, className) {
  var values = [appId, className]
  var out = []
  for (var i = 0; i < values.length; i++) {
    var value = String(values[i] || "").trim()
    if (!value) continue
    if (out.indexOf(value) === -1) out.push(value)
    var lower = value.toLowerCase()
    if (out.indexOf(lower) === -1) out.push(lower)
  }
  for (var j = 0; j < values.length; j++) {
    var name = String(values[j] || "")
    if (name.indexOf("org.omarchy.") !== 0) continue
    var command = name.slice("org.omarchy.".length)
    if (command && out.indexOf(command) === -1) out.push(command)
  }
  return out
}

// Letters and digits only, lowercase, so "Terraria.bin.x86_64" and "Terraria"
// can be compared without the packaging noise.
function normalizeName(text) {
  return String(text || "").toLowerCase().replace(/[^0-9a-z\u00c0-\u024f\u0400-\u04ff]+/g, "")
}

// A last resort for windows whose class names no desktop file: a game started
// from Steam reports "Terraria.bin.x86_64" while its entry is just "Terraria".
// An exact name or startup class wins; a class that begins with an entry name
// is accepted only for names long enough to not swallow half the app list.
function looseEntry(appId, className, entries) {
  var key = normalizeName(className) || normalizeName(appId)
  if (key.length < 4) return null

  var list = entries || []
  var prefixed = null
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || entry.noDisplay === true) continue

    var startup = normalizeName(entry.startupClass)
    if (startup && startup === key) return entry

    var name = normalizeName(entry.name)
    if (!name) continue
    if (name === key) return entry
    if (!prefixed && name.length >= 4 && key.indexOf(name) === 0) prefixed = entry
  }
  return prefixed
}

// Text that reaches the bar's tooltip is Omarchy-owned and rendered as rich
// text there, so the plugin hands it no markup.
function plain(text) {
  return String(text || "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/[<>]/g, "")
    .replace(/\s+/g, " ")
    .trim()
}

function focusOf(ipc) {
  var focus = Number(ipc.focusHistoryID)
  return isFinite(focus) ? focus : 1e6
}

// Windows grouped by the workspace they show on, each workspace holding one
// entry per app, ordered by the app whose window got there first. A minimized
// window counts on the workspace it was minimized from rather than on the
// hidden special workspace it sits on now.
function groupWindows(toplevels, startTimes, windowRanks, firstByFocus) {
  var byWorkspace = ({})
  var list = toplevels || []

  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
    if (!toplevel) continue

    var ipc = toplevel.lastIpcObject || {}
    var wayland = toplevel.wayland || null
    // A dialog or transient belongs to the window it hangs off.
    if (wayland && wayland.parent) continue

    var workspace = toplevel.workspace
    var id = workspace ? Number(workspace.id) : -1
    if (!isFinite(id)) id = -1
    if (id < 1) {
      var origin = minimizedOrigin(ipc.tags)
      if (origin === null) continue
      id = origin
    }

    var appId = wayland ? String(wayland.appId || "") : ""
    var className = String(ipc.class || appId || "")
    var key = (appId || className).toLowerCase()
    if (!key) continue

    var focus = focusOf(ipc)
    var address = String(toplevel.address || "")
    var rank = windowRanks ? Number(windowRanks[address]) : NaN
    if (!isFinite(rank)) {
      var start = startTimes ? Number(startTimes[Number(ipc.pid || 0)]) : NaN
      rank = isFinite(start) ? start : UNKNOWN_BASE + focus
    }

    var apps = byWorkspace[id]
    if (!apps) {
      apps = ({})
      byWorkspace[id] = apps
    }
    var app = apps[key]
    if (!app) {
      app = {
        key: key,
        appId: appId || className,
        className: className || appId,
        rank: rank,
        focus: focus,
        windows: 0
      }
      apps[key] = app
    }
    app.windows += 1
    if (rank < app.rank) app.rank = rank
    if (focus < app.focus) app.focus = focus
  }

  var out = ({})
  for (var workspaceId in byWorkspace) {
    var groups = []
    var map = byWorkspace[workspaceId]
    for (var appKey in map) groups.push(map[appKey])
    groups.sort(function(left, right) {
      var leftKey = firstByFocus ? left.focus : left.rank
      var rightKey = firstByFocus ? right.focus : right.rank
      if (leftKey !== rightKey) return leftKey - rightKey
      return String(left.key).localeCompare(String(right.key))
    })
    out[workspaceId] = groups
  }
  return out
}
