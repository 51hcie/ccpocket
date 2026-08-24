import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'package:ccpocket/constants/brand_config.dart';
import 'package:ccpocket/features/chat_session/state/chat_session_cubit.dart';
import 'package:ccpocket/features/chat_session/state/chat_session_state.dart';
import 'package:ccpocket/features/chat_session/widgets/session_mode_bar.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/theme/app_theme.dart';

class MockChatSessionCubit extends Cubit<ChatSessionState> implements ChatSessionCubit {
  MockChatSessionCubit(super.initialState);

  @override
  Provider get provider => Provider.codex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnyCoding Advanced Options Tests', () {
    Widget buildTestHarness({required Widget child, required ChatSessionCubit cubit}) {
      final bridge = BridgeService();
      return Provider<BridgeService>.value(
        value: bridge,
        child: BlocProvider<ChatSessionCubit>.value(
          value: cubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            theme: AppTheme.darkTheme,
            home: Scaffold(body: child),
          ),
        ),
      );
    }

    testWidgets('SessionModeBar renders collapsed pill in AnyCoding mode and expands on tap', (tester) async {
      final cubit = MockChatSessionCubit(
        const ChatSessionState(
          status: ProcessStatus.idle,
          planMode: false,
          inPlanMode: false,
          executionMode: ExecutionMode.defaultMode,
          codexModel: 'gpt-5.4',
        ),
      );

      await tester.pumpWidget(
        buildTestHarness(
          cubit: cubit,
          child: const SessionModeBar(),
        ),
      );

      if (BrandConfig.isAnyCoding) {
        // Collapsed state
        expect(find.byKey(const ValueKey('anycoding_advanced_options_collapsed')), findsOneWidget);
        expect(find.text('高级选项'), findsOneWidget);

        // Tap to expand
        await tester.tap(find.byKey(const ValueKey('anycoding_advanced_options_collapsed')));
        await tester.pumpAndSettle();

        // Expanded state should reveal plan mode chip and model chips
        expect(find.byType(PlanModeChip), findsOneWidget);
        expect(find.byType(CodexModelChip), findsOneWidget);
      } else {
        // Upstream mode: standard mode bar always expanded
        expect(find.byType(PlanModeChip), findsOneWidget);
      }
    });
  });
}
