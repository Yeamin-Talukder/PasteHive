import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/update/app_info.dart';
import 'package:pastehive/src/update/app_version.dart';
import 'package:pastehive/src/update/update_ports.dart';
import 'package:pastehive/src/update/update_service.dart';
import 'package:pastehive/src/ui/about_view.dart';

import '../update/fake_updates.dart';

void main() {
  late FakeFeed feed;
  late FakeInstaller installer;
  late UpdateService updates;
  late List<String> opened;
  var done = 0;

  setUp(() {
    feed = FakeFeed();
    installer = FakeInstaller(Directory.systemTemp);
    updates = UpdateService(
      currentVersion: const AppVersion(1, 0, 0),
      feed: feed,
      installer: installer,
      store: MemoryUpdateSettingsStore(),
    );
    opened = [];
    done = 0;
  });

  Future<void> show(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: AboutView(
            updates: updates,
            hasMaterial: false,
            onDone: () => done++,
            onOpenLink: opened.add,
          ),
        ),
      ),
    );
  }

  /// A check talks to the fake feed in real time; let it finish.
  Future<void> check(WidgetTester tester) async {
    await tester.runAsync(updates.check);
    await tester.pump();
  }

  testWidgets('names the app, its version and who makes it', (tester) async {
    await show(tester);
    expect(find.text('PasteHive'), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text(kDeveloperName), findsOneWidget);
    expect(find.text('github.com/$kRepository'), findsOneWidget);
    expect(find.text('MIT License'), findsOneWidget);
    expect(find.text('Not Checked Yet'), findsOneWidget);
  });

  testWidgets('the links open the repository, website and issues', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Source Code'));
    await tester.tap(find.text('Website'));
    await tester.tap(find.text('Report a Problem'));
    expect(opened, [kRepositoryUrl, kWebsiteUrl, kIssuesUrl]);
  });

  testWidgets('with nothing published it says so', (tester) async {
    await show(tester);
    await check(tester);
    expect(find.text('No Release Published Yet'), findsOneWidget);
    expect(find.text('Download and Install'), findsNothing);
  });

  testWidgets('a newer version is offered with one prominent button', (
    tester,
  ) async {
    feed.release = ReleaseInfo(
      version: const AppVersion(1, 2, 0),
      pageUrl: 'https://github.com/o/r/releases/tag/v1.2.0',
    );
    await show(tester);
    await check(tester);
    expect(find.text('Version 1.2.0 Is Available'), findsOneWidget);
    expect(find.text('Download and Install'), findsOneWidget);

    await tester.tap(find.text('What’s New'));
    expect(opened, ['https://github.com/o/r/releases/tag/v1.2.0']);
  });

  testWidgets('where the app cannot install, it points to the page', (
    tester,
  ) async {
    installer.unavailableReason = 'PasteHive cannot write to its folder.';
    feed.release = ReleaseInfo(
      version: const AppVersion(1, 2, 0),
      pageUrl: 'https://github.com/o/r/releases/tag/v1.2.0',
    );
    await show(tester);
    await check(tester);
    expect(find.text('Download and Install'), findsNothing);
    expect(find.text('Open Download Page'), findsOneWidget);
    expect(find.text('PasteHive cannot write to its folder.'), findsOneWidget);
  });

  testWidgets('up to date reads as such', (tester) async {
    feed.release = ReleaseInfo(version: const AppVersion(1, 0, 0), pageUrl: '');
    await show(tester);
    await check(tester);
    expect(find.text('PasteHive Is Up to Date'), findsOneWidget);
  });

  testWidgets('the back button returns to the list', (tester) async {
    await show(tester);
    await tester.tap(find.text('Clipboard'));
    expect(done, 1);
  });

  testWidgets('nothing overflows at twice the text size', (tester) async {
    feed.release = ReleaseInfo(
      version: const AppVersion(1, 2, 0),
      pageUrl: 'https://github.com/o/r/releases/tag/v1.2.0',
    );
    await show(tester, textScale: 2);
    await check(tester);
    expect(tester.takeException(), isNull);
  });
}
