import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termex/main.dart';

/// Workbench tests: they exercise the real title bar and layout switches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('termex_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // Vault.init does real file I/O; it only settles while the fake clock is
    // suspended, otherwise `_ready` never flips and the workbench never builds.
    await tester.runAsync(() async {
      await tester.pumpWidget(const TermexApp());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();
  }

  /// `_Zoomed` lays the app out at `size / zoom` and scales it back up, so
  /// every global coordinate comes out multiplied by [zoom].
  double captionX(WidgetTester tester) => tester
      .renderObject<RenderBox>(find.text('HOSTS'))
      .localToGlobal(Offset.zero)
      .dx;

  testWidgets('title-bar buttons respond on pointer-up', (tester) async {
    await pumpApp(tester);
    expect(find.text('HOSTS'), findsOneWidget);
    expect(
      captionX(tester),
      moreOrLessEquals(56 * zoom.value),
      reason: 'docked layout: 44 px nav strip + 12 px panel padding',
    );

    final toggle = find.byTooltip('Toggle sidebar (Ctrl+Shift+B)');
    expect(toggle, findsOneWidget);

    final g = await tester.startGesture(tester.getCenter(toggle));
    await g.up();
    await tester.pump();

    expect(
      find.text('HOSTS'),
      findsNothing,
      reason: 'the tap must fire on pointer-up; a double-tap recognizer in '
          'the same gesture arena would hold it back ~300 ms',
    );
  });

  testWidgets('menu bar entries open as soon as they are pressed', (
    tester,
  ) async {
    await pumpApp(tester);

    final g = await tester.startGesture(tester.getCenter(find.text('File')));
    await tester.pump();
    expect(find.text('New Local Terminal'), findsOneWidget);

    await g.up();
    await tester.pump();
  });

  testWidgets('narrow screens drop the nav strip and fill with the panel', (
    tester,
  ) async {
    // `binding.setSurfaceSize` is ignored by this Flutter build; drive the
    // test view directly. 560 logical px is under the 700 px compact
    // threshold yet still wide enough for the desktop window buttons.
    final view = tester.view;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(560, 760);
    addTearDown(view.reset);
    await pumpApp(tester);

    expect(
      find.byTooltip('New local terminal'),
      findsNothing,
      reason: 'the nav strip is desktop-only in the compact layout',
    );
    expect(find.text('HOSTS'), findsOneWidget);
    expect(
      captionX(tester),
      moreOrLessEquals(12 * zoom.value),
      reason: 'the panel is a full-width page starting at the left edge',
    );
  });
}
