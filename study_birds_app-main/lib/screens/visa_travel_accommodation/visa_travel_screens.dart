import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/student_repository.dart';
import 'arrival_services_screen.dart';

const visaLabels = <String, String>{
  'not-started': 'لم تبدأ',
  'preparing-documents': 'تحضير المستندات',
  'ready': 'جاهزة للتقديم',
  'submitted': 'تم التقديم',
  'under-review': 'قيد المراجعة',
  'approved': 'تمت الموافقة',
  'rejected': 'مرفوضة'
};

class VisaCenterScreen extends StatefulWidget {
  const VisaCenterScreen({super.key});
  @override
  State<VisaCenterScreen> createState() => _VisaCenterScreenState();
}

class _VisaCenterScreenState extends State<VisaCenterScreen> {
  bool loading = true;
  String? error, selectedId;
  List<Map<String, dynamic>> applications = [];
  Map<String, dynamic>? visa;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load([String? id]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (applications.isEmpty)
        applications = (await StudentRepository.instance.getApplications())
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      selectedId = id ??
          selectedId ??
          (applications.isEmpty ? null : '${applications.first['_id']}');
      visa = selectedId == null
          ? null
          : await StudentRepository.instance.getVisaCase(selectedId!);
    } catch (e) {
      error = e is ApiException ? e.message : 'تعذر تحميل ملف التأشيرة.';
    }
    if (mounted) setState(() => loading = false);
  }

  String appLabel(Map<String, dynamic> a) {
    String val(dynamic x) =>
        x is Map ? '${x['title'] ?? x['name'] ?? ''}' : '${x ?? ''}';
    final parts = [val(a['program']), val(a['university'])]
        .where((x) => x.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'طلب جامعي' : parts.join(' — ');
  }

  String date(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    return d == null
        ? ''
        : '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
      title: 'مركز التأشيرة',
      actions: [
        IconButton(
            onPressed: loading ? null : load, icon: const Icon(Icons.refresh))
      ],
      body: loading
          ? const LoadingState(message: 'جارٍ تحميل ملف التأشيرة...')
          : error != null
              ? ErrorState(message: error!, onRetry: load)
              : applications.isEmpty
                  ? const EmptyState(
                      icon: Icons.description_outlined,
                      title: 'لا توجد طلبات جامعية',
                      message: 'سيظهر ملف التأشيرة بعد إنشاء طلب جامعي.')
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      if (applications.length > 1) ...[
                        DropdownButtonFormField<String>(
                          initialValue: selectedId,
                          decoration:
                              const InputDecoration(labelText: 'الطلب الجامعي'),
                          items: applications
                              .map((a) => DropdownMenuItem(
                                  value: '${a['_id']}',
                                  child: Text(appLabel(a),
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) load(v);
                          },
                        ),
                        const SizedBox(height: 14)
                      ],
                      if (visa != null) content(visa!),
                    ]));

  Widget content(Map<String, dynamic> v) {
    if (v['eligible'] != true)
      return const EmptyState(
          icon: Icons.lock_clock_outlined,
          title: 'ملف التأشيرة غير متاح بعد',
          message: 'يصبح الملف متاحاً بعد تسجيل قبول نهائي نشط لهذا الطلب.');
    final status = '${v['status'] ?? 'not-started'}';
    final reqs = (v['requirements'] as List? ?? []).whereType<Map>().toList();
    final appointment =
        v['appointment'] is Map ? v['appointment'] as Map : const {};
    final insurance = v['insurance'] is Map ? v['insurance'] as Map : const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
          alignment: Alignment.centerRight,
          child: StatusBadge(
              label: visaLabels[status] ?? status,
              color: status == 'approved'
                  ? AppColors.success
                  : status == 'rejected'
                      ? AppColors.danger
                      : AppColors.warning)),
      const SizedBox(height: 16),
      const Text('المستندات المطلوبة', style: AppTextStyles.sectionLabel),
      const SizedBox(height: 8),
      reqs.isEmpty
          ? const AppCard(
              child: Text('لم يضف الفريق متطلبات بعد.',
                  style: AppTextStyles.caption))
          : AppCard(
              child: Column(
                  children: reqs
                      .map((r) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              r['done'] == true
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: r['done'] == true
                                  ? AppColors.success
                                  : AppColors.textSecondary),
                          title: Text('${r['label'] ?? ''}')))
                      .toList())),
      if (appointment['date'] != null ||
          '${appointment['location'] ?? ''}'.isNotEmpty) ...[
        const Text('الموعد', style: AppTextStyles.sectionLabel),
        const SizedBox(height: 8),
        AppCard(
            child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(date(appointment['date'])),
                subtitle: Text('${appointment['location'] ?? ''}')))
      ],
      if ('${insurance['provider'] ?? ''}'.isNotEmpty) ...[
        const Text('التأمين', style: AppTextStyles.sectionLabel),
        const SizedBox(height: 8),
        AppCard(
            child: Column(children: [
          row('شركة التأمين', '${insurance['provider']}'),
          if ('${insurance['policyNumber'] ?? ''}'.isNotEmpty)
            row('رقم الوثيقة', '${insurance['policyNumber']}'),
          if (insurance['expiresAt'] != null)
            row('تاريخ الانتهاء',
                date(insurance['expiresAt']).split('  ').first)
        ]))
      ],
      if ('${v['notes'] ?? ''}'.isNotEmpty)
        AppCard(child: Text('${v['notes']}')),
    ]);
  }

  Widget row(String a, String b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(a, style: AppTextStyles.caption)),
        Expanded(child: Text(b, style: AppTextStyles.body))
      ]));
}

class VisaStepsScreen extends StatelessWidget {
  const VisaStepsScreen({super.key});
  @override
  Widget build(BuildContext context) => const VisaCenterScreen();
}

class TravelCenterScreen extends StatelessWidget {
  const TravelCenterScreen({super.key});
  @override
  Widget build(BuildContext context) => const ArrivalServicesScreen();
}

class AirportPickupScreen extends StatelessWidget {
  final bool assigned;
  const AirportPickupScreen({super.key, this.assigned = true});
  @override
  Widget build(BuildContext context) => const ArrivalServicesScreen();
}
