import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NetworkAvailability { unknown, online, offline, cachedOffline }

class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();

  static final NetworkStatus instance = NetworkStatus._();

  NetworkAvailability _value = NetworkAvailability.unknown;
  NetworkAvailability get value => _value;
  bool get isOffline =>
      _value == NetworkAvailability.offline ||
      _value == NetworkAvailability.cachedOffline;
  bool get isShowingCachedData => _value == NetworkAvailability.cachedOffline;

  void markOnline() => _set(NetworkAvailability.online);
  void markOffline({required bool cached}) => _set(
      cached ? NetworkAvailability.cachedOffline : NetworkAvailability.offline);

  void _set(NetworkAvailability next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }

  @visibleForTesting
  void reset() => _set(NetworkAvailability.unknown);
}

class PublicApiCache {
  static const Duration maxAge = Duration(days: 7);
  static const String _prefix = 'public_api_cache_v1:';
  final Map<String, ({DateTime savedAt, dynamic value})> _memory = {};

  static bool canCache(String path, String? token) {
    if (token != null) return false;
    final uri = Uri.parse(path);
    return uri.path == '/universities' ||
        uri.path.startsWith('/universities/') ||
        uri.path == '/programs' ||
        uri.path.startsWith('/programs/') ||
        uri.path == '/scholarships' ||
        uri.path.startsWith('/content/');
  }

  Future<void> write(String path, dynamic value) async {
    final savedAt = DateTime.now().toUtc();
    _memory[path] = (savedAt: savedAt, value: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix${Uri.encodeComponent(path)}',
      jsonEncode({
        'savedAt': savedAt.toIso8601String(),
        'value': value,
      }),
    );
  }

  Future<dynamic> read(String path, {DateTime? now}) async {
    final currentTime = now ?? DateTime.now().toUtc();
    final memoryEntry = _memory[path];
    if (memoryEntry != null) {
      if (currentTime.difference(memoryEntry.savedAt) <= maxAge) {
        return memoryEntry.value;
      }
      _memory.remove(path);
    }
    final preferences = await SharedPreferences.getInstance();
    final key = '$_prefix${Uri.encodeComponent(path)}';
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(entry['savedAt'] as String);
      if (currentTime.difference(savedAt) > maxAge) {
        await preferences.remove(key);
        return null;
      }
      _memory[path] = (savedAt: savedAt, value: entry['value']);
      return entry['value'];
    } catch (_) {
      await preferences.remove(key);
      return null;
    }
  }
}
