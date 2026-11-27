import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_version.dart';
import 'update_ports.dart';
import 'update_service.dart' show UpdateException;

/// Reads a GitHub "latest release" answer. Returns null when it does not
/// describe a release with a version for a tag.
ReleaseInfo? parseGitHubRelease(Object? decoded) {
  if (decoded is! Map<String, Object?>) return null;
  final tag = decoded['tag_name'];
  if (tag is! String) return null;
  final version = AppVersion.tryParse(tag);
  if (version == null) return null;
  final assets = <String, String>{};
  final listed = decoded['assets'];
  if (listed is List) {
    for (final asset in listed) {
      if (asset is! Map<String, Object?>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String && url is String) assets[name] = url;
    }
  }
  final page = decoded['html_url'];
  final notes = decoded['body'];
  return ReleaseInfo(
    version: version,
    pageUrl: page is String ? page : '',
    notes: notes is String ? notes : '',
    assets: assets,
  );
}

/// The releases of a GitHub repository, read over its public API.
///
/// Each request says only what any web request says (this device's address)
/// plus the app's name; nothing about the device or its clipboard.
class GitHubReleaseFeed implements ReleaseFeed {
  GitHubReleaseFeed(
    this.repository, {
    this.timeout = const Duration(seconds: 20),
  });

  /// "owner/name".
  final String repository;
  final Duration timeout;

  // Downloads are only ever taken from GitHub's own hosts, whatever a
  // release claims.
  static bool _trusted(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'github.com' ||
          uri.host == 'api.github.com' ||
          uri.host.endsWith('.githubusercontent.com'));

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    if (!_trusted(uri)) {
      throw UpdateException('Refusing to download from ${uri.host}.');
    }
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'PasteHive')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json, */*');
    // Redirects are followed by hand, so each hop is checked.
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) throw const UpdateException('GitHub sent nowhere.');
      return _get(client, uri.resolve(location));
    }
    return response;
  }

  @override
  Future<ReleaseInfo?> latest() async {
    final client = HttpClient();
    try {
      final response = await _get(
        client,
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
      );
      // No release has been published yet.
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw UpdateException(
          response.statusCode == HttpStatus.forbidden ||
                  response.statusCode == HttpStatus.tooManyRequests
              ? 'GitHub is limiting requests from this network. Try again '
                    'in a while.'
              : 'GitHub answered with an error (${response.statusCode}).',
        );
      }
      final body = await utf8.decodeStream(response).timeout(timeout);
      try {
        return parseGitHubRelease(jsonDecode(body));
      } on FormatException {
        throw const UpdateException(
          'GitHub sent an answer that makes no sense.',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> fetchText(String url) async {
    final client = HttpClient();
    try {
      final response = await _get(client, Uri.parse(url));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw UpdateException(
          'The checksum list could not be read (${response.statusCode}).',
        );
      }
      return await utf8.decodeStream(response).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    String url,
    File target, {
    void Function(double? fraction)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final response = await _get(client, Uri.parse(url));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw UpdateException('The download failed (${response.statusCode}).');
      }
      await target.parent.create(recursive: true);
      final total = response.contentLength;
      final sink = target.openWrite();
      var received = 0;
      try {
        // A stalled download gives up instead of waiting for ever.
        await for (final chunk in response.timeout(
          const Duration(minutes: 1),
        )) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}
