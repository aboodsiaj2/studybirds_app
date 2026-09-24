import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_birds/core/auth_session.dart';
import 'package:study_birds/screens/services_support/services_consultation_screens.dart';

http.Response reply(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() => AuthSession.instance.token = 'service-test');
  tearDown(() => AuthSession.instance.token = null);

  testWidgets('service request creates an order only after confirmation',
      (tester) async {
    var writes = 0;
    Map<String, dynamic>? sent;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: ServiceDetailScreen(service: {
        '_id': 's1',
        'name': 'ترجمة',
        'price': 'يحدد لاحقاً',
        'detailBody': 'ترجمة الوثائق'
      })));
      await tester.enterText(find.byType(TextField), 'وثيقتان');
      await tester.tap(find.text('طلب الخدمة'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(sent, {'serviceId': 's1', 'notes': 'وثيقتان'});
    },
        () => MockClient((request) async {
              writes++;
              sent = Map<String, dynamic>.from(jsonDecode(request.body));
              return reply({'_id': 'o1'}, 201);
            }));
  });

  testWidgets('orders show quote, staff note and status', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ServiceOrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ترجمة'), findsOneWidget);
      expect(find.text('بانتظار الدفع'), findsOneWidget);
      expect(find.text('السعر: 25 USD'), findsOneWidget);
      expect(find.text('أرسل إثبات الدفع'), findsOneWidget);
    },
        () => MockClient((_) async => reply([
              {
                '_id': 'o1',
                '__v': 1,
                'status': 'awaiting-payment',
                'service': {'title': 'ترجمة'},
                'quotedPrice': 25,
                'currency': 'USD',
                'staffNote': 'أرسل إثبات الدفع'
              }
            ])));
  });
}
