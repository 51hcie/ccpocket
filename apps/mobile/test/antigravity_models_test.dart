import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccpocket/models/antigravity_models.dart';

void main() {
  group('Antigravity Models Completeness & Default Tests', () {
    test('Default Antigravity model is gemini-3.7-flash-medium', () {
      expect(defaultAntigravityModel, 'gemini-3.7-flash-medium');
      final defaultOption = findAntigravityModel(null);
      expect(defaultOption.id, 'gemini-3.7-flash-medium');
      expect(defaultOption.name, 'Gemini 3.7 Flash Medium');
      expect(defaultOption.providerName, 'Google');
      expect(defaultOption.isDefault, true);
    });

    test('Contains all 14 official models supported by agy models', () {
      final expectedModelIds = [
        'gemini-3.7-flash-high',
        'gemini-3.7-flash-medium',
        'gemini-3.7-flash-low',
        'gemini-3.6-flash-high',
        'gemini-3.6-flash-medium',
        'gemini-3.6-flash-low',
        'gemini-3.5-flash-high',
        'gemini-3.5-flash-medium',
        'gemini-3.5-flash-low',
        'gemini-3.1-pro-high',
        'gemini-3.1-pro-low',
        'claude-sonnet-4-6',
        'claude-opus-4-6-thinking',
        'gpt-oss-120b-medium',
      ];

      final actualModelIds = defaultAntigravityModels.map((m) => m.id).toList();
      expect(actualModelIds, expectedModelIds);
      expect(defaultAntigravityModels.length, 14);
    });

    test('All models have friendly names and correct provider provenance', () {
      // Gemini models
      for (final id in [
        'gemini-3.7-flash-high',
        'gemini-3.7-flash-medium',
        'gemini-3.7-flash-low',
        'gemini-3.6-flash-high',
        'gemini-3.6-flash-medium',
        'gemini-3.6-flash-low',
        'gemini-3.5-flash-high',
        'gemini-3.5-flash-medium',
        'gemini-3.5-flash-low',
        'gemini-3.1-pro-high',
        'gemini-3.1-pro-low',
      ]) {
        final opt = findAntigravityModel(id);
        expect(opt.providerName, 'Google');
        expect(opt.name.startsWith('Gemini'), true);
      }

      // Claude models are under Antigravity provider (not standalone provider)
      final claudeSonnet = findAntigravityModel('claude-sonnet-4-6');
      expect(claudeSonnet.providerName, 'Anthropic');
      expect(claudeSonnet.name, 'Claude 3.7 Sonnet');

      final claudeOpus = findAntigravityModel('claude-opus-4-6-thinking');
      expect(claudeOpus.providerName, 'Anthropic');
      expect(claudeOpus.name, 'Claude Opus (Thinking)');

      // GPT OSS model
      final gptOss = findAntigravityModel('gpt-oss-120b-medium');
      expect(gptOss.providerName, 'OpenAI');
      expect(gptOss.name, 'GPT-OSS 120B Medium');
    });

    test('findAntigravityModel resolves custom/unknown IDs gracefully', () {
      final custom = findAntigravityModel('custom-gemini-v1');
      expect(custom.id, 'custom-gemini-v1');
      expect(custom.name, 'custom-gemini-v1');
      expect(custom.providerName, 'Antigravity');
    });

    testWidgets('showAntigravityModelSheet renders all 14 options and selects model', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showAntigravityModelSheet(
                      context: context,
                      currentModel: 'gemini-3.7-flash-medium',
                      onSelected: (val) {
                        selectedResult = val;
                      },
                    );
                  },
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.text('Antigravity 模型选择'), findsOneWidget);
      expect(find.text('Gemini 3.7 Flash Medium'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);

      // Tap Claude Sonnet option
      final claudeFinder = find.byKey(const ValueKey('antigravity_model_option_claude-sonnet-4-6'));
      expect(claudeFinder, findsOneWidget);

      await tester.tap(claudeFinder);
      await tester.pumpAndSettle();

      expect(selectedResult, 'claude-sonnet-4-6');
      expect(find.text('Antigravity 模型选择'), findsNothing);
    });
  });
}
