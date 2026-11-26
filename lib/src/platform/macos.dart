/// The few macOS calls the panel needs that nothing else offers: checking
/// for the Accessibility permission and typing Cmd+V into the app in front.
///
/// Only ever call these on macOS.
library;

import 'dart:ffi';
import 'dart:io';

final _services = DynamicLibrary.open(
  '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices',
);
final _coreFoundation = DynamicLibrary.open(
  '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
);

final _isProcessTrusted = _services
    .lookupFunction<Uint8 Function(), int Function()>('AXIsProcessTrusted');
final _createKeyboardEvent = _services
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint16, Bool),
      Pointer<Void> Function(Pointer<Void>, int, bool)
    >('CGEventCreateKeyboardEvent');
final _setFlags = _services
    .lookupFunction<
      Void Function(Pointer<Void>, Uint64),
      void Function(Pointer<Void>, int)
    >('CGEventSetFlags');
final _post = _services
    .lookupFunction<
      Void Function(Uint32, Pointer<Void>),
      void Function(int, Pointer<Void>)
    >('CGEventPost');
final _release = _coreFoundation
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CFRelease',
    );

/// Whether the user has allowed this app to control the computer, under
/// Privacy & Security > Accessibility. Without it macOS drops the key events
/// [sendPasteKeys] sends.
bool canSendKeys() => _isProcessTrusted() != 0;

/// Opens System Settings at the Accessibility list, where the user can
/// allow this app.
Future<void> openAccessibilitySettings() async {
  await Process.run('open', const [
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
  ]);
}

/// Types Cmd+V into whatever app has the keyboard, which pastes the
/// clipboard there. Returns false, sending nothing, without the
/// Accessibility permission.
bool sendPasteKeys() {
  if (!canSendKeys()) return false;
  const keyV = 9;
  const commandFlag = 0x100000;
  // Events posted here go in where the keyboard's own would.
  const hidEventTap = 0;
  for (final down in const [true, false]) {
    final event = _createKeyboardEvent(nullptr, keyV, down);
    if (event == nullptr) return false;
    _setFlags(event, commandFlag);
    _post(hidEventTap, event);
    _release(event);
  }
  return true;
}
