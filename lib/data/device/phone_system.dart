import 'package:flutter/services.dart';
import 'package:notes/domain/model/settings.dart';

/// The few settings of the phone itself the app reaches into.
abstract interface class PhoneSystem {
  /// Holds [theme] as the app's own night mode, so the launch screen Android
  /// draws before the app runs wears the chosen theme.
  Future<void> setNightMode(ThemeChoice theme);

  /// Who made the phone, as Android reports it, such as `Xiaomi`.
  Future<String> manufacturer();

  /// Opens the page where the phone lets the app run in the background.
  /// Returns false when no such page, not even the app's own, could open.
  Future<bool> openBackgroundSettings();
}

/// Android, reached through MainActivity.
class DevicePhoneSystem implements PhoneSystem {
  static const _channel = MethodChannel('com.ionel.notes/system');

  @override
  Future<void> setNightMode(ThemeChoice theme) =>
      _channel.invokeMethod<void>('setNightMode', {'mode': theme.name});

  @override
  Future<String> manufacturer() async =>
      await _channel.invokeMethod<String>('manufacturer') ?? '';

  @override
  Future<bool> openBackgroundSettings() async =>
      await _channel.invokeMethod<bool>('openBackgroundSettings') ?? false;
}

/// Makers whose phones are known to stop apps in the background, and with
/// them the alarms reminders ring from, by the lower-case name Android gives,
/// to the name to show.
const backgroundKillers = {
  'xiaomi': 'Xiaomi',
  'redmi': 'Xiaomi',
  'poco': 'Xiaomi',
  'samsung': 'Samsung',
  'huawei': 'Huawei',
  'honor': 'Honor',
  'oppo': 'OPPO',
  'realme': 'realme',
  'oneplus': 'OnePlus',
  'vivo': 'vivo',
  'iqoo': 'iQOO',
};
