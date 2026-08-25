import 'package:ccpocket/features/settings/widgets/app_icon_bottom_sheet.dart';
import 'package:ccpocket/models/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildTestApp({
  required ValueChanged<AppIconVariant> onChanged,
}) {
  return MaterialApp(
    locale: const Locale('ja'),
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showAppIconBottomSheet(
            context: context,
            current: AppIconVariant.defaultIcon,
            onChanged: onChanged,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  group('AppIconBottomSheet', () {
    testWidgets('displays icon options without supporter locking', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          onChanged: (_) {},
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('ダーク'), findsOneWidget);
      expect(find.text('ライト'), findsOneWidget);
      expect(find.text('メタリック'), findsOneWidget);
    });

    testWidgets('can select any icon directly', (tester) async {
      AppIconVariant? selected;

      await tester.pumpWidget(
        _buildTestApp(
          onChanged: (icon) => selected = icon,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('app_icon_option_light_outline')),
      );
      await tester.pumpAndSettle();

      expect(selected, AppIconVariant.lightOutline);
    });

    testWidgets('can select pro metallic icon directly', (tester) async {
      AppIconVariant? selected;

      await tester.pumpWidget(
        _buildTestApp(
          onChanged: (icon) => selected = icon,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('app_icon_option_pro_copper_emerald')),
      );
      await tester.pumpAndSettle();

      expect(selected, AppIconVariant.proCopperEmerald);
    });
  });
}
