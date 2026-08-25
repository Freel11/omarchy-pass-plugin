# pass — Omarchy shell plugin

A [pass](https://www.passwordstore.org/) integration for the
[Omarchy](https://omarchy.org/) shell. Adds a key-glyph icon to the bar's
right section — click it (or press a keybinding) to open a popover that
searches your password store, add new entries, then copy, type, or generate
an OTP without leaving the keyboard.

Built on the Omarchy plugin contract (Quickshell + QML) and themed through
the bar's `foreground` / `Color.*` / `Style.*` tokens, so it matches whatever
theme is active.

## Features

- Key-glyph icon (󰌆) in the bar's right section, beside Tailscale/Bluetooth
- Popover anchored under the icon — opens the same way other bar panels do
- Fuzzy substring search over every `.gpg` entry in the store
- Entries sorted by file mtime (most-recently-added first)
- Per-entry action submenu:
  - **Copy password** — `pass show -c <entry>` (clipboard auto-clears after 45s)
  - **Type password** — decrypts and types at the cursor via `wtype`
  - **Copy OTP** — `pass otp -c <entry>` (only shown when `pass-otp` is installed)
- Omarchy notification on every successful action
- Add new entries via a plus icon in the header — name + value fields with
  overwrite confirmation if an entry already exists
- Honors `PASSWORD_STORE_DIR` for non-default store locations
- No hardcoded paths — resolves its own directory via `Qt.resolvedUrl`

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

Add the widget to the bar's right section (it defaults to the right section
per the manifest, but if the bar layout doesn't include it yet):

```bash
omarchy bar put pass --after omarchy.tailscale
```

The plugin is discovered automatically on the next shell rescan (usually within
a second, via inotify). If it doesn't appear, force it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin list --json | grep '"id":"pass"'
```

## Keybinding

The plugin registers an IPC target (`pass`) that supports `open`, `close`,
`toggle`, etc., so a keybinding works alongside the bar icon. Add one in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + P", "Pass", "omarchy-shell shell toggle pass")
```

Then `hyprctl reload` to apply.

## Usage

1. Click the key-glyph icon in the bar (or press your keybinding).
2. Type to filter entries (substring, case-insensitive).
3. `Up` / `Down` to move the selection.
4. `Enter` to open the action submenu for the selected entry.
5. `Enter` on an action to run it (the popover dismisses and a notification
   confirms the result).
6. `Esc` or `Left` from the actions submenu returns to the entry list.
7. `Esc` from the entry list clears the filter; `Esc` again dismisses.
8. Click outside the popover to dismiss at any time.

### Adding an entry

1. Press the plus icon (󰐕) in the header, or `Tab` to it from the search
   box and press `Enter`.
2. Enter the entry name (e.g., `work/github` — slashes create subfolders).
3. Enter the password or secret value.
4. Press `Enter` or `Tab` to the **Save** button and press it.
5. If an entry with that name already exists, a confirm dialog asks before
   overwriting.
6. After saving, the list refreshes and filters to the new entry.
7. `Esc` at any time cancels back to the list.

## How it works

| File              | Role                                                              |
| ----------------- | ----------------------------------------------------------------- |
| `manifest.json`   | Plugin contract: id, kinds (`bar-widget`), entry point, barWidget metadata |
| `Pass.qml`        | Bar icon + popover — list, actions, and add modes, keyboard nav, theming |
| `list-entries.sh` | Lists `*.gpg` files under `$PASSWORD_STORE_DIR`, sorted by mtime  |
| `do-action.sh`    | Runs `pass show -c` / `pass show \| wtype`/`pass otp -c` + notifies |
| `add-entry.sh`    | Pipes a value to `pass insert -f -m` and notifies on success      |

The plugin extends Omarchy's `Panel` base (which owns the IPC open/close
lifecycle) and uses `KeyboardPanel` for the popover (layer-shell popup anchored
to the bar icon, with outside-click dismissal and keyboard focus). Entries are
loaded once per session via a `Process` running `list-entries.sh` and filtered
in JS on each keystroke — no subprocess per key press. `pass-otp` availability
is detected once at plugin load.

## File layout

```
pass/
├── manifest.json
├── Pass.qml
├── list-entries.sh
├── do-action.sh
├── add-entry.sh
└── .gitignore
```

## License

MIT
