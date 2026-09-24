import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_session.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_confirmation.text.trim() != 'DELETE') {
      setState(() => _error = 'اكتب DELETE في حقل التأكيد.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance
          .delete('/auth/account', token: AuthSession.instance.token, body: {
        'password': _password.text,
        'confirmation': _confirmation.text.trim(),
      });
      await AuthSession.instance.logout();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.statusCode == 401
            ? 'كلمة المرور الحالية غير صحيحة.'
            : 'تعذر حذف الحساب. ${error.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'حذف الحساب',
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 52, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text('هذا الإجراء نهائي',
                textAlign: TextAlign.center, style: AppTextStyles.cardTitle),
            const SizedBox(height: 8),
            const Text(
              'سيُحذف حسابك وطلباتك ومستنداتك وفواتيرك ورسائلك وبياناتك الشخصية، ولن تتمكن من استعادتها.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  prefixIcon: Icon(Icons.lock_outline_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: 'اكتب DELETE للتأكيد',
                  prefixIcon: Icon(Icons.delete_forever_outlined)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _delete,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(double.infinity, 50)),
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_forever_rounded),
              label: const Text('حذف حسابي نهائيًا'),
            ),
          ],
        ),
      );
}
