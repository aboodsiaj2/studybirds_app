import 'package:flutter_test/flutter_test.dart';
import 'package:study_birds/screens/applications_documents_payments/applications_screens.dart';
import 'package:study_birds/screens/applications_documents_payments/documents_screens.dart';
import 'package:study_birds/screens/applications_documents_payments/payments_screens.dart';
import 'package:study_birds/screens/home_journey/notifications_screen.dart';
import 'package:study_birds/screens/profile_account/student_wallet_screen.dart';
import 'package:study_birds/screens/services_support/community_screen.dart';
import 'package:study_birds/screens/services_support/services_consultation_screens.dart';
import 'package:study_birds/screens/visa_travel_accommodation/accommodation_arrival_screens.dart';
import 'package:study_birds/screens/visa_travel_accommodation/arrival_services_screen.dart';
import 'package:study_birds/screens/visa_travel_accommodation/visa_travel_screens.dart';

void main() {
  test('notification links resolve to their student destination', () {
    expect(notificationDestination('/student/applications'),
        isA<ApplicationsListScreen>());
    expect(notificationDestination('/applications/application-id'),
        isA<ApplicationsListScreen>());
    expect(notificationDestination('/student/documents'),
        isA<MyDocumentsScreen>());
    expect(notificationDestination('/student/payments'),
        isA<PaymentsSummaryScreen>());
    expect(
        notificationDestination('/student/wallet'), isA<StudentWalletScreen>());
    expect(notificationDestination('/student/consultations'),
        isA<ConsultationBookingScreen>());
    expect(notificationDestination('/student/community'),
        isA<StudentCommunityScreen>());
    expect(notificationDestination('/student/service-orders'),
        isA<ServiceOrdersScreen>());
    expect(notificationDestination('/student/arrival-services'),
        isA<ArrivalServicesScreen>());
    expect(notificationDestination('/student/accommodation'),
        isA<AccommodationScreen>());
    expect(notificationDestination('/student/visa'), isA<VisaCenterScreen>());
  });

  test('notification links support app scheme and safely ignore unknown links',
      () {
    expect(notificationDestination('studybirds://student/payments'),
        isA<PaymentsSummaryScreen>());
    expect(notificationDestination('/student/payments/'),
        isA<PaymentsSummaryScreen>());
    expect(notificationDestination(null), isNull);
    expect(notificationDestination(''), isNull);
    expect(notificationDestination('https://example.com/elsewhere'), isNull);
  });
}
