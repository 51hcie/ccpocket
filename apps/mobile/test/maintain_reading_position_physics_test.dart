import 'package:ccpocket/features/chat_session/widgets/maintain_reading_position_physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MaintainReadingPositionPhysics', () {
    test('compensates for new output while reading away from the bottom', () {
      final physics = MaintainReadingPositionPhysics(
        shouldMaintain: () => true,
      );

      final adjusted = physics.adjustPositionForNewDimensions(
        oldPosition: _metrics(pixels: 240, maxScrollExtent: 1000),
        newPosition: _metrics(pixels: 240, maxScrollExtent: 1120),
        isScrolling: false,
        velocity: 0,
      );

      expect(adjusted, 360);
    });

    test('does not compensate while output following is enabled', () {
      final physics = MaintainReadingPositionPhysics(
        shouldMaintain: () => false,
      );

      final adjusted = physics.adjustPositionForNewDimensions(
        oldPosition: _metrics(pixels: 80, maxScrollExtent: 1000),
        newPosition: _metrics(pixels: 80, maxScrollExtent: 1120),
        isScrolling: false,
        velocity: 0,
      );

      expect(adjusted, 80);
    });

    test('compensates when finalized output becomes shorter', () {
      final physics = MaintainReadingPositionPhysics(
        shouldMaintain: () => true,
      );

      final adjusted = physics.adjustPositionForNewDimensions(
        oldPosition: _metrics(pixels: 360, maxScrollExtent: 1120),
        newPosition: _metrics(pixels: 360, maxScrollExtent: 1000),
        isScrolling: false,
        velocity: 0,
      );

      expect(adjusted, 240);
    });

    test('does not double-correct shrinkage at the scroll boundary', () {
      final physics = MaintainReadingPositionPhysics(
        shouldMaintain: () => true,
        parent: const RangeMaintainingScrollPhysics(),
      );

      final adjusted = physics.adjustPositionForNewDimensions(
        oldPosition: _metrics(pixels: 1120, maxScrollExtent: 1120),
        newPosition: _metrics(pixels: 1120, maxScrollExtent: 1000),
        isScrolling: false,
        velocity: 0,
      );

      expect(adjusted, 1000);
    });

    test(
      'does not compensate when reading-position maintenance is disabled',
      () {
        final physics = MaintainReadingPositionPhysics(
          shouldMaintain: () => false,
        );

        final adjusted = physics.adjustPositionForNewDimensions(
          oldPosition: _metrics(pixels: 240, maxScrollExtent: 1000),
          newPosition: _metrics(pixels: 240, maxScrollExtent: 1120),
          isScrolling: false,
          velocity: 0,
        );

        expect(adjusted, 240);
      },
    );

    test('does not fight an active user drag', () {
      final physics = MaintainReadingPositionPhysics(
        shouldMaintain: () => true,
      );

      final adjusted = physics.adjustPositionForNewDimensions(
        oldPosition: _metrics(pixels: 240, maxScrollExtent: 1000),
        newPosition: _metrics(pixels: 240, maxScrollExtent: 1120),
        isScrolling: true,
        velocity: 0,
      );

      expect(adjusted, 240);
    });
  });
}

FixedScrollMetrics _metrics({
  required double pixels,
  required double maxScrollExtent,
}) {
  return FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: maxScrollExtent,
    pixels: pixels,
    viewportDimension: 600,
    axisDirection: AxisDirection.up,
    devicePixelRatio: 1,
  );
}
