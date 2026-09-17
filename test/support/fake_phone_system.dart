import 'package:notes/data/device/phone_system.dart';
import 'package:notes/domain/model/settings.dart';

/// Stands in for the phone's own settings.
class FakePhoneSystem implements PhoneSystem {
  FakePhoneSystem({this.maker = 'Google'});

  String maker;

  /// Night modes set, in order.
  final nightModes = <ThemeChoice>[];

  int backgroundSettingsOpened = 0;

  @override
  Future<void> setNightMode(ThemeChoice theme) async => nightModes.add(theme);

  @override
  Future<String> manufacturer() async => maker;

  @override
  Future<bool> openBackgroundSettings() async {
    backgroundSettingsOpened++;
    return true;
  }
}
