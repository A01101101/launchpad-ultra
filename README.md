# Launchpad for Omarchy

A fullscreen app grid for the [Omarchy](https://omarchy.org) shell: every
installed app on sliding pages of six columns by four rows, over a frosted view
of the desktop, with a search pill at the top.

It is a shell plugin, so it opens instantly, lists whatever apps are installed
on your machine, and uses the same search and hidden-app settings as the
Omarchy launcher.

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
| Escape | Clear the search, then close |

Clicking empty space also closes it.

## Translating

Strings live in `i18n/en.json`. Add a file named after an Omarchy language code
(`da.json`, `pt-BR.json`) with the same keys; missing strings fall back to
English.

## Notes

- The manifest lists the `menu` kind next to `overlay` because the shell only
  hands its app list to plugins of that kind.
- While developing: the shell keeps this plugin loaded between opens, so after
  editing run `omarchy restart shell` if a change does not show up.
