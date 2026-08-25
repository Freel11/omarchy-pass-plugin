# pass — Omarchy shell plugin

A [pass](https://www.passwordstore.org/) integration overlay for the
[Omarchy](https://omarchy.org/) shell. Search your password store from a
keybinding, pick an entry, then copy, type, or generate an OTP without leaving
the keyboard.

Built on the Omarchy plugin contract (Quickshell + QML) and themed through the
shell's `Color.menu.*` / `Style.*` tokens, so it matches whatever theme is
active.

## Features

- Fuzzy substring search over every `.gpg` entry in the store
- Entries sorted by file mtime (most-recently-added first)
- Per-entry action submenu:
  - **Copy password** — `pass show -c <entry>` (clipboard auto-clears after 45s)
  - **Type password** — decrypts and types at the cursor via `wtype`
  - **Copy OTP** — `pass otp -c <entry>` (only shown when `pass-otp` is installed)
- Omarchy notification on every successful action
- Instant open/close (no-animation layer rule, `keepLoaded` manifest flag)
- Honors `PASSWORD_STORE_DIR` for non-default store locations
- No hardcoded paths — resolves its own directory via `manifest.__sourceDir`,
  so it works from any install location

## Requirements

| Dependency    | Required | Purpose                                    |
| ------------- | -------- | ------------------------------------------ |
| `pass`        | yes      | password store CLI                         |
| `wtype`       | yes      | typing passwords at the cursor             |
| `wl-copy`     | yes      | clipboard (pulled in by `pass` on Wayland) |
| `notify-send` | yes      | action confirmation (libnotify)            |
| `pass-otp`    | no       | enables the **Copy OTP** action            |

On Omarchy, `pass`, `wtype`, `wl-copy`, and `notify-send` ship with the system.
For the optional OTP support:

```bash
omarchy pkg aur add pass-otp
```

Then restart the shell (`omarchy restart shell`) so the plugin re-detects it.

## Install

Clone into the Omarchy user plugin directory:

```bash
git clone https://github.com/Freel11/omarchy-pass.git ~/.config/omarchy/plugins/pass
omarchy plugin enable pass
```

The plugin is discovered automatically on the next shell rescan (usually within
a second, via inotify). If it doesn't appear, force it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin list --json | grep '"id":"pass"'
```

## Keybinding

The plugin doesn't bind a key itself — add one in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + P", "Pass", "omarchy-shell shell toggle pass")
```

Then `hyprctl reload` to apply.

## Optional: instant open/close

To make the overlay appear without the default slide/fade (matching Omarchy's
built-in overlays), add a layer rule in `~/.config/hypr/hyprland.lua`:

```lua
hl.layer_rule({ match = { namespace = "pass" }, no_anim = true, animation = "none" })
```

## Usage

1. Press your keybinding (e.g. `SUPER + CTRL + P`).
2. Type to filter entries (substring, case-insensitive).
3. `Up` / `Down` to move the selection.
4. `Enter` to open the action submenu for the selected entry.
5. `Enter` on an action to run it (the overlay dismisses and a notification
   confirms the result).
6. `Esc` or `Left` from the actions submenu returns to the entry list.
7. `Esc` from the entry list clears the filter; `Esc` again dismisses.
8. Click outside the card to dismiss at any time.

## How it works

| File              | Role                                                              |
| ----------------- | ----------------------------------------------------------------- | ------------------------------- |
| `manifest.json`   | Plugin contract: id, kinds (`overlay`), entry point, `keepLoaded` |
| `Pass.qml`        | Overlay UI — list mode + actions mode, keyboard nav, theming      |
| `list-entries.sh` | Lists `*.gpg` files under `$PASSWORD_STORE_DIR`, sorted by mtime  |
| `do-action.sh`    | Runs `pass show -c` / `pass show                                  | wtype`/`pass otp -c` + notifies |

The overlay loads entries once per session (via a `Process` running
`list-entries.sh`) and filters them in JS on each keystroke — no subprocess per
key press. `pass-otp` availability is detected once at plugin load.

## File layout

```
pass/
├── manifest.json
├── Pass.qml
├── list-entries.sh
├── do-action.sh
└── .gitignore
```

## License

MIT
