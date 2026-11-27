import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_version.dart';

/// The version this copy of the app was built as.
///
/// It comes from the build, not from the source: a release is built as the
/// version its tag names, whatever `pubspec.yaml` says.
Future<AppVersion> runningVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.tryParse(info.version) ?? const AppVersion(0, 0, 0);
  } on PlatformException {
    return const AppVersion(0, 0, 0);
  } on MissingPluginException {
    // Running somewhere without the platform side, such as a test.
    return const AppVersion(0, 0, 0);
  }
}
