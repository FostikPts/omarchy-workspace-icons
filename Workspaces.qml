import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "WorkspaceIcons.js" as WorkspaceIcons

// Workspace indicators with the logo of the app that opened on each workspace
// first. A clone of omarchy.workspaces: clicking, scrolling, per-monitor blocks
// and the layout cycle behave the same; only the labels change. The number
// stays in the corner, and +N says how many other apps share the workspace.
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Every monitor has workspaces 1-10 of its own, which Hyprland numbers in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  readonly property bool showNumbers: String(setting("showNumbers", "On")) !== "Off"
  readonly property bool showAppCount: String(setting("showAppCount", "On")) !== "Off"
  // "Focused last" swaps the app the workspace is named after from the one that
  // opened first to the one focused there most recently.
  readonly property bool firstAppByFocus: String(setting("firstAppBy", "Launched first")) === "Focused last"

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
  }

  Component.onCompleted: {
    root.refresh()
    root.seedWindows()
  }
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  // A window that was already on screen when the shell started keeps the order
  // its process started in. Windows that appear later rank after all of those,
  // so a fresh browser window on an old workspace does not inherit the process'
  // age. The start time comes from /proc, read once per process.
  property var seededAddresses: ({})
  property bool seeded: false
  property var windowRanks: ({})
  property int windowSerial: 0
  property var processViews: ({})

  readonly property var toplevels: Hyprland.toplevels.values
  onToplevelsChanged: root.trackNewWindows()

  readonly property var processIds: {
    var seen = ({})
    var ids = []
    var values = root.toplevels
    for (var i = 0; i < values.length; i++) {
      var pid = Number((values[i].lastIpcObject || {}).pid || 0)
      if (!(pid > 0) || seen[pid]) continue
      seen[pid] = true
      ids.push(pid)
    }
    return ids
  }

  onProcessIdsChanged: Qt.callLater(root.syncProcessViews)

  property var startTimes: ({})

  Component {
    id: processViewComponent

    FileView {
      property int processId: 0
      path: "/proc/" + processId + "/stat"
      printErrors: false
      onLoaded: root.noteStartTime(processId, text())
    }
  }

  function noteStartTime(pid, raw) {
    var ticks = WorkspaceIcons.parseStartTime(raw)
    if (!isFinite(ticks) || root.startTimes[pid] === ticks) return
    var next = Object.assign({}, root.startTimes)
    next[pid] = ticks
    root.startTimes = next
  }

  function syncProcessViews() {
    var views = root.processViews
    var ids = root.processIds
    var keep = ({})
    for (var i = 0; i < ids.length; i++) {
      var pid = ids[i]
      keep[pid] = true
      if (views[pid]) continue
      var view = processViewComponent.createObject(root, { processId: pid })
      if (view) views[pid] = view
    }
    for (var key in views) {
      if (keep[key]) continue
      views[key].destroy()
      delete views[key]
    }
    // A start time whose process no longer has a window is only read again,
    // never reused, so it is dropped with the reader.
    var stale = false
    for (var pidKey in root.startTimes) {
      if (keep[pidKey]) continue
      stale = true
      break
    }
    if (stale) {
      var kept = ({})
      for (var liveKey in root.startTimes) {
        if (keep[liveKey]) kept[liveKey] = root.startTimes[liveKey]
      }
      root.startTimes = kept
    }
  }

  function trackNewWindows() {
    if (!root.seeded) return
    var ranks = Object.assign({}, root.windowRanks)
    var known = root.seededAddresses
    var serial = root.windowSerial
    var live = ({})
    var changed = false
    var values = root.toplevels
    for (var i = 0; i < values.length; i++) {
      var address = String(values[i].address || "")
      if (!address) continue
      live[address] = true
      if (known[address] || ranks[address] !== undefined) continue
      ranks[address] = WorkspaceIcons.NEW_WINDOW_BASE + serial
      serial += 1
      changed = true
    }
    for (var key in ranks) {
      if (live[key]) continue
      delete ranks[key]
      changed = true
    }
    if (!changed) return
    root.windowRanks = ranks
    root.windowSerial = serial
  }

  function seedWindows() {
    var known = ({})
    var values = root.toplevels
    for (var i = 0; i < values.length; i++) {
      var address = String(values[i].address || "")
      if (address) known[address] = true
    }
    root.seededAddresses = known
    root.seeded = true
    root.trackNewWindows()
    root.syncProcessViews()
  }

  readonly property var appsByWorkspace: WorkspaceIcons.groupWindows(
    root.toplevels, root.startTimes, root.windowRanks, root.firstAppByFocus)

  function appEntry(app) {
    var candidates = WorkspaceIcons.appIdCandidates(app.appId, app.className)
    for (var i = 0; i < candidates.length; i++) {
      var entry = DesktopEntries.heuristicLookup(candidates[i])
      if (entry) return entry
    }
    // Whatever the class does not name directly is matched loosely against the
    // entries themselves: Steam games and XWayland windows live there.
    return WorkspaceIcons.looseEntry(
      app.appId, app.className, DesktopEntries.applications.values || [])
  }

  function appName(app) {
    var entry = root.appEntry(app)
    return WorkspaceIcons.plain(entry && entry.name ? entry.name : app.className)
  }

  function appIconSource(app) {
    var entry = root.appEntry(app)
    var library = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    var names = []
    if (entry && entry.icon) names.push(String(entry.icon))
    names = names.concat(WorkspaceIcons.appIdCandidates(app.appId, app.className))

    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      if (name.charAt(0) === "/") return Util.fileUrl(name)
      // The app library indexes the icons of every desktop entry by name, and
      // keeps that index fresh when apps are installed while the shell runs.
      if (library && library.iconIndex && library.iconIndex[name])
        return Util.fileUrl(library.iconIndex[name])
      var themed = Quickshell.iconPath(name, true)
      if (themed) return themed
    }
    return ""
  }

  function appInitials(app) {
    var name = root.appName(app)
    for (var i = 0; i < name.length; i++) {
      var glyph = name.charAt(i)
      if (/[0-9A-Za-z\u00c0-\u024f\u0370-\u03ff\u0400-\u04ff]/.test(glyph))
        return glyph.toUpperCase()
    }
    return "•"
  }

  function tooltipTextFor(id) {
    var apps = root.appsByWorkspace[id] || []
    var number = String(root.slotOf(id) === root.slots ? 0 : root.slotOf(id))
    if (apps.length === 0) return number

    var names = []
    var shown = Math.min(apps.length, 3)
    for (var i = 0; i < shown; i++) names.push(root.appName(apps[i]))
    var text = number + " · " + names.join(", ")
    if (apps.length > shown) text += " +" + (apps.length - shown)
    return text
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData
        required property int index

        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool firstGuest: root.blockOf(modelData) !== root.block && index > 0 && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        readonly property var apps: root.appsByWorkspace[modelData] || []
        readonly property bool occupied: apps.length > 0
        readonly property var firstApp: apps.length > 0 ? apps[0] : null
        readonly property string iconSource: firstApp ? root.appIconSource(firstApp) : ""
        readonly property bool hasIcon: occupied && iconSource !== ""
        readonly property int number: root.slotOf(modelData) === root.slots ? 0 : root.slotOf(modelData)

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        bar: root.bar
        foreground: shown ? Commons.Color.accent : Commons.Color.foreground
        text: occupied ? "" : (shown ? root.modeGlyph(root.activeMode) : String(number))
        hasVisualContent: true
        keepSpace: true
        horizontalMargin: 0
        verticalPadding: 0
        fixedWidth: root.vertical ? root.barSize : Style.space(24)
        fixedHeight: root.vertical ? Style.space(24) : root.barSize
        tooltipText: root.tooltipTextFor(modelData)
        opacity: occupied || shown ? 1 : 0.45

        onPressed: function() {
          if (shown) root.cycleLayout()
          else root.focusWorkspace(modelData)
        }
        onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }

        SizedImage {
          visible: parent.hasIcon
          width: Style.space(15)
          height: width
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(0.5)
          url: parent.iconSource
          asynchronous: true
        }

        // An app with no icon file still gets a mark of its own.
        Text {
          visible: parent.occupied && !parent.hasIcon
          textFormat: Text.PlainText
          text: parent.firstApp ? root.appInitials(parent.firstApp) : ""
          color: parent.shown ? Commons.Color.accent : Commons.Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(0.5)
        }

        Text {
          visible: parent.occupied && root.showNumbers
          textFormat: Text.PlainText
          text: String(parent.number)
          color: parent.shown ? Commons.Color.accent : Commons.Color.foreground
          opacity: 0.7
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.68))
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(1.5)
          anchors.bottomMargin: Style.space(0.5)
        }

        Text {
          visible: parent.occupied && root.showAppCount && parent.apps.length > 1
          textFormat: Text.PlainText
          text: "+" + (parent.apps.length - 1)
          color: Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.68))
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: Style.space(1)
          anchors.topMargin: Style.space(0.5)
        }

        // The layout of the workspace in front, small enough not to compete
        // with the app logo. Clicking the workspace still cycles it.
        OpticalGlyph {
          visible: parent.shown && parent.occupied
          width: Style.space(8)
          height: width
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.leftMargin: Style.space(0.5)
          anchors.topMargin: Style.space(0.5)
          text: root.modeGlyph(root.activeMode)
          paintedSize: Style.space(7)
          color: Commons.Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
        }

        Rectangle {
          visible: parent.shown && parent.occupied
          width: Style.space(3)
          height: width
          radius: width / 2
          color: Commons.Color.accent
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: Style.space(1)
          anchors.bottomMargin: Style.space(1)
        }
      }
    }
  }
}
