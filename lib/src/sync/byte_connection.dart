import 'dart:async';
import 'dart:typed_data';

/// A two-way stream of bytes to one other device, such as a TCP socket.
abstract interface class ByteConnection {
  /// Bytes from the other side, in whatever chunks they arrive. Closes when
  /// the other side goes away.
  Stream<List<int>> get incoming;

  void add(List<int> bytes);

  Future<void> close();
}

/// Thrown when the other side sends something that is not a valid frame.
class FrameException implements Exception {
  const FrameException(this.message);

  final String message;

  @override
  String toString() => 'FrameException: $message';
}

/// The largest frame accepted. Copied text is capped well below this.
const int kMaxFrameLength = 8 * 1024 * 1024;

/// Puts a four-byte length in front of [payload].
Uint8List encodeFrame(List<int> payload) {
  if (payload.length > kMaxFrameLength) {
    throw const FrameException('frame too large to send');
  }
  final frame = Uint8List(4 + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length);
  frame.setRange(4, frame.length, payload);
  return frame;
}

/// Cuts a byte stream back into the frames [encodeFrame] produced, however
/// the bytes were split up on the way.
Stream<Uint8List> decodeFrames(Stream<List<int>> bytes) async* {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in bytes) {
    buffer.add(chunk);
    var data = buffer.takeBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      final length = ByteData.sublistView(data, offset).getUint32(0);
      if (length > kMaxFrameLength) {
        throw const FrameException('frame too large');
      }
      if (data.length - offset - 4 < length) break;
      yield Uint8List.sublistView(data, offset + 4, offset + 4 + length);
      offset += 4 + length;
    }
    if (offset < data.length) {
      // Copied, so a frame handed out above is never written over.
      data = Uint8List.fromList(Uint8List.sublistView(data, offset));
      buffer.add(data);
    }
  }
}
