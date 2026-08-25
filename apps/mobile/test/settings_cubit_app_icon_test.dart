import 'package:ccpocket/features/settings/state/settings_cubit.dart';
import 'package:ccpocket/models/app_icon.dart';
import 'package:ccpocket/services/app_icon_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAppIconGateway implements AppIconGateway {
  FakeAppIconGateway({this.currentIcon});

  final appliedIcons = <String?>[];
  String? currentIcon;

  @override
  Future<bool> supportsAlternateIcons() async => true;

  @override
  Future<String?> getCurrentIcon() async => currentIcon;

  @override
  Future<void> setIcon(String? iconId) async {
    currentIcon = iconId;
    appliedIcons.add(iconId);
  }
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsCubit app icon sync', () {
    test('applies selected icon on startup without supporter check', () async {
      SharedPreferences.setMockInitialValues({
        'settings_selected_app_icon': 'light_outline',
      });
      final prefs = await SharedPreferences.getInstance();
      final appIconGateway = FakeAppIconGateway();
      final cubit = SettingsCubit(
        prefs,
        appIconService: AppIconService(
          gateway: appIconGateway,
          platform: TargetPlatform.iOS,
        ),
      );

      await _flushAsync();
      expect(cubit.state.selectedAppIcon, AppIconVariant.lightOutline);
      expect(appIconGateway.appliedIcons, isEmpty);

      await cubit.close();
    });

    test('can reset to default from explicit selection', () async {
      SharedPreferences.setMockInitialValues({
        'settings_selected_app_icon': 'light_outline',
      });
      final prefs = await SharedPreferences.getInstance();
      final appIconGateway = FakeAppIconGateway(currentIcon: 'light_outline');
      final cubit = SettingsCubit(
        prefs,
        appIconService: AppIconService(
          gateway: appIconGateway,
          platform: TargetPlatform.iOS,
        ),
      );

      await _flushAsync();
      await cubit.setSelectedAppIcon(AppIconVariant.defaultIcon);

      expect(cubit.state.selectedAppIcon, AppIconVariant.defaultIcon);
      expect(appIconGateway.appliedIcons.last, isNull);

      await cubit.close();
    });

    test('applies selected icon immediately for any user', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final appIconGateway = FakeAppIconGateway();
      final cubit = SettingsCubit(
        prefs,
        appIconService: AppIconService(
          gateway: appIconGateway,
          platform: TargetPlatform.android,
        ),
      );

      await _flushAsync();
      await cubit.setSelectedAppIcon(AppIconVariant.proCopperEmerald);

      expect(cubit.state.selectedAppIcon, AppIconVariant.proCopperEmerald);
      expect(appIconGateway.appliedIcons.last, 'pro_copper_emerald');

      await cubit.close();
    });
  });
}
