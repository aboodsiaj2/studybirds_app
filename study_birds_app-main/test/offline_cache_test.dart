import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_birds/core/api_client.dart';
import 'package:study_birds/core/offline_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkStatus.instance.reset();
  });

  test('public catalog falls back to its last successful response', () async {
    var online = true;
    final client = ApiClient(client: MockClient((request) async {
      if (!online) throw http.ClientException('offline', request.url);
      return http.Response('[{"_id":"university-1"}]', 200);
    }));

    expect(await client.get('/universities'), isA<List>());
    expect(NetworkStatus.instance.value, NetworkAvailability.online);

    online = false;
    final cached = await client.get('/universities') as List;
    expect(cached.single['_id'], 'university-1');
    expect(NetworkStatus.instance.value, NetworkAvailability.cachedOffline);
  });

  test('authenticated responses are never written to the public cache',
      () async {
    var online = true;
    final client = ApiClient(client: MockClient((request) async {
      if (!online) throw http.ClientException('offline', request.url);
      return http.Response('{"balance":500}', 200);
    }));

    await client.get('/students/wallet', token: 'secret-token');
    online = false;
    await expectLater(
      client.get('/students/wallet', token: 'secret-token'),
      throwsA(isA<ApiException>()),
    );
    expect(NetworkStatus.instance.value, NetworkAvailability.offline);
  });

  test('expired public cache is discarded', () async {
    final cache = PublicApiCache();
    await cache.write('/programs', const [
      {'id': 'old'}
    ]);

    expect(
      await cache.read(
        '/programs',
        now: DateTime.now().toUtc().add(const Duration(days: 8)),
      ),
      isNull,
    );
  });
}
