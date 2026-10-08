class AppConfig {
  const AppConfig._();

  /// Disabled by default so regular UI work stays fully local and provider-free.
  static const useLocalApi = bool.fromEnvironment(
    'YENKO_USE_LOCAL_API',
    defaultValue: false,
  );

  /// Android emulators reach the development machine through 10.0.2.2.
  static const localApiBaseUrl = String.fromEnvironment(
    'YENKO_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
}
