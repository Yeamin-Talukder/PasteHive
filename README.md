# Synchronize Clipboard

A clipboard manager for Windows and macOS that lives in the background. Push the
pointer to the top middle of the screen and a panel drops down with everything
you copied; click an entry (or press Enter) to put it back on the clipboard.

Text you copy on one of your computers also lands on the clipboard of the
others, over the local network, once they share a sync key.

## What it does today

- Runs with no taskbar button or Dock icon. A tray icon (Windows) or menu bar
  icon (macOS) offers Show Clipboard, Sync Settings, Pause Capturing, start at
  login, Clear History and Quit.
- Records plain text you copy, newest first, grouped under Pinned, Today,
  Yesterday, This Week and Earlier. Copying the same text again moves it to
  the top. Links, email addresses and hex colours are recognised; a colour is
  shown as a swatch.
- Opens when the pointer rests at the top middle of any screen, and closes when
  the pointer leaves, on Esc, or when you click elsewhere.
- Filters under the search field: All, Pinned, Text, Links, and Emails, Colors
  and Synced when there is something for them to show.
- Preview an entry in full, pin it, or delete it. A deleted entry can be
  brought back for a few seconds.

| Key | Does |
| --- | --- |
| Type | Search |
| Up / Down | Move through the list |
| Enter | Copy the selected entry and close |
| Space | Preview the selected entry (while the search field is empty) |
| Tab / Shift+Tab | Next / previous filter |
| Delete | Delete the selected entry (while the search field is empty) |
| Ctrl+Z (Cmd+Z) | Bring back the entry just deleted |
| Ctrl+P (Cmd+P) | Pin or unpin the selected entry |
| Esc | Close the preview, clear the search, reset the filter, then close |

History is kept in `history.json` in the app's support folder, as plain text.

### How the glass is drawn

The two systems need different approaches.

- **Windows** blurs behind a window only while that window is the active one,
  and a panel that opens on hover often is not. So the app's window is a
  transparent sheet and the app draws the glass itself: just before the panel
  opens it reads the pixels of the screen where the panel will be, blurs them,
  and draws the panel over that with its own rounded shape, edge highlight and
  shadow. One spring animates all of it and the window never moves. The
  picture is taken once per opening, so what is behind the glass does not
  update while the panel is open.
- **macOS** blurs behind any window, so there the window itself is the panel,
  on the system's vibrancy material with the system's corners and shadow.
  Reading the screen would need the Screen Recording permission and is not
  done.

Either way the panel falls back to an opaque surface when there is nothing to
blur or more contrast is requested, and skips the motion when reduced motion
is on.

## Sync

Sync is off until a key is set, and no network port is opened before then.

1. On the first computer open Sync Settings (the button at the bottom left of
   the panel, or the tray menu) and choose Create a Key.
2. On the other computer open Sync Settings, type that key and choose Join.

Both must be on the same network. From then on, text copied on either one is
put on the other's clipboard and added to its list. Pause Capturing stops both
sending and receiving.

How it works:

- Each device announces itself every few seconds by UDP (port 45817, multicast
  group 239.255.77.67 and broadcast). The announcement carries a device id, a
  TCP port and a tag derived from the sync key; not the key, and not the
  device's name.
- Devices that recognise each other's tag connect over TCP. Each connection
  does a fresh X25519 key exchange, derives its encryption keys from that and
  the sync key together (HKDF-SHA256), and encrypts every message with
  ChaCha20-Poly1305. Without the key a device can neither join nor read.

Things to know:

- The first time sync is switched on, Windows asks whether to let the app
  through the firewall, and macOS asks for access to the local network. Sync
  needs both to be allowed.
- Networks that keep devices apart (guest Wi-Fi, some office networks) will
  not work.
- Only new copies are sent. Histories are not merged, and pins and deletions
  stay on the device they were made on.
- The sync key is stored in `sync.json` in the app's support folder as plain
  text, next to the history.
- The protocol is assembled from standard parts but was written for this app
  and has not had an independent security review.

## Running

```powershell
flutter run -d windows
```

On a Mac: `flutter run -d macos`. The macOS side has been written but not yet
built or run; expect to fix things on first contact.

## Checks

```powershell
flutter analyze
flutter test
```

Render the panel to PNG files in `build/previews/` without launching the app:

```powershell
$env:PANEL_PREVIEW = "1"; flutter test test/ui/panel_preview_test.dart
```

Ask the built app to open its panel, report what the system said, save a
picture of the panel as drawn (`build\smoke.png`, with made-up entries rather
than your history) and quit:

```powershell
$env:SYNC_CLIPBOARD_SMOKE = "$PWD\build\smoke.json"; .\build\windows\x64\runner\Debug\synchronize_clipboard.exe
```

## Layout

| Path | What is there |
| --- | --- |
| `lib/src/history/` | Entries, the history list, saving to disk |
| `lib/src/shell/` | The top-edge gesture and opening/closing the panel |
| `lib/src/platform/` | `ports.dart` (interfaces) and `native_ports.dart` (the real desktop, via `nativeapi`) |
| `lib/src/sync/` | Sync key, encrypted channel, the sync service, and `network.dart` (real UDP and TCP) |
| `lib/src/ui/` | The panel, its animation, and the sync settings view |
| `lib/src/app_shell.dart` | Ties capture, tray and panel together |
| `tool/generate_tray_icons.dart` | Redraws the tray icons in `assets/tray/` |

Everything that touches the operating system is behind an interface in
`ports.dart`, so the logic and the UI are tested with fakes.

## License

MIT. See [LICENSE](LICENSE).
