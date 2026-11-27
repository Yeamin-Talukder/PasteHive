import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'app_version.dart';
import 'update_ports.dart';

/// Where an update check or install has got to.
enum UpdateStatus {
  /// Nothing has been checked yet.
  idle,
  checking,
  upToDate,

  /// A newer version is published and waiting to be downloaded.
  available,
  downloading,

  /// Downloaded; the system or the app is putting it in place.
  installing,
  failed,
}

/// Looks for a newer release of the app, and downloads and installs it when
/// the user asks.
///
/// Nothing is downloaded or installed without the user pressing the button.
/// The check itself asks the release feed one question ("what is the newest
/// version?") and sends nothing about this device or its clipboard.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.currentVersion,
    required this._feed,
    required this._installer,
    required this._store,
    this._quit,
    DateTime Function()? clock,
    this.checkEvery = const Duration(hours: 24),
  }) : _clock = clock ?? DateTime.now;

  /// The version of the app that is running.
  final AppVersion currentVersion;

  /// How long an automatic check stays fresh.
  final Duration checkEvery;

  final ReleaseFeed _feed;
  final UpdateInstaller _installer;
  final UpdateSettingsStore _store;

  /// Closes the app, where an install needs that.
  final Future<void> Function()? _quit;
  final DateTime Function() _clock;

  UpdateSettings _settings = const UpdateSettings();
  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _latest;
  double? _progress;
  String? _error;
  Timer? _timer;
  bool _disposed = false;

  UpdateStatus get status => _status;

  /// The newest release found by the last check; null before one, or when
  /// nothing has been published.
  ReleaseInfo? get latest => _latest;

  /// Whether a version newer than the running one is published.
  bool get hasUpdate {
    final latest = _latest;
    return latest != null && latest.version > currentVersion;
  }

  /// How far the download has got, 0 to 1; null while unknown.
  double? get progress => _progress;

  /// What went wrong, in words for the user; null when nothing did.
  String? get error => _error;

  bool get autoCheck => _settings.autoCheck;
  DateTime? get lastChecked => _settings.lastChecked;

  /// Why the app cannot install an update by itself on this device; null
  /// when it can.
  String? get installUnavailableReason => _installer.unavailableReason;

  /// Whether pressing the install button would do something right now.
  bool get busy =>
      _status == UpdateStatus.checking ||
      _status == UpdateStatus.downloading ||
      _status == UpdateStatus.installing;

  /// Loads the user's choice and, where they have left automatic checks on,
  /// looks now if the last look is old and again whenever it becomes so.
  Future<void> start() async {
    _settings = await _store.load();
    if (_disposed) return;
    notifyListeners();
    unawaited(_checkIfDue());
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _checkIfDue());
  }

  Future<void> _checkIfDue() async {
    if (!_settings.autoCheck || busy) return;
    final last = _settings.lastChecked;
    if (last != null && _clock().difference(last) < checkEvery) return;
    await check(quiet: true);
  }

  Future<void> setAutoCheck(bool on) async {
    _settings = UpdateSettings(
      autoCheck: on,
      lastChecked: _settings.lastChecked,
    );
    notifyListeners();
    await _store.save(_settings);
    if (on) unawaited(_checkIfDue());
  }

  /// Asks the feed for the newest release.
  ///
  /// A [quiet] check is one nobody asked for: when it fails (no network,
  /// say) it leaves things as they were instead of showing an error.
  Future<void> check({bool quiet = false}) async {
    if (busy) return;
    final before = _status;
    _set(UpdateStatus.checking, error: null);
    try {
      final release = await _feed.latest();
      _latest = release;
      _settings = _settings.copyWith(lastChecked: _clock());
      unawaited(_store.save(_settings));
      _set(hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate);
    } on Object catch (error) {
      if (quiet) {
        _set(before);
      } else {
        _set(UpdateStatus.failed, error: _describe(error));
      }
    }
  }

  /// Downloads the newer version for this device, checks it against the
  /// release's checksum list, and installs it.
  Future<void> downloadAndInstall() async {
    final release = _latest;
    if (release == null || !hasUpdate || busy) return;
    final reason = _installer.unavailableReason;
    if (reason != null) {
      _set(UpdateStatus.failed, error: reason);
      return;
    }
    final name = _installer.assetName;
    final url = release.assets[name];
    if (url == null) {
      _set(
        UpdateStatus.failed,
        error: 'Version ${release.version} has no download for this device.',
      );
      return;
    }

    _progress = 0;
    _set(UpdateStatus.downloading, error: null);
    try {
      final folder = await _installer.downloadDirectory();
      final file = File(path.join(folder.path, name));
      await _feed.download(
        url,
        file,
        onProgress: (fraction) {
          _progress = fraction;
          if (!_disposed) notifyListeners();
        },
      );
      await _verify(release, name, file);
      _set(UpdateStatus.installing);
      final mustQuit = await _installer.install(file);
      if (mustQuit) {
        await _quit?.call();
      } else {
        // The system has taken over (it asks the user to confirm); the app
        // is replaced, or not, without telling us.
        _set(UpdateStatus.available);
      }
    } on Object catch (error) {
      _set(UpdateStatus.failed, error: _describe(error));
    }
  }

  // A release lists the SHA-256 of each of its files. A download that does
  // not match was damaged on the way or is not the file that was published.
  Future<void> _verify(ReleaseInfo release, String name, File file) async {
    final listUrl = release.assets['SHA256SUMS.txt'];
    if (listUrl == null) return;
    final expected = checksumFor(await _feed.fetchText(listUrl), name);
    if (expected == null) return;
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final actual = (await sink.hash()).bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actual != expected) {
      try {
        await file.delete();
      } on FileSystemException {
        // Left behind; it is in a temporary folder.
      }
      throw const UpdateException(
        'The download did not match its published checksum, so it was not '
        'installed. Try again.',
      );
    }
  }

  void _set(UpdateStatus status, {Object? error = _keep}) {
    _status = status;
    if (!identical(error, _keep)) _error = error as String?;
    if (status != UpdateStatus.downloading) _progress = null;
    if (!_disposed) notifyListeners();
  }

  static const Object _keep = Object();

  static String _describe(Object error) {
    if (error is UpdateException) return error.message;
    if (error is SocketException || error is HandshakeException) {
      return 'Could not reach GitHub. Check the internet connection and try '
          'again.';
    }
    if (error is TimeoutException) {
      return 'GitHub took too long to answer. Try again.';
    }
    if (error is FileSystemException) {
      return 'The update could not be saved: ${error.message}.';
    }
    return 'The update did not go through: $error';
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Something went wrong that the user can be told in these words.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The checksum listed for [fileName] in the text of a `SHA256SUMS.txt`
/// (lines of `<hex>  <name>`); null when it is not listed.
String? checksumFor(String list, String fileName) {
  for (final line in list.split('\n')) {
    final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$')
        .firstMatch(line.trim());
    if (match != null && match[2]!.trim() == fileName) {
      return match[1]!.toLowerCase();
    }
  }
  return null;
}
