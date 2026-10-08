import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last-used username on this device so returning users don't
/// have to retype it. Never stores a PIN or password.
class LastUsernameStore {
  LastUsernameStore._();
  static const _key = 'yenko_last_username';

  static Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_key);
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> write(String username) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, username);
  }
}
