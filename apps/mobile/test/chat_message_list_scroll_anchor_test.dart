import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:ccpocket/features/chat_session/state/chat_session_cubit.dart';
import 'package:ccpocket/features/chat_session/state/streaming_state_cubit.dart';
import 'package:ccpocket/features/chat_session/widgets/chat_message_list.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:ccpocket/widgets/message_bubble.dart';

void main() {
  testWidgets('streaming growth preserves the visible message being read', (
    tester,
  ) async {
    final bridge = _ScrollTestBridge();
    final streamingCubit = StreamingStateCubit();
    final chatCubit = ChatSessionCubit(
      sessionId: 'scroll-anchor',
      bridge: bridge,
      streamingCubit: streamingCubit,
    );
    final controller = AutoScrollController();
    addTearDown(controller.dispose);
    addTearDown(chatCubit.close);
    addTearDown(streamingCubit.close);
    addTearDown(bridge.dispose);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [RepositoryProvider<BridgeService>.value(value: bridge)],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ChatSessionCubit>.value(value: chatCubit),
            BlocProvider<StreamingStateCubit>.value(value: streamingCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: ChatMessageList(
                sessionId: 'scroll-anchor',
                scrollController: controller,
                httpBaseUrl: null,
                onRetryMessage: null,
                collapseToolResults: null,
                isReadingHistory: true,
              ),
            ),
          ),
        ),
      ),
    );

    bridge.emit(
      PastHistoryMessage(
        claudeSessionId: 'past',
        messages: List.generate(
          40,
          (index) => PastMessage(
            role: 'user',
            content: [TextContent(text: 'message $index')],
          ),
        ),
      ),
    );
    bridge.emit(const StatusMessage(status: ProcessStatus.idle));
    await tester.pumpAndSettle();

    final scrollFuture = controller.scrollToIndex(
      35,
      preferPosition: AutoScrollPosition.middle,
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    await scrollFuture;
    final target = find.text('message 35');
    expect(target, findsOneWidget);

    streamingCubit.appendText('short');
    await tester.pump();
    await tester.pump();
    final streamingEntry = find.byWidgetPredicate(
      (widget) =>
          widget is ChatEntryWidget && widget.entry is StreamingChatEntry,
    );
    expect(streamingEntry, findsOneWidget);
    final before = tester.getTopLeft(target).dy;
    final offsetBefore = controller.offset;
    final streamingHeightBefore = tester.getSize(streamingEntry).height;

    streamingCubit.appendText(
      List.generate(8, (index) => '\n\nstreaming line $index').join(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.getSize(streamingEntry).height,
      greaterThan(streamingHeightBefore),
    );
    expect(tester.getTopLeft(target).dy, closeTo(before, 1));
    expect(controller.offset, greaterThanOrEqualTo(offsetBefore));
    expect(controller.offset, lessThan(controller.position.maxScrollExtent));
    expect(tester.takeException(), isNull);
  });
}

class _ScrollTestBridge extends BridgeService {
  final _messages = StreamController<(ServerMessage, String?)>.broadcast();

  void emit(ServerMessage message) => _messages.add((message, 'scroll-anchor'));

  @override
  Stream<ServerMessage> messagesForSession(String sessionId) => _messages.stream
      .where((event) => event.$2 == sessionId)
      .map((event) => event.$1);

  @override
  void requestSessionHistory(String sessionId) {}

  @override
  void send(ClientMessage message) {}

  @override
  void dispose() {
    _messages.close();
    super.dispose();
  }
}
