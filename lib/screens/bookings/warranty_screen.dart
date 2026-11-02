import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'booking_detail_screen.dart';

const _filters = {
  '': 'All', 'SUBMITTED,UNDER_REVIEW': 'Needs review', 'APPROVED,ASSIGNED,REVISIT_SCHEDULED,IN_PROGRESS': 'In revisit', 'RESOLVED': 'Resolved', 'REJECTED,CLOSED': 'Closed',
};
const _actionLabel = {
  'review': 'Start review', 'approve': 'Approve', 'reject': 'Reject', 'assign': 'Assign technician', 'schedule': 'Schedule revisit',
  'start': 'Mark in progress', 'resolve': 'Mark resolved', 'close': 'Close',
};
const _finalActions = {
  'reject': 'The customer is told the warranty claim was not approved.',
  'resolve': 'The claim is marked resolved and the customer is told.',
  'close': 'The claim is closed and no further action can be taken on it.',
};

/// Warranty claims — review, approve/reject, assign a revisit technician,
/// schedule, follow through to closure.
class WarrantyClaimsScreen extends StatefulWidget {
  const WarrantyClaimsScreen({super.key});
  @override
  State<WarrantyClaimsScreen> createState() => _WarrantyClaimsScreenState();
}

class _WarrantyClaimsScreenState extends State<WarrantyClaimsScreen> {
  final _list = GlobalKey<PagedListState>();
  String _filter = 'SUBMITTED,UNDER_REVIEW';

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      fetch: (p, l, s) => api.get('/admin/bookings/warranty-claims', {'status': _filter, 'page': p, 'limit': l}),
      empty: 'No claims.',
      header: FilterChips<String>(options: _filters, value: _filter, onChanged: (v) {
        setState(() => _filter = v);
        _list.currentState?.reload();
      }),
      itemBuilder: (c, r, i) => RowTile(
        title: '${str(r['claim_uid'])} · ${str(r['issue_label'])}',
        badge: StatusChip(r['status']),
        subtitle: '${str(r['booking_uid'], '#${r['booking_id']}')} · ${str(r['service_name'])}',
        lines: [
          'Technician: ${str(r['assigned_technician_name'] ?? r['original_technician_name'])}',
          'Warranty till ${fmtDate(r['warranty_expires_at'])} · raised ${fmtDate(r['created_at'])}',
        ],
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => WarrantyClaimDetailScreen(id: r['claim_id'])));
          _list.currentState?.reload();
        },
      ),
    );
  }
}

class WarrantyClaimDetailScreen extends StatefulWidget {
  const WarrantyClaimDetailScreen({super.key, required this.id});
  final dynamic id;
  @override
  State<WarrantyClaimDetailScreen> createState() => _WarrantyClaimDetailScreenState();
}

class _WarrantyClaimDetailScreenState extends State<WarrantyClaimDetailScreen> {
  final _key = GlobalKey<ApiLoaderState>();
  final _note = TextEditingController();
  final _reason = TextEditingController();
  final _resolution = TextEditingController();
  int? _tech;
  DateTime? _revisitAt;
  List<Map<String, dynamic>> _techs = [];

  bool get _canEdit => Session.I.canOn('/admin/booking-management/warranty-claims', 'EDIT');

  Future<ApiRes> _load() async {
    final res = await api.get('/admin/bookings/warranty-claims/${widget.id}');
    if (res.ok) {
      final c = ApiRes.asMap(res.map['claim']);
      final t = await api.get('/admin/bookings/${c['booking_id']}/city-technicians', {'serviceId': c['service_id']});
      _techs = t.ok ? t.list : [];
      _tech ??= toInt(c['assigned_technician_id']);
    }
    return res;
  }

  Future<void> _act(Map c, String action) async {
    if (action == 'reject' && _reason.text.trim().isEmpty) return toast('Rejection reason is required', error: true);
    if (action == 'resolve' && _resolution.text.trim().isEmpty) return toast('Describe what was done', error: true);
    if (action == 'assign' && _tech == null) return toast('Select a technician', error: true);
    if (action == 'schedule' && _revisitAt == null) return toast('Pick the revisit time', error: true);
    if (_finalActions.containsKey(action) && !await confirm(context, '${_actionLabel[action]}?', message: _finalActions[action], ok: _actionLabel[action]!, danger: action == 'reject')) return;
    if (!mounted) return;
    final body = switch (action) {
      'reject' => {'reason': _reason.text.trim()},
      'assign' => {'technicianId': _tech},
      'schedule' => {'revisitAt': _revisitAt!.toUtc().toIso8601String()},
      'resolve' => {'resolution': _resolution.text.trim()},
      _ => {if (_note.text.trim().isNotEmpty) 'note': _note.text.trim()},
    };
    final res = await busy(context, () => api.post('/admin/bookings/warranty-claims/${c['claim_id']}/$action', body), success: '${c['claim_uid']}: ${_actionLabel[action] ?? action}');
    if (res.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Warranty claim')),
      body: ApiLoader(
        key: _key,
        load: _load,
        builder: (context, res, reload) {
          final det = res.map;
          final c = ApiRes.asMap(det['claim']);
          final ob = ApiRes.asMap(det['original_booking']);
          final actions = List<String>.from((det['allowed_actions'] as List?) ?? const []);
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(title: str(c['claim_uid']), trailing: StatusChip(c['status']), children: [
              KV('Issue', c['issue_label']),
              KV('Service', c['service_name']),
              KV('Customer', '${str(c['customer_name'])} ${str(c['customer_mobile'], '')}'),
              KV('Completed', fmtDateTime(c['service_completed_at'])),
              KV('Warranty', '${c['warranty_days'] ?? '-'} days · till ${fmtDate(c['warranty_expires_at'])}'),
              KV('Preferred revisit', fmtDateTime(c['preferred_revisit_at'])),
              KV('Original technician', c['original_technician_name']),
              KV('Revisit technician', c['assigned_technician_name']),
              KV('Revisit', fmtDateTime(c['revisit_scheduled_at'])),
              KV('Raised', fmtDateTime(c['created_at'])),
              const Gap(6),
              Text(str(c['description'], ''), style: const TextStyle(color: C.body)),
              if (c['customer_comments'] != null) Text('Customer: ${c['customer_comments']}', style: const TextStyle(color: C.body)),
              if ((c['media'] as List?)?.isNotEmpty == true) ...[const Gap(8), Wrap(spacing: 8, runSpacing: 8, children: [for (final m in c['media']) NetImage(m)])],
              if (c['review_note'] != null) Text('Review note: ${c['review_note']}', style: const TextStyle(fontSize: 12.5)),
              if (c['rejection_reason'] != null) Text('Rejected: ${c['rejection_reason']}', style: const TextStyle(color: C.red)),
              if (c['resolution'] != null) Text('Resolution: ${c['resolution']}', style: const TextStyle(color: C.green)),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: c['booking_id']))),
                child: Text('Original booking ${str(ob['booking_uid'], '#${c['booking_id']}')}'),
              ),
            ]),
            if (ApiRes.asList(det['previous_claims']).isNotEmpty) ...[
              const Gap(),
              SectionCard(title: 'Previous claims by this customer', children: [
                for (final p in ApiRes.asList(det['previous_claims'])) KV('${p['claim_uid']} · ${str(p['issue_label'])}', StatusChip(p['status'])),
              ]),
            ],
            if (_canEdit && actions.isNotEmpty) ...[
              const Gap(),
              StatefulBuilder(builder: (ctx, set) {
                return SectionCard(title: 'Take action', children: [
                  if (actions.contains('reject')) ...[TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Rejection reason (required to reject)')), const Gap(8)],
                  if (actions.contains('assign')) ...[
                    InkWell(
                      onTap: () async {
                        final v = await pickOne<int>(context, 'Revisit technician', {
                          for (final t in _techs) toInt(t['technician_id'])!: '${t['name']}${truthy(t['is_online']) ? '' : ' (offline)'}${t['is_eligible'] == false ? ' · not eligible' : ''}',
                        }, selected: _tech);
                        if (v != null) set(() => _tech = v);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Revisit technician', suffixIcon: Icon(Icons.expand_more)),
                        child: Text(_tech == null ? 'Select technician' : str(_techs.firstWhere((t) => toInt(t['technician_id']) == _tech, orElse: () => {'name': '#$_tech'})['name'])),
                      ),
                    ),
                    const Gap(8),
                  ],
                  if (actions.contains('schedule')) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(_revisitAt == null ? 'Pick revisit date & time' : fmtDateTime(_revisitAt)),
                      onPressed: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
                        if (d == null || !context.mounted) return;
                        final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
                        set(() => _revisitAt = DateTime(d.year, d.month, d.day, t?.hour ?? 10, t?.minute ?? 0));
                      },
                    ),
                    const Gap(8),
                  ],
                  if (actions.contains('resolve')) ...[TextField(controller: _resolution, decoration: const InputDecoration(labelText: 'What was done (required to resolve)')), const Gap(8)],
                  if (actions.contains('review') || actions.contains('approve') || actions.contains('close')) ...[
                    TextField(controller: _note, decoration: const InputDecoration(labelText: 'Internal note (optional)')),
                    const Gap(8),
                  ],
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final a in actions)
                      a == 'reject' ? OutlinedButton(onPressed: () => _act(c, a), child: Text(_actionLabel[a] ?? humanize(a))) : FilledButton(onPressed: () => _act(c, a), child: Text(_actionLabel[a] ?? humanize(a))),
                  ]),
                ]);
              }),
            ],
            const Gap(40),
          ]);
        },
      ),
    );
  }
}
