import 'package:ccpocket/features/chat_session/widgets/bottom_overlay_layout.dart';
import 'package:ccpocket/features/chat_session/widgets/maintain_reading_position_physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keyboard inset does not rebuild chat content', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    var contentBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomOverlayLayout(
            content: _BuildCounter(onBuild: () => contentBuilds++),
            overlay: const SizedBox(height: 80),
          ),
        ),
      ),
    );
    expect(contentBuilds, 1);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();

    expect(contentBuilds, 1);
  });

  testWidgets('keyboard open and close preserves a paused reading position', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _KeyboardScrollHarness(controller: controller, isFollowingOutput: false),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(300);
    await tester.pump();

    final initialPixels = controller.position.pixels;
    final initialMaxExtent = controller.position.maxScrollExtent;

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final extentGrowth = controller.position.maxScrollExtent - initialMaxExtent;
    expect(extentGrowth, greaterThan(0));
    expect(
      controller.position.pixels,
      closeTo(initialPixels + extentGrowth, 1),
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(controller.position.maxScrollExtent, closeTo(initialMaxExtent, 1));
    expect(controller.position.pixels, closeTo(initialPixels, 1));
  });

  testWidgets(
    'animated keyboard insets return to the paused reading position',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _KeyboardScrollHarness(
          controller: controller,
          isFollowingOutput: false,
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(300);
      await tester.pump();

      final initialPixels = controller.position.pixels;
      for (final inset in [
        75.0,
        150.0,
        225.0,
        300.0,
        225.0,
        150.0,
        75.0,
        0.0,
      ]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(controller.position.pixels, closeTo(initialPixels, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard changes keep a followed list at the bottom', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _KeyboardScrollHarness(controller: controller, isFollowingOutput: true),
    );
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(controller.position.pixels, 0);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(controller.position.pixels, 0);
  });
}

class _BuildCounter extends StatelessWidget {
  final VoidCallback onBuild;

  const _BuildCounter({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.expand();
  }
}

class _KeyboardScrollHarness extends StatelessWidget {
  const _KeyboardScrollHarness({
    required this.controller,
    required this.isFollowingOutput,
  });

  final ScrollController controller;
  final bool isFollowingOutput;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: BottomOverlayLayout(
          overlay: const SizedBox(height: 60),
          content: ListView.builder(
            controller: controller,
            reverse: true,
            physics: MaintainReadingPositionPhysics(
              shouldMaintain: () => !isFollowingOutput,
            ),
            itemCount: 100,
            itemBuilder: (_, index) =>
                SizedBox(height: 50, child: Text('Message $index')),
          ),
        ),
      ),
    );
  }
}
