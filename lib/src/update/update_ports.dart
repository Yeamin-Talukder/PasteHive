/// What checking for and installing an update needs from the outside world,
/// behind interfaces so the logic can be tested without a network.
library;

import 'dart:convert';
import 'dart:io';

import 'app_version.dart';

/// A published release.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.pageUrl,
    this.notes = '',
    this.assets = const {},
  });

  final AppVersion version;

  /// The release's page, for reading its notes or downloading by hand.
  final String pageUrl;
  final String notes;

  /// The files attached to the release: file name to download address.
  final Map<String, String> assets;
}

/// Where releases are published.
abstract class ReleaseFeed {
  /// The newest full release; null when none has been published.
  Future<ReleaseInfo?> latest();

  /// The text at [url] (the checksum list).
  Future<String> fetchText(String url);

  /// Saves what is at [url] to [target], reporting how far it has got as a
  /// fraction, or null while the size is unknown.
  Future<void> download(
    String url,
    File target, {
    void Function(double? fraction)? onProgress,
  });
}

/// Puts a downloaded update in place on this kind of device.
abstract class UpdateInstaller {
  /// The release file this device needs.
  String get assetName;

  /// Why the app cannot update itself here; null when it can. When it
  /// cannot, the user is sent to the release's page instead.
  String? get unavailableReason;

  /// A folder to download into.
  Future<Directory> downloadDirectory();

  /// Installs [file]. Returns true when the app must now quit for the
  /// install to go through (it is started again afterwards).
  Future<bool> install(File file);
}

/// What the user chose about updates, kept between runs.
class UpdateSettings {
  const UpdateSettings({this.autoCheck = true, this.lastChecked});

  /// Whether the app looks for a new version by itself, once a day.
  final bool autoCheck;
  final DateTime? lastChecked;

  UpdateSettings copyWith({bool? autoCheck, DateTime? lastChecked}) {
    return UpdateSettings(
      autoCheck: autoCheck ?? this.autoCheck,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

abstract class UpdateSettingsStore {
  Future<UpdateSettings> load();
  Future<void> save(UpdateSettings settings);
}

class MemoryUpdateSettingsStore implements UpdateSettingsStore {
  MemoryUpdateSettingsStore([this.settings = const UpdateSettings()]);

  UpdateSettings settings;

  @override
  Future<UpdateSettings> load() async => settings;

  @override
  Future<void> save(UpdateSettings settings) async => this.settings = settings;
}

class JsonFileUpdateSettingsStore implements UpdateSettingsStore {
  JsonFileUpdateSettingsStore(this.file);

  final File file;

  @override
  Future<UpdateSettings> load() async {
    try {
      if (!await file.exists()) return const UpdateSettings();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return const UpdateSettings();
      final checked = decoded['lastChecked'];
      return UpdateSettings(
        autoCheck: decoded['autoCheck'] != false,
        lastChecked: checked is String ? DateTime.tryParse(checked) : null,
      );
    } on FormatException {
      return const UpdateSettings();
    } on FileSystemException {
      return const UpdateSettings();
    }
  }

  @override
  Future<void> save(UpdateSettings settings) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'autoCheck': settings.autoCheck,
          'lastChecked': settings.lastChecked?.toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } on FileSystemException {
      // Not worth interrupting anything for: the choice is asked again.
    }
  }
}
