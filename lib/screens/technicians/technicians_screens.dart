import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'technician_detail_screen.dart';

const kTechPath = '/admin/technician-management/technicians';
const kAppsPath = '/admin/technician-management/applications';

// ─── Applications ────────────────────────────────────────────────────────────

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});
  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = 'pending';

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      searchHint: 'Search name, mobile, email…',
      fetch: (p, l, s) => api.post('/admin/technicians/paginated', {'page': p, 'limit': l, 'search': s, if (_status.isNotEmpty) 'applicationStatus': _status}),
      header: FilterChips<String>(options: const {'pending': 'Pending review', 'approved': 'Approved', 'rejected': 'Rejected', '': 'All'}, value: _status, onChanged: (v) {
        setState(() => _status = v);
        _list.currentState?.reload();
      }),
      itemBuilder: (c, r, i) => RowTile(
        leading: Avatar(url: r['selfie_photo'], name: fullName(r)),
        title: fullName(r),
        badge: StatusChip(r['application_status'] ?? 'pending'),
        subtitle: '${str(r['mobile_number'], '')} · ${[r['city'], r['state']].where((e) => e != null).join(', ')}',
        lines: [
          'Docs ${r['uploaded_mandatory_documents_count'] ?? 0}/${r['mandatory_documents_count'] ?? 0} · sections ${r['approved_sections_count'] ?? 0} approved, ${r['rejected_sections_count'] ?? 0} rejected',
          'Applied ${fmtDate(r['created_at'])}',
        ],
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ApplicationReviewScreen(id: r['technician_id'])));
          _list.currentState?.reload();
        },
      ),
    );
  }
}

/// Section-by-section KYC review: approve each section, reject one section
/// for correction, or reject the whole application.
class ApplicationReviewScreen extends StatefulWidget {
  const ApplicationReviewScreen({super.key, required this.id});
  final dynamic id;
  @override
  State<ApplicationReviewScreen> createState() => _ApplicationReviewScreenState();
}

class _ApplicationReviewScreenState extends State<ApplicationReviewScreen> {
  final _key = GlobalKey<ApiLoaderState>();
  int get _id => toInt(widget.id)!;
  bool get _canEdit => Session.I.canOn(kAppsPath, 'EDIT') || Session.I.can('TECHNICIAN_APPROVE');

  Future<void> _review(String section, String status) async {
    String? remark;
    if (status == 'rejected') {
      remark = await prompt(context, 'Reject this section', label: 'Reason (shown to the technician)', required: true, lines: 3, ok: 'Reject');
      if (remark == null) return;
    }
    if (!mounted) return;
    final r = await busy(context, () => api.post('/admin/technicians/review-section', {'technicianId': _id, 'section': section, 'status': status, 'remark': ?remark}), toastIt: false);
    if (!r.ok) {
      toastRes(r);
      return;
    }
    if (r['fully_approved'] == true) {
      toast('Technician approved${r['technician_unique_id'] != null ? ' · ID ${r['technician_unique_id']}' : ''}');
    } else {
      toast(status == 'approved' ? 'Section approved' : 'Section rejected — technician notified');
    }
    _key.currentState?.reload();
  }

  Future<void> _approveRemaining(List<(String, String)> pending) async {
    if (!await confirm(context, 'Approve ${pending.length} remaining section(s)?', message: '${pending.map((e) => e.$2).join(', ')} will be marked approved. Make sure you’ve checked them.', ok: 'Approve all')) return;
    if (!mounted) return;
    final r = await busy(context, () async {
      ApiRes last = ApiRes({'status': true});
      for (final p in pending) {
        last = await api.post('/admin/technicians/review-section', {'technicianId': _id, 'section': p.$1, 'status': 'approved'});
        if (!last.ok) break;
      }
      return last;
    }, toastIt: false);
    toastRes(r, success: r['fully_approved'] == true ? 'Technician approved${r['technician_unique_id'] != null ? ' · ID ${r['technician_unique_id']}' : ''}' : 'Sections approved');
    _key.currentState?.reload();
  }

  Future<void> _rejectAll() async {
    final reason = await prompt(context, 'Reject entire application', label: 'Reason (shown to the technician)', required: true, lines: 3, ok: 'Reject application');
    if (reason == null || !mounted) return;
    final r = await busy(context, () => api.post('/admin/technicians/approve', {'technicianId': _id, 'isActive': false, 'applicationStatus': 'rejected', 'rejectRemark': reason}), success: 'Application rejected. The technician has been notified.');
    if (r.ok && mounted) Navigator.pop(context);
  }

  Widget _section(String key, String title, Map? review, List<Widget> body, {String? hint}) {
    final status = str(review?['status'], 'pending');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(title: title, trailing: StatusChip(status), children: [
        if (hint != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(hint, style: const TextStyle(fontSize: 12, color: C.muted))),
        ...body,
        if (review?['remark'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Note: ${review!['remark']}', style: const TextStyle(color: C.red, fontSize: 12.5))),
        if (_canEdit) ...[
          const Gap(8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: status == 'rejected' ? null : () => _review(key, 'rejected'), child: const Text('Reject'))),
            const Gap(8),
            Expanded(child: FilledButton(onPressed: status == 'approved' ? null : () => _review(key, 'approved'), child: const Text('Approve'))),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review application')),
      body: ApiLoader(
        key: _key,
        load: () => api.post('/admin/technicians/detail', {'technicianId': _id}),
        builder: (c, res, reload) {
          final d = res.map;
          final t = ApiRes.asMap(d['technician']);
          final docs = ApiRes.asList(d['documents']);
          final sr = ApiRes.asMap(d['sectionReviews']);
          final selfie = ApiRes.asMap(d['selfie']);
          final bankList = d['bankDetails'] is List ? ApiRes.asList(d['bankDetails']) : [ApiRes.asMap(d['bankDetails'] ?? d['bank'])];
          final bank = bankList.isNotEmpty ? bankList.first : <String, dynamic>{};
          final skills = ApiRes.asList(d['skills']);
          final services = ApiRes.asList(d['services']);
          final selfieReview = selfie['review'] ?? (truthy(t['is_selfie_verified']) ? {'status': 'approved'} : null);
          final steps = <(String, String, dynamic)>[
            ('personal_info', 'Personal details', sr['personal_info']),
            ('skills', 'Skills & category', sr['skills']),
            for (final doc in docs) (str(doc['section_key']), _docTitle(doc), doc['review']),
            ('selfie', 'Selfie', selfieReview),
            ('bank', 'Payout method', sr['bank']),
          ];
          final approved = steps.where((s) => ApiRes.asMap(s.$3)['status'] == 'approved').length;
          final pending = steps.where((s) => !const ['approved', 'rejected'].contains(ApiRes.asMap(s.$3)['status'])).map((s) => (s.$1, s.$2)).toList();
          final idPhoto = docs.map((x) => x['attachment_url'] ?? x['attachement'] ?? x['attachment']).firstWhere((u) => u != null && !'$u'.toLowerCase().endsWith('.pdf'), orElse: () => null);
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(children: [
              Row(children: [
                Avatar(url: selfie['url'] ?? t['selfie_url'] ?? t['selfie_photo'], name: fullName(t), size: 52),
                const Gap(),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fullName(t), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text([t['city'], t['state'], t['pincode']].where((e) => e != null).join(', '), style: const TextStyle(color: C.body)),
                ])),
                StatusChip(t['application_status'] ?? 'pending'),
              ]),
              const Gap(10),
              const Text('Review progress', style: TextStyle(fontWeight: FontWeight.w600)),
              const Gap(4),
              LinearProgressIndicator(value: steps.isEmpty ? 0 : approved / steps.length, minHeight: 6, borderRadius: BorderRadius.circular(4)),
              Text('$approved of ${steps.length} sections approved', style: const TextStyle(fontSize: 12, color: C.muted)),
              if (t['application_reject_reason'] != null) Text('Rejection reason: ${t['application_reject_reason']}', style: const TextStyle(color: C.red)),
              if (t['technician_unique_id'] != null) KV('Technician ID', t['technician_unique_id']),
              const Text('To ask for one correction, reject just that section.', style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
            const Gap(),
            _section('personal_info', 'Personal details', ApiRes.asMap(sr['personal_info']), [
              KV('Full name', fullName(t)),
              KV('Mobile number', t['mobile_number']),
              KV('Email', t['email']),
              KV('Address', t['address']),
              KV('City', t['city']),
              KV('State', t['state']),
              KV('Pincode', t['pincode']),
            ], hint: 'Check the name and address match the ID document'),
            _section('skills', 'Skills & category', ApiRes.asMap(sr['skills']), [
              KV('Category', t['category_name']),
              KV('Sub-category', t['sub_category_name']),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final s in skills) Chip(label: Text(str(s['skill_name'] ?? s['service_name'] ?? s['service'])))]),
              if (services.isNotEmpty) ...[
                const Gap(6),
                const Text('Services this technician wants to take jobs for', style: TextStyle(fontSize: 12, color: C.muted)),
                Text(services.map((s) => s['service_name'] ?? s['service']).join(', ')),
              ],
            ]),
            for (final doc in docs)
              _section(str(doc['section_key']), _docTitle(doc), ApiRes.asMap(doc['review']), [
                KV('Type', doc['document_type_name'] ?? doc['document_type']),
                if (doc['document_number'] != null) KV('Document number', doc['document_number']),
                KV('Uploaded', fmtDateTime(doc['created_at'])),
                const Gap(6),
                NetImage(doc['attachment_url'] ?? doc['attachement'] ?? doc['attachment'], size: 160, label: _docTitle(doc)),
              ], hint: 'Check the photo is clear and the number is readable'),
            _section('selfie', 'Selfie', ApiRes.asMap(selfieReview), [
              Row(children: [
                Expanded(child: Column(children: [NetImage(selfie['url'] ?? t['selfie_url'] ?? t['selfie_photo'], size: 140, label: 'Selfie'), const Text('Selfie', style: TextStyle(fontSize: 12))])),
                Expanded(child: Column(children: [NetImage(idPhoto, size: 140, label: 'ID photo'), const Text('ID document', style: TextStyle(fontSize: 12))])),
              ]),
            ], hint: 'Make sure the face matches the photo on the ID'),
            _section('bank', 'Payout method', ApiRes.asMap(sr['bank']), [
              if (bank.isEmpty) const Text('No payout details submitted', style: TextStyle(color: C.muted)),
              if (bank.isNotEmpty) ...[
                KV('Account holder', bank['acount_holder_name'] ?? bank['account_holder_name']),
                KV('Account number', bank['account_number']),
                KV('IFSC code', bank['ifsc_number'] ?? bank['ifsc_code']),
                KV('Type', bank['account_type'] ?? bank['bank_name']),
              ],
            ], hint: 'Where this technician’s earnings will be paid'),
            if (_canEdit) ...[
              if (pending.isNotEmpty) FilledButton.icon(onPressed: () => _approveRemaining(pending), icon: const Icon(Icons.done_all), label: Text('Approve ${pending.length} remaining')),
              const Gap(8),
              OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: C.red), onPressed: _rejectAll, child: const Text('Reject entire application')),
            ],
            const Gap(40),
          ]);
        },
      ),
    );
  }

  String _docTitle(Map doc) {
    final name = str(doc['document_type_name'] ?? doc['document_type'], 'Document');
    final side = doc['page_type'];
    return side == null || side == 'SINGLE' ? name : '$name (${humanize(side)})';
  }
}

// ─── Technicians list ────────────────────────────────────────────────────────

class TechniciansScreen extends StatefulWidget {
  const TechniciansScreen({super.key});
  @override
  State<TechniciansScreen> createState() => _TechniciansScreenState();
}

class _TechniciansScreenState extends State<TechniciansScreen> {
  final _list = GlobalKey<PagedListState>();
  bool _activeOnly = false;
  String _status = 'approved';
  bool get _canEdit => Session.I.canOn(kTechPath, 'EDIT');

  Future<void> _toggle(Map r) async {
    final on = truthy(r['is_active']);
    if (on && !await confirm(context, 'Deactivate this technician?', message: 'They stop receiving jobs and cannot log in until you activate them again.', danger: true, ok: 'Deactivate')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.post('/admin/technicians/approve', {'technicianId': r['technician_id'], 'isActive': !on}), success: 'Status updated.');
    if (res.ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search name, mobile, code…',
        fetch: (p, l, s) => api.post('/admin/technicians/paginated', {'page': p, 'limit': l, 'search': s, if (_activeOnly) 'isActive': true, if (_status.isNotEmpty) 'applicationStatus': _status}),
        header: Row(children: [
          Expanded(child: FilterChips<String>(options: const {'approved': 'Approved', 'pending': 'Pending', 'rejected': 'Rejected', '': 'All'}, value: _status, onChanged: (v) {
            setState(() => _status = v);
            _list.currentState?.reload();
          })),
          FilterChip(label: const Text('Active'), selected: _activeOnly, onSelected: (v) {
            setState(() => _activeOnly = v);
            _list.currentState?.reload();
          }),
          const Gap(8),
        ]),
        itemBuilder: (c, r, i) => RowTile(
          leading: Stack(children: [
            Avatar(url: r['selfie_photo'], name: fullName(r)),
            if (truthy(r['is_online'])) const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 6, backgroundColor: Colors.white, child: CircleAvatar(radius: 4.5, backgroundColor: C.green))),
          ]),
          title: fullName(r),
          badge: StatusChip(truthy(r['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(r['is_active']) ? 'Active' : 'Inactive'),
          subtitle: '${str(r['technician_unique_id'], '')} · ${str(r['mobile_number'], '')}',
          lines: ['${str(r['city'], '')} · ${humanize(r['application_status'])}'],
          trailing: !_canEdit
              ? null
              : PopupMenuButton<String>(
                  onSelected: (v) => _toggle(r),
                  itemBuilder: (_) => [PopupMenuItem(value: 't', child: Text(truthy(r['is_active']) ? 'Deactivate' : 'Activate'))],
                ),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => TechnicianDetailScreen(id: r['technician_id'])));
            _list.currentState?.reload();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'techmap',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TechnicianMapScreen())),
        icon: const Icon(Icons.map_outlined),
        label: const Text('Live map'),
      ),
    );
  }
}

// ─── Live map (GET /admin/realtime/technicians) ──────────────────────────────

class TechnicianMapScreen extends StatefulWidget {
  const TechnicianMapScreen({super.key});
  @override
  State<TechnicianMapScreen> createState() => _TechnicianMapScreenState();
}

class _TechnicianMapScreenState extends State<TechnicianMapScreen> {
  List<Map<String, dynamic>>? _techs;
  Timer? _timer;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await api.get('/admin/realtime/technicians');
    if (!mounted) return;
    final first = _techs == null;
    setState(() => _techs = r.list.where((t) => truthy(t['is_online']) && t['latitude'] != null && t['longitude'] != null).toList());
    if (first && _techs!.isNotEmpty) _fit();
  }

  void _fit() {
    if (_map == null || _techs == null || _techs!.isEmpty) return;
    final lats = _techs!.map((t) => toNum(t['latitude'])), lngs = _techs!.map((t) => toNum(t['longitude']));
    final sw = LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b));
    final ne = LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b));
    _map!.animateCamera(_techs!.length == 1 ? CameraUpdate.newLatLngZoom(sw, 14) : CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 60));
  }

  @override
  Widget build(BuildContext context) {
    final techs = _techs;
    return Scaffold(
      appBar: AppBar(title: Text(techs == null ? 'Live map' : 'Live map · ${techs.length} online'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: techs == null
          ? const Center(child: CircularProgressIndicator())
          : techs.isEmpty
              ? const EmptyView('No technicians are online with a known location right now.', icon: Icons.location_off_outlined)
              : GoogleMap(
                  initialCameraPosition: CameraPosition(target: LatLng(toNum(techs.first['latitude']), toNum(techs.first['longitude'])), zoom: 12),
                  onMapCreated: (c) {
                    _map = c;
                    _fit();
                  },
                  markers: {
                    for (final t in techs)
                      Marker(
                        markerId: MarkerId('t${t['technician_id']}'),
                        position: LatLng(toNum(t['latitude']), toNum(t['longitude'])),
                        icon: BitmapDescriptor.defaultMarkerWithHue((toInt(t['current_jobs']) ?? 0) > 0 ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueGreen),
                        infoWindow: InfoWindow(
                          title: fullName(t),
                          snippet: '${t['current_jobs'] ?? 0} active job(s) · tap for profile',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TechnicianDetailScreen(id: t['technician_id']))),
                        ),
                      ),
                  },
                ),
    );
  }
}

// ─── Skill requests ──────────────────────────────────────────────────────────

class SkillRequestsScreen extends StatefulWidget {
  const SkillRequestsScreen({super.key});
  @override
  State<SkillRequestsScreen> createState() => _SkillRequestsScreenState();
}

class _SkillRequestsScreenState extends State<SkillRequestsScreen> {
  String _tab = 'P';
  final _key = GlobalKey<ApiLoaderState>();
  bool get _canEdit => Session.I.canOn('/admin/technician-management/skill-requests', 'EDIT');

  Future<void> _decide(Map r, bool approved) async {
    String? remark;
    if (!approved) {
      remark = await prompt(context, 'Reject request', label: 'Reason (shown to the technician)', lines: 3, ok: 'Reject');
      if (remark == null) return;
    }
    if (!mounted) return;
    final res = await busy(context, () => api.post('/admin/technicians/skill-requests/${r['request_id']}/decide', {'approved': approved, if (remark != null && remark.isNotEmpty) 'remark': remark}), success: approved ? 'Skills updated' : 'Request rejected');
    if (res.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      FilterChips<String>(options: const {'P': 'Pending', 'A': 'Approved', 'R': 'Rejected', 'all': 'All'}, value: _tab, onChanged: (v) => setState(() => _tab = v)),
      Expanded(
        child: ApiLoader(
          key: ValueKey(_tab),
          load: () => api.get('/admin/technicians/skill-requests', {'status': _tab}),
          builder: (c, res, reload) {
            final rows = res.list;
            if (rows.isEmpty) return ListView(children: const [EmptyView('No requests.')]);
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (c, i) {
                final r = rows[i];
                final cur = List<String>.from((r['current_skills'] as List?)?.map((e) => '$e') ?? const []);
                final req = List<String>.from((r['requested_skills'] as List?)?.map((e) => '$e') ?? const []);
                return SectionCard(
                  title: '${str(r['technician_name'])} · ${str(r['technician_unique_id'], '')}',
                  trailing: StatusChip(const {'P': 'PENDING', 'A': 'APPROVED', 'R': 'REJECTED'}[r['status']] ?? r['status']),
                  children: [
                    Text('${str(r['mobile_number'], '')} · ${fmtDateTime(r['created_at'])}', style: const TextStyle(color: C.muted, fontSize: 12)),
                    const Gap(6),
                    const Text('Current', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(cur.isEmpty ? 'None' : cur.join(', ')),
                    const Gap(4),
                    const Text('Requested', style: TextStyle(fontWeight: FontWeight.w600)),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final s in req.toSet().union(cur.toSet()))
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s),
                          backgroundColor: !cur.contains(s) ? C.greenSoft : (!req.contains(s) ? C.redSoft : null),
                        ),
                    ]),
                    if (r['note'] != null) Text('Note: ${r['note']}', style: const TextStyle(fontSize: 12.5)),
                    if (r['admin_remark'] != null) Text('Admin remark: ${r['admin_remark']}', style: const TextStyle(fontSize: 12.5, color: C.red)),
                    if (_canEdit && r['status'] == 'P') ...[
                      const Gap(8),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => _decide(r, false), child: const Text('Reject'))),
                        const Gap(8),
                        Expanded(child: FilledButton(onPressed: () => _decide(r, true), child: const Text('Approve'))),
                      ]),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ─── Referrals (/master/referrals) ───────────────────────────────────────────

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});
  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = '';
  String _type = '';

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      searchHint: 'Search code, name, mobile…',
      fetch: (p, l, s) => api.get('/master/referrals', {'page': p, 'limit': l, 'search': s, if (_status.isNotEmpty) 'status': _status, if (_type.isNotEmpty) 'referrer_type': _type}),
      header: Column(children: [
        FilterChips<String>(options: const {'': 'All statuses', 'PENDING': 'Pending', 'REWARDED': 'Rewarded', 'REJECTED': 'Rejected'}, value: _status, onChanged: (v) {
          setState(() => _status = v);
          _list.currentState?.reload();
        }),
        FilterChips<String>(options: const {'': 'All types', 'CUSTOMER': 'Customer', 'TECHNICIAN': 'Technician'}, value: _type, onChanged: (v) {
          setState(() => _type = v);
          _list.currentState?.reload();
        }),
      ]),
      itemBuilder: (c, r, i) => RowTile(
        title: '${str(r['referrer_name'])} → ${str(r['referred_name'])}',
        badge: StatusChip(r['status']),
        subtitle: 'Code ${str(r['referral_code'])} · ${humanize(r['referrer_type'])}',
        lines: [
          '${str(r['referrer_mobile'], '')} → ${str(r['referred_mobile'], '')}',
          'Reward ${inr(r['referrer_reward'])} · registered ${fmtDate(r['created_at'])}${r['rewarded_at'] != null ? ' · rewarded ${fmtDate(r['rewarded_at'])}' : ''}',
        ],
      ),
    );
  }
}
