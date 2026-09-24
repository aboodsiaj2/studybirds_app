import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple SharedPreferences-based response cache.
/// Keys are arbitrary strings; values are JSON-serialisable objects.
/// TTL-based expiry: each entry stores the timestamp it was written.
class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  static const int _defaultTtlSeconds = 300; // 5 minutes
  static const String _prefix = 'cache_v1_';
  static const String _tsPrefix = 'cache_ts_v1_';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<T?> get<T>(String key, {int ttlSeconds = _defaultTtlSeconds}) async {
    final p = _prefs;
    if (p == null) return null;
    final ts = p.getInt('$_tsPrefix$key');
    if (ts == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
    if (age > ttlSeconds) return null;
    final raw = p.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return null;
    }
  }

  Future<void> set(String key, dynamic value) async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setString('$_prefix$key', jsonEncode(value));
      await p.setInt('$_tsPrefix$key', DateTime.now().millisecondsSinceEpoch ~/ 1000);
    } catch (_) {}
  }

  Future<void> remove(String key) async {
    final p = _prefs;
    if (p == null) return;
    await p.remove('$_prefix$key');
    await p.remove('$_tsPrefix$key');
  }

  Future<void> clear() async {
    final p = _prefs;
    if (p == null) return;
    final keys = p.getKeys().where((k) => k.startsWith(_prefix) || k.startsWith(_tsPrefix)).toList();
    for (final k in keys) {
      await p.remove(k);
    }
  }
}
