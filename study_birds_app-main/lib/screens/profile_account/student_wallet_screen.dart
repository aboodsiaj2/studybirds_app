import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/student_repository.dart';
import '../applications_documents_payments/payments_screens.dart';

/// Student wallet (PRD 54): balance, referral code and referrals, the credit
/// ledger, and paying unpaid invoices from the balance. Backed by
/// GET /students/wallet, POST /students/wallet/redeem and /students/financials.
class StudentWalletScreen extends StatefulWidget {
  const StudentWalletScreen({super.key});
  @override
  State<StudentWalletScreen> createState() => _StudentWalletScreenState();
}

/// Arabic text for a failed redemption; server messages are English.
String walletRedeemError(Object error) {
  if (error is! ApiException) return 'تعذر استخدام الرصيد. حاول مجددًا.';
  final message = error.message.toLowerCase();
  if (error.statusCode == 503) {
    return 'الدفع من الرصيد غير متاح مؤقتًا. حاول لاحقًا أو تواصل مع الدعم.';
  }
  if (message.contains('insufficient')) return 'رصيدك لا يكفي لهذا المبلغ.';
  if (message.contains('exceeds')) {
    return 'المبلغ أكبر من المتبقي على الفاتورة.';
  }
  if (message.contains('no longer accept')) {
    return 'هذه الفاتورة لم تعد تقبل الدفع من الرصيد.';
  }
  if (error.statusCode == 409) {
    return 'تغيّرت الفاتورة أو الرصيد للتو. حدّثنا البيانات، راجعها وحاول مجددًا.';
  }
  return 'تعذر استخدام الرصيد. حاول مجددًا.';
}

class _StudentWalletScreenState extends State<StudentWalletScreen> {
  final repo = StudentRepository.instance;
  Map<String, dynamic>? wallet;
  List<Map<String, dynamic>> invoices = [];
  bool loading = true, busy = false;
  String? error;

  static const _kinds = {
    'referral-reward': 'مكافأة إحالة',
    'redemption': 'سداد فاتورة',
    'adjustment': 'تسوية من الفريق',
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
      final results =
          await Future.wait([repo.getWallet(), repo.getFinancials()]);
      if (!mounted) return;
      setState(() {
        wallet = results[0];
        invoices = ((results[1]['invoices'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تحميل محفظتك. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  num get balance => (wallet?['balance'] as num?) ?? 0;

  static num remainingOf(Map<String, dynamic> invoice) =>
      ((invoice['amount'] as num?) ?? 0) -
      ((invoice['walletCreditApplied'] as num?) ?? 0);

  String _money(num value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : value.toStringAsFixed(2);

  Future<void> pay(Map<String, dynamic> invoice) async {
    final remaining = remainingOf(invoice);
    final maxAmount = remaining < balance ? remaining : balance;
    final amount = await showDialog<num>(
        context: context,
        builder: (_) => _RedeemDialog(
            invoiceLabel:
                '${invoice['invoiceNumber'] ?? ''} — ${invoice['description'] ?? ''}',
            maxAmount: maxAmount,
            remaining: remaining));
    if (amount == null || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await repo.redeemWalletCredit(
          invoiceId: '${invoice['_id']}', amount: amount);
      if (!mounted) return;
      final paid = (result['invoice'] is Map) &&
          (result['invoice'] as Map)['status'] == 'paid';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(paid
              ? 'تم سداد الفاتورة بالكامل من رصيدك.'
              : 'تم خصم ${_money(amount)} من رصيدك على الفاتورة.'),
          backgroundColor: AppColors.success));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(walletRedeemError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
      // Balance and invoice may have changed either way; show the truth.
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'محفظتي',
        body: loading && wallet == null
            ? const LoadingState(message: 'جاري تحميل محفظتك...')
            : error != null && wallet == null
                ? ErrorState(message: error!, onRetry: load)
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        _balanceCard(),
                        const SizedBox(height: 16),
                        _referralCard(),
                        const SizedBox(height: 16),
                        _payableInvoices(),
                        const SizedBox(height: 16),
                        _transactions(),
                      ],
                    ),
                  ),
      );

  Widget _balanceCard() => AppCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('رصيدك الحالي', style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Text(_money(balance),
                style: AppTextStyles.screenTitle.copyWith(fontSize: 30)),
            const SizedBox(height: 4),
            const Text(
                'رصيد داخلي من مكافآت الإحالة وتسويات الفريق، يُستخدم لسداد فواتيرك.',
                style: AppTextStyles.caption),
          ],
        ),
      );

  Widget _referralCard() {
    final code = '${wallet?['referralCode'] ?? ''}';
    final referrals =
        ((wallet?['referrals'] as List?) ?? const []).whereType<Map>().toList();
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('رمز الإحالة', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 6),
          const Text(
              'شارك رمزك؛ تحصل على مكافأة عندما يقدّم صديقك أول طلب حقيقي.',
              style: AppTextStyles.caption),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: SelectableText(code.isEmpty ? '—' : code,
                    style:
                        AppTextStyles.cardTitle.copyWith(letterSpacing: 1.5))),
            if (code.isNotEmpty)
              TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ الرمز')));
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ')),
          ]),
          if (referrals.isNotEmpty) ...[
            const Divider(height: 20),
            for (final r in referrals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text('${r['name'] ?? 'طالب'}',
                          style: AppTextStyles.body)),
                  StatusBadge(
                      label: r['status'] == 'qualified'
                          ? 'مكتملة'
                          : 'بانتظار أول طلب',
                      color: r['status'] == 'qualified'
                          ? AppColors.success
                          : AppColors.warning),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _payableInvoices() {
    final payable = invoices
        .where((i) => i['status'] == 'unpaid' && remainingOf(i) > 0)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ادفع من رصيدك', style: AppTextStyles.sectionLabel),
        const SizedBox(height: 8),
        if (payable.isEmpty)
          const Text('لا توجد فواتير غير مدفوعة حاليًا.',
              style: AppTextStyles.caption),
        for (final invoice in payable)
          AppCard(
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${invoice['description'] ?? invoice['invoiceNumber'] ?? ''}',
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text('المتبقي: ${_money(remainingOf(invoice))}',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: busy || balance <= 0 ? null : () => pay(invoice),
                  child: const Text('ادفع من الرصيد')),
            ]),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PaymentsSummaryScreen())),
            child: const Text('كل الفواتير وطرق الدفع الأخرى')),
      ],
    );
  }

  Widget _transactions() {
    final items = ((wallet?['transactions'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final local = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('حركات المحفظة', style: AppTextStyles.sectionLabel),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('لا توجد حركات بعد.', style: AppTextStyles.caption),
        for (final tx in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kinds[tx['kind']] ?? '${tx['kind'] ?? ''}',
                        style: AppTextStyles.body),
                    if ('${tx['notes'] ?? ''}'.isNotEmpty)
                      Text('${tx['notes']}', style: AppTextStyles.caption),
                    if (DateTime.tryParse('${tx['createdAt']}') case final d?)
                      Text(local.formatMediumDate(d.toLocal()),
                          style: AppTextStyles.caption),
                  ],
                ),
              ),
              Text(
                  '${tx['direction'] == 'credit' ? '+' : '−'}${_money((tx['amount'] as num?) ?? 0)}',
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tx['direction'] == 'credit'
                          ? AppColors.success
                          : AppColors.danger)),
            ]),
          ),
      ],
    );
  }
}

/// Amount entry with a confirmation step (PRD 70): returns the amount or null.
class _RedeemDialog extends StatefulWidget {
  final String invoiceLabel;
  final num maxAmount, remaining;
  const _RedeemDialog(
      {required this.invoiceLabel,
      required this.maxAmount,
      required this.remaining});
  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  late final controller = TextEditingController(
      text: widget.maxAmount == widget.maxAmount.roundToDouble()
          ? '${widget.maxAmount.toInt()}'
          : widget.maxAmount.toStringAsFixed(2));

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  num? get amount => num.tryParse(controller.text.trim());
  bool get valid =>
      amount != null && amount! > 0 && amount! <= widget.maxAmount;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          title: const Text('الدفع من الرصيد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.invoiceLabel, style: AppTextStyles.body),
              const SizedBox(height: 8),
              Text(
                  'الحد الأقصى: ${widget.maxAmount} (المتبقي على الفاتورة ${widget.remaining})',
                  style: AppTextStyles.caption),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: 'المبلغ',
                    errorText: controller.text.isEmpty || valid
                        ? null
                        : 'أدخل مبلغًا بين 0 و${widget.maxAmount}'),
              ),
              const SizedBox(height: 8),
              const Text('سيُخصم المبلغ من رصيدك فورًا ولا يمكن التراجع عنه.',
                  style: AppTextStyles.caption),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: valid ? () => Navigator.pop(context, amount) : null,
                child: const Text('تأكيد الدفع')),
          ],
        ),
      );
}
