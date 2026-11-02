import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'booking_detail_screen.dart';

const _filters = {'OPEN,UNDER_REVIEW': 'Needs action', 'WAITING_CUSTOMER,WAITING_TECHNICIAN': 'Waiting', 'RESOLVED,REJECTED': 'Decided', 'CLOSED': 'Closed', '': 'All'};
const _actionLabel = {
  'review': 'Start review', 'request_customer': 'Ask customer', 'request_technician': 'Ask technician',
  'resolve': 'Resolve', 'reject': 'Reject', 'close': 'Close', 'note': 'Add internal note',
};
const _finalActions = {
  'resolve': 'The chosen resolution is applied (a refund is sent for approval if you picked one) and the customer is told.',
  'reject': 'The customer is told the complaint was not upheld.',
  'close': 'The complaint is closed and no further action can be taken on it.',
};
const _resolutionHint = {
  'NO_ACTION': 'Upheld without compensation',
  'REFUND': 'Raises a PENDING refund request for Finance to approve',
  'REVISIT': 'Creates an approved goodwill revisit (warranty claim)',
  'WARRANTY_CLAIM': 'Creates an approved warranty claim (service must be under warranty)',
  'OTHER': 'Anything else — describe it in the note',
};

/// Complaints / disputes — GET /admin/bookings/disputes, actions via
/// POST /admin/bookings/disputes/:id/:action.
class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});
  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  final _list = GlobalKey<PagedListState>();
  String _filter = 'OPEN,UNDER_REVIEW';

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      fetch: (p, l, s) => api.get('/admin/bookings/disputes', {'status': _filter, 'page': p, 'limit': l}),
      empty: 'No disputes.',
      header: FilterChips<String>(options: _filters, value: _filter, onChanged: (v) {
        setState(() => _filter = v);
        _list.currentState?.reload();
      }),
      itemBuilder: (c, r, i) => RowTile(
        title: '${str(r['dispute_uid'], '#${r['dispute_id']}')} · ${str(r['category'], 'General')}',
        badge: StatusChip(r['status']),
        subtitle: 'Booking ${str(r['booking_uid'], '#${r['booking_id']}')} · by ${str(r['raised_by'], '').toLowerCase()}',
        lines: ['${str(r['customer_name'])} / ${str(r['technician_name'])}', fmtDateTime(r['created_at'])],
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => DisputeDetailScreen(id: r['dispute_id'])));
          _list.currentState?.reload();
        },
      ),
    );
  }
}

class DisputeDetailScreen extends StatefulWidget {
  const DisputeDetailScreen({super.key, required this.id});
  final dynamic id;
  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  final _key = GlobalKey<ApiLoaderState>();
  final _note = TextEditingController();
  final _refund = TextEditingController();
  String _resolution = 'NO_ACTION';

  bool get _canEdit => Session.I.canOn('/admin/booking-management/disputes', 'EDIT');

  Future<void> _act(Map<String, dynamic> d, String action) async {
    final needsNote = const ['request_customer', 'request_technician', 'reject', 'resolve', 'note'].contains(action);
    if (needsNote && _note.text.trim().isEmpty) {
      toast('Note is required for this action', error: true);
      return;
    }
    if (_finalActions.containsKey(action) &&
        !await confirm(context, '${_actionLabel[action]}?', message: _finalActions[action], ok: _actionLabel[action]!, danger: action != 'resolve')) {
      return;
    }
    if (!mounted) return;
    final body = <String, dynamic>{'note': _note.text.trim()};
    if (action == 'resolve') {
      body['resolutionType'] = _resolution;
      if (_resolution == 'REFUND' && _refund.text.isNotEmpty) body['refundAmount'] = double.tryParse(_refund.text);
    }
    final res = await busy(context, () => api.post('/admin/bookings/disputes/${d['dispute_id']}/$action', body), toastIt: false);
    if (res.ok) {
      final data = res.map;
      final extra = data['refund'] != null
          ? ' · refund ₹${ApiRes.asMap(data['refund'])['amount']} pending approval'
          : data['warranty_claim'] != null
              ? ' · claim ${ApiRes.asMap(data['warranty_claim'])['claim_uid']}'
              : data['warranty_error'] != null
                  ? ' · ${data['warranty_error']}'
                  : '';
      toast('${_actionLabel[action]} done$extra');
      _note.clear();
      _key.currentState?.reload();
    } else {
      toastRes(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint')),
      body: ApiLoader(
        key: _key,
        load: () => api.get('/admin/bookings/disputes/${widget.id}'),
        builder: (context, res, reload) {
          final det = res.map;
          final d = ApiRes.asMap(det['dispute']);
          final booking = ApiRes.asMap(det['booking']);
          final bal = ApiRes.asMap(det['balance']);
          final actions = List<String>.from((det['allowed_actions'] as List?) ?? const []);
          final types = List<String>.from((det['resolution_types'] as List?) ?? _resolutionHint.keys);
          if (!types.contains(_resolution) && types.isNotEmpty) _resolution = types.first;
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(
              title: str(d['dispute_uid'], 'Dispute #${d['dispute_id']}'),
              trailing: StatusChip(d['status']),
              children: [
                KV('Category', d['category'] ?? 'General'),
                if (d['requested_resolution'] != null) KV('Customer wants', humanize(d['requested_resolution'])),
                KV('Raised by', humanize(d['raised_by'])),
                KV('Raised', fmtDateTime(d['created_at'])),
                const Gap(6),
                const Text('Customer complaint', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(str(d['description']), style: const TextStyle(color: C.body)),
                if ((d['media'] as List?)?.isNotEmpty == true) ...[
                  const Gap(8),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final m in d['media']) NetImage(m, size: 72)]),
                ],
                if (d['resolution'] != null) ...[const Gap(6), Text('Resolution: ${humanize(d['resolution_type'])} — ${d['resolution']}', style: const TextStyle(color: C.green))],
              ],
            ),
            const Gap(),
            SectionCard(title: 'Booking', children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(str(booking['booking_uid'], '#${d['booking_id']}'), style: const TextStyle(color: C.primary, fontWeight: FontWeight.w700)),
                subtitle: Text('Status ${str(booking['booking_status_id'])} · completed ${fmtDateTime(booking['completed_at'])}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: d['booking_id']))),
              ),
              KV('Customer', d['customer_name']),
              KV('Technician', d['technician_name']),
              if ((booking['completion_photo_urls'] as List?)?.isNotEmpty == true) ...[
                const Text('Completion evidence', style: TextStyle(fontWeight: FontWeight.w600)),
                const Gap(6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in booking['completion_photo_urls']) NetImage(m, size: 64),
                  if (booking['customer_signature_url'] != null) NetImage(booking['customer_signature_url'], size: 64, label: 'Signature'),
                ]),
              ],
            ]),
            const Gap(),
            SectionCard(title: 'Money', children: [
              if (bal.isNotEmpty) ...[KV('Total', inr(bal['total'], paise: true)), KV('Paid', inr(bal['paid'], paise: true)), KV('Due', inr(bal['due'], paise: true))],
              for (final p in ApiRes.asList(det['payments'])) KV('Payment #${p['payment_id']} ${str(p['payment_type'], '')}', '${inr(p['amount'], paise: true)} · ${fmtDate(p['paid_at'])}'),
              for (final r in ApiRes.asList(det['refunds']))
                KV('Refund #${r['refund_id']}', '${inr(r['amount'], paise: true)} · ${r['refund_status_id'] == 'P' ? 'pending approval' : r['refund_status_id'] == 'A' ? 'approved' : 'rejected'}', color: C.amber),
              KV('Invoice', det['invoice'] == null ? 'not generated' : '${ApiRes.asMap(det['invoice'])['invoice_number']} · ${inr(ApiRes.asMap(det['invoice'])['amount'], paise: true)}'),
            ]),
            if (ApiRes.asList(det['chat']).isNotEmpty) ...[
              const Gap(),
              SectionCard(title: 'Chat (last ${ApiRes.asList(det['chat']).length})', children: [
                for (final m in ApiRes.asList(det['chat']))
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${str(m['sender_type'], '?')}: ${str(m['message'] ?? m['body'], '')}', style: const TextStyle(fontSize: 13))),
              ]),
            ],
            const Gap(),
            SectionCard(title: 'History', children: [
              for (final e in ApiRes.asList(d['events']))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${fmtDateTime(e['at'])} · ${humanize(e['event'])} by ${str(e['actor'])}${truthy(e['internal']) ? ' (internal)' : ''}${e['note'] != null ? '\n${e['note']}' : ''}', style: const TextStyle(fontSize: 12.5)),
                ),
            ]),
            if (_canEdit && actions.isNotEmpty) ...[
              const Gap(),
              SectionCard(title: 'Take action', children: [
                TextField(controller: _note, maxLines: 3, minLines: 2, decoration: const InputDecoration(labelText: 'Note (required for info requests, reject and resolve)')),
                if (actions.contains('resolve')) ...[
                  const Gap(10),
                  const Text('Resolution', style: TextStyle(fontWeight: FontWeight.w600)),
                  StatefulBuilder(builder: (c, set) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, children: [
                        for (final t in types) ChoiceChip(label: Text(humanize(t)), selected: _resolution == t, onSelected: (_) => set(() => _resolution = t)),
                      ]),
                      Text(_resolutionHint[_resolution] ?? '', style: const TextStyle(fontSize: 12, color: C.muted)),
                      if (_resolution == 'REFUND')
                        TextField(controller: _refund, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Refund amount (max ${inr(bal['paid'], paise: true)})')),
                    ]);
                  }),
                ],
                const Gap(10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in actions)
                    a == 'reject' || a == 'note'
                        ? OutlinedButton(onPressed: () => _act(d, a), child: Text(_actionLabel[a] ?? humanize(a)))
                        : FilledButton(onPressed: () => _act(d, a), child: Text(_actionLabel[a] ?? humanize(a))),
                ]),
              ]),
            ],
            const Gap(40),
          ]);
        },
      ),
    );
  }
}
