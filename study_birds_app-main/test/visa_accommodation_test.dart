import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_birds/core/auth_session.dart';
import 'package:study_birds/core/student_repository.dart';
import 'package:study_birds/screens/visa_travel_accommodation/visa_travel_screens.dart';
import 'package:study_birds/screens/visa_travel_accommodation/arrival_services_screen.dart';
import 'package:study_birds/screens/visa_travel_accommodation/accommodation_arrival_screens.dart';

http.Response reply(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() => AuthSession.instance.token = 'student-token');
  tearDown(() => AuthSession.instance.token = null);

  test('accommodation repository uses booking API and optimistic version',
      () async {
    final requests = <http.Request>[];
    await http.runWithClient(() async {
      await StudentRepository.instance.createAccommodationBooking(
          listingId: 'listing-1',
          moveInDate: DateTime.utc(2027, 1, 5),
          notes: 'قرب الجامعة');
      await StudentRepository.instance
          .cancelAccommodationBooking('booking-1', 3);
    },
        () => MockClient((request) async {
              requests.add(request);
              return reply({});
            }));
    expect(requests[0].url.path, '/api/accommodation/bookings');
    expect(jsonDecode(requests[0].body)['listingId'], 'listing-1');
    expect(
        requests[1].url.path, '/api/accommodation/bookings/booking-1/cancel');
    expect(jsonDecode(requests[1].body)['version'], 3);
    expect(
        requests
            .every((r) => r.headers['authorization'] == 'Bearer student-token'),
        isTrue);
  });

  testWidgets('visa center renders the actual server case', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: VisaCenterScreen()));
      await tester.pumpAndSettle();
      expect(find.text('قيد المراجعة'), findsOneWidget);
      expect(find.text('جواز السفر'), findsOneWidget);
      expect(find.text('القنصلية التركية'), findsOneWidget);
      expect(find.text('شركة الاختبار'), findsOneWidget);
    },
        () => MockClient((request) async {
              if (request.url.path == '/api/students/applications') {
                return reply([
                  {
                    '_id': 'app-1',
                    'program': {'title': 'الطب'}
                  }
                ]);
              }
              expect(request.url.path, '/api/applications/app-1/visa-case');
              return reply({
                'eligible': true,
                'status': 'under-review',
                'requirements': [
                  {'label': 'جواز السفر', 'done': true}
                ],
                'appointment': {
                  'date': '2027-01-10T10:00:00.000Z',
                  'location': 'القنصلية التركية'
                },
                'insurance': {
                  'provider': 'شركة الاختبار',
                  'policyNumber': 'P-1'
                },
                'notes': 'احتفظ بالأصل',
              });
            }));
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrival services show the real pickup assignment',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ArrivalServicesScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('قيد التنسيق'), findsOneWidget);
      expect(find.text('تم تعيين السائق'), findsOneWidget);
      expect(find.text('السائق: أحمد'), findsOneWidget);
      expect(find.text('الهاتف: +905550001122'), findsOneWidget);
      expect(find.text('تأكد من بوابة الوصول'), findsOneWidget);
    },
        () => MockClient((request) async => reply({
              'status': 'in-progress',
              'travelAlert': 'تأكد من بوابة الوصول',
              'services': {'airportPickup': true},
              'pickup': {
                'status': 'assigned',
                'driverName': 'أحمد',
                'driverPhone': '+905550001122'
              }
            })));
    expect(tester.takeException(), isNull);
  });

  testWidgets('university registration uses the post-admission stage',
      (tester) async {
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: UniversityRegistrationScreen()));
      await tester.pumpAndSettle();
      expect(find.text('بانتظار الجامعة'), findsOneWidget);
      expect(find.text('أحضر جواز السفر الأصلي'), findsOneWidget);
      expect(find.text('مرجع المتابعة: REG-42'), findsOneWidget);
    },
        () => MockClient((request) async {
              if (request.url.path == '/api/students/applications') {
                return reply([
                  {'_id': 'app-1'}
                ]);
              }
              expect(
                  request.url.path, '/api/applications/app-1/post-admission');
              return reply({
                'stages': [
                  {
                    'key': 'registration',
                    'status': 'waiting-university',
                    'descriptionAr': 'أحضر جواز السفر الأصلي',
                    'reference': 'REG-42',
                    'dueAt': '2027-01-15T00:00:00.000Z'
                  }
                ]
              });
            }));
    expect(tester.takeException(), isNull);
  });
}
