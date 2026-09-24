import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/api_client.dart';
import '../../core/admin_modules_repository.dart';

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

const _statusesRequiringReason = {'action-required', 'rejected', 'cancelled'};

class AdminServiceRequestsScreen extends StatefulWidget {
  const AdminServiceRequestsScreen({super.key});

  @override
  State<AdminServiceRequestsScreen> createState() => _AdminServiceRequestsScreenState();
}

class _AdminServiceRequestsScreenState extends State<AdminServiceRequestsScreen> {
  List<dynamic> _items = [];
  List<dynamic> _assignees = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = '';
  final Map<String, Map<String, dynamic>> _forms = {};
  final Map<String, bool> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    AdminModulesRepository.instance.getServiceRequestAssignees()
        .then((a) { if (mounted) setState(() => _assignees = a); })
        .catchError((_) {});
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await AdminModulesRepository.instance.getServiceRequests(
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        for (final item in items) {
          final id = item['_id'] as String;
          _forms.putIfAbsent(id, () => {
            'nextStatus': '',
            'reason': '',
            'staffNote': '',
            'amount': '',
            'dueDate': '',
            'assignedTo': item['assignedTo']?['_id'] ?? '',
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e is ApiException ? e.message : 'تعذر تحميل الطلبات'; _loading = false; });
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> item) async {
    final id = item['_id'] as String;
    final form = _forms[id]!;
    final nextStatus = form['nextStatus'] as String;
    if (nextStatus.isEmpty) return;
    setState(() => _busy[id] = true);
    try {
      final updated = await AdminModulesRepository.instance.updateServiceRequestStatus(
        id,
        status: nextStatus,
        version: item['__v'] as int,
        reason: (form['reason'] as String).isNotEmpty ? form['reason'] as String : null,
        staffNote: (form['staffNote'] as String).isNotEmpty ? form['staffNote'] as String : null,
        amount: (form['amount'] as String).isNotEmpty ? num.tryParse(form['amount'] as String) : null,
        dueDate: (form['dueDate'] as String).isNotEmpty ? form['dueDate'] as String : null,
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((r) => r['_id'] == id);
        if (idx >= 0) _items[idx] = updated;
        _forms[id]!['nextStatus'] = '';
        _forms[id]!['reason'] = '';
        _forms[id]!['staffNote'] = '';
        _forms[id]!['amount'] = '';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : 'تعذر تحديث الحالة')));
    } finally {
      if (mounted) setState(() => _busy[id] = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> item) async {
    final id = item['_id'] as String;
    final form = _forms[id]!;
    final assignTo = (form['assignedTo'] as String).isEmpty ? null : form['assignedTo'] as String;
    setState(() => _busy['assign-$id'] = true);
    try {
      final updated = await AdminModulesRepository.instance.assignServiceRequest(
        id, assignedTo: assignTo, version: item['__v'] as int,
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((r) => r['_id'] == id);
        if (idx >= 0) _items[idx] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : 'تعذر تعيين المسؤول')));
    } finally {
      if (mounted) setState(() => _busy['assign-$id'] = false);
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
      appBar: AppBar(title: const Text('طلبات الخدمات'), actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ]),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final s in ['', ..._statusLabels.keys])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.isEmpty ? 'الكل' : (_statusLabels[s] ?? s)),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() { _statusFilter = s; _load(); }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, style: const TextStyle(color: AppColors.danger)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ]))
                    : _items.isEmpty
                        ? const Center(child: Text('لا توجد طلبات', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _RequestCard(
                              item: _items[i] as Map<String, dynamic>,
                              form: _forms[_items[i]['_id']] ?? {},
                              assignees: _assignees,
                              busy: _busy,
                              onFormChanged: (id, patch) => setState(() => _forms[id]?.addAll(patch)),
                              onUpdateStatus: () => _updateStatus(_items[i] as Map<String, dynamic>),
                              onAssign: () => _assign(_items[i] as Map<String, dynamic>),
                              statusChip: _statusChip,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> form;
  final List<dynamic> assignees;
  final Map<String, bool> busy;
  final void Function(String id, Map<String, dynamic> patch) onFormChanged;
  final VoidCallback onUpdateStatus;
  final VoidCallback onAssign;
  final Widget Function(String status) statusChip;

  const _RequestCard({
    required this.item,
    required this.form,
    required this.assignees,
    required this.busy,
    required this.onFormChanged,
    required this.onUpdateStatus,
    required this.onAssign,
    required this.statusChip,
  });

  @override
  Widget build(BuildContext context) {
    final id = item['_id'] as String;
    final status = item['status'] as String? ?? '';
    final allowed = List<String>.from(item['allowedStatuses'] as List? ?? []);
    final nextStatus = form['nextStatus'] as String? ?? '';
    final needsReason = _statusesRequiringReason.contains(nextStatus);
    final needsAmount = nextStatus == 'awaiting-payment';
    final student = item['student'] as Map<String, dynamic>?;
    final service = item['service'] as Map<String, dynamic>?;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(service?['title'] as String? ?? '', style: AppTextStyles.cardTitle)),
            statusChip(status),
          ]),
          if (student != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${student['name']} · ${student['email']}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ),
          if ((item['notes'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(item['notes'] as String, style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic)),
            ),
          if ((item['reason'] as String?)?.isNotEmpty == true)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.warning.withAlpha(20), borderRadius: BorderRadius.circular(10)),
              child: Text('السبب: ${item['reason']}', style: AppTextStyles.caption.copyWith(color: AppColors.warning)),
            ),
          if ((item['studentReply'] as String?)?.isNotEmpty == true)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.navy.withAlpha(15), borderRadius: BorderRadius.circular(10)),
              child: Text('رد الطالب: ${item['studentReply']}', style: AppTextStyles.caption),
            ),

          // Assign
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: (form['assignedTo'] as String?)?.isEmpty == true ? null : form['assignedTo'] as String?,
                decoration: const InputDecoration(labelText: 'المسؤول', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— بدون مسؤول —')),
                  for (final a in assignees)
                    DropdownMenuItem(value: a['_id'] as String, child: Text(a['name'] as String? ?? '')),
                ],
                onChanged: (v) => onFormChanged(id, {'assignedTo': v ?? ''}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy['assign-$id'] == true ? null : onAssign,
              child: Text(busy['assign-$id'] == true ? '...' : 'تعيين'),
            ),
          ]),

          // Status update
          if (allowed.isNotEmpty) ...[
            const Divider(height: 24),
            DropdownButtonFormField<String>(
              value: nextStatus.isEmpty ? null : nextStatus,
              decoration: const InputDecoration(labelText: 'الحالة التالية', isDense: true),
              items: [
                for (final s in allowed)
                  DropdownMenuItem(value: s, child: Text(_statusLabels[s] ?? s)),
              ],
              onChanged: (v) => onFormChanged(id, {'nextStatus': v ?? ''}),
            ),
            if (needsReason) ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: form['reason'] as String?,
                decoration: const InputDecoration(labelText: 'السبب (يراه الطالب)', isDense: true),
                maxLines: 2,
                onChanged: (v) => onFormChanged(id, {'reason': v}),
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              initialValue: form['staffNote'] as String?,
              decoration: const InputDecoration(labelText: 'ملاحظة داخلية (اختياري)', isDense: true),
              maxLines: 2,
              onChanged: (v) => onFormChanged(id, {'staffNote': v}),
            ),
            if (needsAmount) ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: form['amount'] as String?,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ', isDense: true),
                onChanged: (v) => onFormChanged(id, {'amount': v}),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: nextStatus.isEmpty || busy[id] == true ? null : onUpdateStatus,
              child: Text(busy[id] == true ? 'جارٍ الحفظ...' : 'تحديث الحالة'),
            ),
          ],
        ]),
      ),
    );
  }
}
