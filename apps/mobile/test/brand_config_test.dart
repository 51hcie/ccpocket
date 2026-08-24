import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccpocket/constants/brand_config.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/new_session_tab.dart';
import 'package:ccpocket/features/session_list/state/session_list_cubit.dart';
import 'package:ccpocket/features/session_list/state/session_list_state.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:ccpocket/widgets/anycoding_logo.dart';
import 'package:ccpocket/widgets/new_session_sheet.dart';
import 'package:ccpocket/features/session_list/widgets/session_list_app_bar.dart';
import 'package:ccpocket/features/session_list/widgets/dual_engine_dashboard_card.dart';
import 'package:ccpocket/models/messages.dart';

void main() {
  group('BrandConfig unit tests', () {
    test('default brand values when ANYCODING_BRAND is off', () {
      // In normal test runs without --dart-define=ANYCODING_BRAND=true
      if (!BrandConfig.isAnyCoding) {
        expect(BrandConfig.appName, 'CC Pocket');
        expect(BrandConfig.notificationTitle, 'CC Pocket');
        expect(BrandConfig.showSupporterFeatures, isTrue);
        expect(BrandConfig.showStoreReview, isTrue);
        expect(BrandConfig.showSharePromotion, isTrue);
      } else {
        expect(BrandConfig.appName, 'AnyCoding');
        expect(BrandConfig.notificationTitle, 'AnyCoding');
        expect(BrandConfig.showSupporterFeatures, isFalse);
        expect(BrandConfig.showStoreReview, isFalse);
        expect(BrandConfig.showSharePromotion, isFalse);
      }
    });

    test('BrandConfig exposes openSourceAttribution and aboutDescription', () {
      expect(BrandConfig.openSourceAttribution, isNotEmpty);
      expect(BrandConfig.aboutDescription, isNotEmpty);
    });

    test('resolveVisibleNewSessionTabs excludes Claude when isAnyCoding is true', () {
      final anycodingTabs = resolveVisibleNewSessionTabs(
        configuredTabs: defaultNewSessionTabs,
        isAnyCoding: true,
      );
      expect(anycodingTabs, equals([NewSessionTab.codex, NewSessionTab.antigravity]));
      expect(anycodingTabs.contains(NewSessionTab.claude), isFalse);

      final upstreamTabs = resolveVisibleNewSessionTabs(
        configuredTabs: defaultNewSessionTabs,
        isAnyCoding: false,
      );
      expect(upstreamTabs, equals(defaultNewSessionTabs));
      expect(upstreamTabs.contains(NewSessionTab.claude), isTrue);
    });

    test('providerFiltersForEnabledTabs excludes Claude when isAnyCoding is true', () {
      final anycodingFilters = providerFiltersForEnabledTabs(
        defaultNewSessionTabs,
        isAnyCoding: true,
      );
      expect(
        anycodingFilters,
        equals([
          ProviderFilter.all,
          ProviderFilter.codex,
          ProviderFilter.antigravity,
        ]),
      );
      expect(anycodingFilters.contains(ProviderFilter.claude), isFalse);

      final upstreamFilters = providerFiltersForEnabledTabs(
        defaultNewSessionTabs,
        isAnyCoding: false,
      );
      expect(upstreamFilters.contains(ProviderFilter.claude), isTrue);
    });
  });

  group('AnyCoding branding & visual widgets', () {
    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );
    }

    testWidgets('renders AnyCodingLogo custom paint without error', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const AnyCodingLogo(size: 32, showContainer: true),
        ),
      );
      expect(find.byType(AnyCodingLogo), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders DualEngineDashboardCard with online state and counters', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const DualEngineDashboardCard(
            connectionState: BridgeConnectionState.connected,
            endpointLabel: 'ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
            runningCount: 2,
            waitingCount: 1,
            failedCount: 0,
            completedCount: 4,
            codexStatusLabel: 'Ready',
            antigravityStatusLabel: 'Ready',
            isCodexOnline: true,
            isAntigravityOnline: true,
          ),
        ),
      );

      expect(find.byKey(const ValueKey('dual_engine_dashboard_card')), findsOneWidget);
      expect(find.text('Codex: Ready'), findsOneWidget);
      expect(find.text('Antigravity: Ready'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('SessionListSliverAppBar renders BrandConfig.appName runtime title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SessionListSliverAppBar(
                  onTitleTap: () {},
                  onDisconnect: () {},
                  bridgeLabel: 'AnyCoding Mac',
                ),
              ],
            ),
          ),
        ),
      );

      // In AnyCoding mode it must find AnyCoding; in standard mode CC Pocket
      expect(find.text(BrandConfig.appName), findsOneWidget);
      expect(find.text('AnyCoding Mac'), findsOneWidget);
    });

    testWidgets('SessionListPaneHeader renders BrandConfig.appName runtime title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SessionListPaneHeader(
              onTitleTap: () {},
              onOpenSettings: () {},
              bridgeLabel: 'AnyCoding Mac',
            ),
          ),
        ),
      );

      expect(find.text(BrandConfig.appName), findsOneWidget);
      expect(find.text('AnyCoding Mac'), findsOneWidget);
    });

    testWidgets('showNewSessionSheet renders only Codex and Antigravity when resolved for AnyCoding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showNewSessionSheet(
                    context: context,
                    recentProjects: const [],
                    visibleTabs: resolveVisibleNewSessionTabs(
                      configuredTabs: defaultNewSessionTabs,
                      isAnyCoding: true,
                    ),
                    initialParams: NewSessionParams(
                      projectPath: '/workspace',
                      provider: Provider.codex,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Provider selector must contain Codex and Antigravity, but not Claude
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Antigravity'), findsOneWidget);
      expect(find.text('Claude'), findsNothing);
    });
  });
}
