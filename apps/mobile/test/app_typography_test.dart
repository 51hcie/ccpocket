import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket/theme/app_typography.dart';
import 'package:ccpocket/theme/app_theme.dart';

void main() {
  group('AppTypography Scale & Tokens Test', () {
    testWidgets('provides consistent text styles across light and dark themes', (tester) async {
      late TextStyle displayStyle;
      late TextStyle titleStyle;
      late TextStyle bodyStyle;
      late TextStyle labelStyle;
      late TextStyle captionStyle;
      late TextStyle monoStyle;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              displayStyle = AppTypography.display(context);
              titleStyle = AppTypography.titleLarge(context);
              bodyStyle = AppTypography.bodyMedium(context);
              labelStyle = AppTypography.labelMedium(context);
              captionStyle = AppTypography.caption(context);
              monoStyle = AppTypography.mono(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(displayStyle.fontSize, 26);
      expect(titleStyle.fontSize, 17);
      expect(bodyStyle.fontSize, 13.5);
      expect(labelStyle.fontSize, 12);
      expect(captionStyle.fontSize, 11);
      expect(monoStyle.fontFamilyFallback, contains('monospace'));
    });

    testWidgets('renders all typography tokens at text scale 1.0 and 1.3 without overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      for (final scale in [1.0, 1.3]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(412, 915),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: ListView(
                  children: [
                    Builder(
                      builder: (ctx) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AnyCoding Display 42', style: AppTypography.display(ctx)),
                          Text('Section Title Header', style: AppTypography.titleLarge(ctx)),
                          Text('Medium Card Title', style: AppTypography.titleMedium(ctx)),
                          Text('Readable Body Paragraph in Chinese & English · 测试混排文本', style: AppTypography.bodyMedium(ctx)),
                          Text('Button & Chip Label', style: AppTypography.labelMedium(ctx)),
                          Text('2026-08-25 12:00:00 · 来源: Bridge', style: AppTypography.caption(ctx)),
                          Text('ws://[2408:824e:...]:8766', style: AppTypography.mono(ctx)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
