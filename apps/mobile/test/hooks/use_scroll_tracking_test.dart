import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket/features/chat_session/widgets/maintain_reading_position_physics.dart';
import 'package:ccpocket/hooks/use_scroll_tracking.dart';
import 'package:ccpocket/l10n/app_localizations.dart';

void main() {
  group('nextAutoFollowState', () {
    test('pauses as soon as the user scrolls away from the bottom', () {
      expect(
        nextAutoFollowState(
          isFollowing: true,
          distanceFromBottom: 8,
          direction: ScrollDirection.reverse,
        ),
        isFalse,
      );
    });

    test('stays paused while layout growth changes the offset', () {
      expect(
        nextAutoFollowState(
          isFollowing: false,
          distanceFromBottom: 240,
          direction: ScrollDirection.idle,
        ),
        isFalse,
      );
    });

    test('resumes when the user scrolls back near the bottom', () {
      expect(
        nextAutoFollowState(
          isFollowing: false,
          distanceFromBottom: 16,
          direction: ScrollDirection.forward,
        ),
        isTrue,
      );
    });

    test('always follows at the exact bottom', () {
      expect(
        nextAutoFollowState(
          isFollowing: false,
          distanceFromBottom: 0,
          direction: ScrollDirection.idle,
        ),
        isTrue,
      );
    });
  });

  group('useScrollTracking', () {
    testWidgets('returns a ScrollController and initial state', (tester) async {
      late ScrollTrackingResult result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking('session-1');
              // Use reverse: true — offset 0 = bottom of chat
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(result.controller, isA<ScrollController>());
      // Initially at offset 0 with reverse list → at bottom → not scrolled up
    });

    testWidgets('isScrolledUp becomes false when at bottom', (tester) async {
      late ScrollTrackingResult result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking('session-2');
              // Use reverse: true — offset 0 = bottom of chat
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 200,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With reverse list, offset 0 = bottom → isScrolledUp should be false
      expect(result.isScrolledUp, isFalse);
    });

    testWidgets('keeps following within the near-bottom threshold', (
      tester,
    ) async {
      late ScrollTrackingResult result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking('session-4');
              // Use reverse: true — offset 0 = bottom of chat
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 200,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Near bottom (within the 24px threshold) → still following.
      result.controller.jumpTo(16);
      await tester.pumpAndSettle();
      expect(result.isScrolledUp, isFalse);
    });

    testWidgets('does not auto-scroll after following has paused', (
      tester,
    ) async {
      late ScrollTrackingResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking('session-paused');
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      result.controller.jumpTo(200);
      await tester.pump();
      expect(result.isFollowingOutput, isFalse);

      result.scrollToBottom();
      await tester.pumpAndSettle();
      expect(result.controller.offset, 200);
    });

    testWidgets('resumes following after returning to the bottom', (
      tester,
    ) async {
      late ScrollTrackingResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking('session-resumed');
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      result.controller.jumpTo(200);
      await tester.pump();
      result.forceScrollToBottom();
      await tester.pumpAndSettle();

      expect(result.isFollowingOutput, isTrue);
      expect(result.isScrolledUp, isFalse);
      expect(result.controller.offset, 0);
    });

    testWidgets('starts following when switching to an unsaved session', (
      tester,
    ) async {
      late ScrollTrackingResult result;
      var sessionId = 'session-switch-source';

      Widget buildApp() {
        return MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking(sessionId);
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      result.controller.jumpTo(200);
      await tester.pump();
      expect(result.isFollowingOutput, isFalse);

      sessionId = 'session-switch-new';
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(result.isFollowingOutput, isTrue);
      expect(result.isScrolledUp, isFalse);
    });

    testWidgets('restores an explicitly paused near-bottom session', (
      tester,
    ) async {
      late ScrollTrackingResult result;
      var sessionId = 'session-near-bottom-paused';

      Widget buildApp() {
        return MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useScrollTracking(sessionId);
              return ListView.builder(
                controller: result.controller,
                reverse: true,
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, 16));
      await tester.pump();
      expect(result.isFollowingOutput, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(result.controller.offset, lessThanOrEqualTo(24));

      sessionId = 'session-near-bottom-other';
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      sessionId = 'session-near-bottom-paused';
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(result.isFollowingOutput, isFalse);
    });

    testWidgets('force scroll cooperates with reading-position physics', (
      tester,
    ) async {
      late ScrollTrackingResult result;
      final bottomItemHeight = ValueNotifier(50.0);
      addTearDown(bottomItemHeight.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: _IntegratedScrollHarness(
            bottomItemHeight: bottomItemHeight,
            onResult: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(result.isFollowingOutput, isFalse);

      final maxExtentBeforeGrowth = result.controller.position.maxScrollExtent;
      bottomItemHeight.value += 50;
      await tester.pumpAndSettle();
      expect(
        result.controller.position.maxScrollExtent,
        greaterThan(maxExtentBeforeGrowth),
      );
      expect(result.isFollowingOutput, isFalse);

      result.forceScrollToBottom();
      await tester.pumpAndSettle();

      expect(result.isFollowingOutput, isTrue);
      expect(result.controller.offset, 0);
      expect(tester.takeException(), isNull);
    });
  });
}

class _IntegratedScrollHarness extends HookWidget {
  const _IntegratedScrollHarness({
    required this.bottomItemHeight,
    required this.onResult,
  });

  final ValueNotifier<double> bottomItemHeight;
  final ValueChanged<ScrollTrackingResult> onResult;

  @override
  Widget build(BuildContext context) {
    final result = useScrollTracking('session-integrated-physics');
    onResult(result);

    return ValueListenableBuilder<double>(
      valueListenable: bottomItemHeight,
      builder: (context, firstItemHeight, _) {
        return ListView.builder(
          controller: result.controller,
          reverse: true,
          physics: MaintainReadingPositionPhysics(
            shouldMaintain: () => !result.isFollowingOutput,
          ),
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(
            height: i == 0 ? firstItemHeight : 50,
            child: Text('$i'),
          ),
        );
      },
    );
  }
}
