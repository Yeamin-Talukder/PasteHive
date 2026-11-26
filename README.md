# Synchronize Clipboard

A clipboard manager for Windows and macOS that lives in the background. Push the
pointer to the top middle of the screen and a panel drops down with everything
you copied; click an entry (or press Enter) to put it back on the clipboard.

Syncing between devices is not built yet. This is the local half: capture,
history, and the panel.

## What it does today

- Runs with no taskbar button or Dock icon. A tray icon (Windows) or menu bar
  icon (macOS) offers Show Clipboard, Pause Capturing, start at login, Clear
  History and Quit.
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
| `lib/src/ui/` | The panel and its animation |
| `lib/src/app_shell.dart` | Ties capture, tray and panel together |
| `tool/generate_tray_icons.dart` | Redraws the tray icons in `assets/tray/` |

Everything that touches the operating system is behind an interface in
`ports.dart`, so the logic and the UI are tested with fakes.
