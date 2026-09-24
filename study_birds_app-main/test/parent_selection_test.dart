import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_birds/core/auth_session.dart';
import 'package:study_birds/screens/roles/parent_dashboard_screen.dart';

void main() {
  tearDown(() {
    AuthSession.instance.token = null;
    AuthSession.instance.currentUser = null;
  });
  for (final staleFails in [false, true]) {
    testWidgets(
        'child selection ignores late ${staleFails ? 'failure' : 'success'} from previous child',
        (tester) async {
      AuthSession.instance.token = 'test-parent';
      final oldResponse = Completer<http.Response>();
      var requestedOld = false;
      http.Response json(Object data) => http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
      await http.runWithClient(() async {
        await tester
            .pumpWidget(const MaterialApp(home: ParentDashboardScreen()));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(requestedOld, isTrue);
        await tester.tap(find.text('Second child'));
        await tester.pumpAndSettle();
        expect(find.text('second@example.test'), findsOneWidget);
        oldResponse.complete(staleFails
            ? http.Response('{}', 500)
            : json({
                'student': {
                  'name': 'First child',
                  'email': 'first@example.test'
                },
                'applications': <Object>[],
              }));
        await tester.pumpAndSettle();
        expect(find.text('second@example.test'), findsOneWidget);
        expect(find.text('first@example.test'), findsNothing);
      },
          () => MockClient((request) async {
                if (request.url.path.endsWith('/parents/children')) {
                  return json([
                    {'_id': 'a', 'name': 'First child'},
                    {'_id': 'b', 'name': 'Second child'}
                  ]);
                }
                if (request.url.path.endsWith('/link-requests')) {
                  return json([]);
                }
                if (request.url.path.endsWith('/a/overview')) {
                  requestedOld = true;
                  return oldResponse.future;
                }
                if (request.url.path.endsWith('/b/overview')) {
                  return json({
                    'student': {
                      'name': 'Second child',
                      'email': 'second@example.test'
                    },
                    'applications': <Object>[]
                  });
                }
                throw StateError('Unexpected request: ${request.url.path}');
              }));
    });
  }
}
