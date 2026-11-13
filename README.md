# Launchpad for Omarchy

A fullscreen app grid for the [Omarchy](https://omarchy.org) shell: every
installed app on sliding pages of six columns by four rows, over a frosted view
of the desktop, with a search pill at the top.

It is a shell plugin, so it opens instantly, lists whatever apps are installed
on your machine, and uses the same search and hidden-app settings as the
Omarchy launcher.

It also brings its own dock: Omarchy's dock, with the apps button opening
Launchpad, a **Launchpad settings** row in its right-click menu, an icon size
setting, and hold-to-move: hold or drag the apps button and the dock follows
the pointer to the nearest screen edge, the way the bar moves. Enabling the plugin switches the built-in dock off; removing the plugin
brings it back. `omarchy dock` and the dock's settings in `shell.json` keep
working as before.

## Install

```bash
omarchy plugin add <git-url-of-this-repo> --enable
```

## Open it

From a terminal or script:

```bash
omarchy-shell shell toggle launchpad
```

From a key, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + SPACE", "Launchpad", { panel = "launchpad" })
```

Or click the apps button on the dock (the dock shows on floating workspaces).

## Settings

Right-click the dock's apps button and pick **Launchpad settings**, or click
the gear in the top corner of Launchpad. The grid behind the card redraws as
you change things.

| Setting | Range | Default |
|---|---|---|
| Columns | 4 to 10 | 6 |
| Rows | 2 to 6 | 4 |
| Icon size | 56 to 128 | 86 |
| Show app names | on / off | on |
| Backdrop darkness | 31% to 90% | 34% |
| Use theme colors | on / off | off (dark glass, white text) |
| Reopen on the last page | on / off | off |
| Scrolling | Pages / Smooth (one long grid that scrolls) | Pages |
| Scroll sensitivity | 1 to 5 | 3 |
| Next page comes from | Right / Left / Below / Above | Right |
| Page indicator | Pill / Dots / Numbers / Off | Pill |
| Page arrows | Round / Plain / Edge / Off | Round |
| Click on empty space | Close / Turn page | Close |
| Search bar size | 60% to 180% | 100% |
| Search bar border | None to 6 | 1 |
| Show sort box | on / off | off |
| Sort apps by | A–Z / Most used | A–Z |
| Dock position | Top / Bottom / Left / Right | Omarchy's |
| Dock auto-hide | on / off | Omarchy's |
| Dock icon size | 24 to 64 | 36 |

The sort box sits beside the search bar. "Most used" counts how often each app
is opened from Launchpad or its dock, kept in
`~/.local/state/omarchy/launchpad-usage.json`; apps opened any other way are
not counted. A search always shows the best matches first.

The direction, indicator, arrow and empty-click settings apply when scrolling
by pages and are greyed out in smooth mode. With "Turn page", a right-click on
empty space still closes Launchpad. Dock position and auto-hide are Omarchy's
own dock settings, the same ones `omarchy dock` changes.

They are saved in `~/.config/omarchy/launchpad.json`, which you can also edit
by hand, and scripts can change them while the shell runs:

```bash
omarchy-shell shell call launchpad configure '{"columns": 8, "rows": 3}'
omarchy-shell shell summon launchpad '{"view": "settings"}'
```

## Blur the desktop behind it

Without this the desktop shows through dimmed but sharp. Add to
`~/.config/hypr/hyprland.lua`:

```lua
hl.layer_rule({ match = { namespace = "^launchpad$" }, blur = true, ignore_alpha = 0.3 })
```

## Keys

| Key | Does |
|---|---|
| Type | Search by name, description or keyword |
| Enter | Open the first match |
| Left / Right, Page Up / Page Down, scroll | Turn the page |
| Up / Down | Put the keyboard on an app; the arrows then move between apps |
| Enter (with an app selected) | Open it |
| Delete (with an app selected) | Uninstall it, after asking |
| Escape | Clear the search, then close settings, then close |

Clicking empty space also closes it.

## With the mouse

- Click an app to open it.
- Right-click an app to open it, keep it in the dock or take it out, or
  uninstall it.
- Drag an app onto the dock to keep it there.

## Translating

Strings live in `i18n/en.json`. Add a file named after an Omarchy language code
(`da.json`, `pt-BR.json`) with the same keys; missing strings fall back to
English.

## Notes

- The manifest lists the `menu` kind next to `overlay` because the shell only
  hands its app list to plugins of that kind.
- The dock in `dock/` is copied from Omarchy (MIT, see `dock/LICENSE`). It will
  not pick up later changes to Omarchy's dock by itself. Its strings, in every
  language Omarchy ships, are copied into `i18n/`.
- `tests/check.py` checks the plugin against Omarchy's plugin guidelines: plain
  text everywhere, own string catalogs, animation lengths and easing.
- If you already run your own clone of the dock, disable it first; two docks
  would both show.
- While developing: the shell keeps this plugin loaded between opens, so after
  editing run `omarchy restart shell` if a change does not show up.
