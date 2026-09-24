import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_birds/core/api_client.dart';
import 'package:study_birds/core/auth_session.dart';
import 'package:study_birds/screens/profile_account/profile_account_screens.dart';
import 'package:study_birds/screens/profile_account/student_wallet_screen.dart';

http.Response reply(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> wallet(num balance) => {
      'referralCode': 'SB-AB12CD',
      'balance': balance,
      'referrals': [
        {'_id': 'r1', 'name': 'Lina', 'status': 'qualified'},
        {'_id': 'r2', 'name': 'Omar', 'status': 'pending'},
      ],
      'transactions': [
        {
          '_id': 't1',
          'direction': 'credit',
          'kind': 'referral-reward',
          'amount': 50,
          'createdAt': '2026-09-01T10:00:00Z',
        },
      ],
    };

const financials = {
  'summary': {},
  'invoices': [
    {
      '_id': 'inv1',
      'invoiceNumber': 'INV-1',
      'description': 'رسوم الخدمة',
      'amount': 200,
      'walletCreditApplied': 20,
      'status': 'unpaid',
    },
    {
      '_id': 'inv2',
      'invoiceNumber': 'INV-2',
      'description': 'فاتورة مدفوعة',
      'amount': 100,
      'status': 'paid',
    },
  ],
  'paymentProofs': [],
};

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    AuthSession.instance.token = 'test-session';
    AuthSession.instance.currentUser = const AuthUser(
        id: 'me', name: 'Me', email: 'me@example.test', role: UserRole.student);
  });
  tearDown(() {
    AuthSession.instance.token = null;
    AuthSession.instance.currentUser = null;
  });

  testWidgets(
      'shows balance, referrals and ledger; pays an unpaid invoice after confirmation',
      (tester) async {
    phone(tester);
    num balance = 50;
    final redeemBodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: MyWalletScreen()));
      await tester.pumpAndSettle();

      expect(find.text('50'), findsOneWidget);
      expect(find.text('SB-AB12CD'), findsOneWidget);
      expect(find.text('مكتملة'), findsOneWidget);
      expect(find.text('بانتظار أول طلب'), findsOneWidget);
      // Only the unpaid invoice is payable, with what is still owed.
      expect(find.text('رسوم الخدمة'), findsOneWidget);
      expect(find.text('المتبقي: 180'), findsOneWidget);
      expect(find.text('فاتورة مدفوعة'), findsNothing);
      final list = find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('+50'), 200, scrollable: list);
      expect(find.text('مكافأة إحالة'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('ادفع من الرصيد'), -200,
          scrollable: list);

      await tester.tap(find.text('ادفع من الرصيد'));
      await tester.pumpAndSettle();
      expect(find.text('سيُخصم المبلغ من رصيدك فورًا ولا يمكن التراجع عنه.'),
          findsOneWidget);
      // Defaults to the smaller of balance and remaining.
      expect(find.widgetWithText(TextField, '50'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();
      expect(find.text('أدخل مبلغًا بين 0 و50'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '30');
      await tester.pump();
      await tester.tap(find.text('تأكيد الدفع'));
      await tester.pumpAndSettle();

      expect(redeemBodies, [
        {'invoiceId': 'inv1', 'amount': 30}
      ]);
      expect(find.text('تم خصم 30 من رصيدك على الفاتورة.'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              expect(request.headers['authorization'], 'Bearer test-session');
              switch (request.url.path) {
                case '/api/students/wallet':
                  return reply(wallet(balance));
                case '/api/students/financials':
                  return reply(financials);
                case '/api/students/wallet/redeem':
                  final body = jsonDecode(request.body) as Map<String, dynamic>;
                  redeemBodies.add(body);
                  balance -= body['amount'] as num;
                  return reply({
                    'balance': balance,
                    'invoice': {'_id': 'inv1', 'status': 'unpaid'}
                  });
              }
              return reply({'message': 'unexpected ${request.url.path}'}, 404);
            }));
  });

  testWidgets('a stale invoice conflict shows an Arabic message and reloads',
      (tester) async {
    phone(tester);
    var walletReads = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StudentWalletScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ادفع من الرصيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد الدفع'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'تغيّرت الفاتورة أو الرصيد للتو. حدّثنا البيانات، راجعها وحاول مجددًا.'),
          findsOneWidget);
      expect(walletReads, 2);
    },
        () => MockClient((request) async {
              switch (request.url.path) {
                case '/api/students/wallet':
                  walletReads++;
                  return reply(wallet(50));
                case '/api/students/financials':
                  return reply(financials);
                case '/api/students/wallet/redeem':
                  return reply(
                      {'message': 'Invoice changed. Refresh and retry.'}, 409);
              }
              return reply({'message': 'unexpected'}, 404);
            }));
  });

  test('redeem errors map to Arabic', () {
    expect(
        walletRedeemError(
            const ApiException(409, 'Insufficient wallet balance')),
        'رصيدك لا يكفي لهذا المبلغ.');
    expect(
        walletRedeemError(
            const ApiException(400, 'Amount exceeds what is still owed')),
        'المبلغ أكبر من المتبقي على الفاتورة.');
    expect(
        walletRedeemError(const ApiException(
            409, 'This invoice can no longer accept credit')),
        'هذه الفاتورة لم تعد تقبل الدفع من الرصيد.');
    expect(
        walletRedeemError(const ApiException(503, 'Transactions unavailable')),
        contains('غير متاح مؤقتًا'));
  });

  testWidgets('no balance disables paying from credit', (tester) async {
    phone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StudentWalletScreen()));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ادفع من الرصيد'));
      expect(button.onPressed, isNull);
    },
        () => MockClient((request) async {
              if (request.url.path == '/api/students/wallet') {
                return reply(wallet(0));
              }
              return reply(financials);
            }));
  });

  testWidgets('student referral screen shows the account code from the wallet',
      (tester) async {
    phone(tester);
    final paths = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ReferralProgramScreen()));
      await tester.pumpAndSettle();
      expect(find.text('SB-AB12CD'), findsOneWidget);
      expect(paths, ['/api/students/wallet']);
    },
        () => MockClient((request) async {
              paths.add(request.url.path);
              return reply(wallet(0));
            }));
  });
}
