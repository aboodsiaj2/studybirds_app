import 'live_consultation_screen.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/api_client.dart';
import '../../core/student_repository.dart';
import '../../core/catalog_repository.dart';

class ServicesCenterScreen extends StatefulWidget {
  const ServicesCenterScreen({super.key});
  @override
  State<ServicesCenterScreen> createState() => _ServicesCenterScreenState();
}

class _ServicesCenterScreenState extends State<ServicesCenterScreen> {
  late Future<List<dynamic>> future = CatalogRepository.instance.getServices();
  Future<void> refresh() async {
    final next = CatalogRepository.instance.getServices();
    setState(() => future = next);
    try {
      await next;
    } catch (_) {/* The FutureBuilder presents the retry state. */}
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'مركز الخدمات',
        actions: [
          IconButton(
              tooltip: 'طلباتي',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ServiceOrdersScreen())),
              icon: const Icon(Icons.receipt_long_outlined))
        ],
        body: FutureBuilder<List<dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingState();
            }
            if (snapshot.hasError) {
              return ErrorState(
                  message: 'تعذر تحميل الخدمات', onRetry: refresh);
            }
            final rows = (snapshot.data ?? []).whereType<Map>().toList();
            if (rows.isEmpty) {
              return const EmptyState(
                  icon: Icons.miscellaneous_services,
                  title: 'لا توجد خدمات متاحة',
                  message: 'ستظهر الخدمات التي ينشرها الفريق هنا.');
            }
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            return RefreshIndicator(
                onRefresh: refresh,
                child: GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 152 + (scale > 1 ? (scale - 1) * 90 : 0)),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = Map<String, dynamic>.from(rows[index]);
                    final title = row['title']?.toString() ?? '';
                    return Semantics(
                        button: true,
                        label: title,
                        child: Material(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.border)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ServiceDetailScreen(service: {
                                          ...row,
                                          'name': title,
                                          'price': 'يحدد بعد مراجعة الطلب',
                                        }))),
                            child: Padding(
                                padding: const EdgeInsets.all(13),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFFFEEDD),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Icon(_serviceIcon(title),
                                            size: 19, color: AppColors.orange)),
                                    const Spacer(),
                                    Text(title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body.copyWith(
                                            fontSize: 14,
                                            height: 1.5,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 16),
                                    const Text('السعر عند الطلب',
                                        style: AppTextStyles.caption),
                                  ],
                                )),
                          ),
                        ));
                  },
                ));
          },
        ),
      );
}

IconData _serviceIcon(String title) {
  final value = title.toLowerCase();
  if (value.contains('ترجم') || value.contains('translat')) {
    return Icons.translate_rounded;
  }
  if (value.contains('تصديق') ||
      value.contains('توثيق') ||
      value.contains('certif')) {
    return Icons.verified_rounded;
  }
  if (value.contains('تأمين') ||
      value.contains('تامين') ||
      value.contains('insur')) {
    return Icons.health_and_safety_rounded;
  }
  if (value.contains('مطار') ||
      value.contains('استقبال') ||
      value.contains('airport')) {
    return Icons.directions_car_filled_rounded;
  }
  if (value.contains('شريحة') ||
      value.contains('اتصال') ||
      value.contains('sim')) {
    return Icons.sim_card_rounded;
  }
  if (value.contains('بنك') ||
      value.contains('بنكي') ||
      value.contains('bank')) {
    return Icons.account_balance_wallet_rounded;
  }
  if (value.contains('إقام') ||
      value.contains('اقام') ||
      value.contains('residen') ||
      value.contains('تأشير')) {
    return Icons.badge_rounded;
  }
  if (value.contains('سكن') || value.contains('housing')) {
    return Icons.apartment_rounded;
  }
  if (value.contains('جامع') ||
      value.contains('قبول') ||
      value.contains('دراس')) {
    return Icons.school_rounded;
  }
  return Icons.miscellaneous_services_rounded;
}

class ServiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const ServiceDetailScreen({super.key, required this.service});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  bool _submitting = false;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _requestService() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'تأكيد طلب الخدمة',
      message:
          'سيُنشأ طلب خدمة مستقل ويمكنك متابعة حالته وسعره من قسم طلباتي. متابعة؟',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await StudentRepository.instance.createServiceOrder(
          serviceId: '${widget.service['_id']}', notes: _notes.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم إنشاء طلب الخدمة ويمكنك متابعته من طلباتي'),
          backgroundColor: AppColors.success));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException
              ? e.message
              : 'تعذر إرسال الطلب، حاول مرة أخرى')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return AppScaffold(
      title: service['name'] as String? ?? 'الخدمة',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Column(
                children: [
                  _Row(
                      label: 'السعر',
                      value: service['price'] as String? ?? '—'),
                  const Divider(height: 20),
                  Text(
                      service['detailBody']
                              ?.toString()
                              .replaceAll(RegExp(r'<[^>]*>'), '') ??
                          '',
                      style: AppTextStyles.body),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'بعد الإرسال سيحدد الفريق السعر والخطوات المطلوبة، وستظهر جميع التحديثات في طلباتي.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 14),
            TextField(
                controller: _notes,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                    labelText: 'تفاصيل أو ملاحظات للطلب (اختياري)')),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _submitting ? 'جاري الإرسال...' : 'طلب الخدمة',
              onPressed: _submitting ? null : _requestService,
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceOrdersScreen extends StatefulWidget {
  const ServiceOrdersScreen({super.key});
  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen> {
  bool loading = true, changing = false;
  String? error;
  List<Map<String, dynamic>> orders = [];
  static const labels = {
    'submitted': 'تم الإرسال',
    'in-progress': 'قيد التنفيذ',
    'awaiting-payment': 'بانتظار الدفع',
    'completed': 'مكتمل',
    'rejected': 'مرفوض',
    'cancelled': 'ملغي'
  };
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
      orders = (await StudentRepository.instance.getServiceOrders())
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      error = e is ApiException ? e.message : 'تعذر تحميل طلبات الخدمات.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> cancel(Map<String, dynamic> order) async {
    final yes = await showAppConfirmDialog(context,
        title: 'إلغاء طلب الخدمة', message: 'هل تريد إلغاء هذا الطلب؟');
    if (yes != true || !mounted) return;
    setState(() => changing = true);
    try {
      await StudentRepository.instance
          .cancelServiceOrder('${order['_id']}', order['__v'] as int? ?? 0);
      await load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.message : 'تعذر إلغاء الطلب')));
    }
    if (mounted) setState(() => changing = false);
  }

  Color color(String s) => s == 'completed'
      ? AppColors.success
      : s == 'rejected'
          ? AppColors.danger
          : s == 'cancelled'
              ? AppColors.neutral
              : AppColors.warning;
  @override
  Widget build(BuildContext context) => AppScaffold(
      title: 'طلبات الخدمات',
      actions: [
        IconButton(
            onPressed: loading ? null : load, icon: const Icon(Icons.refresh))
      ],
      body: loading
          ? const LoadingState(message: 'جارٍ تحميل الطلبات...')
          : error != null
              ? ErrorState(message: error!, onRetry: load)
              : orders.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'لا توجد طلبات خدمات',
                      message: 'اختر خدمة من مركز الخدمات وأنشئ طلبك.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: orders.map((o) {
                        final service = o['service'] is Map
                            ? o['service'] as Map
                            : const {};
                        final state = '${o['status']}';
                        final active = [
                          'submitted',
                          'in-progress',
                          'awaiting-payment'
                        ].contains(state);
                        return AppCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text('${service['title'] ?? 'خدمة'}',
                                        style: AppTextStyles.cardTitle)),
                                StatusBadge(
                                    label: labels[state] ?? state,
                                    color: color(state))
                              ]),
                              if ('${o['staffNote'] ?? ''}'.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('${o['staffNote']}',
                                    style: AppTextStyles.body)
                              ],
                              if (o['quotedPrice'] != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                    'السعر: ${o['quotedPrice']} ${o['currency'] ?? ''}',
                                    style: AppTextStyles.sectionLabel)
                              ],
                              if ('${o['notes'] ?? ''}'.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('ملاحظاتك: ${o['notes']}',
                                    style: AppTextStyles.caption)
                              ],
                              if (active)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                        onPressed:
                                            changing ? null : () => cancel(o),
                                        child: const Text('إلغاء الطلب'))),
                            ]));
                      }).toList()));
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.caption),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w700))),
      ],
    );
  }
}

class ConsultationBookingScreen extends StatelessWidget {
  final VoidCallback? onConfirm;
  const ConsultationBookingScreen({super.key, this.onConfirm});
  @override
  Widget build(BuildContext context) =>
      LiveConsultationScreen(onBooked: onConfirm);
}

class ConsultationConfirmationScreen extends StatelessWidget {
  const ConsultationConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تأكيد الموعد',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.success, size: 42),
            ),
            const SizedBox(height: 16),
            const Text('تم تأكيد موعدك بنجاح', style: AppTextStyles.cardTitle),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                children: const [
                  _Row(label: 'التاريخ والوقت', value: '18 سبتمبر - 11:00 ص'),
                  Divider(height: 20),
                  _Row(label: 'نوع الاستشارة', value: 'أونلاين'),
                  Divider(height: 20),
                  _Row(label: 'المستشار', value: 'سارة أحمد'),
                  Divider(height: 20),
                  _Row(
                      label: 'رابط الاجتماع', value: 'meet.studybirds.com/xyz'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('سيتم إرسال تذكير لك قبل الموعد.',
                style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
