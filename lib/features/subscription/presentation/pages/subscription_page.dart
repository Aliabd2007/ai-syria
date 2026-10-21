import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _usage;
  bool _loading = true;
  String? _error;

  // Payment form
  final _txId = TextEditingController();
  String _provider = 'syriatel_cash';
  String _planRequested = 'student';
  final _amount = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _txId.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _damascusDate() {
    // Approximate Asia/Damascus date (UTC+3). For exact, use server date via RPC.
    final nowUtc = DateTime.now().toUtc().add(const Duration(hours: 3));
    return nowUtc.toIso8601String().split('T')[0];
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _error = 'غير مسجل الدخول');
        return;
      }
      final uid = user.id;
      Map<String, dynamic>? profile;
      try {
        profile = await Supabase.instance.client.from('profiles').select().eq('id', uid).single();
      } catch (e) {
        debugPrint('profiles fetch failed: $e');
      }
      // Fallback profile if RLS or missing row
      profile ??= {'plan': 'free', 'expires_at': null, 'email': user.email};

      final today = _damascusDate();
      Map<String, dynamic>? usage;
      try {
        usage = await Supabase.instance.client
            .from('daily_usage')
            .select()
            .eq('user_id', uid)
            .eq('date', today)
            .maybeSingle();
      } catch (e) {
        debugPrint('daily_usage fetch failed: $e');
      }
      // If no row, show 0/ limit
      usage ??= {'heavy_count': 0, 'fast_count': 0, 'date': today};

      if (!mounted) return;
      setState(() { _profile = profile; _usage = usage; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPayment() async {
    if (_txId.text.trim().isEmpty || _amount.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل جميع الحقول')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('payment_requests').insert({
        'user_id': uid,
        'provider': _provider,
        'tx_id': _txId.text.trim(),
        'amount_syp': int.parse(_amount.text.trim()),
        'plan_requested': _planRequested,
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الطلب — بانتظار المراجعة')));
      _txId.clear();
      _amount.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الاشتراك والمحفظة')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PlanCard(profile: _profile!),
                        const SizedBox(height: 16),
                        _UsageCard(usage: _usage, plan: _profile!['plan'] as String),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text('طلب تفعيل اشتراك', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _provider,
                          decoration: const InputDecoration(labelText: 'مزود الدفع', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'syriatel_cash', child: Text('سيريتل كاش')),
                            DropdownMenuItem(value: 'sham_cash', child: Text('شام كاش')),
                            DropdownMenuItem(value: 'mtn_cash', child: Text('MTN كاش')),
                          ],
                          onChanged: (v) => setState(() => _provider = v!),
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: _txId, decoration: const InputDecoration(labelText: 'رقم العملية (tx_id)', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ (ل.س)', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _planRequested,
                          decoration: const InputDecoration(labelText: 'الخطة المطلوبة', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'student', child: Text('طالب')),
                            DropdownMenuItem(value: 'pro', child: Text('احترافي')),
                          ],
                          onChanged: (v) => setState(() => _planRequested = v!),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submitPayment,
                            child: _submitting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('إرسال الطلب'),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _PlanCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final plan = profile['plan'] as String;
    final expiresAt = profile['expires_at'] as String?;
    final isExpired = expiresAt != null && DateTime.tryParse(expiresAt)?.isBefore(DateTime.now()) == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(plan == 'pro' ? Icons.star : plan == 'student' ? Icons.school : Icons.person, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('الخطة: $plan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Chip(label: Text(isExpired ? 'منتهي' : 'نشط'), backgroundColor: isExpired ? Colors.red[100] : Colors.green[100]),
            ]),
            if (expiresAt != null) ...[
              const SizedBox(height: 8),
              Text('ينتهي في: $expiresAt', style: Theme.of(context).textTheme.bodySmall),
            ],
            if (profile['email'] != null) ...[
              const SizedBox(height: 4),
              Text(profile['email'] as String, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final Map<String, dynamic>? usage;
  final String plan;
  const _UsageCard({required this.usage, required this.plan});

  @override
  Widget build(BuildContext context) {
    final heavy = usage?['heavy_count'] as int? ?? 0;
    final fast = usage?['fast_count'] as int? ?? 0;
    final limits = AppConstants.quotaLimits[plan] ?? AppConstants.quotaLimits['free']!;
    final heavyLimit = limits['heavy']!;
    final fastLimit = limits['fast']!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الاستهلاك اليومي', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _QuotaRow(label: 'الثقيل (heavy)', used: heavy, limit: heavyLimit),
            const SizedBox(height: 8),
            _QuotaRow(label: 'السريع (fast)', used: fast, limit: fastLimit),
          ],
        ),
      ),
    );
  }
}

class _QuotaRow extends StatelessWidget {
  final String label;
  final int used;
  final int limit;
  const _QuotaRow({required this.label, required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final unlimited = limit == -1;
    final progress = unlimited ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(unlimited ? '$used / ∞' : '$used / $limit', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: unlimited ? null : progress),
      ],
    );
  }
}
