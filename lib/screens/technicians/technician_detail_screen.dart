import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/track_screen.dart';
import 'technicians_screens.dart' show kTechPath;

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const _weekOrder = [1, 2, 3, 4, 5, 6, 0];
const _offTypes = {'LEAVE': 'Leave', 'BLOCKED': 'Blocked time', 'HOLIDAY': 'Holiday', 'EMERGENCY': 'Emergency unavailability', 'BREAK': 'Break'};

String _hm(dynamic t) => str(t, '').length >= 5 ? str(t).substring(0, 5) : str(t, '');

/// Technician profile: overview + admin actions, documents, schedule &
/// availability, jobs & pending offers.
class TechnicianDetailScreen extends StatefulWidget {
  const TechnicianDetailScreen({super.key, required this.id});
  final dynamic id;
  @override
  State<TechnicianDetailScreen> createState() => _TechnicianDetailScreenState();
}

class _TechnicianDetailScreenState extends State<TechnicianDetailScreen> {
  final _key = GlobalKey<ApiLoaderState>();
  int get _id => toInt(widget.id)!;
  bool get _canEdit => Session.I.canOn(kTechPath, 'EDIT');

  Future<ApiRes> _load() async {
    final r = await Future.wait([
      api.post('/admin/technicians/detail', {'technicianId': _id}),
      api.get('/admin/technicians/performance', {'technician_id': _id}),
      api.get('/admin/technicians/job-offers', {'technician_id': _id}),
    ]);
    if (!r[0].ok) return r[0];
    return ApiRes({'status': true, 'data': r[0].data, 'performance': r[1].ok ? r[1].data : null, 'offers': r[2].ok ? r[2].data : []});
  }

  Future<void> _suspend(bool suspend) async {
    if (suspend && !await confirm(context, 'Suspend this technician?', message: 'They stop receiving jobs until re-activated.', danger: true, ok: 'Suspend')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.post('/admin/technicians/suspend', {'technicianId': _id, 'suspend': suspend}), success: suspend ? 'Technician suspended' : 'Technician activated');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _forceOffline() async {
    if (!await confirm(context, 'Force this technician offline?', message: 'They stop receiving new job offers until they go online again.', ok: 'Force offline')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.post('/admin/technicians/force-offline', {'technicianId': _id}), success: 'Technician forced offline');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _approve() async {
    final r = await busy(context, () => api.post('/admin/technicians/approve', {'technicianId': _id, 'isActive': true, 'applicationStatus': 'approved'}), success: 'Application approved');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _assignManager(dynamic current) async {
    final admins = await api.post('/admin/admin-paginated', {'isActive': true, 'limit': 200});
    if (!mounted) return;
    final picked = await pickOne<int>(context, 'Assign manager', {
      0: 'No manager',
      for (final a in admins.list) toInt(a['admin_id'])!: '${fullName(a)}${a['role_name'] != null ? ' · ${a['role_name']}' : ''}',
    }, selected: toInt(current) ?? 0);
    if (picked == null || !mounted) return;
    final r = await busy(context, () => api.patch('/admin/technicians/assign-manager', {'technicianId': _id, 'managerAdminId': picked == 0 ? null : picked}), success: picked == 0 ? 'Manager unassigned' : 'Manager assigned');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _acceptOffer(Map o) async {
    if (!await confirm(context, 'Accept job on behalf of technician?', message: '${str(o['booking_uid'])} · ${str(o['service_name'])}', ok: 'Accept')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.post('/admin/technicians/accept-job-offer', {'technicianId': _id, 'bookingId': o['booking_id']}), success: 'Job accepted on behalf of technician');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Technician'),
          bottom: const TabBar(tabs: [Tab(text: 'Overview'), Tab(text: 'Documents'), Tab(text: 'Schedule'), Tab(text: 'Jobs')]),
        ),
        body: ApiLoader(
          key: _key,
          load: _load,
          builder: (c, res, reload) {
            final d = res.map;
            final t = ApiRes.asMap(d['technician']);
            return TabBarView(children: [
              _overview(d, t, ApiRes.asMap(res['performance'])),
              _documents(d),
              TechnicianSchedule(technicianId: _id, canEdit: _canEdit),
              _jobs(d, ApiRes.asList(res['offers'])),
            ]);
          },
        ),
      ),
    );
  }

  Widget _overview(Map d, Map t, Map perf) {
    final wallet = ApiRes.asMap(d['wallet']);
    final manager = ApiRes.asMap(d['manager']);
    final ref = ApiRes.asMap(d['referral']);
    final loc = ApiRes.asMap(d['liveLocation']);
    final jobs = ApiRes.asMap(perf['jobs']);
    final ratings = ApiRes.asMap(perf['ratings']);
    final status = str(t['application_status'], 'pending').toLowerCase();
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(children: [
        Row(children: [
          Avatar(url: t['selfie_photo'] ?? t['profile_photo'], name: fullName(t), size: 56),
          const Gap(),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fullName(t), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('${str(t['technician_unique_id'], 'Partner ID pending')} · ${str(t['category_name'], '')}', style: const TextStyle(color: C.body)),
              const Gap(4),
              Wrap(spacing: 6, children: [
                StatusChip(truthy(t['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(t['is_active']) ? 'Active' : 'Suspended'),
                StatusChip(truthy(t['is_online']) ? 'ACTIVE' : 'DRAFT', label: truthy(t['is_online']) ? 'Online' : 'Offline'),
                StatusChip(status),
              ]),
            ]),
          ),
        ]),
        const Gap(10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(t['mobile_number']), icon: const Icon(Icons.call, size: 18), label: const Text('Call'))),
          const Gap(8),
          Expanded(child: OutlinedButton.icon(onPressed: () => whatsapp(t['mobile_number']), icon: const Icon(Icons.chat, size: 18), label: const Text('WhatsApp'))),
          const Gap(8),
          IconButton.filledTonal(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(technicianId: _id))), icon: const Icon(Icons.location_on_outlined)),
        ]),
      ]),
      const Gap(),
      StatGrid([
        StatTile(label: 'Avg rating', value: toNum(ratings['avg_rating'] ?? t['avg_rating']).toStringAsFixed(1), sub: '${ratings['review_count'] ?? t['review_count'] ?? 0} reviews', icon: Icons.star_outline, color: C.amber),
        StatTile(label: 'Jobs completed', value: '${jobs['completed'] ?? 0}', sub: 'of ${jobs['total'] ?? t['total_jobs'] ?? 0}', icon: Icons.task_alt, color: C.green),
        StatTile(label: 'Wallet balance', value: inr(wallet['wallet_balance']), icon: Icons.account_balance_wallet_outlined, color: C.violet),
        StatTile(label: 'This month', value: inr(wallet['this_month']), sub: 'Total ${inr(wallet['total_earned'])}', icon: Icons.trending_up),
      ]),
      const Gap(),
      if (_canEdit)
        SectionCard(title: 'Admin actions', children: [
          if (status != 'approved') ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.verified, color: C.green), title: const Text('Approve application'), onTap: _approve),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(truthy(t['is_active']) ? Icons.block : Icons.check_circle_outline, color: truthy(t['is_active']) ? C.red : C.green),
            title: Text(truthy(t['is_active']) ? 'Suspend technician' : 'Activate technician'),
            onTap: () => _suspend(truthy(t['is_active'])),
          ),
          if (truthy(t['is_online'])) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.wifi_off), title: const Text('Force offline'), onTap: _forceOffline),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Assign manager'),
            subtitle: Text(manager.isEmpty ? 'No manager assigned' : str(manager['name'])),
            onTap: () => _assignManager(t['manager_admin_id']),
          ),
        ]),
      const Gap(),
      SectionCard(title: 'Contact & location', children: [
        KV('Mobile', t['mobile_number']),
        KV('Email', t['email']),
        KV('Address', t['address']),
        KV('City', '${str(t['city'], '')}, ${str(t['state'], '')} ${str(t['pincode'], '')}'),
        KV('Service radius', t['service_radius_km'] == null ? '—' : '${t['service_radius_km']} km'),
        KV('Geo-fence', truthy(t['geo_fence_enabled']) ? 'On' : 'Off'),
        KV('Capacity', '${t['current_jobs'] ?? 0}/${t['max_jobs'] ?? '-'} jobs'),
        KV('Availability', humanize(t['availability_status'])),
        if (truthy(t['vacation_mode'])) KV('Vacation until', fmtDate(t['vacation_until'])),
        KV('Last known location', loc.isEmpty ? '—' : '${loc['lat']}, ${loc['lng']} (${ago(loc['updated_at'])})'),
        KV('Joined', fmtDate(t['created_at'])),
      ]),
      const Gap(),
      SectionCard(title: 'Skills & services', children: [
        Wrap(spacing: 6, runSpacing: 6, children: [for (final s in ApiRes.asList(d['skills'])) Chip(label: Text(str(s['skill_name'])))]),
        const Gap(6),
        Text(ApiRes.asList(d['services']).map((s) => s['service_name']).join(', '), style: const TextStyle(color: C.body)),
      ]),
      const Gap(),
      SectionCard(title: 'Bank details', children: [
        for (final b in ApiRes.asList(d['bankDetails'])) ...[
          KV('Account holder', b['account_holder_name'] ?? b['acount_holder_name']),
          KV('Bank', b['bank_name']),
          KV('Account number', b['account_number']),
          KV('IFSC', b['ifsc_code'] ?? b['ifsc_number']),
          KV('Verified', truthy(b['is_verified']) ? 'Yes' : 'No'),
        ],
        if (ApiRes.asList(d['bankDetails']).isEmpty) const Text('No bank details', style: TextStyle(color: C.muted)),
      ]),
      const Gap(),
      SectionCard(title: 'Referral', children: [
        KV('Referral code', t['referral_code']),
        KV('Referred', '${ref['total_referrals'] ?? 0} (${ref['rewarded'] ?? 0} rewarded, ${ref['pending'] ?? 0} pending)'),
        KV('Reward earned', inr(ref['total_earned'])),
        if (ref['referred_by'] != null) KV('Referred by', ApiRes.asMap(ref['referred_by'])['name']),
      ]),
      const Gap(40),
    ]);
  }

  Widget _documents(Map d) {
    final docs = ApiRes.asList(d['documents']);
    final selfie = ApiRes.asMap(d['selfie']);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(title: 'Selfie verification', trailing: StatusChip(ApiRes.asMap(selfie['review'])['status'] ?? (truthy(selfie['is_verified']) ? 'approved' : 'pending')), children: [
        NetImage(selfie['url'], size: 160, label: 'Selfie'),
      ]),
      const Gap(),
      if (docs.isEmpty) const EmptyView('No documents uploaded'),
      for (final doc in docs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SectionCard(title: str(doc['document_type']), trailing: StatusChip(ApiRes.asMap(doc['review'])['status'] ?? (truthy(doc['is_verified']) ? 'approved' : 'pending')), children: [
            NetImage(doc['attachment_url'] ?? doc['attachement'], size: 160, label: str(doc['document_type'])),
            if (ApiRes.asMap(doc['review'])['remark'] != null) Text('Note: ${ApiRes.asMap(doc['review'])['remark']}', style: const TextStyle(color: C.red)),
          ]),
        ),
    ]);
  }

  Widget _jobs(Map d, List<Map<String, dynamic>> offers) {
    final jobs = ApiRes.asList(d['recentJobs']);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(title: 'Pending job requests', children: [
        if (offers.isEmpty) const Text('No pending offers', style: TextStyle(color: C.muted)),
        for (final o in offers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${str(o['booking_uid'])} · ${str(o['service_name'])}'),
            subtitle: Text('${str(o['customer_name'])} · ${fmtDate(o['scheduled_date'])} ${fmtTime(o['scheduled_time'])}\nExpires ${fmtDateTime(o['expires_at'])}'),
            isThreeLine: true,
            trailing: _canEdit ? FilledButton.tonal(onPressed: () => _acceptOffer(o), child: const Text('Accept')) : null,
          ),
      ]),
      const Gap(),
      SectionCard(title: 'Recent jobs', children: [
        if (jobs.isEmpty) const Text('No jobs yet', style: TextStyle(color: C.muted)),
        for (final j in jobs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${str(j['booking_uid'])} · ${str(j['service_name'])}'),
            subtitle: Text('${str(j['customer_name'])} · ${fmtDate(j['scheduled_date'])}'),
            trailing: Text(inr(j['final_price']), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: j['booking_id']))),
          ),
      ]),
    ]);
  }
}

// ─── Schedule & availability ─────────────────────────────────────────────────

class TechnicianSchedule extends StatefulWidget {
  const TechnicianSchedule({super.key, required this.technicianId, required this.canEdit});
  final int technicianId;
  final bool canEdit;
  @override
  State<TechnicianSchedule> createState() => _TechnicianScheduleState();
}

class _TechnicianScheduleState extends State<TechnicianSchedule> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();
  String get _b => '/admin/scheduling/technicians/${widget.technicianId}';

  @override
  bool get wantKeepAlive => true;

  Future<ApiRes> _load() async {
    final r = await Future.wait([
      api.get('$_b/working-hours'),
      api.get('$_b/time-off', {'from': DateTime.now().toUtc().toIso8601String()}),
      api.get('$_b/schedule-requests'),
      api.get('$_b/timeline', {'from': ymd(DateTime.now()), 'days': '7'}),
    ]);
    if (!r[0].ok) return r[0];
    return ApiRes({'status': true, 'hours': r[0].data, 'off': r[1].ok ? r[1].data : [], 'reqs': r[2].ok ? r[2].data : [], 'timeline': r[3].ok ? r[3].data : null});
  }

  Future<void> _editHours(Map<int, List<Map<String, String>>> saved) async {
    final draft = {for (final d in _weekOrder) d: [for (final w in saved[d]!) Map<String, String>.from(w)]};
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _HoursEditor(draft: draft)));
    if (ok != true || !mounted) return;
    final allEmpty = _weekOrder.every((d) => draft[d]!.isEmpty);
    if (allEmpty && !await confirm(context, 'Clear the weekly schedule?', message: 'The technician is then treated as available at any time.', danger: true, ok: 'Clear')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.put('$_b/working-hours', {
          'days': allEmpty
              ? []
              : [for (final d in _weekOrder) {'day_of_week': d, 'windows': [for (final w in draft[d]!) {'start_time': w['start'], 'end_time': w['end']}]}],
        }), success: 'Working hours saved');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _addOff() async {
    var type = 'LEAVE';
    var starts = DateTime.now().add(const Duration(days: 1));
    var ends = DateTime.now().add(const Duration(days: 2));
    final reason = TextEditingController();
    Future<DateTime?> pick(BuildContext c, DateTime init) async {
      final d = await showDatePicker(context: c, initialDate: init, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
      if (d == null || !c.mounted) return null;
      final t = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(init));
      return DateTime(d.year, d.month, d.day, t?.hour ?? init.hour, t?.minute ?? init.minute);
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Leave, blocked time & holidays', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Gap(8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final e in _offTypes.entries) ChoiceChip(label: Text(e.value), selected: type == e.key, onSelected: (_) => set(() => type = e.key))]),
              const Gap(8),
              OutlinedButton(onPressed: () async {
                final v = await pick(c, starts);
                if (v != null) set(() => starts = v);
              }, child: Text('From ${fmtDateTime(starts)}')),
              const Gap(6),
              OutlinedButton(onPressed: () async {
                final v = await pick(c, ends);
                if (v != null) set(() => ends = v);
              }, child: Text('To ${fmtDateTime(ends)}')),
              const Gap(8),
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
              const Gap(),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
            ]),
          )),
    );
    if (ok != true || !mounted) return;
    if (!starts.isBefore(ends)) return toast('Start must be before end', error: true);
    final r = await busy(context, () => api.post('$_b/time-off', {
          'starts_at': starts.toUtc().toIso8601String(),
          'ends_at': ends.toUtc().toIso8601String(),
          'type': type,
          if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
        }), toastIt: false);
    if (r.ok) {
      final clashes = ApiRes.asList(r.map['conflicting_jobs']).length;
      toast(clashes > 0 ? 'Time off added — $clashes job(s) fall in this period, reassign them.' : 'Time off added');
      _key.currentState?.reload();
    } else {
      toastRes(r);
    }
  }

  Future<void> _removeOff(Map t) async {
    if (!await confirm(context, 'Remove this time off?', danger: true, ok: 'Remove')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.delete('$_b/time-off/${t['time_off_id']}'), success: 'Removed');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _reviewOff(Map t, String decision) async {
    String? note;
    if (decision == 'reject') {
      note = await prompt(context, 'Reject time off', label: 'Reason (shown to the technician)', lines: 3, ok: 'Reject');
      if (note == null) return;
    }
    if (!mounted) return;
    final r = await busy(context, () => api.post('$_b/time-off/${t['time_off_id']}/$decision', {if (note != null && note.isNotEmpty) 'note': note}), success: decision == 'approve' ? 'Approved' : 'Rejected');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _reviewRequest(Map req, String decision) async {
    String? note;
    if (decision == 'approve' && !await confirm(context, 'Apply requested schedule?', message: "Replace the technician's working hours with the requested schedule?", ok: 'Apply')) return;
    if (decision == 'reject') {
      if (!mounted) return;
      note = await prompt(context, 'Reject schedule request', label: 'Reason (shown to the technician)', lines: 3, ok: 'Reject');
      if (note == null) return;
    }
    if (!mounted) return;
    final r = await busy(context, () => api.post('$_b/schedule-requests/${req['request_id']}/$decision', {if (note != null && note.isNotEmpty) 'note': note}), success: decision == 'approve' ? 'Schedule applied' : 'Request rejected');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ApiLoader(
      key: _key,
      load: _load,
      builder: (c, res, reload) {
        final hours = ApiRes.asList(res['hours']);
        final saved = {
          for (final d in _weekOrder)
            d: [for (final h in hours.where((h) => toInt(h['day_of_week']) == d && truthy(h['is_available']))) {'start': _hm(h['start_time']), 'end': _hm(h['end_time'])}],
        };
        final offs = ApiRes.asList(res['off']);
        final reqs = ApiRes.asList(res['reqs']);
        final pendingReq = reqs.where((r) => r['status'] == 'PENDING').firstOrNull;
        final tl = ApiRes.asMap(res['timeline']);
        final days = ApiRes.asList(tl['days']);
        return ListView(padding: const EdgeInsets.all(12), children: [
          if (tl.isNotEmpty)
            Text('Live status: ${truthy(ApiRes.asMap(tl['technician'])['is_online']) ? 'Online' : 'Offline'} (separate from working hours — dispatch needs both)', style: const TextStyle(color: C.body, fontSize: 12.5)),
          if (pendingReq != null || offs.any((o) => o['status'] == 'PENDING')) ...[
            const Gap(8),
            SectionCard(title: 'Requests waiting for approval', children: [
              if (pendingReq != null) ...[
                const Text('New weekly schedule', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final d in ApiRes.asList(pendingReq['days']))
                  Text('${_days[toInt(d['day_of_week'])!]}: ${ApiRes.asList(d['windows']).map((w) => '${_hm(w['start_time'])}–${_hm(w['end_time'])}').join(', ').isEmpty ? 'Off' : ApiRes.asList(d['windows']).map((w) => '${_hm(w['start_time'])}–${_hm(w['end_time'])}').join(', ')}'),
                if (pendingReq['note'] != null) Text('Note: ${pendingReq['note']}', style: const TextStyle(color: C.body)),
                if (widget.canEdit)
                  Row(children: [
                    TextButton(onPressed: () => _reviewRequest(pendingReq, 'reject'), child: const Text('Reject')),
                    FilledButton(onPressed: () => _reviewRequest(pendingReq, 'approve'), child: const Text('Approve')),
                  ]),
                const Divider(),
              ],
              for (final o in offs.where((o) => o['status'] == 'PENDING'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_offTypes[o['off_type']] ?? humanize(o['off_type'])} · ${fmtDateTime(o['starts_at'])} → ${fmtDateTime(o['ends_at'])}'),
                  subtitle: Text(str(o['reason'], '')),
                  trailing: !widget.canEdit
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(onPressed: () => _reviewOff(o, 'reject'), icon: const Icon(Icons.close, color: C.red)),
                          IconButton(onPressed: () => _reviewOff(o, 'approve'), icon: const Icon(Icons.check, color: C.green)),
                        ]),
                ),
            ]),
          ],
          const Gap(),
          SectionCard(
            title: 'Weekly working hours',
            trailing: widget.canEdit ? TextButton(onPressed: () => _editHours(saved), child: const Text('Edit')) : null,
            children: [
              if (hours.isEmpty) const Text('No hours set — available at any time.', style: TextStyle(color: C.muted)),
              for (final d in _weekOrder)
                if (hours.isNotEmpty) KV(_days[d], saved[d]!.isEmpty ? 'Off' : saved[d]!.map((w) => '${fmtTime(w['start'])}–${fmtTime(w['end'])}').join(', ')),
            ],
          ),
          const Gap(),
          SectionCard(
            title: 'Leave, blocked time & holidays',
            trailing: widget.canEdit ? TextButton(onPressed: _addOff, child: const Text('Add')) : null,
            children: [
              if (offs.where((o) => o['status'] != 'PENDING').isEmpty) const Text('Nothing upcoming.', style: TextStyle(color: C.muted)),
              for (final o in offs.where((o) => o['status'] != 'PENDING'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_offTypes[o['off_type']] ?? humanize(o['off_type'])} · ${fmtDateTime(o['starts_at'])} → ${fmtDateTime(o['ends_at'])}'),
                  subtitle: Text([o['reason'], o['status'], o['review_note']].whereType<Object>().join(' · ')),
                  trailing: widget.canEdit ? IconButton(onPressed: () => _removeOff(o), icon: const Icon(Icons.delete_outline, color: C.red)) : null,
                ),
            ],
          ),
          const Gap(),
          SectionCard(title: 'Next 7 days', children: [
            for (final day in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${fmtDate(day['date'])} · ${_days[(toInt(day['weekday']) ?? 0) % 7]}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    !truthy(day['hours_set'])
                        ? 'Any time'
                        : ApiRes.asList(day['working']).map((w) => '${_hm(w['start'])}–${_hm(w['end'])}').join(', ').isEmpty
                            ? 'Not working'
                            : 'Working ${ApiRes.asList(day['working']).map((w) => '${_hm(w['start'])}–${_hm(w['end'])}').join(', ')}',
                    style: const TextStyle(fontSize: 12.5, color: C.body),
                  ),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final s in ApiRes.asList(day['segments']))
                      StatusChip(s['type'], label: '${humanize(s['type'])} ${_hm(s['start'])}–${_hm(s['end'])}'),
                  ]),
                ]),
              ),
          ]),
          const Gap(40),
        ]);
      },
    );
  }
}

class _HoursEditor extends StatefulWidget {
  const _HoursEditor({required this.draft});
  final Map<int, List<Map<String, String>>> draft;
  @override
  State<_HoursEditor> createState() => _HoursEditorState();
}

class _HoursEditorState extends State<_HoursEditor> {
  int _copyFrom = 1;

  int _m(String t) => (int.tryParse(t.split(':')[0]) ?? 0) * 60 + (int.tryParse(t.split(':')[1]) ?? 0);

  Future<String?> _time(String? init) async {
    final m = _m(init ?? '09:00');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    return t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String? _error() {
    for (final d in _weekOrder) {
      final w = widget.draft[d]!;
      for (final x in w) {
        if (_m(x['start']!) >= _m(x['end']!)) return '${_days[d]}: start must be before end';
      }
      for (var i = 0; i < w.length; i++) {
        for (var j = i + 1; j < w.length; j++) {
          if (_m(w[i]['start']!) < _m(w[j]['end']!) && _m(w[j]['start']!) < _m(w[i]['end']!)) return '${_days[d]}: windows overlap';
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly working hours')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          const Text('Copy '),
          DropdownButton<int>(value: _copyFrom, items: [for (final d in _weekOrder) DropdownMenuItem(value: d, child: Text(_days[d]))], onChanged: (v) => setState(() => _copyFrom = v!)),
          TextButton(
            onPressed: () => setState(() {
              for (final d in _weekOrder) {
                widget.draft[d] = [for (final w in widget.draft[_copyFrom]!) Map<String, String>.from(w)];
              }
            }),
            child: const Text('to all days'),
          ),
        ]),
        for (final d in _weekOrder)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_days[d], style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton.icon(onPressed: () => setState(() => widget.draft[d]!.add({'start': '09:00', 'end': '18:00'})), icon: const Icon(Icons.add, size: 18), label: const Text('Window')),
                ]),
                if (widget.draft[d]!.isEmpty) const Text('Off', style: TextStyle(color: C.muted)),
                for (var i = 0; i < widget.draft[d]!.length; i++)
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () async {
                      final v = await _time(widget.draft[d]![i]['start']);
                      if (v != null) setState(() => widget.draft[d]![i]['start'] = v);
                    }, child: Text(fmtTime(widget.draft[d]![i]['start'])))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                    Expanded(child: OutlinedButton(onPressed: () async {
                      final v = await _time(widget.draft[d]![i]['end']);
                      if (v != null) setState(() => widget.draft[d]![i]['end'] = v);
                    }, child: Text(fmtTime(widget.draft[d]![i]['end'])))),
                    IconButton(onPressed: () => setState(() => widget.draft[d]!.removeAt(i)), icon: const Icon(Icons.close, color: C.red)),
                  ]),
              ]),
            ),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () {
              final e = _error();
              if (e != null) return toast(e, error: true);
              Navigator.pop(context, true);
            },
            child: const Text('Save working hours'),
          ),
        ),
      ),
    );
  }
}
