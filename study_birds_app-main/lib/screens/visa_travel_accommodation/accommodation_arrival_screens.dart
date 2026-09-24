import '../services_support/support_team_ai_screens.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/api_client.dart';
import '../../core/student_repository.dart';

// ---- Accommodation (fully wired to /api/accommodation) -------------------

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});
  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen> {
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _listings = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        StudentRepository.instance.getMyAccommodationBookings(),
        StudentRepository.instance.getAccommodationListings(),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = List<Map<String, dynamic>>.from(results[0]);
        _listings = List<Map<String, dynamic>>.from(results[1]);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'تعذر تحميل بيانات السكن';
        _loading = false;
      });
    }
  }

  Future<void> _cancel(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الحجز'),
        content: const Text('هل تريد إلغاء هذا الحجز؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، إلغاء')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated =
          await StudentRepository.instance.cancelAccommodationBooking(
        id: booking['_id'] as String,
        version: booking['__v'] as int,
      );
      if (!mounted) return;
      setState(() {
        final idx = _bookings.indexWhere((b) => b['_id'] == booking['_id']);
        if (idx >= 0) _bookings[idx] = Map<String, dynamic>.from(updated);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e is ApiException ? e.message : 'تعذر إلغاء الحجز')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _book(Map<String, dynamic> listing) async {
    final notesCtrl = TextEditingController();
    DateTime? moveIn;
    // StatefulBuilder so date selection refreshes inside the dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('حجز: ${listing['title']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '${listing['price']} ${listing['currency']} / شهر',
              style: AppTextStyles.cardTitle,
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 18, color: AppColors.navy),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate:
                        DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setS(() => moveIn = date);
                },
                child: Text(moveIn != null
                    ? '${moveIn!.day}/${moveIn!.month}/${moveIn!.year}'
                    : 'تاريخ الانتقال (اختياري)'),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد الحجز')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    String? moveInStr;
    if (moveIn != null) {
      moveInStr =
          '${moveIn!.year}-${moveIn!.month.toString().padLeft(2, '0')}-${moveIn!.day.toString().padLeft(2, '0')}';
    }
    setState(() => _busy = true);
    try {
      await StudentRepository.instance.bookAccommodation(
        listingId: listing['_id'] as String,
        moveInDate: moveInStr,
        notes: notesCtrl.text.trim(),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الحجز')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e is ApiException ? e.message : 'تعذر إرسال الحجز')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _statusBadge(String status) {
    const colors = <String, Color>{
      'pending': AppColors.warning,
      'confirmed': AppColors.success,
      'rejected': AppColors.danger,
      'cancelled': AppColors.textSecondary,
    };
    const labels = <String, String>{
      'pending': 'بانتظار التأكيد',
      'confirmed': 'مؤكد',
      'rejected': 'مرفوض',
      'cancelled': 'ملغي',
    };
    return StatusBadge(
        label: labels[status] ?? status,
        color: colors[status] ?? AppColors.textSecondary);
  }

  String _typeLabel(String type) {
    const m = {
      'single': 'غرفة مفردة',
      'shared': 'غرفة مشتركة',
      'apartment': 'شقة'
    };
    return m[type] ?? type;
  }

  @override
  Widget build(BuildContext context) {
    final activeBooking = _bookings
        .where((b) =>
            b['status'] == 'pending' || b['status'] == 'confirmed')
        .firstOrNull;

    return AppScaffold(
      title: 'السكن',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (activeBooking != null) ...[
                        const Text('حجزي الحالي',
                            style: AppTextStyles.sectionLabel),
                        const SizedBox(height: 10),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      activeBooking['listing']
                                              ?['title'] as String? ??
                                          '—',
                                      style: AppTextStyles.cardTitle,
                                    ),
                                  ),
                                  _statusBadge(
                                      activeBooking['status'] as String? ??
                                          ''),
                                ],
                              ),
                              if (activeBooking['listing']?['university']
                                      ?['name'] !=
                                  null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    activeBooking['listing']['university']
                                        ['name'] as String,
                                    style: AppTextStyles.caption,
                                  ),
                                ),
                              if (activeBooking['moveInDate'] != null) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  const Icon(Icons.calendar_today_rounded,
                                      size: 16, color: AppColors.navy),
                                  const SizedBox(width: 6),
                                  Text(
                                    (activeBooking['moveInDate'] as String)
                                        .substring(0, 10),
                                    style: AppTextStyles.caption,
                                  ),
                                ]),
                              ],
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed:
                                    _busy ? null : () => _cancel(activeBooking),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.danger),
                                child: const Text('إلغاء الحجز'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                        activeBooking != null
                            ? 'خيارات أخرى متاحة'
                            : 'خيارات السكن المتاحة',
                        style: AppTextStyles.sectionLabel,
                      ),
                      const SizedBox(height: 10),
                      if (_listings.isEmpty)
                        const AppCard(
                          child: Text('لا توجد خيارات متاحة حالياً',
                              style: AppTextStyles.caption),
                        )
                      else
                        for (final listing in _listings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          listing['title'] as String? ??
                                              '',
                                          style: AppTextStyles.cardTitle,
                                        ),
                                      ),
                                      Text(
                                        '${listing['price']} ${listing['currency']}',
                                        style: AppTextStyles.cardTitle
                                            .copyWith(
                                                color: AppColors.navy),
                                      ),
                                    ],
                                  ),
                                  if (listing['university']?['name'] !=
                                      null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Text(
                                        listing['university']['name']
                                            as String,
                                        style: AppTextStyles.caption,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.bed_rounded,
                                        size: 14,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                        _typeLabel(listing['type']
                                                as String? ??
                                            ''),
                                        style: AppTextStyles.caption),
                                    if ((listing['distanceFromCampusKm']
                                            as num?) !=
                                        null) ...[
                                      const SizedBox(width: 12),
                                      const Icon(Icons.place_rounded,
                                          size: 14,
                                          color: AppColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                          '${listing['distanceFromCampusKm']} كم',
                                          style: AppTextStyles.caption),
                                    ],
                                  ]),
                                  if ((listing['amenities'] as List?)
                                          ?.isNotEmpty ==
                                      true)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 6),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: (listing['amenities']
                                                as List)
                                            .take(4)
                                            .map((a) => Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.border
                                                        .withAlpha(80),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(20),
                                                  ),
                                                  child: Text(a as String,
                                                      style: AppTextStyles
                                                          .caption
                                                          .copyWith(
                                                              fontSize:
                                                                  11)),
                                                ))
                                            .toList(),
                                      ),
                                    ),
                                  if (activeBooking == null) ...[
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed:
                                          _busy ? null : () => _book(listing),
                                      child: const Text('احجز الآن'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      // Past bookings
                      if (_bookings.any((b) =>
                          b['status'] == 'cancelled' ||
                          b['status'] == 'rejected')) ...[
                        const SizedBox(height: 20),
                        const Text('حجوزات سابقة',
                            style: AppTextStyles.sectionLabel),
                        const SizedBox(height: 10),
                        for (final b in _bookings.where((b) =>
                            b['status'] == 'cancelled' ||
                            b['status'] == 'rejected'))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      b['listing']?['title'] as String? ??
                                          '—',
                                      style: AppTextStyles.body,
                                    ),
                                  ),
                                  _statusBadge(
                                      b['status'] as String? ?? ''),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ---- University Registration (static — no dedicated server endpoint) -----

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
            const Text('المستندات المطلوبة',
                style: AppTextStyles.sectionLabel),
            const SizedBox(height: 10),
            const AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
            const AppCard(
              child: Row(
                children: [
                  Icon(Icons.school_rounded, color: AppColors.navy),
                  SizedBox(width: 10),
                  Text('يُحدَّد بالتنسيق مع الجامعة',
                      style: AppTextStyles.cardTitle),
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
