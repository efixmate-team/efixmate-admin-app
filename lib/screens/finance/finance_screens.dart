import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../bookings/booking_detail_screen.dart';
import '../common/crud_screen.dart';

const _f = '/admin/finance';

bool _canEdit(String path) => Session.I.canOn(path, 'EDIT') || Session.I.can('FINANCE_EDIT');

/// Date range chip used by every finance list.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.range, required this.onChanged, this.trailing});
  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(range == null ? 'All dates' : '${fmtDate(range!.start)} – ${fmtDate(range!.end)}'),
          onPressed: () async {
            final r = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: range);
            if (r != null) onChanged(r);
          },
        ),
        if (range != null) IconButton(onPressed: () => onChanged(null), icon: const Icon(Icons.close, size: 18)),
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

Map<String, dynamic> _rangeQ(DateTimeRange? r) => r == null ? {} : {'from': ymd(r.start), 'to': ymd(r.end)};

// ─── Finance Center ──────────────────────────────────────────────────────────

class FinanceCenterScreen extends StatefulWidget {
  const FinanceCenterScreen({super.key});
  @override
  State<FinanceCenterScreen> createState() => _FinanceCenterScreenState();
}

class _FinanceCenterScreenState extends State<FinanceCenterScreen> {
  DateTimeRange? _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
  final _key = GlobalKey<ApiLoaderState>();

  Future<ApiRes> _load() async {
    final r = await Future.wait([api.get('$_f/dashboard', _rangeQ(_range)), api.get('$_f/revenue', {..._rangeQ(_range), 'groupBy': 'day'})]);
    if (!r[0].ok) return r[0];
    return ApiRes({'status': true, 'data': r[0].data, 'series': r[1].ok ? ApiRes.asMap(r[1].data)['gateway'] : []});
  }

  void _go(Widget w, String title) => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: w)));

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      RangeBar(range: _range, onChanged: (r) {
        setState(() => _range = r);
        _key.currentState?.reload();
      }),
      Expanded(
        child: ApiLoader(
          key: _key,
          load: _load,
          builder: (c, res, reload) {
            final s = res.map;
            final w = ApiRes.asMap(s['wallets']);
            final series = ApiRes.asList(res['series']);
            return ListView(padding: const EdgeInsets.all(12), children: [
              StatGrid([
                StatTile(label: 'Revenue', value: inr(ApiRes.asMap(s['revenue'])['total']), sub: '${ApiRes.asMap(s['revenue'])['count'] ?? 0} payments', icon: Icons.currency_rupee, color: C.green, onTap: () => _go(const PaymentsScreen(), 'Payments')),
                StatTile(label: 'GST collected', value: inr(s['gst_collected']), icon: Icons.account_balance, onTap: () => _go(const FinanceReportsScreen(initial: 'gst'), 'Financial reports')),
                StatTile(label: 'Refunds', value: inr(ApiRes.asMap(s['refunds'])['total']), sub: '${s['pending_refunds'] ?? 0} pending approval', icon: Icons.undo, color: C.amber, onTap: () => _go(const RefundsScreen(), 'Refunds')),
                StatTile(label: 'Settlements', value: inr(ApiRes.asMap(s['settlements'])['total']), sub: '${ApiRes.asMap(s['settlements'])['batches'] ?? 0} batches', icon: Icons.payments_outlined, color: C.violet, onTap: () => _go(const PayoutsScreen(), 'Payouts')),
                StatTile(label: 'Failed payments', value: '${s['failed_payments'] ?? 0}', icon: Icons.error_outline, color: C.red, onTap: () => _go(const FailedPaymentsScreen(), 'Failed payments')),
                StatTile(label: 'Customer wallet', value: inr(w['customer_balance']), icon: Icons.account_balance_wallet_outlined, onTap: () => _go(const WalletLedgerScreen(), 'Wallet ledger')),
                StatTile(label: 'Technician credits', value: inr(w['technician_credits']), icon: Icons.engineering, color: C.sky, onTap: () => _go(const WalletLedgerScreen(), 'Wallet ledger')),
                StatTile(label: 'Invoices', value: '${s['invoices_count'] ?? 0}', icon: Icons.description_outlined, onTap: () => _go(const InvoicesScreen(), 'Invoices')),
              ]),
              const Gap(),
              SectionCard(title: 'Revenue trend', children: [
                SizedBox(
                  height: 180,
                  child: series.isEmpty
                      ? const Center(child: Text('No revenue in this period', style: TextStyle(color: C.muted)))
                      : BarChart(BarChartData(
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(drawVerticalLine: false),
                          titlesData: const FlTitlesData(
                            topTitles: AxisTitles(), rightTitles: AxisTitles(), bottomTitles: AxisTitles(),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
                          ),
                          barGroups: [
                            for (var i = 0; i < series.length; i++)
                              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: toNum(series[i]['revenue']), color: C.primary, width: 6, borderRadius: BorderRadius.circular(2))]),
                          ],
                        )),
                ),
              ]),
              const Gap(),
              SectionCard(title: 'Finance', children: [
                for (final e in <(String, IconData, Widget)>[
                  ('Payments', Icons.payments_outlined, const PaymentsScreen()),
                  ('Invoices', Icons.description_outlined, const InvoicesScreen()),
                  ('Payouts & settlements', Icons.account_balance_outlined, const PayoutsScreen()),
                  ('Refunds', Icons.undo, const RefundsScreen()),
                  ('Transaction taxes', Icons.percent, CrudScreen(transactionTaxesConfig())),
                  ('Failed payments', Icons.error_outline, const FailedPaymentsScreen()),
                  ('Wallet ledger', Icons.account_balance_wallet_outlined, const WalletLedgerScreen()),
                  ('Financial reports', Icons.insights_outlined, const FinanceReportsScreen()),
                ])
                  ListTile(contentPadding: EdgeInsets.zero, leading: Icon(e.$2, color: C.primary), title: Text(e.$1), trailing: const Icon(Icons.chevron_right), onTap: () => _go(e.$3, e.$1)),
              ]),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ─── Payments (/master/payments) ─────────────────────────────────────────────

const _payStatus = {'P': 'Pending', 'D': 'Paid', 'S': 'Success', 'F': 'Failed', 'R': 'Refunded'};

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});
  @override
  Widget build(BuildContext context) => CrudScreen(CrudConfig(
        title: 'Payment',
        base: '/master/payments',
        idKey: 'payment_id',
        menuPath: '$_f/payments',
        activeKey: null,
        searchHint: 'Search payments…',
        filters: const {'All': {}, 'Cash': {'payment_type': 'CASH'}, 'Online': {'payment_type': 'ONLINE'}},
        titleOf: (r) => '${inr(r['amount'], paise: true)} · ${str(r['booking_uid'], '#${r['booking_id']}')}',
        subtitleOf: (r) => '${fullName(r)} · ${humanize(r['payment_type'])}',
        linesOf: (r) => ['${_payStatus[r['payment_status_id']] ?? str(r['payment_status_id'])} · ${fmtDateTime(r['paid_at'] ?? r['created_at'])}'],
        fields: (_) => [
          Field('booking_id', 'Booking ID', type: F.number, required: true),
          Field('amount', 'Amount', type: F.decimal, required: true),
          Field('payment_type', 'Payment Mode', type: F.select, options: const {'CASH': 'Cash', 'ONLINE': 'Online'}, required: true),
          Field('payment_status_id', 'Status', type: F.select, options: _payStatus, initial: 'D'),
        ],
        actions: [
          RowAction('Initiate refund', Icons.undo, (c, r, reload) async {
            final reason = await prompt(c, 'Initiate refund?', label: 'Reason', initial: 'Refund by admin', required: true, ok: 'Refund');
            if (reason == null || !c.mounted) return;
            final res = await busy(c, () => api.post('/booking/refund', {'bookingId': r['booking_id'], 'amount': r['amount'], 'reason': reason}), success: 'Refund requested');
            if (res.ok) reload();
          }),
          RowAction('Open booking', Icons.event_note, (c, r, _) async {
            Navigator.push(c, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: r['booking_id'])));
          }),
        ],
      ));
}

CrudConfig transactionTaxesConfig() => CrudConfig(
      title: 'Tax Record',
      base: '/master/transaction-taxes',
      idKey: 'tax_log_id',
      menuPath: '$_f/taxes',
      deactivateMessage: 'It stops being applied to new bookings.',
      titleOf: (r) => '${humanize(r['tax_type'])} · ${inr(r['tax_amount'], paise: true)}',
      subtitleOf: (r) => 'Transaction ${str(r['transaction_id'])}',
      linesOf: (r) => [fmtDateTime(r['created_at'])],
      fields: (_) => [
        Field('transaction_id', 'Transaction ID', type: F.number, required: true),
        Field('tax_type', 'Type', required: true),
        Field('tax_amount', 'Amount', type: F.decimal, required: true),
        Field('is_active', 'Active', type: F.toggle),
      ],
    );

// ─── Invoices ────────────────────────────────────────────────────────────────

const _invStatus = {'': 'All', 'UNPAID': 'Unpaid', 'PARTIALLY_PAID': 'Partially paid', 'PAID': 'Paid', 'PARTIALLY_REFUNDED': 'Partially refunded', 'REFUNDED': 'Refunded', 'CANCELLED': 'Cancelled'};

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = '';
  DateTimeRange? _range;

  Future<void> _generate() async {
    final id = await prompt(context, 'Generate / refresh invoice', label: 'Booking ID (numeric)', keyboard: TextInputType.number, required: true, ok: 'Generate');
    if (id == null || !mounted) return;
    final r = await busy(context, () => api.post('$_f/invoices/generate', {'bookingId': int.tryParse(id)}), success: 'Invoice generated');
    if (r.ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Invoice # or booking',
        fetch: (p, l, s) => api.get('$_f/invoices', {..._rangeQ(_range), 'search': s, 'status': _status, 'page': '$p', 'limit': '$l'}),
        header: Column(children: [
          RangeBar(range: _range, onChanged: (r) {
            setState(() => _range = r);
            _list.currentState?.reload();
          }),
          FilterChips<String>(options: _invStatus, value: _status, onChanged: (v) {
            setState(() => _status = v);
            _list.currentState?.reload();
          }),
        ]),
        itemBuilder: (c, r, i) => RowTile(
          title: '${str(r['invoice_number'])} · ${str(r['booking_uid'])}',
          badge: StatusChip(r['status']),
          subtitle: str(r['customer_name'], ''),
          lines: [
            'Amount ${inr(r['amount'], paise: true)} · paid ${inr(r['amount_paid'], paise: true)}${toNum(r['balance_due']) > 0 ? ' · due ${inr(r['balance_due'], paise: true)}' : ''}',
            '${humanize(r['payment_mode'])}${toNum(r['amount_refunded']) > 0 ? ' · refunded ${inr(r['amount_refunded'], paise: true)}' : ''}',
          ],
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: r['invoice_id']))),
        ),
      ),
      floatingActionButton: _canEdit('$_f/invoices') ? FloatingActionButton.extended(heroTag: 'inv', onPressed: _generate, icon: const Icon(Icons.add), label: const Text('Generate')) : null,
    );
  }
}

class InvoiceDetailScreen extends StatelessWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final dynamic id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: ApiLoader(
        load: () => api.get('$_f/invoices/$id'),
        builder: (c, res, reload) {
          final d = res.map;
          final inv = ApiRes.asMap(d['invoice']).isNotEmpty ? ApiRes.asMap(d['invoice']) : d;
          final bal = ApiRes.asMap(d['balance']);
          final booking = ApiRes.asMap(d['booking']);
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(title: str(inv['invoice_number']), trailing: StatusChip(inv['status']), children: [
              KV('Booking', booking['booking_uid'] ?? inv['booking_uid']),
              KV('Booking status', booking['booking_status_id']),
              KV('Customer', booking['customer_name'] ?? inv['customer_name']),
              KV('Payment mode', humanize(inv['payment_mode'])),
              KV('Revision', inv['revision']),
              KV('Created', fmtDateTime(inv['created_at'])),
              const Divider(),
              KV('Taxable amount', inr(inv['taxable_amount'], paise: true)),
              if (inv['cgst_amount'] != null) KV('CGST', inr(inv['cgst_amount'], paise: true)),
              if (inv['sgst_amount'] != null) KV('SGST', inr(inv['sgst_amount'], paise: true)),
              KV('Invoice total', inr(inv['amount'], paise: true), bold: true),
              KV('Paid', inr(bal['paid'] ?? inv['amount_paid'], paise: true), color: C.green),
              KV('Refunded', inr(bal['refunded'] ?? inv['amount_refunded'], paise: true)),
              KV('Balance due', inr(bal['due'] ?? inv['balance_due'], paise: true), color: toNum(bal['due'] ?? inv['balance_due']) > 0 ? C.red : null),
              if (inv['pdf_url'] != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => openUrl(fileUrl(inv['pdf_url'])), icon: const Icon(Icons.picture_as_pdf), label: const Text('Open PDF'))),
            ]),
            for (final sec in const ['items', 'charges', 'discounts', 'additional_work', 'adjustments'])
              if (ApiRes.asList(d[sec]).isNotEmpty) ...[
                const Gap(),
                SectionCard(title: humanize(sec), children: [
                  for (final x in ApiRes.asList(d[sec])) KV(str(x['service_name'] ?? x['name'] ?? x['description'] ?? x['label']), inr(x['line_total'] ?? x['amount'] ?? x['total'], paise: true)),
                ]),
              ],
            const Gap(),
            SectionCard(title: 'Payments', children: [
              if (ApiRes.asList(d['payments']).isEmpty) const Text('No payments captured.', style: TextStyle(color: C.muted)),
              for (final p in ApiRes.asList(d['payments'])) KV('#${p['payment_id']} ${humanize(p['payment_type'])} · ${fmtDate(p['paid_at'])}', inr(p['amount'], paise: true)),
            ]),
            const Gap(),
            SectionCard(title: 'Refunds', children: [
              if (ApiRes.asList(d['refunds']).isEmpty) const Text('No refunds.', style: TextStyle(color: C.muted)),
              for (final r in ApiRes.asList(d['refunds'])) KV('#${r['refund_id']} · ${fmtDate(r['created_at'])}', '${inr(r['approved_amount'] ?? r['amount'], paise: true)} (${r['refund_status_id']})'),
            ]),
            if (ApiRes.asList(d['revisions']).isNotEmpty) ...[
              const Gap(),
              SectionCard(title: 'Revisions', children: [
                for (final r in ApiRes.asList(d['revisions'])) KV('${r['invoice_number']} rev ${r['revision']}', truthy(r['is_active']) ? 'Current' : 'Superseded ${fmtDate(r['superseded_at'])}'),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}

// ─── Refunds ─────────────────────────────────────────────────────────────────

const _refundFilters = {'pending': 'Awaiting approval', 'in_progress': 'At gateway', 'failed': 'Failed', 'completed': 'Completed', 'rejected': 'Rejected', 'all': 'All'};
const _refundLabels = {'P': 'Requested', 'A': 'Approved', 'I': 'Initiated', 'G': 'Processing', 'C': 'Completed', 'X': 'Failed', 'R': 'Rejected'};

class RefundsScreen extends StatefulWidget {
  const RefundsScreen({super.key});
  @override
  State<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends State<RefundsScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = 'pending';
  bool get _can => _canEdit('$_f/refunds');

  Future<void> _run(Future<ApiRes> Function() call, String ok) async {
    final r = await busy(context, call, success: ok);
    if (r.ok) _list.currentState?.reload();
  }

  Future<void> _approve(Map r) async {
    final requested = toNum(r['requested_amount'] ?? r['amount']);
    final v = await prompt(context, 'Approve refund of ${inr(requested, paise: true)}?', label: 'Approved amount (₹)', hint: 'Enter a lower amount to approve partially', initial: '$requested', keyboard: const TextInputType.numberWithOptions(decimal: true), required: true, ok: 'Approve');
    if (v == null) return;
    final amt = double.tryParse(v) ?? 0;
    if (amt <= 0 || amt > requested) return toast('Enter an amount between 0 and $requested', error: true);
    _run(() => api.post('$_f/refunds/approve', {'refundId': toInt(r['refund_id']), 'approved': true, 'approvedAmount': amt, 'note': 'Approved'}), 'Refund approved and sent');
  }

  Future<void> _reject(Map r) async {
    final note = await prompt(context, 'Reject refund', label: 'Reason (shown to the customer)', required: true, lines: 3, ok: 'Reject');
    if (note == null) return;
    _run(() => api.post('$_f/refunds/approve', {'refundId': toInt(r['refund_id']), 'approved': false, 'note': note}), 'Refund rejected');
  }

  Future<void> _resolve(Map r, String outcome) async {
    String? reference;
    if (outcome == 'COMPLETED') {
      reference = await prompt(context, 'Mark refund completed', label: 'Payout / transfer reference (UPI, bank, cash receipt)', required: true, ok: 'Continue');
      if (reference == null) return;
    }
    if (!mounted) return;
    final note = await prompt(context, outcome == 'COMPLETED' ? 'Mark refund completed' : 'Mark refund failed', label: 'Note (optional)', lines: 3, ok: outcome == 'COMPLETED' ? 'Mark completed' : 'Mark failed');
    if (note == null) return;
    _run(() => api.post('$_f/refunds/${r['refund_id']}/resolve', {'outcome': outcome, 'reference': reference, if (note.isNotEmpty) 'note': note}), outcome == 'COMPLETED' ? 'Marked completed' : 'Marked failed');
  }

  List<Widget> _actions(Map r) {
    if (!_can) return [];
    final st = str(r['refund_status_id'], 'P');
    final id = r['refund_id'];
    if (st == 'P') return [FilledButton(onPressed: () => _approve(r), child: const Text('Approve')), OutlinedButton(onPressed: () => _reject(r), child: const Text('Reject'))];
    if (st == 'X') {
      return [
        FilledButton(onPressed: () async {
          if (await confirm(context, 'Retry refund of ${inr(r['approved_amount'] ?? r['amount'], paise: true)}?', message: 'The refund is sent to the payment gateway again.', ok: 'Retry refund')) {
            _run(() => api.post('$_f/refunds/$id/retry'), 'Retry sent');
          }
        }, child: const Text('Retry')),
        OutlinedButton(onPressed: () => _resolve(r, 'COMPLETED'), child: const Text('Refunded manually')),
      ];
    }
    if (st == 'I' && r['gateway'] == 'manual') {
      return [FilledButton(onPressed: () => _resolve(r, 'COMPLETED'), child: const Text('Mark refunded')), OutlinedButton(onPressed: () => _resolve(r, 'FAILED'), child: const Text('Mark failed'))];
    }
    if (st == 'I' || st == 'G') return [OutlinedButton(onPressed: () => _run(() => api.post('$_f/refunds/$id/refresh'), 'Status refreshed'), child: const Text('Refresh status'))];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      fetch: (p, l, s) => api.get('$_f/refunds', {'status': _status, 'page': '$p', 'limit': '$l'}),
      header: FilterChips<String>(options: _refundFilters, value: _status, onChanged: (v) {
        setState(() => _status = v);
        _list.currentState?.reload();
      }),
      empty: 'No refunds.',
      itemBuilder: (c, r, i) {
        final acts = _actions(r);
        return SectionCard(
          title: 'Refund #${r['refund_id']} · ${str(r['booking_uid'])}',
          trailing: StatusChip(_refundLabels[r['refund_status_id']] ?? r['refund_status_id']),
          children: [
            KV('Customer', r['customer_name']),
            KV('Requested', inr(r['requested_amount'] ?? r['amount'], paise: true)),
            if (r['approved_amount'] != null) KV('Approved', inr(r['approved_amount'], paise: true)),
            KV('Gateway', '${str(r['gateway'])}${r['gateway_status'] != null ? ' · ${r['gateway_status']}' : ''}'),
            if (r['gateway_refund_id'] != null) KV('Refund ID', r['gateway_refund_id']),
            if (r['failure_reason'] != null) KV('Failure', r['failure_reason'], color: C.red),
            KV('Requested on', fmtDateTime(r['created_at'])),
            if (r['completed_at'] != null) KV('Completed', fmtDateTime(r['completed_at'])),
            if (acts.isNotEmpty) ...[const Gap(8), Wrap(spacing: 8, runSpacing: 8, children: acts)],
          ],
        );
      },
    );
  }
}

// ─── Payouts ─────────────────────────────────────────────────────────────────

class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});
  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = '';
  DateTimeRange? _range;
  bool get _can => _canEdit('$_f/payouts');

  Future<void> _settle() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now(), helpText: 'Settlement period');
    if (r == null || !mounted) return;
    if (!await confirm(context, 'Run settlement for ${fmtDate(r.start)} to ${fmtDate(r.end)}?', message: "Technician earnings in this period are settled into payouts. This can't be undone.", danger: true, ok: 'Run settlement')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.post('$_f/settlements/process', {'periodStart': ymd(r.start), 'periodEnd': ymd(r.end)}), toastIt: false);
    if (!res.ok) {
      toastRes(res);
      return;
    }
    final d = res.map;
    final held = ApiRes.asMap(d['held']).entries.map((e) => '${e.value} ${humanize(e.key).toLowerCase()}').join(', ');
    toast('Settlement processed — ${inr(d['total_amount'])} to ${d['technicians'] ?? 0} technician(s)${held.isNotEmpty ? '. Held: $held' : ''}');
    _list.currentState?.reload();
  }

  Future<void> _mark(Map r, String next) async {
    final input = next == 'PAID'
        ? await prompt(context, 'Mark payout #${r['payout_id']} as paid', label: 'Bank / UPI reference', required: true, ok: 'Mark paid')
        : await prompt(context, 'Mark payout #${r['payout_id']} as failed', label: 'Reason', hint: "The amount goes back to the technician's wallet", required: true, lines: 3, ok: 'Mark failed');
    if (input == null || !mounted) return;
    final res = await busy(context, () => api.post('$_f/payouts/${r['payout_id']}/status', next == 'PAID' ? {'status': next, 'reference': input} : {'status': next, 'note': input}),
        success: next == 'PAID' ? 'Payout marked paid' : 'Payout marked failed — wallet restored');
    if (res.ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        fetch: (p, l, s) => api.get('$_f/payouts', {..._rangeQ(_range), 'status': _status, 'page': '$p', 'limit': '$l'}),
        header: Column(children: [
          RangeBar(
            range: _range,
            onChanged: (r) {
              setState(() => _range = r);
              _list.currentState?.reload();
            },
            trailing: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReconciliationScreen())), icon: const Icon(Icons.fact_check_outlined, size: 18), label: const Text('Reconcile')),
          ),
          FilterChips<String>(options: const {'': 'All', 'PENDING': 'Pending', 'PAID': 'Paid', 'FAILED': 'Failed', 'NETTED': 'Netted'}, value: _status, onChanged: (v) {
            setState(() => _status = v);
            _list.currentState?.reload();
          }),
        ]),
        itemBuilder: (c, r, i) => RowTile(
          title: '#${r['payout_id']} · ${str(r['vendor_name'] ?? r['technician_name'])}',
          badge: StatusChip(r['status']),
          subtitle: '${inr(r['amount'], paise: true)} · gross ${inr(r['gross_amount'], paise: true)} · TDS ${inr(r['tds_amount'], paise: true)}',
          lines: ['Batch ${r['settlement_batch_id'] == null ? '—' : '#${r['settlement_batch_id']}'} · ${fmtDate(r['created_at'])}${r['reference_no'] != null ? ' · Ref ${r['reference_no']}' : ''}'],
          trailing: _can && r['status'] == 'PENDING'
              ? PopupMenuButton<String>(onSelected: (v) => _mark(r, v), itemBuilder: (_) => const [PopupMenuItem(value: 'PAID', child: Text('Mark paid')), PopupMenuItem(value: 'FAILED', child: Text('Mark failed'))])
              : null,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayoutTraceScreen(id: r['payout_id']))),
        ),
      ),
      floatingActionButton: _can ? FloatingActionButton.extended(heroTag: 'settle', onPressed: _settle, icon: const Icon(Icons.playlist_add_check), label: const Text('Run settlement')) : null,
    );
  }
}

class PayoutTraceScreen extends StatelessWidget {
  const PayoutTraceScreen({super.key, required this.id});
  final dynamic id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Payout #$id')),
      body: ApiLoader(
        load: () => api.get('$_f/payouts/$id/trace'),
        builder: (c, res, reload) {
          final d = res.map;
          final p = ApiRes.asMap(d['payout']);
          final meta = ApiRes.asMap(p['meta']);
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(title: str(p['technician_name'], 'Technician #${p['technician_id']}'), trailing: StatusChip(p['status']), children: [
              KV('Paid out', inr(p['amount'], paise: true), bold: true),
              KV('Commission', inr(p['commission_amount'], paise: true)),
              KV('TDS withheld', inr(p['tds_amount'], paise: true)),
              if (p['reference_no'] != null) KV('Reference', p['reference_no']),
              for (final e in meta.entries.where((e) => e.value is! Map && e.value is! List)) KV(humanize(e.key), e.value is num ? inr(e.value, paise: true) : e.value),
            ]),
            if (d['batch'] != null) ...[
              const Gap(),
              SectionCard(title: 'Settlement batch', children: [for (final e in ApiRes.asMap(d['batch']).entries.where((e) => e.value is! Map && e.value is! List)) KV(humanize(e.key), e.value)]),
            ],
            for (final b in ApiRes.asList(d['bookings'])) ...[
              const Gap(),
              SectionCard(
                title: str(b['booking_uid']),
                trailing: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: b['booking_id']))), child: const Text('Open')),
                children: [
                  for (final s in ApiRes.asList(b['services'])) KV('${s['service_name']} × ${s['quantity']}', inr(s['line_total'], paise: true)),
                  for (final e in ApiRes.asMap(b['commission']).entries.where((e) => e.value is! Map && e.value is! List)) KV('Commission · ${humanize(e.key)}', e.value is num ? inr(e.value, paise: true) : e.value),
                  for (final t in ApiRes.asList(b['tds'])) KV('TDS ${str(t['section_code'], '')}', inr(t['tds_amount'], paise: true)),
                  for (final w in ApiRes.asList(b['wallet_entries'])) KV('Wallet ${humanize(w['entry_type'])} · ${fmtDate(w['created_at'])}', '${inr(w['amount'], paise: true)} → ${inr(w['balance_after'], paise: true)}'),
                ],
              ),
            ],
            if (ApiRes.asList(d['wallet_entries']).where((w) => w['booking_id'] == null).isNotEmpty) ...[
              const Gap(),
              SectionCard(title: 'Wallet', children: [
                for (final w in ApiRes.asList(d['wallet_entries']).where((w) => w['booking_id'] == null))
                  KV('${humanize(w['entry_type'])} · ${fmtDate(w['created_at'])}', '${inr(w['amount'], paise: true)} → ${inr(w['balance_after'], paise: true)}'),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});
  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final _tech = TextEditingController();
  ApiRes? _res;
  bool _loading = false;

  Future<void> _run() async {
    setState(() => _loading = true);
    final r = await api.get('$_f/settlement-reconciliation', {'technicianId': _tech.text.trim()});
    if (mounted) {
      setState(() {
      _res = r;
      _loading = false;
    });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _res?.map ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Settlement reconciliation')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: TextField(controller: _tech, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Technician ID (optional)'))),
          const Gap(8),
          FilledButton(onPressed: _loading ? null : _run, child: Text(_loading ? 'Checking…' : 'Run checks')),
        ]),
        const Gap(),
        if (_res != null && !_res!.ok) Text(_res!.message, style: const TextStyle(color: C.red)),
        if (d.isNotEmpty) ...[
          Wrap(spacing: 8, children: [
            StatusChip(d['ok'] == true ? 'SUCCESS' : 'FAILED', label: d['ok'] == true ? 'Consistent' : '${d['errors']} error check(s)'),
            if ((toInt(d['warnings']) ?? 0) > 0) StatusChip('PENDING', label: '${d['warnings']} warning(s)'),
          ]),
          const Gap(8),
          Text('Pending settlement: ${ApiRes.asMap(d['pending']).entries.map((e) => '${e.value} ${humanize(e.key).toLowerCase()}').join(', ').isEmpty ? 'none' : ApiRes.asMap(d['pending']).entries.map((e) => '${e.value} ${humanize(e.key).toLowerCase()}').join(', ')}'),
          const Gap(8),
          for (final ch in ApiRes.asList(d['checks']))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon((toInt(ch['count']) ?? 0) > 0 || truthy(ch['failed']) ? Icons.warning_amber : Icons.check_circle, color: (toInt(ch['count']) ?? 0) > 0 || truthy(ch['failed']) ? (ch['severity'] == 'error' ? C.red : C.amber) : C.green),
                title: Text(str(ch['description'] ?? ch['code'])),
                subtitle: Text('${ch['count'] ?? 0} found'),
              ),
            ),
        ],
      ]),
    );
  }
}

// ─── Wallet ledger / failed payments ─────────────────────────────────────────

class WalletLedgerScreen extends StatefulWidget {
  const WalletLedgerScreen({super.key});
  @override
  State<WalletLedgerScreen> createState() => _WalletLedgerScreenState();
}

class _WalletLedgerScreenState extends State<WalletLedgerScreen> {
  final _list = GlobalKey<PagedListState>();
  String _type = 'combined';
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      searchHint: _type == 'customer' ? 'Customer ID' : (_type == 'technician' ? 'Technician ID' : null),
      fetch: (p, l, s) => api.get('$_f/wallet', {
        'ledgerType': _type,
        ..._rangeQ(_range),
        if (_type == 'customer') 'customerId': s,
        if (_type == 'technician') 'technicianId': s,
        'page': '$p',
        'limit': '$l',
      }),
      extract: (r) => ApiRes.asList(ApiRes.asMap(r.data)['ledger'] ?? r.data),
      header: Column(children: [
        FilterChips<String>(options: const {'combined': 'Combined', 'customer': 'Customer', 'technician': 'Technician'}, value: _type, onChanged: (v) {
          setState(() => _type = v);
          _list.currentState?.reload();
        }),
        RangeBar(range: _range, onChanged: (r) {
          setState(() => _range = r);
          _list.currentState?.reload();
        }),
      ]),
      itemBuilder: (c, r, i) => RowTile(
        title: '${humanize(r['entry_type'])} · ${inr(r['amount'], paise: true)}',
        subtitle: '${humanize(r['ledger_type'])} #${r['party_id']}',
        lines: [fmtDateTime(r['created_at'])],
        trailing: Icon(toNum(r['amount']) >= 0 ? Icons.arrow_downward : Icons.arrow_upward, color: toNum(r['amount']) >= 0 ? C.green : C.red),
      ),
    );
  }
}

class FailedPaymentsScreen extends StatefulWidget {
  const FailedPaymentsScreen({super.key});
  @override
  State<FailedPaymentsScreen> createState() => _FailedPaymentsScreenState();
}

class _FailedPaymentsScreenState extends State<FailedPaymentsScreen> {
  final _list = GlobalKey<PagedListState>();
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      limit: 50,
      searchHint: 'Payment ID or booking',
      fetch: (p, l, s) => api.get('$_f/failed-payments', {..._rangeQ(_range), 'search': s, 'limit': '$l', 'page': '$p'}),
      header: RangeBar(range: _range, onChanged: (r) {
        setState(() => _range = r);
        _list.currentState?.reload();
      }),
      empty: 'No failed transactions.',
      itemBuilder: (c, r, i) => RowTile(
        title: '${inr(r['amount'], paise: true)} · ${str(r['booking_uid'])}',
        badge: StatusChip(r['status'] ?? 'FAILED'),
        subtitle: 'Payment ${str(r['payment_id'])} · ${str(r['gateway_type'])}',
        lines: [fmtDateTime(r['created_at']), str(r['error_message'] ?? r['message'], '')],
      ),
    );
  }
}

// ─── Financial reports ───────────────────────────────────────────────────────

const _reportTypes = {
  'revenue': 'Revenue', 'gst': 'GST', 'tds': 'TDS', 'settlements': 'Settlements', 'commissions': 'Commissions', 'wallet': 'Wallet ledger',
  'payouts': 'Payouts', 'refunds': 'Refunds', 'failed': 'Failed payments', 'invoices': 'Invoices',
};
const _reportPath = {
  'revenue': 'revenue', 'gst': 'gst', 'tds': 'tds', 'settlements': 'settlements', 'commissions': 'commissions', 'wallet': 'wallet',
  'payouts': 'payouts', 'refunds': 'refunds', 'failed': 'failed-payments', 'invoices': 'invoices',
};

class FinanceReportsScreen extends StatefulWidget {
  const FinanceReportsScreen({super.key, this.initial = 'gst'});
  final String initial;
  @override
  State<FinanceReportsScreen> createState() => _FinanceReportsScreenState();
}

class _FinanceReportsScreenState extends State<FinanceReportsScreen> {
  late String _type = widget.initial;
  DateTimeRange? _range;
  final _list = GlobalKey<PagedListState>();

  List<Map<String, dynamic>> _extract(ApiRes r) {
    final d = r.data;
    if (d is List) return ApiRes.asList(d);
    final m = ApiRes.asMap(d);
    for (final k in const ['rows', 'ledger', 'batches', 'gateway']) {
      if (m[k] is List) return ApiRes.asList(m[k]);
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      fetch: (p, l, s) => api.get('$_f/${_reportPath[_type]}', {..._rangeQ(_range), 'page': '$p', 'limit': '$l', if (_type == 'tds') 'sync': 'true'}),
      extract: _extract,
      header: Column(children: [
        FilterChips<String>(options: _reportTypes, value: _type, onChanged: (v) {
          setState(() => _type = v);
          _list.currentState?.reload();
        }),
        RangeBar(range: _range, onChanged: (r) {
          setState(() => _range = r);
          _list.currentState?.reload();
        }),
      ]),
      itemBuilder: (c, r, i) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (final e in r.entries.where((e) => e.value is! Map && e.value is! List))
              KV(humanize(e.key), e.key.contains('amount') || e.key.contains('total') || e.key.contains('revenue') || e.key.contains('gst') || e.key == 'tds'
                  ? inr(e.value, paise: true)
                  : (e.key.endsWith('_at') || e.key.contains('date') ? fmtDateTime(e.value) : e.value)),
          ]),
        ),
      ),
    );
  }
}
