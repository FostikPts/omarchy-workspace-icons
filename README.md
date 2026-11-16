# Workspace Icons for Omarchy

Workspace indicators for the [Omarchy](https://omarchy.org) bar that show the **logo of the app that opened on each workspace first** instead of a bare number.

Omarchy's stock workspace widget names a workspace by its number. This plugin keeps the navigation you already know and replaces the number with the app's own icon: Steam on the workspace where Steam lives, the game on the workspace where you started it, and so on. The number does not disappear — it moves to a corner, small enough not to compete with the logo.

![The bar: menu button, then workspaces 1–5 with Terraria, Foot and Steam logos](preview.png)

*Workspaces 1, 2 and 3 hold Terraria, Foot and Steam — the number sits in the corner; empty workspaces keep the dimmed number.*

## Features

- The logo of the app that launched there first — the order comes from process start times, so it does not jump around when you switch windows.
- The workspace number in the bottom-right corner (`Super+1…5` stays readable), and a `+N` badge when a workspace holds more apps than the one whose logo is drawn.
- Active workspace: an accent dot and a tiny layout glyph (tile / scroll / float). Clicking the active workspace still cycles the layout, exactly as before.
- Empty workspace: the familiar dimmed number; an empty active workspace shows the layout glyph.
- Everything else from the built-in widget: click to focus, wheel to scroll, per-monitor workspace blocks, workspaces visiting from an unplugged monitor, hover tooltips.
- Apps with no desktop entry get an initials badge instead of a blank slot.
- Minimized windows keep counting on the workspace they were minimized from.

## Requirements

- Omarchy 4.x (Hyprland + `omarchy-shell`). Tested on Omarchy 4.5.
- Nothing else — no extra binaries, no Python, no scripts.

## Install

One command:

```bash
omarchy plugin add https://github.com/FostikPts/omarchy-workspace-icons --enable --yes
```

This clones the plugin into `~/.config/omarchy/plugins/fostik.workspace-icons`, validates it, enables it, and places it on the bar. The plugin is a clone of the built-in `omarchy.workspaces` widget, so it **replaces that widget in place** — same section, same position, with its settings carried over. If the bar looks unchanged afterwards, run `omarchy restart shell`.

Manual install, if you prefer:

```bash
git clone https://github.com/FostikPts/omarchy-workspace-icons \
  ~/.config/omarchy/plugins/fostik.workspace-icons
omarchy plugin enable fostik.workspace-icons --section left
```

## Settings

Settings live in `~/.config/omarchy/shell.json` and apply live.

```bash
omarchy bar set fostik.workspace-icons showNumbers Off
omarchy bar set fostik.workspace-icons showAppCount Off
omarchy bar set fostik.workspace-icons firstAppBy "Focused last"
```

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `showNumbers` | `On`, `Off` | `On` | Show the workspace number in the corner of an occupied workspace. |
| `showAppCount` | `On`, `Off` | `On` | Show `+N` when the workspace holds more apps than the one drawn. |
| `firstAppBy` | `Launched first`, `Focused last` | `Launched first` | Pick the app that opened first there, or the one focused there most recently. |

## How it works

- **Which app is first.** For windows already on screen when the shell started, the order is the start time of their process, read once from `/proc/<pid>/stat` (field 22, clock ticks since boot). Windows that appear later rank after all of those and are ordered by when they were first seen. That keeps "first launched" honest: a fresh browser window on an old workspace does not inherit its process' age, and switching focus never changes the answer.
- **Minimized windows.** Omarchy moves a minimized window to the hidden `special:minimized` workspace and tags it `omarchy-minimized-from-N`. The tag wins over the hidden workspace, so the logo stays put. (Omarchy itself only minimizes on floating workspaces.)
- **Dialogs.** Transient and child windows are not counted as separate apps; they belong to the window they hang off.
- **Icons.** The app id is looked up with `DesktopEntries.heuristicLookup`, then the entry icon is resolved through the shell's app-library icon index and `Quickshell.iconPath`. Windows whose class names no desktop entry (a Steam game reports `Terraria.bin.x86_64`, for example) are matched loosely against desktop-entry names, and anything still unresolved gets a round initials badge.
- **Layout refresh.** The widget keeps the built-in `moduleName: "omarchy.workspaces"` on purpose: Omarchy's layout commands broadcast their refresh to that IPC target. Because the plugin replaces the built-in widget during install, only one of them is on the bar at a time — don't add the built-in Workspaces widget next to this one.

## Uninstall

```bash
omarchy plugin disable fostik.workspace-icons
omarchy plugin remove fostik.workspace-icons --yes
```

Disabling a clone puts the built-in `omarchy.workspaces` widget back where the clone was, so the bar returns to its stock look.

## Development

The plugin is three files plus tests:

- `manifest.json` — plugin metadata, settings schema, default bar section.
- `Workspaces.qml` — the widget: slots, clicks, scrolling, layout glyph, IPC.
- `WorkspaceIcons.js` — pure helpers: `/proc` parsing, minimized-origin tags, window grouping and ordering, desktop-entry matching, text escaping.

```bash
node tests/helpers.test.js          # 17 checks, no dependencies
omarchy plugin validate .           # manifest and entry points
```

## Русский

Индикатор рабочих столов для бара Omarchy: вместо номера — логотип приложения, которое запустилось на этом столе первым. Номер остаётся мелкой цифрой в углу, а `+N` показывает, сколько ещё приложений живёт на столе.

Установка одной командой:

```bash
omarchy plugin add https://github.com/FostikPts/omarchy-workspace-icons --enable --yes
```

Плагин — клон штатного виджета `omarchy.workspaces`, поэтому при включении он занимает его место в баре (та же секция и позиция). Если бар не изменился — `omarchy restart shell`.

Настройки применяются на лету:

```bash
omarchy bar set fostik.workspace-icons showNumbers Off      # убрать цифры в углу
omarchy bar set fostik.workspace-icons showAppCount Off     # убрать +N
omarchy bar set fostik.workspace-icons firstAppBy "Focused last"  # последнее активное вместо первого
```

Удаление: `omarchy plugin disable fostik.workspace-icons`, затем `omarchy plugin remove fostik.workspace-icons --yes`. Штатный виджет вернётся на место автоматически.

## License

MIT — see [LICENSE](LICENSE).
