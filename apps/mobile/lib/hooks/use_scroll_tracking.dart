import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:scroll_to_index/scroll_to_index.dart';

/// Cross-session scroll position and output-following intent persistence.
final Map<String, ({double offset, bool isFollowingOutput})> _scrollStates = {};

/// Minimum change in maxScrollExtent (in logical pixels) to be considered a
/// layout-driven shift rather than floating-point rounding noise.
const _kExtentChangeTolerance = 1.0;

/// Distance from the bottom that still counts as following live output.
const _kAutoFollowThreshold = 24.0;

@visibleForTesting
bool nextAutoFollowState({
  required bool isFollowing,
  required double distanceFromBottom,
  required ScrollDirection direction,
}) {
  if (distanceFromBottom <= 1) return true;
  if (direction == ScrollDirection.reverse) return false;
  if (distanceFromBottom > _kAutoFollowThreshold) return false;
  if (!isFollowing && direction == ScrollDirection.forward) return true;
  return isFollowing;
}

/// Result record returned by [useScrollTracking].
typedef ScrollTrackingResult = ({
  AutoScrollController controller,
  bool isScrolledUp,
  bool isFollowingOutput,
  void Function() scrollToBottom,
  void Function() forceScrollToBottom,
});

/// Manages scroll position tracking with three responsibilities:
///
/// 1. **Output following**: Follows live output only while the user remains at
///    the bottom. Scrolling toward older messages pauses following immediately.
/// 2. **Cross-session offset persistence**: Saves/restores scroll offset keyed
///    by [sessionId] so switching sessions preserves position.
/// 3. **Scroll-to-bottom**: Provides a [scrollToBottom] callback that smoothly
///    animates to the bottom (skipped while output following is paused).
ScrollTrackingResult useScrollTracking(String sessionId) {
  final controller = useMemoized(AutoScrollController.new);
  // Dispose the controller when the hook is disposed.
  useEffect(() => controller.dispose, const []);

  final isFollowingOutput = useState(true);
  final isFollowingOutputRef = useRef(true);

  // Track previous maxScrollExtent to detect layout-driven changes
  // (e.g. Android notification shade toggling safe-area padding).
  final prevMaxExtent = useRef<double?>(null);

  useEffect(() {
    void onScroll() {
      if (!controller.hasClients) return;
      final pos = controller.position;

      final prevMax = prevMaxExtent.value;
      prevMaxExtent.value = pos.maxScrollExtent;

      // When maxScrollExtent shifts (viewport/layout change) while we were
      // already at the bottom, ignore this event — don't pause following.
      // The framework will settle the scroll position on the next frame.
      // This prevents the FAB from flashing when the Android notification
      // shade is pulled down/up.
      // Note: when following is already paused (user scrolled up), we don't
      // guard — the user's intent takes priority over layout shifts.
      if (prevMax != null && isFollowingOutputRef.value) {
        final extentDelta = (pos.maxScrollExtent - prevMax).abs();
        if (extentDelta > _kExtentChangeTolerance) return;
      }

      final next = nextAutoFollowState(
        isFollowing: isFollowingOutputRef.value,
        distanceFromBottom: pos.pixels - pos.minScrollExtent,
        direction: pos.userScrollDirection,
      );
      isFollowingOutputRef.value = next;
      if (next != isFollowingOutput.value) {
        isFollowingOutput.value = next;
      }
    }

    controller.addListener(onScroll);

    // Restore saved offset after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = _scrollStates[sessionId];
      final followsSavedPosition = saved?.isFollowingOutput ?? true;
      isFollowingOutputRef.value = followsSavedPosition;
      isFollowingOutput.value = followsSavedPosition;
      if (saved != null && controller.hasClients) {
        controller.jumpTo(saved.offset);
      }
    });

    return () {
      // Persist offset before disposal.
      if (controller.hasClients) {
        _scrollStates[sessionId] = (
          offset: controller.offset,
          isFollowingOutput: isFollowingOutputRef.value,
        );
      }
      controller.removeListener(onScroll);
      prevMaxExtent.value = null;
    };
  }, [sessionId]);

  void animateToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void scrollToBottom() {
    if (!isFollowingOutputRef.value) return;
    animateToBottom();
  }

  void forceScrollToBottom() {
    isFollowingOutputRef.value = true;
    isFollowingOutput.value = true;
    animateToBottom();
  }

  return (
    controller: controller,
    isScrolledUp: !isFollowingOutput.value,
    isFollowingOutput: isFollowingOutput.value,
    scrollToBottom: scrollToBottom,
    forceScrollToBottom: forceScrollToBottom,
  );
}
