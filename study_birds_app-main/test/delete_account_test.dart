import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_birds/screens/profile_account/delete_account_screen.dart';

void main() {
  testWidgets('account deletion requires the explicit DELETE phrase',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeleteAccountScreen()));

    expect(find.text('هذا الإجراء نهائي'), findsOneWidget);
    expect(find.text('حذف حسابي نهائيًا'), findsOneWidget);
    await tester.tap(find.text('حذف حسابي نهائيًا'));
    await tester.pump();

    expect(find.text('اكتب DELETE في حقل التأكيد.'), findsOneWidget);
  });
}
