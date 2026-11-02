import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../bookings/booking_detail_screen.dart';

// ─── SLA monitor ─────────────────────────────────────────────────────────────

const _slaTypes = {
  '': 'All types', 'UNASSIGNED': 'Unassigned', 'DISPATCH_TIMEOUT': 'Dispatch timeout', 'ACCEPTANCE_TIMEOUT': 'Acceptance timeout', 'DELAYED_ARRIVAL': 'Delayed arrival',
  'OVERDUE_JOB': 'Overdue jobs', 'INCOMPLETE_JOB': 'Incomplete jobs', 'CASH_PENDING': 'Cash pending', 'PAYMENT_PENDING': 'Payment pending',
  'REFUND_PENDING': 'Refund pending', 'PAYOUT_PENDING': 'Payout pending',
};
const _policyFields = {
  'assignment_minutes': 'Assign within', 'acceptance_minutes': 'Accept within', 'arrival_grace_minutes': 'Arrive within (after slot)',
  'completion_minutes': 'Complete within', 'payment_minutes': 'Collect payment within', 'refund_minutes': 'Refund within',
  'payout_minutes': 'Pay out within', 'warning_percent': 'At-risk at (% of window)',
};

String _dur(dynamic minutes) {
  final m = toInt(minutes);
  if (m == null) return '—';
  final a = m.abs();
  if (a < 60) return '${a}m';
  if (a < 1440) return '${a ~/ 60}h ${a % 60}m';
  return '${a ~/ 1440}d ${(a % 1440) ~/ 60}h';
}

class SlaMonitorScreen extends StatefulWidget {
  const SlaMonitorScreen({super.key});
  @override
  State<SlaMonitorScreen> createState() => _SlaMonitorScreenState();
}

class _SlaMonitorScreenState extends State<SlaMonitorScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = 'attention';
  String _type = '';
  Map<String, dynamic> _head = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _list.currentState?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<ApiRes> _fetch(int p, int l, String s) async {
    final r = await api.get('/admin/bookings/sla/queue', {'type': _type, 'status': _status, 'page': '$p', 'limit': '$l'});
    if (r.ok && p == 1 && mounted) setState(() => _head = r.map);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        limit: 25,
        fetch: _fetch,
        header: Column(children: [
          if (_head.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                Expanded(child: StatTile(label: 'Breached', value: '${_head['breached'] ?? 0}', icon: Icons.error_outline, color: C.red)),
                const Gap(8),
                Expanded(child: StatTile(label: 'At risk', value: '${_head['at_risk'] ?? 0}', icon: Icons.warning_amber, color: C.amber)),
              ]),
            ),
          FilterChips<String>(options: const {'attention': 'Needs attention', 'BREACHED': 'Breached', 'AT_RISK': 'At risk', 'ON_TRACK': 'On track', 'all': 'All open'}, value: _status, onChanged: (v) {
            setState(() => _status = v);
            _list.currentState?.reload();
          }),
          FilterChips<String>(options: _slaTypes, value: _type, onChanged: (v) {
            setState(() => _type = v);
            _list.currentState?.reload();
          }),
        ]),
        empty: 'Nothing needs attention.',
        itemBuilder: (c, r, i) {
          final over = (toInt(r['overdue_minutes']) ?? 0) > 0;
          return RowTile(
            title: '${str(r['label'] ?? _slaTypes[r['type']])} · ${str(r['booking_uid'] ?? (r['refund_id'] != null ? 'Refund #${r['refund_id']}' : 'Payout #${r['payout_id']}'))}',
            badge: StatusChip(r['status']),
            subtitle: [r['customer_name'], r['technician_name'], r['area_name']].where((e) => e != null).join(' · '),
            lines: [
              'Severity ${humanize(r['severity'])}${r['priority'] != null ? ' · ${humanize(r['priority'])} priority' : ''}${r['amount'] != null ? ' · ${inr(r['amount'])}' : ''}',
              over ? 'Overdue by ${_dur(r['overdue_minutes'])} (due ${fmtDateTime(r['due_at'])})' : 'Time left ${_dur(r['remaining_minutes'])} · elapsed ${_dur(r['elapsed_minutes'])}',
            ],
            onTap: r['booking_id'] == null ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: r['booking_id']))),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'slapol',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SlaPoliciesScreen())),
        icon: const Icon(Icons.tune),
        label: const Text('SLA policies'),
      ),
    );
  }
}

class SlaPoliciesScreen extends StatefulWidget {
  const SlaPoliciesScreen({super.key});
  @override
  State<SlaPoliciesScreen> createState() => _SlaPoliciesScreenState();
}

class _SlaPoliciesScreenState extends State<SlaPoliciesScreen> {
  final _key = GlobalKey<ApiLoaderState>();
  final _ctl = <String, TextEditingController>{};

  @override
  Widget build(BuildContext context) {
    final canEdit = Session.I.canOn('/admin/operations/sla', 'EDIT');
    return Scaffold(
      appBar: AppBar(title: const Text('SLA policies (minutes)')),
      body: ApiLoader(
        key: _key,
        load: () => api.get('/admin/bookings/sla/policies'),
        builder: (c, res, reload) => ListView(padding: const EdgeInsets.all(12), children: [
          for (final p in res.list) ...[
            SectionCard(title: '${humanize(p['priority'])} priority', children: [
              for (final f in _policyFields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _ctl.putIfAbsent('${p['priority']}.${f.key}', () => TextEditingController(text: '${p[f.key] ?? ''}')),
                    enabled: canEdit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: f.value),
                  ),
                ),
              if (canEdit)
                FilledButton(
                  onPressed: () async {
                    final payload = <String, dynamic>{};
                    for (final f in _policyFields.keys) {
                      final v = _ctl['${p['priority']}.$f']!.text.trim();
                      if (v.isNotEmpty && v != '${p[f] ?? ''}') payload[f] = num.tryParse(v);
                    }
                    if (payload.isEmpty) return toast('No changes');
                    final r = await busy(context, () => api.put('/admin/bookings/sla/policies/${p['priority']}', payload), success: 'SLA policy "${p['priority']}" saved');
                    if (r.ok) reload();
                  },
                  child: const Text('Save'),
                ),
            ]),
            const Gap(),
          ],
        ]),
      ),
    );
  }
}

// ─── Audit logs ──────────────────────────────────────────────────────────────

class AuditLogsScreen extends StatelessWidget {
  const AuditLogsScreen({super.key});

  String _pretty(dynamic v) {
    if (v == null) return '—';
    try {
      final o = v is String ? jsonDecode(v) : v;
      return const JsonEncoder.withIndent('  ').convert(o);
    } catch (_) {
      return '$v';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PagedList(
      fetch: (p, l, s) => api.get('/admin/audit/logs', {'page': p, 'limit': l}),
      itemBuilder: (c, r, i) => RowTile(
        leading: const Icon(Icons.history, color: C.primary),
        title: str(r['action_label'] ?? humanize(r['action_type'])),
        subtitle: '${str(r['actor_name'])} · ${str(r['target_entity'], '')}',
        lines: ['${fmtDateTime(r['created_at'])} · ${str(r['ip_address'], '')}'],
        onTap: () => showModalBottomSheet(
          context: c,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (s) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .7,
            builder: (s, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
              Text(str(r['action_label'] ?? r['action_type']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Gap(8),
              KV('Admin', r['actor_name']),
              KV('Email', r['actor_email'] ?? r['email']),
              KV('Time', fmtDateTime(r['created_at'])),
              KV('IP address', r['ip_address']),
              KV('Action type', r['action_type']),
              KV('Target entity', r['target_entity']),
              KV('User agent', r['user_agent']),
              const Gap(8),
              const Text('Previous value', style: TextStyle(fontWeight: FontWeight.w600)),
              Container(padding: const EdgeInsets.all(8), color: C.bg, child: SelectableText(_pretty(r['previous_value']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
              const Gap(8),
              const Text('New value', style: TextStyle(fontWeight: FontWeight.w600)),
              Container(padding: const EdgeInsets.all(8), color: C.bg, child: SelectableText(_pretty(r['new_value']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Reports hub (/admin/reports/:id/export) ─────────────────────────────────

const _reports = [
  ('Financial Reports', [
    ('revenue', 'Revenue Report', 'Total revenue, collections and payouts by date range', ['csv', 'xlsx', 'pdf']),
    ('transactions', 'Transaction Report', 'All payment gateway transactions with status', ['csv', 'xlsx', 'pdf']),
    ('commissions', 'Commission Report', 'Technician commission breakdowns and settlements', ['csv', 'xlsx', 'pdf']),
    ('taxes', 'Tax Report', 'GST and tax collected across all bookings', ['csv', 'xlsx', 'pdf']),
    ('refunds', 'Refund Report', 'All refunds issued with reasons and amounts', ['csv', 'xlsx', 'pdf']),
  ]),
  ('Booking Reports', [
    ('all-bookings', 'All Bookings', 'Complete booking list with all details and status', ['csv', 'xlsx', 'pdf']),
    ('bookings-by-status', 'Bookings by Status', 'Bookings grouped and filtered by current status', ['csv', 'xlsx']),
    ('bookings-by-service', 'Bookings by Service', 'Service-wise booking count and revenue summary', ['csv', 'xlsx', 'pdf']),
  ]),
  ('User & Technician Reports', [
    ('customers', 'Customer Report', 'All registered customers with booking activity', ['csv', 'xlsx', 'pdf']),
    ('technicians', 'Technician Report', 'Technician profiles, earnings and ratings', ['csv', 'xlsx', 'pdf']),
  ]),
  ('Operations Reports', [
    ('audit-logs', 'Audit Log Report', 'All admin actions with timestamps and IP addresses', ['csv', 'xlsx']),
    ('login-activity', 'Login Activity', 'Admin login/logout history and access events', ['csv', 'xlsx']),
  ]),
];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
  String? _busy;

  Future<void> _export(String id, String format) async {
    if (!Session.I.can('REPORTS_EXPORT') && !Session.I.canOn('/admin/reports', 'EXPORT')) return toast('You don’t have export permission', error: true);
    setState(() => _busy = '$id-$format');
    final bytes = await api.download('/admin/reports/$id/export', {'format': format, 'from': ymd(_range.start), 'to': ymd(_range.end)});
    if (!mounted) return;
    setState(() => _busy = null);
    if (bytes == null) return toast('Export failed', error: true);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$id-${ymd(_range.start)}-to-${ymd(_range.end)}.$format');
    await file.writeAsBytes(bytes);
    final r = await OpenFilex.open(file.path);
    if (r.type != ResultType.done) toast('Saved to ${file.path} (no app to open .$format)');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.date_range, color: C.primary),
          title: const Text('Date range — applied to all exports'),
          subtitle: Text('${fmtDate(_range.start)} – ${fmtDate(_range.end)}'),
          onTap: () async {
            final r = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now(), initialDateRange: _range);
            if (r != null) setState(() => _range = r);
          },
        ),
      ),
      for (final g in _reports) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text(g.$1.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted))),
        for (final r in g.$2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SectionCard(title: r.$2, children: [
              Text(r.$3, style: const TextStyle(color: C.body, fontSize: 12.5)),
              const Gap(8),
              Wrap(spacing: 8, children: [
                for (final f in r.$4)
                  OutlinedButton.icon(
                    onPressed: _busy != null ? null : () => _export(r.$1, f),
                    icon: _busy == '${r.$1}-$f' ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download, size: 16),
                    label: Text(f == 'xlsx' ? 'Excel' : f.toUpperCase()),
                  ),
              ]),
            ]),
          ),
      ],
    ]);
  }
}
