import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/admin_modules_repository.dart';

// ---- Admin Alumni Screen --------------------------------------------------

class AdminAlumniScreen extends StatefulWidget {
  const AdminAlumniScreen({super.key});

  @override
  State<AdminAlumniScreen> createState() => _AdminAlumniScreenState();
}

class _AdminAlumniScreenState extends State<AdminAlumniScreen> {
  bool _loading = true;
  List<dynamic> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AdminModulesRepository.instance.getAlumni();
      if (mounted) setState(() => _profiles = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String id, bool currentVerified) async {
    try {
      await AdminModulesRepository.instance.updateAlumni(id, {'isVerified': !currentVerified});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'شبكة الخريجين',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _profiles.isEmpty
                  ? const Center(child: Text('لا يوجد ملفات بعد'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _profiles.length,
                      itemBuilder: (_, i) {
                        final p = _profiles[i] as Map<String, dynamic>;
                        final name = p['name'] ?? p['email'] ?? '—';
                        final verified = p['isVerified'] == true;
                        final isPublic = p['isPublic'] == true;
                        return AppCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(name, style: AppTextStyles.cardTitle),
                            subtitle: Text([
                              if (p['field'] != null) p['field'],
                              if (p['currentCountry'] != null) p['currentCountry'],
                              if (!isPublic) 'مخفي',
                            ].join(' · ')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusBadge(
                                  label: verified ? 'موثق' : 'غير موثق',
                                  color: verified ? AppColors.success : AppColors.warning,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(verified ? Icons.verified : Icons.verified_outlined, color: AppColors.navy),
                                  tooltip: verified ? 'إلغاء التوثيق' : 'توثيق',
                                  onPressed: () => _toggle(p['_id'] as String, verified),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ---- Admin Promo Codes Screen --------------------------------------------

class AdminPromoCodesScreen extends StatefulWidget {
  const AdminPromoCodesScreen({super.key});

  @override
  State<AdminPromoCodesScreen> createState() => _AdminPromoCodesScreenState();
}

class _AdminPromoCodesScreenState extends State<AdminPromoCodesScreen> {
  bool _loading = true;
  List<dynamic> _codes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AdminModulesRepository.instance.getPromoCodes();
      if (mounted) setState(() => _codes = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String id, bool isActive) async {
    try {
      await AdminModulesRepository.instance.updatePromoCode(id, {'isActive': !isActive});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  void _showCreateDialog() {
    final codeCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنشاء رمز عرض'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'الرمز (PROMO2024)')),
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ الرصيد')),
          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'وصف (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final amount = double.tryParse(amountCtrl.text.trim());
              if (code.isEmpty || amount == null) return;
              Navigator.pop(ctx);
              try {
                await AdminModulesRepository.instance.createPromoCode({
                  'code': code,
                  'creditAmount': amount,
                  'description': descCtrl.text.trim(),
                });
                await _load();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
              }
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'رموز العروض',
      actions: [
        IconButton(icon: const Icon(Icons.add), onPressed: _showCreateDialog, tooltip: 'إنشاء رمز'),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _codes.isEmpty
                  ? const Center(child: Text('لا توجد رموز بعد'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _codes.length,
                      itemBuilder: (_, i) {
                        final c = _codes[i] as Map<String, dynamic>;
                        final code = c['code'] ?? '';
                        final amount = c['creditAmount'];
                        final used = c['usedCount'] ?? 0;
                        final max = c['maxUsesTotal'];
                        final isActive = c['isActive'] == true;
                        return AppCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.local_offer, color: isActive ? AppColors.navy : Colors.grey),
                            title: Text(code, style: AppTextStyles.cardTitle),
                            subtitle: Text('$amount رصيد · استُخدم $used${max != null ? '/$max' : ''} مرة'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusBadge(
                                  label: isActive ? 'نشط' : 'معطل',
                                  color: isActive ? AppColors.success : AppColors.danger,
                                ),
                                const SizedBox(width: 4),
                                Switch(
                                  value: isActive,
                                  onChanged: (_) => _toggle(c['_id'] as String, isActive),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
