import 'arrival_services_screen.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/api_client.dart';
import '../../core/student_repository.dart';

// ---- Document status helpers ---------------------------------------------

const _docStatusLabels = <String, String>{
  'missing': 'مطلوب',
  'uploaded': 'تم الرفع',
  'under-review': 'قيد المراجعة',
  'approved': 'معتمد',
  'rejected': 'مرفوض',
  'needs-revision': 'يحتاج تعديل',
  'needs-translation': 'يحتاج ترجمة',
  'expired': 'منتهي الصلاحية',
};

const _docStatusColors = <String, Color>{
  'missing': AppColors.danger,
  'uploaded': AppColors.warning,
  'under-review': AppColors.warning,
  'approved': AppColors.success,
  'rejected': AppColors.danger,
  'needs-revision': AppColors.orange,
  'needs-translation': AppColors.orange,
  'expired': AppColors.danger,
};

// ---- Visa Center ---------------------------------------------------------

class VisaCenterScreen extends StatefulWidget {
  const VisaCenterScreen({super.key});
  @override
  State<VisaCenterScreen> createState() => _VisaCenterScreenState();
}

class _VisaCenterScreenState extends State<VisaCenterScreen> {
  List<Map<String, dynamic>> _docs = [];
  Map<String, dynamic>? _application;
  bool _loading = true;
  String? _error;

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
        StudentRepository.instance.getDocuments(),
        StudentRepository.instance.getApplications(),
      ]);
      if (!mounted) return;
      final docs = List<Map<String, dynamic>>.from(results[0]);
      final apps = List<Map<String, dynamic>>.from(results[1]);
      // Latest application by createdAt (list is sorted newest-first by server).
      final app = apps.isNotEmpty ? apps.first : null;
      setState(() {
        // Show only latest version of each document type.
        _docs = docs.where((d) => d['isLatest'] == true).toList();
        _application = app;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            e is ApiException ? e.message : 'تعذر تحميل بيانات التأشيرة';
        _loading = false;
      });
    }
  }

  Widget _docRow(Map<String, dynamic> doc) {
    final statusInfo =
        doc['statusInfo'] as Map<String, dynamic>? ?? {};
    final status =
        statusInfo['status'] as String? ?? doc['detailedStatus'] as String? ?? '';
    final arLabel =
        (statusInfo['ar'] as Map<String, dynamic>?)?['label'] as String? ??
            _docStatusLabels[status] ??
            status;
    final color = _docStatusColors[status] ?? AppColors.textSecondary;
    final icon = status == 'approved'
        ? Icons.check_circle_rounded
        : status == 'missing'
            ? Icons.radio_button_unchecked_rounded
            : Icons.circle_outlined;
    final type = doc['type'] as String? ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(type, style: AppTextStyles.body)),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(20)),
          child: Text(arLabel,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailedStatus = _application?['detailedStatus'] as String?;
    final appCard =
        _application?['card'] as Map<String, dynamic>?;
    final stageName = appCard?['stage'] as String? ?? detailedStatus ?? '';

    return AppScaffold(
      title: 'مركز التأشيرة',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _load,
                        child: const Text('إعادة المحاولة')),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_application != null && stageName.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: StatusBadge(
                            label: stageName,
                            color: detailedStatus == 'visa-preparation'
                                ? AppColors.orange
                                : detailedStatus == 'final-admission' ||
                                        detailedStatus == 'completed'
                                    ? AppColors.success
                                    : AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const Text('حالة المستندات',
                          style: AppTextStyles.sectionLabel),
                      const SizedBox(height: 10),
                      if (_docs.isEmpty)
                        const AppCard(
                          child: Text(
                              'لا توجد مستندات مرفوعة بعد',
                              style: AppTextStyles.caption),
                        )
                      else
                        AppCard(
                          child: Column(
                            children: _docs
                                .map((d) => _docRow(d))
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 20),
                      const Text('هل تحتاج دعماً في التأشيرة؟',
                          style: AppTextStyles.sectionLabel),
                      const SizedBox(height: 10),
                      PrimaryButton(
                        label: 'طلب دعم تأشيرة',
                        icon: Icons.support_agent_outlined,
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const ArrivalServicesScreen())),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ---- Visa Steps (connected to application detailedStatus) ----------------

class VisaStepsScreen extends StatefulWidget {
  const VisaStepsScreen({super.key});
  @override
  State<VisaStepsScreen> createState() => _VisaStepsScreenState();
}

class _VisaStepsScreenState extends State<VisaStepsScreen> {
  static const _stages = [
    {'key': 'final-admission', 'label': 'القبول النهائي'},
    {'key': 'visa-preparation', 'label': 'تجهيز التأشيرة'},
    {'key': 'travel-and-settlement', 'label': 'السفر والاستقرار'},
    {'key': 'completed', 'label': 'مكتمل'},
  ];

  String? _currentKey;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await StudentRepository.instance.getApplications();
      if (!mounted) return;
      final status = apps.isNotEmpty
          ? apps.first['detailedStatus'] as String? ?? ''
          : '';
      setState(() {
        _currentKey = status;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = _stages.indexWhere((s) => s['key'] == _currentKey);
    return AppScaffold(
      title: 'مراحل التأشيرة',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _stages.length,
              itemBuilder: (_, i) {
                final done = currentIdx >= 0 && i < currentIdx;
                final active = i == currentIdx;
                final isLast = i == _stages.length - 1;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: done
                                ? AppColors.success
                                : (active
                                    ? AppColors.orange
                                    : Colors.white),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: done
                                  ? AppColors.success
                                  : (active
                                      ? AppColors.orange
                                      : AppColors.border),
                              width: 2,
                            ),
                          ),
                          child: done
                              ? const Icon(Icons.check_rounded,
                                  size: 15, color: Colors.white)
                              : active
                                  ? const Icon(Icons.circle,
                                      size: 8, color: Colors.white)
                                  : null,
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                                width: 2,
                                color: done
                                    ? AppColors.success
                                    : AppColors.border),
                          ),
                      ]),
                      const SizedBox(width: 14),
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: 28, top: 4),
                        child: Text(
                          _stages[i]['label']!,
                          style: active
                              ? AppTextStyles.cardTitle
                                  .copyWith(color: AppColors.orange)
                              : AppTextStyles.body,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ---- Travel Center (wired to arrival-services) ---------------------------

class TravelCenterScreen extends StatefulWidget {
  const TravelCenterScreen({super.key});
  @override
  State<TravelCenterScreen> createState() => _TravelCenterScreenState();
}

class _TravelCenterScreenState extends State<TravelCenterScreen> {
  Map<String, dynamic>? _arrival;
  bool _loading = true;
  String? _error;

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
      final data = await StudentRepository.instance.getArrivalServices();
      if (!mounted) return;
      setState(() {
        _arrival = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'تعذر تحميل بيانات السفر';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final flight = _arrival?['flightNumber'] as String? ?? '';
    final airport = _arrival?['airport'] as String? ?? '';
    final arrivalDate = _arrival?['arrivalDate'] as String?;
    final arrivalTime = _arrival?['arrivalTime'] as String? ?? '';
    final hasData = flight.isNotEmpty || airport.isNotEmpty;

    return AppScaffold(
      title: 'مركز السفر',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _load,
                        child: const Text('إعادة المحاولة')),
                  ]))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (hasData) ...[
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('معلومات الرحلة',
                                style: AppTextStyles.sectionLabel),
                            const SizedBox(height: 10),
                            if (flight.isNotEmpty)
                              _KV(label: 'رقم الرحلة', value: flight),
                            if (airport.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _KV(label: 'مطار الوصول', value: airport),
                            ],
                            if (arrivalDate != null) ...[
                              const SizedBox(height: 6),
                              _KV(
                                label: 'تاريخ الوصول',
                                value:
                                    '${arrivalDate.substring(0, 10)}${arrivalTime.isNotEmpty ? '  $arrivalTime' : ''}',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('لم تُدخل تفاصيل رحلتك بعد.',
                                style: AppTextStyles.body),
                            const SizedBox(height: 4),
                            Text(
                              'أدخل رقم الرحلة والمطار ليتمكن الفريق من تنسيق استقبالك.',
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      label: hasData
                          ? 'تعديل تفاصيل الوصول'
                          : 'أدخل تفاصيل وصولك',
                      icon: Icons.flight_land_rounded,
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => const ArrivalServicesScreen()))
                          .then((_) => _load()),
                    ),
                  ],
                ),
    );
  }
}

class _KV extends StatelessWidget {
  final String label;
  final String value;
  const _KV({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.caption),
      Text(value,
          style:
              AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

// ---- Airport Pickup (wired to arrival-services) --------------------------

class AirportPickupScreen extends StatefulWidget {
  const AirportPickupScreen({super.key});
  @override
  State<AirportPickupScreen> createState() => _AirportPickupScreenState();
}

class _AirportPickupScreenState extends State<AirportPickupScreen> {
  Map<String, dynamic>? _arrival;
  bool _loading = true;
  String? _error;

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
      final data = await StudentRepository.instance.getArrivalServices();
      if (!mounted) return;
      setState(() {
        _arrival = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            e is ApiException ? e.message : 'تعذر تحميل بيانات الاستقبال';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services =
        _arrival?['services'] as Map<String, dynamic>? ?? {};
    final requested = services['airportPickup'] == true;
    final flight = _arrival?['flightNumber'] as String? ?? '—';
    final arrivalDate = (_arrival?['arrivalDate'] as String?)
        ?.substring(0, 10) ??
        '—';
    final arrivalTime = _arrival?['arrivalTime'] as String? ?? '';
    final status = _arrival?['status'] as String? ?? '';

    return AppScaffold(
      title: 'استقبال المطار',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!,
                      style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة')),
                ]))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppCard(
                      child: Column(children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('الحالة',
                                style: AppTextStyles.caption),
                            StatusBadge(
                              label: !requested
                                  ? 'غير مطلوب'
                                  : status == 'completed'
                                      ? 'تم الاستقبال'
                                      : status == 'in-progress'
                                          ? 'جارٍ التنسيق'
                                          : 'مطلوب — قيد التنسيق',
                              color: !requested
                                  ? AppColors.textSecondary
                                  : status == 'completed'
                                      ? AppColors.success
                                      : AppColors.warning,
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        _KV(label: 'رقم الرحلة', value: flight),
                        const SizedBox(height: 6),
                        _KV(
                          label: 'تاريخ الوصول',
                          value:
                              '$arrivalDate${arrivalTime.isNotEmpty ? '  $arrivalTime' : ''}',
                        ),
                      ]),
                    ),
                    if (!requested) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('لم تطلب خدمة الاستقبال بعد.',
                                style: AppTextStyles.body),
                            const SizedBox(height: 4),
                            Text(
                              'يمكنك طلبها من نموذج خدمات الوصول.',
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'تعديل خدمات الوصول',
                        icon: Icons.edit_rounded,
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(
                                builder: (_) =>
                                    const ArrivalServicesScreen()))
                            .then((_) => _load()),
                      ),
                    ],
                  ],
                ),
    );
  }
}
