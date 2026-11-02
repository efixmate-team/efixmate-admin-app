import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../users/customer_detail_screen.dart';
import 'bookings_screen.dart';
import 'disputes_screen.dart';
import 'track_screen.dart';
import 'warranty_screen.dart';

const _terminal = {'X': 'cancelled', 'F': 'failed', 'R': 'refunded', 'N': 'no_service'};

/// Same rule as the web bookingView.bookingPhase(): a terminal value in
/// either status field wins.
String bookingPhase(Map b) {
  final s = str(b['booking_status_id'], '');
  final l = str(b['lifecycle_state'], '');
  if (_terminal.containsKey(s)) return _terminal[s]!;
  if (l == 'CANCELLED') return 'cancelled';
  if (l == 'FAILED') return 'failed';
  if (s == 'D' || l == 'COMPLETED') return 'completed';
  return 'active';
}

const _steps = [
  ('Confirmed', ['CREATED', 'PAYMENT_PENDING', 'PAYMENT_COMPLETED'], ['P', 'C', 'B']),
  ('Assigned', ['ASSIGNED', 'ACCEPTED'], ['A']),
  ('On the way', ['TECHNICIAN_ARRIVING'], ['O', 'V']),
  ('Started', ['STARTED', 'PAUSED', 'RESUMED', 'PARTIALLY_COMPLETED'], ['S', 'I', 'K']),
  ('Completed', ['COMPLETED'], ['D']),
];

/// GET /admin/bookings/:id/overview — every panel and action of the web
/// Booking Details page.
class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.id});
  final dynamic id;
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  static const path = '/admin/booking-management/bookings';
  Map<String, dynamic>? _d;
  String? _error;
  Timer? _poll;
  final _selectedItems = <int>{};

  int get _id => toInt(widget.id) ?? 0;
  bool get _canEdit => Session.I.canOn(path, 'EDIT');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await api.get('/admin/bookings/$_id/overview');
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _d = res.map;
        _error = null;
      } else {
        _error = res.message.isEmpty ? 'Failed to load booking' : res.message;
      }
    });
    // Poll quietly while a technician still has to accept an offer.
    final awaiting = _items.any((it) => it['technician_id'] != null && it['technician_accepted_at'] == null && it['item_status'] != 'COMPLETED' && (toInt(it['response_seconds_left']) ?? 0) > 0);
    _poll?.cancel();
    if (awaiting) _poll = Timer(const Duration(seconds: 10), _load);
  }

  Map<String, dynamic> get _b => ApiRes.asMap(_d?['booking']);
  List<Map<String, dynamic>> get _items => ApiRes.asList(_d?['items']);
  List<Map<String, dynamic>> get _visits => ApiRes.asList(_d?['technicianVisits']);

  String get _phase => bookingPhase(_b);
  bool get _canAssign => _canEdit && _phase == 'active';

  /// Technicians actually working the job, rolled up from per-item assignments.
  List<Map<String, dynamic>> get _techs {
    final byId = <int, Map<String, dynamic>>{};
    for (final it in _items) {
      final tid = toInt(it['technician_id']);
      if (tid == null) continue;
      final t = byId.putIfAbsent(tid, () {
        final visit = _visits.firstWhere((v) => toInt(v['technician_id']) == tid, orElse: () => {});
        final stage = visit['completed_at'] != null
            ? 'Completed'
            : visit['started_at'] != null
                ? 'Started'
                : visit['arrived_at'] != null
                    ? 'Arrived'
                    : visit['on_the_way_at'] != null
                        ? 'On the way'
                        : 'Assigned';
        return {'technician_id': tid, 'name': str(it['item_technician_name'], 'Technician #$tid'), 'mobile': it['item_technician_mobile'], 'visit': visit, 'stage': stage, 'open': <int>[], 'count': 0, 'accepted': 0};
      });
      t['count'] = (t['count'] as int) + 1;
      if (it['item_status'] != 'COMPLETED') (t['open'] as List<int>).add(toInt(it['item_id'])!);
      if (it['technician_accepted_at'] != null) t['accepted'] = (t['accepted'] as int) + 1;
    }
    return byId.values.toList();
  }

  String? get _paymentState {
    final fromBooking = _b['payment_status_name'];
    if (fromBooking != null) return fromBooking.toString();
    final s = str(ApiRes.asMap(_d?['payment'])['status'], '').toLowerCase();
    if (s.isEmpty) return null;
    if (const ['success', 'captured', 'paid'].contains(s)) return 'PAID';
    if (s == 'failed') return 'FAILED';
    if (s.contains('refund')) return 'REFUNDED';
    return 'PENDING';
  }

  Map<String, dynamic> get _problem {
    final raw = _b['problem_description'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {}
    }
    return raw == null ? {} : {'customer_instructions': raw.toString()};
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  Future<void> _assign(List<int> itemIds, {int? current, String? serviceName}) async {
    final serviceIds = _items.where((it) => itemIds.contains(toInt(it['item_id']))).map((it) => toInt(it['service_id'])).whereType<int>().toSet().toList();
    final tech = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => TechnicianPickerScreen(bookingId: _id, serviceIds: serviceIds, current: current, title: serviceName == null ? 'Assign technician' : 'Assign — $serviceName')),
    );
    if (tech == null || !mounted) return;
    final reassigning = _items.where((it) => itemIds.contains(toInt(it['item_id'])) && it['technician_id'] != null && toInt(it['technician_id']) != tech).length;
    if (reassigning > 0 && !await confirm(context, 'Reassign $reassigning service(s)?', message: 'The current technician will be removed from these services.', ok: 'Reassign')) return;
    if (!mounted) return;
    final res = itemIds.length == 1
        ? await busy(context, () => api.post('/admin/bookings/$_id/items/${itemIds.first}/assign-technician', {'technicianId': tech}), success: 'Technician assigned')
        : await busy(context, () => api.post('/admin/bookings/$_id/items/bulk-assign-technician', {'itemIds': itemIds, 'technicianId': tech}), success: 'Technician assigned');
    if (res.ok) {
      _selectedItems.clear();
      _load();
    }
  }

  Future<void> _assignUnassigned() async {
    final ids = _items.where((it) => it['technician_id'] == null && it['item_status'] != 'COMPLETED').map((it) => toInt(it['item_id'])!).toList();
    if (ids.isEmpty) {
      // Legacy single-service booking without item rows.
      final tech = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => TechnicianPickerScreen(bookingId: _id, serviceIds: const [], title: 'Assign technician')));
      if (tech == null || !mounted) return;
      final res = await busy(context, () => api.post('/admin/bookings/reassign', {'bookingId': _id, 'technicianId': tech, 'reason': 'Assigned by admin'}), success: 'Technician assigned');
      if (res.ok) _load();
      return;
    }
    await _assign(ids, serviceName: ids.length == 1 ? str(_items.firstWhere((it) => toInt(it['item_id']) == ids.first)['service_name']) : null);
  }

  Future<void> _resendOtp(int techId) async {
    final res = await busy(context, () => api.post('/admin/bookings/$_id/resend-start-otp', {'technicianId': techId}), success: 'Start OTP sent');
    if (res.ok) _load();
  }

  Future<void> _reschedule({Map<String, dynamic>? attempt}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => attempt == null
          ? _RescheduleSheet(bookingId: _id)
          : _ResolveVisitSheet(bookingId: _id, attempt: attempt, bookingAmount: toNum(ApiRes.asMap(_d?['pricing'])['customer_payable'] ?? _b['final_price'])),
    );
    if (ok == true) _load();
  }

  Future<void> _recordCash() async {
    final collectors = _visits.where((v) => v['completed_at'] != null).toList();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CashSheet(bookingId: _id, collectors: collectors, techs: _techs, due: ApiRes.asMap(_d?['balance'])['due']),
    );
    if (ok == true) _load();
  }

  Future<void> _changeStatus() async {
    final v = await pickOne<String>(context, 'Booking status', kBookingStatuses, selected: str(_b['booking_status_id'], ''));
    if (v == null || !mounted) return;
    if (!await confirm(context, 'Change status to ${kBookingStatuses[v]}?', message: 'This overrides the booking status directly.')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.put('/master/bookings/$_id', {'booking_status_id': v}), success: 'Status updated');
    if (res.ok) _load();
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    toast('$what copied');
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(_error!, onRetry: _load),
      );
    }
    final b = _b;
    final phone = b['customer_mobile'];
    return Scaffold(
      appBar: AppBar(
        title: Text(str(b['booking_uid'], 'Booking')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  _copy(str(b['booking_uid'], ''), 'Booking ID');
                case 'call':
                  callPhone(phone);
                case 'wa':
                  whatsapp(phone);
                case 'reschedule':
                  _reschedule();
                case 'status':
                  _changeStatus();
                case 'customer':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: b['customer_id'])));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy booking ID')),
              if (phone != null) const PopupMenuItem(value: 'call', child: Text('Call customer')),
              if (phone != null) const PopupMenuItem(value: 'wa', child: Text('WhatsApp customer')),
              if (_canEdit && _phase == 'active') const PopupMenuItem(value: 'reschedule', child: Text('Reschedule')),
              if (_canEdit) const PopupMenuItem(value: 'status', child: Text('Change status')),
              if (b['customer_id'] != null) const PopupMenuItem(value: 'customer', child: Text('View customer profile')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), children: [
          _header(),
          ..._alerts(),
          const Gap(),
          _progress(),
          const Gap(),
          _summary(),
          const Gap(),
          _customer(),
          const Gap(),
          _services(),
          const Gap(),
          _technicians(),
          const Gap(),
          ..._finance(),
          ..._extras(),
          _timeline(),
        ]),
      ),
      bottomNavigationBar: _bottomAction(),
    );
  }

  Widget? _bottomAction() {
    final unassigned = _items.where((it) => it['technician_id'] == null && it['item_status'] != 'COMPLETED').length;
    final noTechAtAll = _items.isEmpty && _b['technician_id'] == null;
    Widget? btn;
    if (_canAssign && (unassigned > 0 || noTechAtAll)) {
      btn = FilledButton.icon(onPressed: _assignUnassigned, icon: const Icon(Icons.person_add_alt), label: Text(unassigned > 1 ? 'Assign technician ($unassigned)' : 'Assign technician'));
    } else if (_selectedItems.isNotEmpty) {
      btn = FilledButton.icon(onPressed: () => _assign(_selectedItems.toList()), icon: const Icon(Icons.swap_horiz), label: Text('Assign selected (${_selectedItems.length})'));
    } else if (_canRecordCash) {
      btn = FilledButton.icon(onPressed: _recordCash, icon: const Icon(Icons.payments_outlined), label: const Text('Record cash collected'));
    } else if (_techs.isNotEmpty && _phase == 'active') {
      final t = _techs.first;
      btn = FilledButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(bookingId: _id, technicianId: t['technician_id']))),
        icon: const Icon(Icons.location_on_outlined),
        label: Text('Track ${t['name']}'),
      );
    }
    if (btn == null) return null;
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 10), child: btn));
  }

  bool get _canRecordCash {
    final pay = _paymentState;
    final collectors = _visits.where((v) => v['completed_at'] != null);
    return _canEdit &&
        (_b['payment_mode_name'] == 'CASH' || pay == 'PARTIALLY_PAID') &&
        (pay == 'PENDING' || pay == 'PARTIALLY_PAID') &&
        _phase == 'completed' &&
        collectors.isNotEmpty;
  }

  Widget _header() {
    final b = _b;
    return SectionCard(children: [
      Row(children: [
        Expanded(child: Text(str(b['service_name']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink))),
        StatusChip(_phase == 'active' ? (b['status_name'] ?? b['booking_status_id']) : _phase, label: kBookingStatuses[b['booking_status_id']] ?? humanize(b['status_name'] ?? _phase)),
      ]),
      const Gap(6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (b['booking_speed'] == 'EMERGENCY' || truthy(b['is_emergency'])) const StatusChip('EMERGENCY', label: 'Emergency'),
        if (b['booking_speed'] == 'UNDER_30_MIN') const StatusChip('PROCESS', label: 'Under 30 min'),
        if (b['lifecycle_state'] != null) StatusChip(b['lifecycle_state']),
        if (_paymentState != null) StatusChip(_paymentState, label: 'Payment: ${humanize(_paymentState)}'),
      ]),
      if (b['cancellation_reason'] != null) ...[const Gap(8), Text('Cancelled: ${b['cancellation_reason']}', style: const TextStyle(color: C.red))],
    ]);
  }

  List<Widget> _alerts() {
    final out = <Widget>[];
    void add(String text, Color color, {String? action, VoidCallback? onTap}) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: .3))),
          child: Row(children: [
            Icon(Icons.info_outline, color: color, size: 18),
            const Gap(8),
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
            if (action != null) TextButton(onPressed: onTap, child: Text(action)),
          ]),
        ),
      ));
    }

    final unassigned = _items.where((it) => it['technician_id'] == null).length;
    if (_phase == 'active' && unassigned > 0) add('$unassigned service(s) waiting for a technician', C.amber, action: _canAssign ? 'Assign now' : null, onTap: _assignUnassigned);
    final waiting = _items.where((it) => it['technician_id'] != null && it['technician_accepted_at'] == null && it['item_status'] != 'COMPLETED').length;
    if (_phase == 'active' && waiting > 0) add('Waiting for technician to accept ($waiting)', C.violet);
    if (_paymentState == 'FAILED') add('Payment failed', C.red);
    if (_b['lifecycle_state'] == 'ESCALATED') add('Booking escalated', C.red);
    for (final c in ApiRes.asList(_d?['technicianCancellations'])) {
      if (truthy(c['needs_admin_assignment']) || c['redispatch_status'] == 'ADMIN_ACTION_NEEDED' || c['redispatch_status'] == 'NO_TECHNICIAN_FOUND') {
        add('${str(c['technician_name'], 'A technician')} dropped the job — ${str(c['reason_text'] ?? c['reason'], 'no reason')}. Needs manual assignment.', C.red, action: _canAssign ? 'Assign' : null, onTap: _assignUnassigned);
      }
    }
    for (final a in ApiRes.asList(_d?['serviceAttempts'])) {
      if (a['status'] == 'OPEN' || a['status'] == 'WAITING') {
        add('Missed visit: ${str(a['technician_name'], 'Technician')} couldn’t start — ${str(a['reason_label'] ?? a['reason_text'], '')}', C.red,
            action: _canEdit && a['status'] == 'OPEN' ? 'Resolve' : null, onTap: () => _reschedule(attempt: a));
      }
    }
    final openDisputes = ApiRes.asList(_d?['disputes']).where((x) => !const ['RESOLVED', 'REJECTED', 'CLOSED'].contains(x['status'])).length;
    if (openDisputes > 0) add('$openDisputes open complaint(s)', C.amber, action: 'Open', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DisputesScreen())));
    final openClaims = ApiRes.asList(_d?['warrantyClaims']).where((x) => !const ['RESOLVED', 'REJECTED', 'CLOSED'].contains(x['status'])).length;
    if (openClaims > 0) add('$openClaims open warranty claim(s)', C.amber, action: 'Open', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarrantyClaimsScreen())));
    return out;
  }

  Widget _progress() {
    final l = str(_b['lifecycle_state'], '');
    final s = str(_b['booking_status_id'], '');
    var idx = -1;
    for (var i = 0; i < _steps.length; i++) {
      if (_steps[i].$2.contains(l) || _steps[i].$3.contains(s)) idx = i;
    }
    final closed = const ['cancelled', 'failed', 'refunded', 'no_service'].contains(_phase);
    return SectionCard(title: 'Booking progress', children: [
      Row(children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Expanded(
            child: Column(children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: closed ? C.line : (i <= idx ? C.green : C.line),
                child: i <= idx && !closed ? const Icon(Icons.check, size: 14, color: Colors.white) : Text('${i + 1}', style: const TextStyle(fontSize: 11, color: C.body)),
              ),
              const Gap(4),
              Text(_steps[i].$1, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500, color: i <= idx ? C.ink : C.muted)),
            ]),
          ),
        ],
      ]),
    ]);
  }

  Widget _summary() {
    final b = _b;
    final pricing = ApiRes.asMap(_d?['pricing']);
    final total = pricing['customer_payable'] ?? ApiRes.asMap(_problem['price'])['total'] ?? b['final_price'];
    final slot = b['slot_start'] != null && b['slot_end'] != null ? '${fmtTime(b['slot_start'])} – ${fmtTime(b['slot_end'])}' : fmtTime(b['scheduled_time']);
    return SectionCard(children: [
      KV('Booking value', inr(total, paise: true), bold: true),
      KV('Payment', '${humanize(b['payment_mode_name'])} · ${humanize(_paymentState)}'),
      KV('Scheduled', '${fmtDate(b['scheduled_date'])} · $slot'),
      KV('Booking type', b['booking_type_name']),
      KV('Service area', b['area_name']),
      KV('Booked on', fmtDateTime(b['created_at'])),
    ]);
  }

  Widget _customer() {
    final b = _b;
    final address = [b['service_address'], b['service_city'], b['service_state'], b['service_pincode']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    final instructions = str(_problem['customer_instructions'] ?? _problem['notes'], '');
    return SectionCard(title: 'Customer', children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Avatar(url: b['customer_avatar'], name: str(b['customer_name'], '')),
        title: Text(str(b['customer_name']), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${str(b['customer_mobile'], '')}  ${str(b['customer_email'], '')}'),
        onTap: b['customer_id'] == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: b['customer_id']))),
      ),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(b['customer_mobile']), icon: const Icon(Icons.call, size: 18), label: const Text('Call'))),
        const Gap(8),
        Expanded(child: OutlinedButton.icon(onPressed: () => whatsapp(b['customer_mobile']), icon: const Icon(Icons.chat, size: 18), label: const Text('WhatsApp'))),
      ]),
      const Gap(10),
      const Text('Service location', style: TextStyle(fontWeight: FontWeight.w600)),
      Text(address.isEmpty ? 'No service address recorded.' : address, style: const TextStyle(color: C.body)),
      if (b['service_lat'] != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openUrl('https://www.google.com/maps/search/?api=1&query=${b['service_lat']},${b['service_lng']}'),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Open in Maps'),
          ),
        ),
      if (instructions.isNotEmpty) ...[const Gap(6), const Text('Special instructions', style: TextStyle(fontWeight: FontWeight.w600)), Text(instructions, style: const TextStyle(color: C.body))],
    ]);
  }

  Widget _services() {
    return SectionCard(
      title: 'Services booked (${_items.length})',
      children: [
        if (_items.isEmpty) const Text('No services are recorded on this booking.', style: TextStyle(color: C.muted)),
        for (final it in _items) _serviceRow(it),
      ],
    );
  }

  Widget _serviceRow(Map<String, dynamic> it) {
    final itemId = toInt(it['item_id'])!;
    final done = it['item_status'] == 'COMPLETED';
    final assignable = _canAssign && !done;
    final tech = it['technician_id'];
    final left = toInt(it['response_seconds_left']) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: _selectedItems.contains(itemId) ? C.primary : C.line), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (assignable)
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: _selectedItems.contains(itemId),
            onChanged: (v) => setState(() => v == true ? _selectedItems.add(itemId) : _selectedItems.remove(itemId)),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(it['service_name']), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${it['quantity'] ?? 1} ${str(it['unit_name'], '')} × ${inr(it['unit_price'], paise: true)} = ${inr(it['line_total'], paise: true)}', style: const TextStyle(color: C.body, fontSize: 12.5)),
            const Gap(4),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tech == null ? 'Unassigned' : str(it['item_technician_name']), style: TextStyle(fontSize: 12.5, color: tech == null ? C.amber : C.ink, fontWeight: FontWeight.w600)),
              if (done) const StatusChip('COMPLETED'),
              if (tech != null && !done) StatusChip(it['technician_accepted_at'] != null ? 'ACCEPTED' : 'PENDING', label: it['technician_accepted_at'] != null ? 'Accepted' : 'Not accepted'),
              if (tech != null && it['technician_accepted_at'] == null && left > 0) Text('${(left / 60).ceil()} min left to respond', style: const TextStyle(fontSize: 11.5, color: C.muted)),
            ]),
          ]),
        ),
        if (assignable)
          TextButton(
            onPressed: () => _assign([itemId], current: toInt(tech), serviceName: str(it['service_name'])),
            child: Text(tech == null ? 'Assign' : 'Change'),
          ),
      ]),
    );
  }

  Widget _technicians() {
    final techs = _techs;
    final legacy = techs.isEmpty && _b['technician_id'] != null;
    return SectionCard(title: 'Technicians', children: [
      if (techs.isEmpty && !legacy) const Text('No technician assigned', style: TextStyle(color: C.muted)),
      if (legacy)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Avatar(url: _b['tech_avatar'], name: str(_b['technician_name'], '')),
          title: Text(str(_b['technician_name'])),
          subtitle: Text(str(_b['tech_mobile'], '')),
          trailing: IconButton(icon: const Icon(Icons.call), onPressed: () => callPhone(_b['tech_mobile'])),
        ),
      for (final t in techs) _techCard(t),
    ]);
  }

  Widget _techCard(Map<String, dynamic> t) {
    final visit = ApiRes.asMap(t['visit']);
    final otp = visit['start_otp'];
    final id = t['technician_id'] as int;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: t['name'], size: 36),
          const Gap(10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${t['count']} service(s) · ${t['accepted']} accepted', style: const TextStyle(fontSize: 12, color: C.body)),
            ]),
          ),
          StatusChip(t['stage'] == 'Completed' ? 'COMPLETED' : 'PROCESS', label: t['stage']),
        ]),
        const Gap(6),
        if (visit['on_the_way_at'] != null) Text('On the way: ${fmtDateTime(visit['on_the_way_at'])}', style: const TextStyle(fontSize: 12, color: C.body)),
        if (visit['arrived_at'] != null) Text('Arrived: ${fmtDateTime(visit['arrived_at'])}', style: const TextStyle(fontSize: 12, color: C.body)),
        if (visit['started_at'] != null) Text('Started: ${fmtDateTime(visit['started_at'])}', style: const TextStyle(fontSize: 12, color: C.body)),
        if (visit['completed_at'] != null) Text('Completed: ${fmtDateTime(visit['completed_at'])}', style: const TextStyle(fontSize: 12, color: C.body)),
        Row(children: [
          Text(otp != null ? 'Start OTP: $otp' : 'No OTP sent yet', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (otp != null) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.copy, size: 16), onPressed: () => _copy('$otp', 'Start OTP')),
          if (_canEdit && _phase == 'active' && visit['started_at'] == null) TextButton(onPressed: () => _resendOtp(id), child: const Text('Resend OTP')),
        ]),
        Wrap(spacing: 4, children: [
          TextButton.icon(onPressed: () => callPhone(t['mobile']), icon: const Icon(Icons.call, size: 16), label: const Text('Call')),
          TextButton.icon(onPressed: () => whatsapp(t['mobile']), icon: const Icon(Icons.chat, size: 16), label: const Text('WhatsApp')),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(bookingId: _id, technicianId: id))),
            icon: const Icon(Icons.location_on_outlined, size: 16),
            label: const Text('Track'),
          ),
          if (_canAssign && (t['open'] as List).isNotEmpty)
            TextButton.icon(onPressed: () => _assign(List<int>.from(t['open']), current: id), icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Change')),
        ]),
      ]),
    );
  }

  List<Widget> _finance() {
    final p = ApiRes.asMap(_d?['pricing']);
    final quote = ApiRes.asMap(_problem['price']);
    final pay = ApiRes.asMap(_d?['payment']);
    final bal = ApiRes.asMap(_d?['balance']);
    final out = <Widget>[];
    out.add(SectionCard(title: 'Price details', children: [
      if (p.isNotEmpty) ...[
        for (final e in const [
          ['base_price', 'Base price'], ['area_amount', 'Area charge'], ['slot_amount', 'Slot charge'], ['emergency_amount', 'Emergency'],
          ['quick_service_amount', 'Quick service'], ['surge_amount', 'Surge'], ['technician_charges', 'Technician charges'], ['platform_fees', 'Platform fee'],
          ['tax_amount', 'Tax'], ['discount_amount', 'Discount'], ['coupon_amount', 'Coupon'], ['wallet_deduction', 'Wallet used'], ['cashback_amount', 'Cashback'],
        ])
          if (toNum(p[e[0]]) != 0) KV(e[1], inr(p[e[0]], paise: true)),
        const Divider(),
        KV('Grand total', inr(p['customer_payable'], paise: true), bold: true),
      ] else if (quote.isNotEmpty) ...[
        KV('Subtotal', inr(quote['subtotal'], paise: true)),
        KV('Platform fee', inr(quote['platform_fee'], paise: true)),
        KV('Tax', inr(quote['tax_amount'], paise: true)),
        KV('Discount', inr(quote['discount'] ?? quote['coupon_discount'], paise: true)),
        const Divider(),
        KV('Grand total', inr(quote['total'], paise: true), bold: true),
        const Text('From the checkout quote stored on this booking.', style: TextStyle(fontSize: 11.5, color: C.muted)),
      ] else
        const Text('No itemised price breakdown was recorded for this booking.', style: TextStyle(color: C.muted)),
      if (bal.isNotEmpty) ...[
        const Divider(),
        KV('Paid', inr(bal['paid'], paise: true), color: C.green),
        KV('Outstanding', inr(bal['due'], paise: true), color: toNum(bal['due']) > 0 ? C.red : null),
        if (toNum(bal['refunded']) > 0) KV('Refunded', inr(bal['refunded'], paise: true)),
        if (toNum(bal['refund_pending']) > 0) KV('Refund pending', inr(bal['refund_pending'], paise: true)),
      ],
    ]));
    out.add(const Gap());
    out.add(SectionCard(title: 'Payment', children: [
      if (pay.isEmpty) const Text('No gateway transaction recorded for this booking.', style: TextStyle(color: C.muted)),
      if (pay.isNotEmpty) ...[
        KV('Amount', inr(pay['amount'], paise: true), bold: true),
        KV('Method', '${str(pay['payment_mode'])} · ${str(pay['gateway'])}'),
        KV('Gateway status', StatusChip(pay['status'])),
        KV('Transaction ID', pay['gateway_txn_id'] ?? pay['payment_uid']),
        KV('Completed', fmtDateTime(pay['completed_at'])),
      ],
      for (final l in ApiRes.asList(_d?['paymentLedger']))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Attempt ${fmtDateTime(l['attempted_at'])} · ${humanize(l['payment_type'])} · ${inr(l['order_amount'] ?? l['amount'], paise: true)} · ${humanize(l['status'] ?? l['order_status'])}',
              style: const TextStyle(fontSize: 12, color: C.body)),
        ),
    ]));
    final cash = ApiRes.asList(_d?['cashCollections']);
    if (cash.isNotEmpty) {
      out.addAll([
        const Gap(),
        SectionCard(title: 'Cash collections', children: [
          for (final c in cash)
            KV('${str(c['technician_name'])} · ${fmtDateTime(c['collected_at'])}${c['reason'] != null ? '\n${c['reason']}' : ''}', '${inr(c['collected'], paise: true)}${c['expected'] != null ? ' / ${inr(c['expected'], paise: true)}' : ''}'),
        ]),
      ]);
    }
    final refunds = ApiRes.asList(_d?['refunds']);
    if (refunds.isNotEmpty) {
      out.addAll([
        const Gap(),
        SectionCard(title: 'Refunds', children: [
          for (final r in refunds)
            KV('#${r['refund_id']} · ${fmtDate(r['created_at'])}${r['failure_reason'] != null ? '\n${r['failure_reason']}' : ''}', Row(mainAxisSize: MainAxisSize.min, children: [Text(inr(r['approved_amount'] ?? r['amount'], paise: true)), const Gap(6), StatusChip(r['status'])])),
        ]),
      ]);
    }
    final payouts = ApiRes.asList(_d?['payouts']);
    if (payouts.isNotEmpty) {
      out.addAll([
        const Gap(),
        SectionCard(title: 'Technician payouts', children: [
          for (final p in payouts) ...[
            Text(_techs.firstWhere((t) => t['technician_id'] == toInt(p['technician_id']), orElse: () => {'name': 'Technician #${p['technician_id']}'})['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
            KV('Gross basis', inr(p['gross_basis'], paise: true)),
            KV('Commission', inr(p['total_commission_amount'], paise: true)),
            if (toNum(p['gst_on_commission']) > 0) KV('GST on commission', inr(p['gst_on_commission'], paise: true)),
            if (toNum(p['tds_accrued']) > 0) KV('TDS (${p['tds_rate']}%)', inr(p['tds_accrued'], paise: true)),
            KV('Technician net', inr(p['technician_net_earning'], paise: true), bold: true),
            KV('Platform net revenue', inr(p['platform_net_revenue'], paise: true)),
            KV('Settled', truthy(p['settled']) ? 'Yes' : 'No'),
            const Divider(),
          ],
        ]),
      ]);
    }
    out.add(const Gap());
    return out;
  }

  List<Widget> _extras() {
    final out = <Widget>[];
    final work = ApiRes.asList(_d?['additionalWork']);
    if (work.isNotEmpty) {
      out.addAll([
        SectionCard(title: 'Additional work', children: [
          for (final w in work)
            KV('${str(w['service_name'])} × ${w['quantity']}\n${str(w['technician_name'], '')} · ${str(w['reason'], '')}', Row(mainAxisSize: MainAxisSize.min, children: [Text(inr(w['total'], paise: true)), const Gap(6), StatusChip(w['status'])])),
        ]),
        const Gap(),
      ]);
    }
    final quotes = ApiRes.asList(_d?['quotations']);
    if (quotes.isNotEmpty) {
      out.addAll([
        SectionCard(title: 'Inspection quotations', children: [
          for (final q in quotes) ...[
            Row(children: [Expanded(child: Text('${str(q['quote_uid'])} · rev ${q['revision'] ?? 1}', style: const TextStyle(fontWeight: FontWeight.w700))), StatusChip(q['status'])]),
            if (q['findings'] != null) Text('Findings: ${q['findings']}', style: const TextStyle(color: C.body, fontSize: 12.5)),
            for (final l in ApiRes.asList(q['lines'])) KV('${str(l['service_name'], humanize(l['line_kind']))} × ${l['quantity']}', inr(l['total'], paise: true)),
            KV('Total', inr(q['total'], paise: true), bold: true),
            const Divider(),
          ],
        ]),
        const Gap(),
      ]);
    }
    final attempts = ApiRes.asList(_d?['serviceAttempts']);
    if (attempts.isNotEmpty) {
      out.addAll([
        SectionCard(title: 'Missed visits', children: [
          for (final a in attempts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${str(a['technician_name'])} · ${str(a['reason_label'] ?? a['reason_code'])}'),
              subtitle: Text([a['reason_text'], a['resolution'] != null ? 'Resolution: ${humanize(a['resolution'])}' : null, a['resolution_note']].whereType<Object>().join('\n')),
              trailing: a['status'] == 'OPEN' && _canEdit ? TextButton(onPressed: () => _reschedule(attempt: a), child: const Text('Resolve')) : StatusChip(a['status']),
            ),
        ]),
        const Gap(),
      ]);
    }
    final sla = ApiRes.asMap(_d?['sla']);
    if (sla.isNotEmpty) {
      out.addAll([
        SectionCard(title: 'SLA', trailing: StatusChip(sla['sla_status']), children: [
          KV('Priority', humanize(sla['priority'])),
          KV('Severity', humanize(sla['severity'])),
          for (final c in ApiRes.asList(sla['clocks'])) KV(humanize(c['label'] ?? c['key'] ?? c['name']), '${humanize(c['status'])} · due ${fmtDateTime(c['due_at'])}'),
        ]),
        const Gap(),
      ]);
    }
    return out;
  }

  Widget _timeline() {
    final tl = ApiRes.asList(_d?['timeline']);
    return SectionCard(title: 'Activity', children: [
      if (tl.isEmpty) const Text('No activity has been recorded for this booking yet.', style: TextStyle(color: C.muted)),
      for (final e in tl.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 8, color: C.primary)),
            const Gap(10),
            Expanded(child: Text(_tlLabel(e), style: const TextStyle(fontSize: 13))),
            Text(fmtDateTime(e['created_at']), style: const TextStyle(fontSize: 11, color: C.muted)),
          ]),
        ),
    ]);
  }

  String _tlLabel(Map e) {
    final label = str(e['event_label'], '');
    if (e['event_type'] == 'lifecycle' && label.contains('→')) {
      final parts = label.split('→').map((s) => s.trim()).toList();
      return parts[0].isEmpty || parts[0] == '—' ? humanize(parts[1]) : '${humanize(parts[0])} → ${humanize(parts[1])}';
    }
    return label;
  }
}

// ─── Technician picker (GET /admin/bookings/:id/city-technicians) ────────────

class TechnicianPickerScreen extends StatefulWidget {
  const TechnicianPickerScreen({super.key, required this.bookingId, required this.serviceIds, this.current, this.title = 'Select technician'});
  final int bookingId;
  final List<int> serviceIds;
  final int? current;
  final String title;
  @override
  State<TechnicianPickerScreen> createState() => _TechnicianPickerScreenState();
}

class _TechnicianPickerScreenState extends State<TechnicianPickerScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = widget.serviceIds.length > 1 ? {'serviceIds': widget.serviceIds.join(',')} : (widget.serviceIds.length == 1 ? {'serviceId': widget.serviceIds.first} : null);
    final res = await api.get('/admin/bookings/${widget.bookingId}/city-technicians', q);
    if (!mounted) return;
    setState(() {
      _rows = res.ok ? res.list : [];
      _error = res.ok ? null : res.message;
    });
  }

  String? _tag(Map t) {
    if (!truthy(t['is_online'])) return 'Offline';
    if (!truthy(t['is_eligible'])) return 'Not eligible';
    if (truthy(t['is_busy'])) return 'Busy';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = (_rows ?? []).where((t) => _q.isEmpty || '${t['name']} ${t['mobile_number']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(decoration: const InputDecoration(hintText: 'Search by name or phone…', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Technicians with this service skill — offline, ineligible or fully-booked ones can’t be selected', style: TextStyle(fontSize: 12, color: C.muted)),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: C.red))),
              Expanded(
                child: rows.isEmpty
                    ? const EmptyView('No technicians found')
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (c, i) {
                          final t = rows[i];
                          final tag = _tag(t);
                          final id = toInt(t['technician_id'])!;
                          return RowTile(
                            leading: Avatar(url: t['avatar'], name: str(t['name'], '')),
                            title: str(t['name']),
                            badge: id == widget.current ? const StatusChip('ACTIVE', label: 'Current') : (tag == null ? const StatusChip('ACTIVE', label: 'Available') : StatusChip('CANCEL', label: tag)),
                            subtitle: str(t['mobile_number'], ''),
                            lines: ['Jobs ${t['current_jobs'] ?? 0}/${t['max_jobs'] ?? '-'}${t['distance_km'] != null ? ' · ${toNum(t['distance_km']).toStringAsFixed(1)} km away' : ''}'],
                            onTap: tag != null || id == widget.current ? null : () => Navigator.pop(context, id),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

// ─── Reschedule ──────────────────────────────────────────────────────────────

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.slots, required this.selected, required this.onSelect});
  final List<Map<String, dynamic>> slots;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('No slots are configured for this date.', style: TextStyle(color: C.muted)));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in slots)
        ChoiceChip(
          label: Text('${str(s['name'], '')} ${str(s['time'], '')}${s['available'] == false ? ' · ${str(s['message'] ?? humanize(s['unavailable_reason']), 'Unavailable')}' : ''}'),
          selected: selected == toInt(s['slot_id']),
          onSelected: s['available'] == false ? null : (_) => onSelect(toInt(s['slot_id'])!),
        ),
    ]);
  }
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({required this.bookingId});
  final int bookingId;
  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  DateTime? _date;
  List<Map<String, dynamic>> _slots = [];
  int? _slot;
  bool _loading = false;
  String? _error;
  final _reason = TextEditingController();

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (d == null) return;
    setState(() {
      _date = d;
      _slot = null;
      _loading = true;
      _error = null;
    });
    final res = await api.get('/admin/bookings/${widget.bookingId}/reschedule-options', {'date': ymd(d)});
    if (!mounted) return;
    final data = res.map;
    setState(() {
      _loading = false;
      if (!res.ok) {
        _error = res.message;
        _slots = [];
      } else if (data['eligible'] == false) {
        _error = str(data['reason'], "This booking can't be rescheduled.");
        _slots = [];
      } else {
        _slots = ApiRes.asList(data['slots']);
      }
    });
  }

  Future<void> _submit() async {
    final res = await busy(context, () => api.post('/admin/bookings/${widget.bookingId}/reschedule', {'scheduledDate': ymd(_date!), 'slotId': _slot, if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim()}), success: 'Booking rescheduled');
    if (res.ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Reschedule booking', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Gap(),
          OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today, size: 18), label: Text(_date == null ? 'Pick new date' : fmtDate(_date))),
          const Gap(),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: const TextStyle(color: C.red)),
          if (_date != null && !_loading && _error == null) _SlotPicker(slots: _slots, selected: _slot, onSelect: (v) => setState(() => _slot = v)),
          const Gap(),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. Customer called to move the visit')),
          const Gap(),
          FilledButton(onPressed: _date != null && _slot != null ? _submit : null, child: const Text('Reschedule')),
        ]),
      ),
    );
  }
}

// ─── Resolve missed visit ────────────────────────────────────────────────────

class _ResolveVisitSheet extends StatefulWidget {
  const _ResolveVisitSheet({required this.bookingId, required this.attempt, required this.bookingAmount});
  final int bookingId;
  final Map<String, dynamic> attempt;
  final double bookingAmount;
  @override
  State<_ResolveVisitSheet> createState() => _ResolveVisitSheetState();
}

class _ResolveVisitSheetState extends State<_ResolveVisitSheet> {
  static const _resolutions = {
    'CONTINUE': ('Continue job', 'Customer is reachable again — the technician can start with the OTP.'),
    'RESCHEDULE': ('Reschedule', 'Move the visit to a new slot. The technician stays on it if free then.'),
    'REASSIGN': ('Reassign', 'Release the technician and offer the booking to others.'),
    'CANCEL': ('Cancel booking', 'Close the booking. A paid booking gets a refund request for the paid amount minus any charge.'),
    'NO_SERVICE': ('Mark failed / no-service', 'Close as no-service. Refund handled the same way as cancel.'),
  };
  String _resolution = 'CONTINUE';
  String _charge = 'NONE';
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime? _date;
  List<Map<String, dynamic>> _slots = [];
  int? _slot;

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (d == null) return;
    setState(() {
      _date = d;
      _slot = null;
    });
    final res = await api.get('/admin/bookings/${widget.bookingId}/reschedule-options', {'date': ymd(d), 'failedVisit': '1'});
    if (!mounted) return;
    setState(() => _slots = res.ok && res.map['eligible'] != false ? ApiRes.asList(res.map['slots']) : []);
    if (!res.ok || res.map['eligible'] == false) toast(str(res.map['reason'] ?? res.message, 'No slots'), error: true);
  }

  bool get _valid {
    if (_charge == 'CHARGE') {
      final a = double.tryParse(_amount.text) ?? 0;
      if (a <= 0 || (widget.bookingAmount > 0 && a > widget.bookingAmount)) return false;
    }
    if (_resolution == 'RESCHEDULE' && (_date == null || _slot == null)) return false;
    return true;
  }

  Future<void> _submit() async {
    final res = await busy(context, () => api.post('/admin/bookings/${widget.bookingId}/service-attempts/${widget.attempt['attempt_id']}/resolve', {
          'resolution': _resolution,
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          'chargeDecision': _charge,
          if (_charge == 'CHARGE') 'chargeAmount': double.tryParse(_amount.text),
          if (_resolution == 'RESCHEDULE') ...{'scheduledDate': ymd(_date!), 'slotId': _slot},
        }), success: 'Visit resolved');
    if (res.ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Resolve missed visit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${str(widget.attempt['technician_name'])} · ${str(widget.attempt['reason_label'] ?? widget.attempt['reason_text'])}', style: const TextStyle(color: C.body)),
          const Gap(8),
          for (final e in _resolutions.entries)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: e.key,
              groupValue: _resolution,
              onChanged: (v) => setState(() => _resolution = v!),
              title: Text(e.value.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(e.value.$2, style: const TextStyle(fontSize: 12)),
            ),
          if (_resolution == 'RESCHEDULE') ...[
            OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today, size: 18), label: Text(_date == null ? 'New date' : fmtDate(_date))),
            const Gap(8),
            if (_date != null) _SlotPicker(slots: _slots, selected: _slot, onSelect: (v) => setState(() => _slot = v)),
          ],
          const Gap(8),
          const Text('Customer charge (per your policy)', style: TextStyle(fontWeight: FontWeight.w600)),
          Wrap(spacing: 8, children: [
            for (final c in const {'NONE': 'No decision', 'WAIVE': 'Waive', 'CHARGE': 'Charge'}.entries)
              ChoiceChip(label: Text(c.value), selected: _charge == c.key, onSelected: (_) => setState(() => _charge = c.key)),
          ]),
          if (_charge == 'CHARGE')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount (₹)', helperText: 'Enter an amount up to the booking total (${inr(widget.bookingAmount)}).'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          const Gap(8),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note', hintText: 'What was agreed with the customer')),
          const Gap(),
          FilledButton(onPressed: _valid ? _submit : null, child: const Text('Resolve')),
        ]),
      ),
    );
  }
}

// ─── Record cash collected ───────────────────────────────────────────────────

class _CashSheet extends StatefulWidget {
  const _CashSheet({required this.bookingId, required this.collectors, required this.techs, required this.due});
  final int bookingId;
  final List<Map<String, dynamic>> collectors;
  final List<Map<String, dynamic>> techs;
  final dynamic due;
  @override
  State<_CashSheet> createState() => _CashSheetState();
}

class _CashSheetState extends State<_CashSheet> {
  int? _tech;
  late final _amount = TextEditingController(text: widget.due == null ? '' : toNum(widget.due).toStringAsFixed(2));
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.collectors.length == 1) _tech = toInt(widget.collectors.first['technician_id']);
  }

  String _name(Map v) {
    final id = toInt(v['technician_id']);
    final t = widget.techs.firstWhere((t) => t['technician_id'] == id, orElse: () => {});
    return str(t['name'] ?? v['technician_name'], 'Technician #$id');
  }

  String get _kind {
    final a = double.tryParse(_amount.text);
    if (a == null || widget.due == null) return 'FULL';
    final diff = ((a - toNum(widget.due)) * 100).round() / 100;
    return diff == 0 ? 'FULL' : (diff < 0 ? 'SHORT' : 'EXCESS');
  }

  bool get _valid {
    final a = double.tryParse(_amount.text) ?? 0;
    return _tech != null && a > 0 && _kind != 'EXCESS' && (_kind != 'SHORT' || _reason.text.trim().length >= 5);
  }

  Future<void> _submit() async {
    final res = await busy(context, () => api.post('/admin/bookings/${widget.bookingId}/cash-collected', {
          'technicianId': _tech,
          'amount': double.parse(_amount.text),
          if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        }), success: 'Cash collection recorded');
    if (res.ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Record cash collected', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const Gap(8),
        const Text('Collected by', style: TextStyle(fontWeight: FontWeight.w600)),
        if (widget.collectors.isEmpty) const Text('No technician has completed their services yet.', style: TextStyle(color: C.muted)),
        for (final c in widget.collectors)
          RadioListTile<int>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: toInt(c['technician_id'])!,
            groupValue: _tech,
            onChanged: (v) => setState(() => _tech = v),
            title: Text(_name(c)),
          ),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Amount (₹)', helperText: widget.due == null ? null : 'Outstanding: ${inr(widget.due, paise: true)}'),
          onChanged: (_) => setState(() {}),
        ),
        if (_kind == 'EXCESS') const Padding(padding: EdgeInsets.only(top: 6), child: Text('Amount is more than what is due.', style: TextStyle(color: C.red))),
        if (_kind == 'SHORT') ...[
          const Gap(8),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason for the shortfall (min 5 chars)'), onChanged: (_) => setState(() {})),
        ],
        const Gap(),
        FilledButton(onPressed: _valid ? _submit : null, child: const Text('Record')),
      ]),
    );
  }
}
