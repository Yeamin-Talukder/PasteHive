/// The few Win32 calls the panel needs that nothing else offers: reading the
/// pixels of the screen behind it, taking the keyboard when it opens, and
/// telling the desktop compositor to leave its window alone.
///
/// Only ever call these on Windows.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _dwmapi = DynamicLibrary.open('dwmapi.dll');

final _getDC = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final _releaseDC = _user32
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'ReleaseDC',
    );
final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetWindowRect');
final _getForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );
final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
final _attachThreadInput = _user32
    .lookupFunction<
      Int32 Function(Uint32, Uint32, Int32),
      int Function(int, int, int)
    >('AttachThreadInput');

final _createCompatibleDC = _gdi32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'CreateCompatibleDC',
    );
final _createCompatibleBitmap = _gdi32
    .lookupFunction<
      IntPtr Function(IntPtr, Int32, Int32),
      int Function(int, int, int)
    >('CreateCompatibleBitmap');
final _selectObject = _gdi32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
      'SelectObject',
    );
final _bitBlt = _gdi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Int32,
        Int32,
        Int32,
        IntPtr,
        Int32,
        Int32,
        Uint32,
      ),
      int Function(int, int, int, int, int, int, int, int, int)
    >('BitBlt');
final _getDIBits = _gdi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        IntPtr,
        Uint32,
        Uint32,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Uint32,
      ),
      int Function(int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int)
    >('GetDIBits');
final _deleteObject = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');
final _deleteDC = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');

final _dwmSetWindowAttribute = _dwmapi
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Uint32>, Uint32),
      int Function(int, int, Pointer<Uint32>, int)
    >('DwmSetWindowAttribute');

const _srcCopy = 0x00CC0020;
const _bitmapInfoHeaderSize = 40;

/// The pixels of a rectangle of the screen, four bytes each in BGRA order,
/// top row first.
class ScreenPixels {
  const ScreenPixels({
    required this.bgra,
    required this.width,
    required this.height,
  });

  final Uint8List bgra;
  final int width;
  final int height;
}

/// Reads what is on screen where the window [hwnd] is positioned.
///
/// Meant to be called while that window is hidden, so the result is what is
/// behind it. Returns null if any step fails.
ScreenPixels? captureBehindWindow(int hwnd) {
  final rect = calloc<Int32>(4);
  try {
    if (_getWindowRect(hwnd, rect) == 0) return null;
    final left = rect[0];
    final top = rect[1];
    final width = rect[2] - left;
    final height = rect[3] - top;
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192) {
      return null;
    }
    return _captureScreen(left, top, width, height);
  } finally {
    calloc.free(rect);
  }
}

ScreenPixels? _captureScreen(int left, int top, int width, int height) {
  final screen = _getDC(0);
  if (screen == 0) return null;
  final memory = _createCompatibleDC(screen);
  final bitmap = _createCompatibleBitmap(screen, width, height);
  final header = calloc<Uint8>(_bitmapInfoHeaderSize);
  final pixels = calloc<Uint8>(width * height * 4);
  try {
    if (memory == 0 || bitmap == 0) return null;
    final previous = _selectObject(memory, bitmap);
    final copied = _bitBlt(
      memory,
      0,
      0,
      width,
      height,
      screen,
      left,
      top,
      _srcCopy,
    );
    _selectObject(memory, previous);
    if (copied == 0) return null;

    // A 32-bit, uncompressed bitmap; the negative height asks for the top
    // row first.
    ByteData.sublistView(header.asTypedList(_bitmapInfoHeaderSize))
      ..setUint32(0, _bitmapInfoHeaderSize, Endian.little)
      ..setInt32(4, width, Endian.little)
      ..setInt32(8, -height, Endian.little)
      ..setUint16(12, 1, Endian.little)
      ..setUint16(14, 32, Endian.little);
    if (_getDIBits(memory, bitmap, 0, height, pixels, header, 0) == 0) {
      return null;
    }

    final bytes = Uint8List.fromList(pixels.asTypedList(width * height * 4));
    // The screen has no transparency, and what GDI leaves in the fourth
    // byte is not meaningful: make every pixel opaque.
    for (var i = 3; i < bytes.length; i += 4) {
      bytes[i] = 0xFF;
    }
    return ScreenPixels(bgra: bytes, width: width, height: height);
  } finally {
    calloc
      ..free(pixels)
      ..free(header);
    if (bitmap != 0) _deleteObject(bitmap);
    if (memory != 0) _deleteDC(memory);
    _releaseDC(0, screen);
  }
}

/// Makes [hwnd] the window that receives keys.
///
/// Windows refuses this to a program the user is not already working in, and
/// a panel that opens on hover is exactly that. Joining the input queue of
/// whatever is in front for a moment is the accepted way to be let through.
/// Returns whether the window ended up in front.
bool takeForeground(int hwnd) {
  final foreground = _getForegroundWindow();
  if (foreground == hwnd) return true;
  final ours = _getWindowThreadProcessId(hwnd, nullptr);
  final theirs = foreground == 0
      ? 0
      : _getWindowThreadProcessId(foreground, nullptr);
  if (theirs == 0 || theirs == ours) {
    return _setForegroundWindow(hwnd) != 0;
  }
  _attachThreadInput(theirs, ours, 1);
  final taken = _setForegroundWindow(hwnd) != 0;
  _attachThreadInput(theirs, ours, 0);
  return taken;
}

/// Stops the desktop compositor decorating or animating [hwnd]: no rounding,
/// no border line, and no open/close transition of its own. The panel draws
/// and animates itself; anything the system added would fight with that.
void leaveWindowUndecorated(int hwnd) {
  const transitionsForceDisabled = 3;
  const windowCornerPreference = 33;
  const borderColor = 34;
  const doNotRound = 1;
  const colorNone = 0xFFFFFFFE;

  final value = calloc<Uint32>();
  try {
    for (final (attribute, setting) in const [
      (transitionsForceDisabled, 1),
      (windowCornerPreference, doNotRound),
      (borderColor, colorNone),
    ]) {
      value.value = setting;
      // Older Windows versions do not know every attribute; a refusal is
      // harmless.
      _dwmSetWindowAttribute(hwnd, attribute, value, sizeOf<Uint32>());
    }
  } finally {
    calloc.free(value);
  }
}
