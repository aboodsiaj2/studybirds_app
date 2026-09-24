import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/api_client.dart';
import '../../core/student_repository.dart';

const _statusLabels = <String, String>{
  'submitted': 'مُرسَل',
  'under-review': 'قيد المراجعة',
  'action-required': 'إجراء مطلوب',
  'awaiting-payment': 'بانتظار الدفع',
  'in-progress': 'جارٍ التنفيذ',
  'completed': 'مكتمل',
  'rejected': 'مرفوض',
  'cancelled': 'ملغي',
};

const _statusColors = <String, Color>{
  'submitted': Color(0xFF1D4ED8),
  'under-review': Color(0xFFCA8A04),
  'action-required': Color(0xFFEA580C),
  'awaiting-payment': Color(0xFF7C3AED),
  'in-progress': Color(0xFF0369A1),
  'completed': Color(0xFF15803D),
  'rejected': Color(0xFFBE123C),
  'cancelled': Color(0xFF64748B),
};

class StudentServiceRequestsScreen extends StatefulWidget {
  const StudentServiceRequestsScreen({super.key});

  @override
  State<StudentServiceRequestsScreen> createState() => _StudentServiceRequestsScreenState();
}

class _StudentServiceRequestsScreenState extends State<StudentServiceRequestsScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await StudentRepository.instance.getMyServiceRequests();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e is ApiException ? e.message : 'تعذر تحميل الطلبات'; _loading = false; });
    }
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('هل تريد إلغاء هذا الطلب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، إلغاء')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final updated = await StudentRepository.instance.cancelServiceRequest(
        id: item['_id'] as String,
        version: item['__v'] as int,
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((r) => r['_id'] == item['_id']);
        if (idx >= 0) _items[idx] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : 'تعذر إلغاء الطلب')));
    }
  }

  Future<void> _respond(Map<String, dynamic> item) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الرد على الطلب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(item['reason'] as String? ?? '', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLines: 4,
              decoration: const InputDecoration(hintText: 'ردك هنا...', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty || !mounted) return;
    try {
      final updated = await StudentRepository.instance.respondToServiceRequest(
        id: item['_id'] as String,
        version: item['__v'] as int,
        reply: ctrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((r) => r['_id'] == item['_id']);
        if (idx >= 0) _items[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال ردك بنجاح'), backgroundColor: AppColors.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : 'تعذر إرسال الرد')));
    }
  }

  Widget _statusChip(String status) {
    final color = _statusColors[status] ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(20)),
      child: Text(_statusLabels[status] ?? status,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي'), actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ]))
              : _items.isEmpty
                  ? const Center(child: Text('لا توجد طلبات بعد', style: TextStyle(color: AppColors.textSecondary)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final item = _items[i] as Map<String, dynamic>;
                          final service = item['service'] as Map<String, dynamic>?;
                          final status = item['status'] as String? ?? '';
                          final statusInfo = item['statusInfo'] as Map<String, dynamic>?;
                          final canCancel = item['canCancel'] == true;
                          final canRespond = item['canRespond'] == true;
                          final invoice = item['invoice'] as Map<String, dynamic>?;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.border)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(child: Text(service?['title'] as String? ?? '',
                                      style: AppTextStyles.cardTitle)),
                                  _statusChip(status),
                                ]),
                                if (statusInfo?['meaning'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(statusInfo!['meaning'] as String,
                                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                                  ),
                                if ((item['reason'] as String?)?.isNotEmpty == true)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: AppColors.warning.withAlpha(20),
                                        borderRadius: BorderRadius.circular(10)),
                                    child: Text('ملاحظة: ${item['reason']}',
                                        style: AppTextStyles.caption.copyWith(color: AppColors.warning)),
                                  ),
                                if (invoice != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: AppColors.navy.withAlpha(15),
                                        borderRadius: BorderRadius.circular(10)),
                                    child: Text(
                                        'فاتورة: ${invoice['invoiceNumber']} · ${invoice['amount']} · ${invoice['status']}',
                                        style: AppTextStyles.caption),
                                  ),
                                if (canRespond || canCancel) ...[
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    if (canRespond)
                                      FilledButton(
                                        onPressed: () => _respond(item),
                                        child: const Text('الرد'),
                                      ),
                                    if (canCancel) ...[
                                      if (canRespond) const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () => _cancel(item),
                                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                        child: const Text('إلغاء الطلب'),
                                      ),
                                    ],
                                  ]),
                                ],
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
