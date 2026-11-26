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
- Records plain text you copy, newest first. Copying the same text again moves
  it to the top. Entries can be pinned or deleted; pinned ones survive Clear
  History.
- Opens when the pointer rests at the top middle of any screen, and closes when
  the pointer leaves, on Esc, or when you click elsewhere.
- Search by typing; arrow keys and Enter work without touching the mouse.
- The window uses the system's translucent material (acrylic on Windows,
  vibrancy on macOS) with native rounded corners and shadow. It falls back to
  an opaque surface where the system has no material or more contrast is
  requested, and skips the motion when reduced motion is on.

History is kept in `history.json` in the app's support folder, as plain text.

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

Ask the built app to open its panel, report what the system said, and quit:

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
