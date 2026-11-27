import 'dart:io';

import 'package:pastehive/src/update/update_ports.dart';

/// A release feed that answers from memory.
class FakeFeed implements ReleaseFeed {
  ReleaseInfo? release;

  /// Thrown by [latest] when set.
  Object? failure;
  final Map<String, List<int>> files = {};
  final Map<String, String> texts = {};
  int checks = 0;
  int downloads = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    checks++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return release;
  }

  @override
  Future<String> fetchText(String url) async => texts[url]!;

  @override
  Future<void> download(
    String url,
    File target, {
    void Function(double? fraction)? onProgress,
  }) async {
    downloads++;
    onProgress?.call(0.5);
    await target.writeAsBytes(files[url]!);
    onProgress?.call(1);
  }
}

/// An installer that only notes what it was given.
class FakeInstaller implements UpdateInstaller {
  FakeInstaller(this.folder);

  final Directory folder;
  final List<File> installed = [];
  bool mustQuit = true;

  @override
  String? unavailableReason;

  @override
  String get assetName => 'PasteHive-test.zip';

  @override
  Future<Directory> downloadDirectory() async => folder;

  @override
  Future<bool> install(File file) async {
    installed.add(file);
    return mustQuit;
  }
}
