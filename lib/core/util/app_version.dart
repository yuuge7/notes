/// The version the app was built as: what `flutter build --build-name` set,
/// or the version in pubspec.yaml. `dev` where no build set one, as in tests.
const appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: 'dev',
);
