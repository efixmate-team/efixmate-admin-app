import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which backend the app talks to. Switchable from the login screen
/// (long-press the logo) and persisted, so QA can flip between servers
/// without rebuilding.
enum ServerEnv { live, dev, local, custom }

class AppConfig {
  static const _prefKey = 'efm_admin_server';

  /// Store (release) builds talk to the live server; debug builds to dev.
  /// Override with `--dart-define=SERVER_ENV=dev` (e.g. a staging AAB).
  static const _envOverride = String.fromEnvironment('SERVER_ENV');
  static ServerEnv env = ServerEnv.values.firstWhere(
    (e) => e.name == _envOverride,
    orElse: () => kReleaseMode ? ServerEnv.live : ServerEnv.dev,
  );

  /// Android emulator reaches the host machine at 10.0.2.2. On a real device
  /// use `adb reverse tcp:5000 tcp:5000` and this still works via localhost.
  static String localHost = 'http://10.0.2.2:5000';

  /// API base taken from a scanned login QR (e.g. https://efixmate.com/api).
  static String customUrl = '';

  static String get baseUrl {
    switch (env) {
      case ServerEnv.live:
        return 'https://api.efixmate.com';
      case ServerEnv.dev:
        return 'https://dev.api.efixmate.com';
      case ServerEnv.local:
        return localHost;
      case ServerEnv.custom:
        return customUrl.isEmpty ? 'https://dev.api.efixmate.com' : customUrl;
    }
  }

  /// Point the app at the API a login QR names: reuse a known server when it
  /// matches, otherwise store it as a custom server.
  static Future<void> useScannedServer(String url) async {
    final u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isEmpty) return;
    for (final e in const [ServerEnv.live, ServerEnv.dev]) {
      env = e;
      if (baseUrl == u) return save(e);
    }
    customUrl = u;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefKey}_custom', u);
    await save(ServerEnv.custom);
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      env = ServerEnv.values.firstWhere((e) => e.name == saved, orElse: () => env);
    }
    localHost = prefs.getString('${_prefKey}_local') ?? localHost;
    customUrl = prefs.getString('${_prefKey}_custom') ?? customUrl;
  }

  static Future<void> save(ServerEnv next, {String? local}) async {
    env = next;
    if (local != null && local.trim().isNotEmpty) localHost = local.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, next.name);
    await prefs.setString('${_prefKey}_local', localHost);
  }

  /// Public URL for an uploaded file the API returned as a path.
  /// Mirrors partner_app ApiStrings.resolveImageUrl.
  static String fileUrl(dynamic path) {
    final raw = (path ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('data:')) {
      // Local dev uploads come back as localhost URLs the phone can't reach.
      final m = RegExp(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?/(api/)?uploads/(.*)$').firstMatch(raw);
      if (m != null) return '$baseUrl/uploads/${m.group(4)}';
      return raw;
    }
    final rel = raw.replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'^(api/)?uploads/', caseSensitive: false), '');
    String enc;
    try {
      enc = Uri.encodeFull(Uri.decodeFull(rel));
    } catch (_) {
      enc = Uri.encodeFull(rel);
    }
    return '$baseUrl/uploads/$enc';
  }
}
