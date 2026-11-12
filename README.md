# Launchpad for Omarchy

A fullscreen app grid for the [Omarchy](https://omarchy.org) shell: every
installed app on sliding pages of six columns by four rows, over a frosted view
of the desktop, with a search pill at the top.

It is a shell plugin, so it opens instantly, lists whatever apps are installed
on your machine, and uses the same search and hidden-app settings as the
Omarchy launcher.

It also brings its own dock: Omarchy's dock, unchanged except that the apps
button opens Launchpad and its right-click menu has a **Launchpad settings**
row. Enabling the plugin switches the built-in dock off; removing the plugin
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
| Escape | Clear the search, then close settings, then close |

Clicking empty space also closes it.

## Translating

Strings live in `i18n/en.json`. Add a file named after an Omarchy language code
(`da.json`, `pt-BR.json`) with the same keys; missing strings fall back to
English.

## Notes

- The manifest lists the `menu` kind next to `overlay` because the shell only
  hands its app list to plugins of that kind.
- The dock in `dock/` is copied from Omarchy (MIT, see `dock/LICENSE`). It will
  not pick up later changes to Omarchy's dock by itself. Dragging an app out of
  Omarchy's own app grid onto the dock is gone along with that grid.
- If you already run your own clone of the dock, disable it first; two docks
  would both show.
- While developing: the shell keeps this plugin loaded between opens, so after
  editing run `omarchy restart shell` if a change does not show up.
