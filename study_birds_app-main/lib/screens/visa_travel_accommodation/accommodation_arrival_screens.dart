import '../services_support/support_team_ai_screens.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/api_client.dart';
import '../../core/student_repository.dart';

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});
  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen> {
  bool loading = true, saving = false;
  String? error;
  List<Map<String, dynamic>> listings = [], bookings = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        StudentRepository.instance.getAccommodationListings(),
        StudentRepository.instance.getAccommodationBookings()
      ]);
      listings = values[0]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      bookings = values[1]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      error = e is ApiException ? e.message : 'تعذر تحميل بيانات السكن.';
    }
    if (mounted) setState(() => loading = false);
  }

  bool get hasActive => bookings
      .any((b) => b['status'] == 'pending' || b['status'] == 'confirmed');
  String status(String s) =>
      {
        'pending': 'قيد المراجعة',
        'confirmed': 'مؤكد',
        'rejected': 'مرفوض',
        'cancelled': 'ملغي'
      }[s] ??
      s;
  Color statusColor(String s) => s == 'confirmed'
      ? AppColors.success
      : s == 'rejected'
          ? AppColors.danger
          : s == 'cancelled'
              ? AppColors.neutral
              : AppColors.warning;
  String type(String s) =>
      {
        'single': 'غرفة فردية',
        'shared': 'غرفة مشتركة',
        'apartment': 'شقة'
      }[s] ??
      s;

  Future<void> book(Map<String, dynamic> listing) async {
    DateTime? moveIn;
    final notes = TextEditingController();
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: Text('طلب ${listing['title']}'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_month),
                          title: Text(moveIn == null
                              ? 'اختيار تاريخ السكن'
                              : '${moveIn!.day}/${moveIn!.month}/${moveIn!.year}'),
                          onTap: () async {
                            final d = await showDatePicker(
                                context: ctx,
                                initialDate: DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 730)));
                            if (d != null) setLocal(() => moveIn = d);
                          }),
                      TextField(
                          controller: notes,
                          maxLength: 500,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'ملاحظات اختيارية')),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('رجوع')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('تأكيد الطلب'))
                    ])));
    if (yes != true) {
      notes.dispose();
      return;
    }
    setState(() => saving = true);
    try {
      await StudentRepository.instance.createAccommodationBooking(
          listingId: '${listing['_id']}',
          moveInDate: moveIn,
          notes: notes.text);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم إرسال طلب السكن')));
      await load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.message : 'تعذر إرسال الطلب')));
    }
    notes.dispose();
    if (mounted) setState(() => saving = false);
  }

  Future<void> cancel(Map<String, dynamic> booking) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('إلغاء طلب السكن؟'),
                content:
                    const Text('سيتم تحرير هذا الطلب ويمكنك اختيار سكن آخر.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('رجوع')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('إلغاء الطلب'))
                ]));
    if (yes != true) return;
    setState(() => saving = true);
    try {
      await StudentRepository.instance.cancelAccommodationBooking(
          '${booking['_id']}', booking['__v'] as int? ?? 0);
      await load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.message : 'تعذر إلغاء الطلب')));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
      title: 'السكن الطلابي',
      actions: [
        IconButton(
            onPressed: loading ? null : load, icon: const Icon(Icons.refresh))
      ],
      body: loading
          ? const LoadingState(message: 'جارٍ تحميل خيارات السكن...')
          : error != null
              ? ErrorState(message: error!, onRetry: load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (bookings.isNotEmpty) ...[
                    const Text('طلباتي', style: AppTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    ...bookings.map((b) {
                      final l =
                          b['listing'] is Map ? b['listing'] as Map : const {};
                      final active = b['status'] == 'pending' ||
                          b['status'] == 'confirmed';
                      return AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${l['title'] ?? 'سكن'}',
                                      style: AppTextStyles.cardTitle)),
                              StatusBadge(
                                  label: status('${b['status']}'),
                                  color: statusColor('${b['status']}'))
                            ]),
                            if (b['moveInDate'] != null)
                              Text(
                                  'تاريخ البدء: ${DateTime.tryParse('${b['moveInDate']}')?.toLocal().toString().split(' ').first ?? ''}',
                                  style: AppTextStyles.caption),
                            if (active)
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                      onPressed:
                                          saving ? null : () => cancel(b),
                                      child: const Text('إلغاء الطلب')))
                          ]));
                    }),
                    const SizedBox(height: 8)
                  ],
                  const Text('خيارات السكن المتاحة',
                      style: AppTextStyles.sectionLabel),
                  const SizedBox(height: 8),
                  if (listings.isEmpty)
                    const EmptyState(
                        icon: Icons.home_work_outlined,
                        title: 'لا توجد خيارات متاحة',
                        message: 'ستظهر الوحدات التي يضيفها فريق السكن هنا.')
                  else
                    ...listings.map((l) {
                      final u = l['university'] is Map
                          ? l['university'] as Map
                          : const {};
                      return AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${l['title']}',
                                      style: AppTextStyles.cardTitle)),
                              Text('${l['price']} ${l['currency']}',
                                  style: AppTextStyles.sectionLabel)
                            ]),
                            const SizedBox(height: 6),
                            Text('${type('${l['type']}')} • ${u['name'] ?? ''}',
                                style: AppTextStyles.body),
                            if (l['distanceFromCampusKm'] != null)
                              Text('${l['distanceFromCampusKm']} كم عن الحرم',
                                  style: AppTextStyles.caption),
                            if ((l['amenities'] as List? ?? []).isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: (l['amenities'] as List)
                                          .map((a) => Chip(label: Text('$a')))
                                          .toList())),
                            if ('${l['rules'] ?? ''}'.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('الشروط: ${l['rules']}',
                                      style: AppTextStyles.caption)),
                            const SizedBox(height: 8),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                    onPressed: hasActive ||
                                            saving ||
                                            l['capacity'] == 0
                                        ? null
                                        : () => book(l),
                                    child: Text(l['capacity'] == 0
                                        ? 'مكتمل'
                                        : hasActive
                                            ? 'لديك طلب نشط'
                                            : 'طلب الحجز')))
                          ]));
                    })
                ]));
}

class UniversityRegistrationScreen extends StatelessWidget {
  const UniversityRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تسجيل الجامعة',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
                alignment: Alignment.centerRight,
                child: StatusBadge(
                    label: 'بانتظار الموعد', color: AppColors.warning)),
            const SizedBox(height: 16),
            const Text('المستندات المطلوبة', style: AppTextStyles.sectionLabel),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('• جواز السفر الأصلي', style: AppTextStyles.body),
                  SizedBox(height: 6),
                  Text('• خطاب القبول النهائي', style: AppTextStyles.body),
                  SizedBox(height: 6),
                  Text('• إيصال دفع الرسوم', style: AppTextStyles.body),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('الموعد', style: AppTextStyles.sectionLabel),
            const SizedBox(height: 10),
            AppCard(
              child: Row(
                children: const [
                  Icon(Icons.school_rounded, color: AppColors.navy),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('13 أكتوبر 2026', style: AppTextStyles.cardTitle),
                      Text('الحرم الجامعي الرئيسي',
                          style: AppTextStyles.caption),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InsuranceScreen extends StatelessWidget {
  const InsuranceScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const NewSupportTicketScreen(initialSubject: 'طلب تأمين');
}

class EquivalencyScreen extends StatelessWidget {
  const EquivalencyScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const NewSupportTicketScreen(initialSubject: 'طلب معادلة');
}
