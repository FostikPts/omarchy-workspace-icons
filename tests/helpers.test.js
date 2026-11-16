// Checks for the pure helpers in WorkspaceIcons.js, run with plain node:
//
//   node tests/helpers.test.js
//
// They cover the rules that are easy to break and hard to see on the bar:
// ordering by process start time, windows minimized away to a special
// workspace, dialog windows, and the loose desktop-entry match used by games.

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "WorkspaceIcons.js"), "utf8")
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)

const ok = []
const fail = []

function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) ok.push(name)
  else fail.push(`${name}\n  got:      ${a}\n  expected: ${e}`)
}

// /proc stat line: field 2 is the command name and may hold spaces,
// parentheses, and even a stray ")".
const stat = "4242 (Terraria.bin.x86_64) S 1 4242 4242 0 -1 4194560 1 0 0 0 1 2 0 0 20 0 5 0 999 100 200"
check("parseStartTime", sandbox.parseStartTime(stat), 999)
check("parseStartTime parenthesis in comm",
  sandbox.parseStartTime("1 (a b)) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 0 0 0 0 777 0 0"), 777)
check("parseStartTime garbage", Number.isNaN(sandbox.parseStartTime("nope")), true)

check("minimizedOrigin", sandbox.minimizedOrigin(["terminal*", "omarchy-minimized-from-3"]), 3)
check("minimizedOrigin none", sandbox.minimizedOrigin(["terminal*"]), null)

check("candidates of an Omarchy TUI",
  sandbox.appIdCandidates("org.omarchy.nvim", "org.omarchy.nvim"),
  ["org.omarchy.nvim", "nvim"])
check("normalizeName", sandbox.normalizeName("Terraria.bin.x86_64"), "terrariabinx8664")

const entries = [
  { name: "Steam", startupClass: "", noDisplay: 0, icon: "steam" },
  { name: "Terraria", startupClass: "", noDisplay: 0, icon: "steam_icon_105600" },
  { name: "Hidden Thing", startupClass: "", noDisplay: 1, icon: "x" }
]
check("looseEntry prefix", sandbox.looseEntry("Terraria.bin.x86_64", "Terraria.bin.x86_64", entries).icon,
  "steam_icon_105600")
check("looseEntry exact", sandbox.looseEntry("steam", "steam", entries).icon, "steam")
check("looseEntry short name ignored", sandbox.looseEntry("qt", "qt", entries), null)

function toplevel({ address, appId, pid, workspaceId, focus = 0, tags = [], parent = null }) {
  return {
    address,
    wayland: { appId, parent },
    workspace: { id: workspaceId },
    lastIpcObject: { pid, class: appId, focusHistoryID: focus, tags }
  }
}

const windows = [
  toplevel({ address: "a", appId: "steam", pid: 1, workspaceId: 3, focus: 1 }),
  toplevel({ address: "b", appId: "foot", pid: 2, workspaceId: 2, focus: 2 }),
  toplevel({ address: "c", appId: "Terraria.bin.x86_64", pid: 3, workspaceId: 1, focus: 3 }),
  // A second app that opened later on workspace 1.
  toplevel({ address: "d", appId: "foot", pid: 4, workspaceId: 1, focus: 0 }),
  // A window minimized away from workspace 1.
  toplevel({ address: "e", appId: "discord", pid: 5, workspaceId: -99, focus: 4,
    tags: ["omarchy-minimized-from-1"] }),
  // A dialog belongs to the window it hangs off, not to the app count.
  toplevel({ address: "f", appId: "foot", pid: 2, workspaceId: 1, focus: 5, parent: "0xb" })
]
const starts = { 1: 100, 2: 200, 3: 300, 4: 400, 5: 50 }
const ranks = { d: 1e15 + 7 }

const grouped = sandbox.groupWindows(windows, starts, ranks, false)
check("workspaces", Object.keys(grouped).sort(), ["1", "2", "3"])
check("workspace 1 by launch order", grouped[1].map(a => a.key),
  ["discord", "terraria.bin.x86_64", "foot"])
check("workspace 1 app counts", grouped[1].map(a => a.windows), [1, 1, 1])
check("workspace 2 single app", grouped[2].map(a => a.key), ["foot"])

const byFocus = sandbox.groupWindows(windows, starts, ranks, true)
check("workspace 1 by focus order", byFocus[1].map(a => a.key),
  ["foot", "terraria.bin.x86_64", "discord"])

const noStart = sandbox.groupWindows(
  [toplevel({ address: "z", appId: "zen", pid: 9, workspaceId: 1, focus: 0 })], {}, {}, false)
check("unread start time falls back", noStart[1].length, 1)

check("plain strips markup", sandbox.plain("<b>Foot</b>\u0000  x"), "bFoot/b x")

console.log(`ok ${ok.length}: ${ok.join(", ")}`)
if (fail.length) {
  console.error(`\nFAILED ${fail.length}:\n${fail.join("\n")}`)
  process.exit(1)
}
