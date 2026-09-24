import 'package:flutter/material.dart';
import '../../core/student_repository.dart';
import '../../core/auth_session.dart';
import '../../core/app_theme.dart';

class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final _codeController = TextEditingController();
  bool _redeeming = false;
  bool _loadingHistory = true;
  List<dynamic> _history = [];
  String? _redeemError;
  String? _redeemSuccess;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final token = AuthSession.instance.token;
      if (token == null) return;
      final repo = StudentRepository.instance;
      final data = await repo.getMyPromoRedemptions();
      if (mounted) setState(() => _history = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() { _redeeming = true; _redeemError = null; _redeemSuccess = null; });
    try {
      final result = await StudentRepository.instance.redeemPromoCode(code);
      final amount = result['creditAmount'];
      if (mounted) {
        _codeController.clear();
        setState(() => _redeemSuccess = 'تمت الإضافة: $amount رصيد!');
        await _loadHistory();
      }
    } catch (e) {
      if (mounted) setState(() => _redeemError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'رمز العرض',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أدخل رمز العرض', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 10),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'PROMO2024',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_redeemError != null) ...[
                  const SizedBox(height: 8),
                  Text(_redeemError!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                if (_redeemSuccess != null) ...[
                  const SizedBox(height: 8),
                  Text(_redeemSuccess!, style: TextStyle(color: AppColors.success, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _redeeming
                      ? const Center(child: CircularProgressIndicator())
                      : PrimaryButton(
                          label: 'استرداد الرمز',
                          onPressed: _redeem,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('سجل الاستردادات', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 8),
          if (_loadingHistory)
            const Center(child: CircularProgressIndicator())
          else if (_history.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('لا توجد استردادات بعد', style: TextStyle(color: Colors.grey)),
            ))
          else
            ..._history.map((r) {
              final promo = r['promoCode'] as Map<String, dynamic>?;
              final code = promo?['code'] ?? '';
              final amount = promo?['creditAmount'] ?? r['creditAmount'];
              final desc = promo?['description'] ?? '';
              return AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.local_offer, color: AppColors.navy),
                  title: Text(code, style: AppTextStyles.cardTitle),
                  subtitle: desc.isNotEmpty ? Text(desc) : null,
                  trailing: Text('+$amount', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                ),
              );
            }),
        ],
      ),
    );
  }
}
