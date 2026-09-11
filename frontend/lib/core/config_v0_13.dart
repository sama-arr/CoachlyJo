/// App-wide configuration.
class AppConfig {
  /// Base URL of the backend API.
  ///
  /// IMPORTANT for testing:
  ///  - Android emulator: use http://10.0.2.2:4000  (10.0.2.2 = host machine)
  ///  - iOS simulator:    use http://localhost:4000
  ///  - Real device:      use http://<your-computer-LAN-IP>:4000
  ///  - Web (chrome):     use http://localhost:4000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );
}
