import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/widgets/bubbles/result_chip.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';
import 'package:ccpocket/theme/app_theme.dart';

void main() {
  group('Antigravity Session UI & Duration Tests', () {
    testWidgets('ResultChip displays single-turn wall-clock duration accurately', (tester) async {
      const resultMsgTurn1 = ResultMessage(
        subtype: 'success',
        duration: 1870, // 1.87s turn wall-clock duration
        result: 'Turn 1 completed',
      );

      const resultMsgTurn2 = ResultMessage(
        subtype: 'success',
        duration: 3170, // 3.17s turn wall-clock duration
        result: 'Turn 2 completed',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                BlocProvider<FileListCubit>(
                  create: (_) => FileListCubit(const [], const Stream.empty()),
                  child: const ResultChip(message: resultMsgTurn1),
                ),
                BlocProvider<FileListCubit>(
                  create: (_) => FileListCubit(const [], const Stream.empty()),
                  child: const ResultChip(message: resultMsgTurn2),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check duration strings
      expect(find.textContaining('1.9s'), findsOneWidget); // 1870ms -> 1.9s
      expect(find.textContaining('3.2s'), findsOneWidget); // 3170ms -> 3.2s
      expect(find.textContaining('耗时 1.9s'), findsOneWidget);
      expect(find.textContaining('耗时 3.2s'), findsOneWidget);
    });
  });
}
