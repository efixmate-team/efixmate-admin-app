import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const _weekOrder = [1, 2, 3, 4, 5, 6, 0];
const _base = '/admin/scheduling';

String _hm(dynamic t) => str(t, '').length >= 5 ? str(t).substring(0, 5) : str(t, '');

int _mins(String t) {
  final p = t.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
}

Future<String?> _pickTime(BuildContext context, String? initial) async {
  final m = _mins(initial ?? '09:00');
  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Area Configuration — every value comes from /admin/scheduling, the same
/// data the availability engine uses.
class AreaConfigScreen extends StatelessWidget {
  const AreaConfigScreen({super.key, required this.area});
  final Map<String, dynamic> area;

  int get id => toInt(area['area_id'])!;

  @override
  Widget build(BuildContext context) {
    final canEdit = Session.I.canOn('/admin/masters/geography/countries', 'EDIT');
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: Text(str(area['area_name'], 'Area configuration')),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Overview'), Tab(text: 'Services'), Tab(text: 'Operating hours'), Tab(text: 'Time slots'),
            Tab(text: 'Capacity'), Tab(text: 'Exceptions'), Tab(text: 'Pricing'), Tab(text: 'Technicians'),
          ]),
        ),
        body: TabBarView(children: [
          _OverviewTab(id),
          _ServicesTab(id, canEdit),
          _HoursTab(id, canEdit),
          _SlotsTab(id, canEdit),
          _CapacityTab(id, canEdit),
          _ExceptionsTab(id, canEdit),
          _PricingTab(id, canEdit),
          _TechniciansTab(id),
        ]),
      ),
    );
  }
}

// ─── Overview ────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab(this.id);
  final int id;

  @override
  Widget build(BuildContext context) {
    return ApiLoader(
      load: () => api.get('$_base/areas/$id/overview'),
      builder: (c, res, reload) {
        final a = ApiRes.asMap(res.map['area']);
        final s = ApiRes.asMap(res.map['serviceability']);
        final today = ApiRes.asMap(s['today']);
        final next = ApiRes.asMap(s['next_bookable']);
        final label = s['serviceable'] != true ? 'Needs setup' : (s['next_bookable'] == null ? 'Nothing bookable' : 'Serviceable');
        final issues = List<String>.from((s['issues'] as List?)?.map((e) => '$e') ?? const []);
        final warnings = List<String>.from((s['warnings'] as List?)?.map((e) => '$e') ?? const []);
        return ListView(padding: const EdgeInsets.all(12), children: [
          SectionCard(title: str(a['area_name']), trailing: StatusChip(label == 'Serviceable' ? 'ACTIVE' : 'PENDING', label: label), children: [
            KV('City', a['city_name']),
            KV('Status', truthy(a['is_active']) ? 'Active' : 'Inactive'),
            KV('Boundary', truthy(a['has_polygon']) ? 'Polygon' : 'Radius ${str(a['radius_km'])} km'),
            KV('Emergency bookings', truthy(a['emergency_available']) ? 'Yes' : 'No'),
            KV('Under-30-min', truthy(a['under_30_min_available']) ? 'Yes' : 'No'),
          ]),
          const Gap(),
          StatGrid([
            StatTile(label: 'Services enabled', value: '${s['services_enabled'] ?? 0}/${s['services_total'] ?? 0}', icon: Icons.home_repair_service_outlined),
            StatTile(label: 'Open days', value: '${s['open_days'] ?? 0}', sub: truthy(s['operating_hours_configured']) ? 'Hours set' : 'Open all day', icon: Icons.schedule),
            StatTile(label: 'Slots enabled', value: '${s['slots_enabled'] ?? 0}', icon: Icons.view_timeline_outlined),
            StatTile(label: 'Technicians', value: '${s['eligible_technicians'] ?? 0}', sub: '${s['technicians_online'] ?? 0} online', icon: Icons.engineering),
            StatTile(label: 'Upcoming exceptions', value: '${s['upcoming_exceptions'] ?? 0}', icon: Icons.event_busy),
            StatTile(label: 'Next bookable', value: next.isEmpty ? '—' : fmtDate(next['date']), sub: next.isEmpty ? 'within 14 days' : '${next['bookable']} slot(s)', icon: Icons.event_available),
          ]),
          const Gap(),
          SectionCard(title: 'Today', children: [
            if (today.isEmpty) const Text('—'),
            if (today.isNotEmpty) ...[
              KV('Closed', truthy(today['closed']) ? 'Yes${today['reason'] != null ? ' (${humanize(today['reason'])})' : ''}' : 'No'),
              KV('Slots', '${today['slots'] ?? 0} (${today['bookable'] ?? '-'} bookable)'),
              KV('Hours', ApiRes.asList(today['operating_windows']).map((w) => '${_hm(w['open'])}–${_hm(w['close'])}').join(', ').ifEmpty('All day')),
            ],
          ]),
          if (issues.isNotEmpty || warnings.isNotEmpty) ...[
            const Gap(),
            SectionCard(title: 'Setup checklist', children: [
              for (final i in issues) ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.error_outline, color: C.red), title: Text(i)),
              for (final w in warnings) ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.warning_amber, color: C.amber), title: Text(w)),
            ]),
          ],
        ]);
      },
    );
  }
}

extension on String {
  String ifEmpty(String v) => isEmpty ? v : this;
}

// ─── Services ────────────────────────────────────────────────────────────────

class _ServicesTab extends StatefulWidget {
  const _ServicesTab(this.id, this.canEdit);
  final int id;
  final bool canEdit;
  @override
  State<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<_ServicesTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();
  final _sel = <int>{};
  String _q = '';
  String _status = '';

  @override
  bool get wantKeepAlive => true;

  Future<void> _set(List<int> ids, bool enabled) async {
    if (!enabled && !await confirm(context, 'Disable ${ids.length} service(s) in this area?', message: "Customers won't be able to book them here. Their slot configuration is kept.", danger: true, ok: 'Disable')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.put('$_base/areas/${widget.id}/services', {'service_ids': ids, 'enabled': enabled}), success: '${ids.length} service(s) ${enabled ? 'enabled' : 'disabled'}');
    if (r.ok) {
      _sel.clear();
      _key.currentState?.reload();
    }
  }

  Future<void> _override(Map s) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _ServiceOverrideSheet(areaId: widget.id, serviceId: toInt(s['service_id'])!, canEdit: widget.canEdit));
    if (ok == true) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: TextField(decoration: const InputDecoration(hintText: 'Search service or category', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
      ),
      FilterChips<String>(options: const {'': 'All', 'active': 'Enabled', 'inactive': 'Not enabled'}, value: _status, onChanged: (v) => setState(() => _status = v)),
      Expanded(
        child: ApiLoader(
          key: _key,
          load: () => api.get('$_base/areas/${widget.id}/services'),
          builder: (c, res, reload) {
            final rows = res.list.where((s) {
              final txt = '${s['service_name']} ${s['category_name']}'.toLowerCase();
              final en = truthy(s['enabled']);
              return (_q.isEmpty || txt.contains(_q)) && (_status.isEmpty || (_status == 'active' ? en : !en));
            }).toList();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (c, i) {
                final s = rows[i];
                final sid = toInt(s['service_id'])!;
                final en = truthy(s['enabled']);
                final dur = s['area_duration'] != null ? '${s['area_duration']} min (this area)' : (s['default_duration'] != null ? '${s['default_duration']} min' : '60 min (default)');
                return RowTile(
                  leading: widget.canEdit ? Checkbox(value: _sel.contains(sid), onChanged: (v) => setState(() => v == true ? _sel.add(sid) : _sel.remove(sid))) : null,
                  title: str(s['service_name']),
                  badge: StatusChip(en ? 'ACTIVE' : 'INACTIVE', label: en ? 'Enabled' : 'Disabled'),
                  subtitle: str(s['category_name'], ''),
                  lines: ['Duration $dur · Price ${s['base_price'] == null ? '—' : inr(s['base_price'])}${toInt(s['slot_overrides']) != null && toInt(s['slot_overrides'])! > 0 ? ' · ${s['slot_overrides']} slot override(s)' : ''}'],
                  trailing: widget.canEdit
                      ? TextButton(onPressed: () => _set([sid], !en), child: Text(en ? 'Disable' : 'Enable'))
                      : null,
                  onTap: () => _override(s),
                );
              },
            );
          },
        ),
      ),
      if (_sel.isNotEmpty)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _set(_sel.toList(), false), child: Text('Disable (${_sel.length})'))),
              const Gap(8),
              Expanded(child: FilledButton(onPressed: () => _set(_sel.toList(), true), child: Text('Enable (${_sel.length})'))),
            ]),
          ),
        ),
    ]);
  }
}

class _ServiceOverrideSheet extends StatefulWidget {
  const _ServiceOverrideSheet({required this.areaId, required this.serviceId, required this.canEdit});
  final int areaId;
  final int serviceId;
  final bool canEdit;
  @override
  State<_ServiceOverrideSheet> createState() => _ServiceOverrideSheetState();
}

class _ServiceOverrideSheetState extends State<_ServiceOverrideSheet> {
  Map<String, dynamic>? _d;
  final _dur = TextEditingController();
  final _price = TextEditingController();

  @override
  void initState() {
    super.initState();
    api.get('$_base/areas/${widget.areaId}/services/${widget.serviceId}').then((r) {
      if (!mounted) return;
      setState(() {
        _d = r.ok ? r.map : {'error': r.message};
        _dur.text = ApiRes.asMap(_d!['duration'])['area']?.toString() ?? '';
        _price.text = ApiRes.asMap(_d!['price'])['area']?.toString() ?? '';
      });
    });
  }

  Future<void> _save() async {
    final d = _dur.text.trim(), p = _price.text.trim();
    if (d.isNotEmpty && ((int.tryParse(d) ?? 0) < 5 || (int.tryParse(d) ?? 0) > 1440)) return toast('Duration: 5–1440 minutes, or empty for the default', error: true);
    if (p.isNotEmpty && (double.tryParse(p) ?? -1) < 0) return toast('Price must be 0 or more, or empty for the default', error: true);
    final r = await busy(context, () => api.put('$_base/areas/${widget.areaId}/services/${widget.serviceId}', {'duration_minutes': d.isEmpty ? null : int.parse(d), 'price': p.isEmpty ? null : double.parse(p)}), success: 'Area override saved');
    if (r.ok && mounted) Navigator.pop(context, true);
  }

  Widget _layer(String title, Map l, String unit) => SectionCard(title: title, children: [
        KV('Default', l['default'] == null ? '—' : '${l['default']} $unit'),
        KV('Area override', l['area'] == null ? '—' : '${l['area']} $unit'),
        KV('Effective', l['effective'] == null ? '—' : '${l['effective']} $unit', bold: true),
        if (l['inspection_charge'] != null) KV('Inspection charge', inr(l['inspection_charge'])),
        for (final s in ApiRes.asList(l['slots'])) KV('Slot override', '${s['value']} $unit on ${s['slots']} slot(s), e.g. ${s['example']}'),
      ]);

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: d == null
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : d['error'] != null
              ? Text(d['error'])
              : SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(str(ApiRes.asMap(d['service'])['service_name']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text('${str(ApiRes.asMap(d['service'])['category_name'], '')} · ${truthy(d['enabled']) ? 'Enabled in area' : 'Not enabled in area'}', style: const TextStyle(color: C.body)),
                    const Gap(),
                    _layer('Duration', ApiRes.asMap(d['duration']), 'min'),
                    const Gap(8),
                    _layer('Price', ApiRes.asMap(d['price']), '₹'),
                    const Gap(8),
                    KV('Emergency', truthy(ApiRes.asMap(d['emergency'])['available']) ? '+${inr(ApiRes.asMap(d['emergency'])['charge'])}' : 'Not available'),
                    KV('Quick service', truthy(ApiRes.asMap(d['quick_service'])['available']) ? '+${inr(ApiRes.asMap(d['quick_service'])['charge'])}' : 'Not available'),
                    if (widget.canEdit) ...[
                      const Gap(),
                      TextField(controller: _dur, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Area duration (min)', helperText: 'Empty = use the default')),
                      const Gap(8),
                      TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Area price (₹)', helperText: 'Empty = use the default')),
                      const Gap(),
                      FilledButton(onPressed: _save, child: const Text('Save override')),
                    ],
                  ]),
                ),
    );
  }
}

// ─── Operating hours ─────────────────────────────────────────────────────────

class _HoursTab extends StatefulWidget {
  const _HoursTab(this.id, this.canEdit);
  final int id;
  final bool canEdit;
  @override
  State<_HoursTab> createState() => _HoursTabState();
}

class _HoursTabState extends State<_HoursTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _editDay(int day, Map<String, dynamic> current) async {
    var closed = current['closed'] == true;
    final wins = List<Map<String, String>>.from((current['windows'] as List).map((w) => Map<String, String>.from(w)));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_days[day], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Closed this day'), value: closed, onChanged: (v) => set(() => closed = v)),
            if (!closed) ...[
              for (var i = 0; i < wins.length; i++)
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () async {
                    final t = await _pickTime(c, wins[i]['start']);
                    if (t != null) set(() => wins[i]['start'] = t);
                  }, child: Text(fmtTime(wins[i]['start'])))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                  Expanded(child: OutlinedButton(onPressed: () async {
                    final t = await _pickTime(c, wins[i]['end']);
                    if (t != null) set(() => wins[i]['end'] = t);
                  }, child: Text(fmtTime(wins[i]['end'])))),
                  IconButton(onPressed: () => set(() => wins.removeAt(i)), icon: const Icon(Icons.close, color: C.red)),
                ]),
              TextButton.icon(onPressed: () => set(() => wins.add({'start': '09:00', 'end': '18:00'})), icon: const Icon(Icons.add), label: const Text('Add window')),
            ],
            const Gap(8),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save day')),
          ]),
        );
      }),
    );
    if (ok != true || !mounted) return;
    if (!closed && wins.isEmpty) return toast('${_days[day]}: add a window or mark the day closed', error: true);
    for (final w in wins) {
      if (_mins(w['start']!) >= _mins(w['end']!)) return toast('${_days[day]}: a window ends before it starts', error: true);
    }
    final r = await busy(context, () => api.put('$_base/areas/${widget.id}/operating-hours/$day', {
          'is_closed': closed,
          'windows': [for (final w in wins) {'open_time': w['start'], 'close_time': w['end']}],
        }), success: '${_days[day]} saved');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _copyMonday(Map<int, Map<String, dynamic>> draft) async {
    final src = draft[1]!;
    if (!truthy(src['closed']) && (src['windows'] as List).isEmpty) return toast('Set up Monday first', error: true);
    if (!await confirm(context, 'Copy operating hours?', message: 'Monday’s hours replace every other open day.', ok: 'Copy')) return;
    if (!mounted) return;
    final r = await busy(context, () async {
      ApiRes last = ApiRes({'status': true});
      for (final d in _weekOrder.where((d) => d != 1 && !truthy(draft[d]!['closed']))) {
        last = await api.put('$_base/areas/${widget.id}/operating-hours/$d', {
          'is_closed': false,
          'windows': [for (final w in src['windows']) {'open_time': w['start'], 'close_time': w['end']}],
        });
        if (!last.ok) break;
      }
      return last;
    }, success: 'Hours copied');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _reset() async {
    if (!await confirm(context, 'Reset to open all day?', message: 'All weekly hours for this area are removed.', danger: true, ok: 'Reset')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.delete('$_base/areas/${widget.id}/operating-hours'), success: 'Hours cleared');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ApiLoader(
      key: _key,
      load: () => api.get('$_base/areas/${widget.id}/operating-hours'),
      builder: (c, res, reload) {
        final rows = res.list;
        final configured = rows.isNotEmpty;
        final draft = <int, Map<String, dynamic>>{};
        for (final d in _weekOrder) {
          final own = rows.where((r) => toInt(r['day_of_week']) == d && r['effective_from'] == null && r['effective_to'] == null).toList();
          draft[d] = {
            'closed': own.any((r) => truthy(r['is_closed'])),
            'windows': [for (final r in own.where((r) => !truthy(r['is_closed']) && r['open_time'] != null)) {'start': _hm(r['open_time']), 'end': _hm(r['close_time'])}],
          };
        }
        final seasonal = rows.where((r) => r['effective_from'] != null || r['effective_to'] != null).toList();
        return ListView(padding: const EdgeInsets.all(12), children: [
          Text(configured ? 'When this area takes bookings. Several windows per day are allowed (e.g. a lunch break).' : 'No hours set — the area is treated as open all day. Add hours to limit when slots can be booked.',
              style: const TextStyle(color: C.body)),
          const Gap(8),
          for (final d in _weekOrder)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_days[d], style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(truthy(draft[d]!['closed'])
                    ? 'Closed'
                    : (draft[d]!['windows'] as List).isEmpty
                        ? (configured ? 'No hours — closed' : 'Open all day')
                        : (draft[d]!['windows'] as List).map((w) => '${fmtTime(w['start'])} – ${fmtTime(w['end'])}').join(', ')),
                trailing: widget.canEdit ? const Icon(Icons.edit_outlined) : null,
                onTap: widget.canEdit ? () => _editDay(d, draft[d]!) : null,
              ),
            ),
          if (widget.canEdit) ...[
            OutlinedButton.icon(onPressed: () => _copyMonday(draft), icon: const Icon(Icons.copy_all), label: const Text('Copy Monday to open days')),
            const Gap(8),
            OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt), label: const Text('Reset to open all day')),
          ],
          if (seasonal.isNotEmpty) ...[
            const Gap(),
            SectionCard(title: 'Seasonal schedules', children: [
              for (final r in seasonal)
                Text('${_days[toInt(r['day_of_week'])!]} · ${truthy(r['is_closed']) ? 'closed' : '${_hm(r['open_time'])}–${_hm(r['close_time'])}'} · ${fmtDate(r['effective_from'])} to ${r['effective_to'] == null ? 'open-ended' : fmtDate(r['effective_to'])}'),
            ]),
          ],
        ]);
      },
    );
  }
}

// ─── Time slots ──────────────────────────────────────────────────────────────

class _SlotsTab extends StatefulWidget {
  const _SlotsTab(this.id, this.canEdit);
  final int id;
  final bool canEdit;
  @override
  State<_SlotsTab> createState() => _SlotsTabState();
}

class _SlotsTabState extends State<_SlotsTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();

  @override
  bool get wantKeepAlive => true;

  Future<ApiRes> _load() async {
    final r = await Future.wait([
      api.get('$_base/areas/${widget.id}/slots'),
      api.get('$_base/areas/${widget.id}/slots/health'),
    ]);
    if (!r[0].ok) return r[0];
    return ApiRes({'status': true, 'slots': r[0].data, 'health': r[1].ok ? r[1].data : []});
  }

  Future<void> _toggle(Map s) async {
    final r = await busy(context, () => api.put('$_base/areas/${widget.id}/slots/${s['template_id']}', {'is_enabled': !truthy(s['is_enabled'])}));
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _settings(Map s) async {
    final cutoff = TextEditingController(text: s['booking_cutoff_minutes']?.toString() ?? '');
    final lead = TextEditingController(text: s['lead_time_minutes']?.toString() ?? '');
    final surge = TextEditingController(text: s['surge_multiplier'] == null ? '' : toNum(s['surge_multiplier']).toString());
    var emergency = truthy(s['emergency_allowed']);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${_hm(s['start_time'])}–${_hm(s['end_time'])} ${str(s['name'], '')}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Gap(8),
              TextField(controller: lead, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Book at least (min ahead)')),
              const Gap(8),
              TextField(controller: cutoff, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stop booking (min before end)')),
              const Gap(8),
              TextField(controller: surge, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price multiplier', helperText: '1 = normal price, 1.2 = 20% more in this slot.')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Allow emergency bookings in this slot'), value: emergency, onChanged: (v) => set(() => emergency = v)),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
            ]),
          )),
    );
    if (ok != true || !mounted) return;
    final sv = surge.text.trim();
    if (sv.isNotEmpty && ((double.tryParse(sv) ?? 0) <= 0 || (double.tryParse(sv) ?? 0) > 10)) return toast('Multiplier must be more than 0, at most 10', error: true);
    final r = await busy(context, () => api.put('$_base/areas/${widget.id}/slots/${s['template_id']}', {
          'is_enabled': truthy(s['is_enabled']),
          'booking_cutoff_minutes': cutoff.text.trim().isEmpty ? null : int.tryParse(cutoff.text.trim()),
          'lead_time_minutes': lead.text.trim().isEmpty ? null : int.tryParse(lead.text.trim()),
          'surge_multiplier': sv.isEmpty ? null : double.parse(sv),
          'emergency_allowed': emergency,
        }), success: 'Slot saved');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _newSlot() async {
    var start = '08:00', end = '10:00';
    final name = TextEditingController();
    final order = TextEditingController(text: '0');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('New slot', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Text('Added and turned on for this area.', style: TextStyle(color: C.body, fontSize: 12.5)),
              const Gap(8),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Morning')),
              const Gap(8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () async {
                  final v = await _pickTime(c, start);
                  if (v != null) set(() => start = v);
                }, child: Text('From ${fmtTime(start)}'))),
                const Gap(8),
                Expanded(child: OutlinedButton(onPressed: () async {
                  final v = await _pickTime(c, end);
                  if (v != null) set(() => end = v);
                }, child: Text('To ${fmtTime(end)}'))),
              ]),
              const Gap(8),
              TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
            ]),
          )),
    );
    if (ok != true || !mounted) return;
    final body = {'name': name.text.trim().isEmpty ? '$start–$end' : name.text.trim(), 'start_time': start, 'end_time': end, 'display_order': int.tryParse(order.text) ?? 0};
    final r = await busy(context, () => api.post('$_base/slot-templates', body), success: 'Slot added');
    final id = r.ok ? r.map['template_id'] : null;
    if (id != null) await api.put('$_base/areas/${widget.id}/slots/$id', {'is_enabled': true});
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _quickSetup() async {
    var open = '09:00', close = '18:00', len = 60;
    final cap = TextEditingController(text: '2');
    final days = {1, 2, 3, 4, 5, 6};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final slots = <String>[];
        for (var m = _mins(open); m + len <= _mins(close); m += len) {
          String hh(int x) => '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
          slots.add('${hh(m)}–${hh(m + len)}');
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Quick setup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Text('Sets the open days’ hours, then creates and enables slots of one length with a booking limit.', style: TextStyle(color: C.body, fontSize: 12.5)),
              const Gap(8),
              Wrap(spacing: 6, children: [
                for (final d in _weekOrder)
                  FilterChip(label: Text(_days[d].substring(0, 3)), selected: days.contains(d), onSelected: (v) => set(() => v ? days.add(d) : days.remove(d))),
              ]),
              const Gap(8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () async {
                  final v = await _pickTime(c, open);
                  if (v != null) set(() => open = v);
                }, child: Text('Opening ${fmtTime(open)}'))),
                const Gap(8),
                Expanded(child: OutlinedButton(onPressed: () async {
                  final v = await _pickTime(c, close);
                  if (v != null) set(() => close = v);
                }, child: Text('Closing ${fmtTime(close)}'))),
              ]),
              const Gap(8),
              Wrap(spacing: 6, children: [
                for (final l in const [30, 60, 90, 120, 180, 240]) ChoiceChip(label: Text('$l min'), selected: len == l, onSelected: (_) => set(() => len = l)),
              ]),
              const Gap(8),
              TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bookings per slot (empty = no limit)')),
              const Gap(8),
              Text(slots.isEmpty ? 'No slot of that length fits between these times.' : 'Customers will see: ${slots.join(', ')}', style: const TextStyle(fontSize: 12.5, color: C.body)),
              const Gap(8),
              FilledButton(onPressed: slots.isEmpty || days.isEmpty ? null : () => Navigator.pop(c, true), child: const Text('Apply schedule')),
            ]),
          ),
        );
      }),
    );
    if (ok != true || !mounted) return;
    final capacity = int.tryParse(cap.text.trim());
    final wins = <(String, String)>[];
    String hh(int x) => '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
    for (var m = _mins(open); m + len <= _mins(close); m += len) {
      wins.add((hh(m), hh(m + len)));
    }
    final res = await busy(context, () async {
      // 1. Weekly hours: chosen days open, the rest closed.
      for (final d in _weekOrder) {
        final r = await api.put('$_base/areas/${widget.id}/operating-hours/$d', days.contains(d)
            ? {'is_closed': false, 'windows': [{'open_time': open, 'close_time': close}]}
            : {'is_closed': true, 'windows': []});
        if (!r.ok) return r;
      }
      // 2. Disable slots enabled here that aren't in the new schedule.
      final current = await api.get('$_base/areas/${widget.id}/slots');
      final keep = wins.map((w) => '${w.$1}-${w.$2}').toSet();
      for (final s in current.list.where((s) => truthy(s['is_enabled']))) {
        if (!keep.contains('${_hm(s['start_time'])}-${_hm(s['end_time'])}')) {
          await api.put('$_base/areas/${widget.id}/slots/${s['template_id']}', {'is_enabled': false});
        }
      }
      // 3. Reuse or create the slots, enable each with the capacity.
      final lib = await api.get('$_base/slot-templates', {'includeInactive': 'true'});
      ApiRes last = ApiRes({'status': true});
      for (var i = 0; i < wins.length; i++) {
        final w = wins[i];
        var t = lib.list.firstWhere((t) => _hm(t['start_time']) == w.$1 && _hm(t['end_time']) == w.$2, orElse: () => {});
        if (t.isEmpty) {
          final c = await api.post('$_base/slot-templates', {'name': '${w.$1}–${w.$2}', 'start_time': w.$1, 'end_time': w.$2, 'display_order': i});
          if (!c.ok) return c;
          t = c.map;
        }
        last = await api.put('$_base/areas/${widget.id}/slots/${t['template_id']}', {'is_enabled': true, 'capacity_mode': 'BOOKING_COUNT', 'capacity': capacity});
        if (!last.ok) return last;
      }
      return last;
    }, success: 'Schedule applied');
    if (res.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ApiLoader(
      key: _key,
      load: _load,
      builder: (c, res, reload) {
        final slots = ApiRes.asList(res['slots'])..sort((a, b) => _mins(_hm(a['start_time'])).compareTo(_mins(_hm(b['start_time']))));
        final health = {for (final h in ApiRes.asList(res['health'])) toInt(h['template_id']): h};
        return ListView(padding: const EdgeInsets.all(12), children: [
          if (widget.canEdit)
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _quickSetup, icon: const Icon(Icons.bolt), label: const Text('Quick setup'))),
              const Gap(8),
              Expanded(child: OutlinedButton.icon(onPressed: _newSlot, icon: const Icon(Icons.add), label: const Text('New slot'))),
            ]),
          const Gap(),
          SectionCard(title: 'Slots offered in this area', children: [
            if (slots.where((s) => truthy(s['is_enabled'])).isEmpty) const Text('No slots offered in this area yet', style: TextStyle(color: C.muted)),
            for (final s in slots)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${fmtTime(s['start_time'])} – ${fmtTime(s['end_time'])}  ${str(s['name'], '')}'),
                subtitle: Text([
                  if (s['lead_time_minutes'] != null) 'lead ${s['lead_time_minutes']}m',
                  if (s['booking_cutoff_minutes'] != null) 'cutoff ${s['booking_cutoff_minutes']}m',
                  if (s['surge_multiplier'] != null) '×${toNum(s['surge_multiplier'])}',
                  if (truthy(s['emergency_allowed'])) 'emergency',
                  if (health[toInt(s['template_id'])] != null) ...List<String>.from((health[toInt(s['template_id'])]!['warnings'] as List?) ?? const []),
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.canEdit && truthy(s['is_enabled'])) IconButton(onPressed: () => _settings(s), icon: const Icon(Icons.tune)),
                  Switch(value: truthy(s['is_enabled']), onChanged: widget.canEdit ? (_) => _toggle(s) : null),
                ]),
              ),
          ]),
        ]);
      },
    );
  }
}

// ─── Capacity ────────────────────────────────────────────────────────────────

class _CapacityTab extends StatefulWidget {
  const _CapacityTab(this.id, this.canEdit);
  final int id;
  final bool canEdit;
  @override
  State<_CapacityTab> createState() => _CapacityTabState();
}

class _CapacityTabState extends State<_CapacityTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _edit(Map s) async {
    var mode = str(s['capacity_mode'], 'BOOKING_COUNT');
    final cap = TextEditingController(text: s['capacity']?.toString() ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${fmtTime(s['start_time'])} – ${fmtTime(s['end_time'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Gap(8),
              Wrap(spacing: 6, children: [
                ChoiceChip(label: const Text('Booking count'), selected: mode == 'BOOKING_COUNT', onSelected: (_) => set(() => mode = 'BOOKING_COUNT')),
                ChoiceChip(label: const Text('Technician capacity'), selected: mode == 'TECHNICIAN_CAPACITY', onSelected: (_) => set(() => mode = 'TECHNICIAN_CAPACITY')),
                ChoiceChip(label: const Text('Minutes'), selected: mode == 'MINUTES', onSelected: (_) => set(() => mode = 'MINUTES')),
              ]),
              const Gap(8),
              TextField(
                controller: cap,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: mode == 'MINUTES' ? 'Service minutes per slot' : (mode == 'TECHNICIAN_CAPACITY' ? 'Optional cap' : 'Bookings per slot'),
                  helperText: mode == 'MINUTES' ? 'Required — a 90-min job uses 90' : (mode == 'TECHNICIAN_CAPACITY' ? 'One booking per free technician, at most this many' : 'Empty = no limit'),
                ),
              ),
              const Gap(8),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
            ]),
          )),
    );
    if (ok != true || !mounted) return;
    final v = cap.text.trim();
    if (v.isEmpty && mode == 'MINUTES') return toast('Minutes capacity needs a number', error: true);
    if (v.isNotEmpty && (int.tryParse(v) ?? -1) < 0) return toast('Enter a whole number, 0 or more', error: true);
    final r = await busy(context, () => api.put('$_base/areas/${widget.id}/slots/${s['template_id']}', {'is_enabled': true, 'capacity_mode': mode, 'capacity': v.isEmpty ? null : int.parse(v)}), success: 'Capacity saved');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ApiLoader(
      key: _key,
      load: () => api.get('$_base/areas/${widget.id}/slots'),
      builder: (c, res, reload) {
        final slots = res.list.where((s) => truthy(s['is_enabled'])).toList();
        if (slots.isEmpty) return ListView(children: const [EmptyView('No slots enabled in this area')]);
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final s in slots)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${fmtTime(s['start_time'])} – ${fmtTime(s['end_time'])}'),
                subtitle: Text('${humanize(s['capacity_mode'] ?? 'BOOKING_COUNT')} · ${s['capacity'] ?? 'no limit'}'),
                trailing: widget.canEdit ? const Icon(Icons.edit_outlined) : null,
                onTap: widget.canEdit ? () => _edit(s) : null,
              ),
            ),
        ]);
      },
    );
  }
}

// ─── Exceptions ──────────────────────────────────────────────────────────────

const _exTypes = {
  'HOLIDAY': ('Holiday', 'No bookings that day.'),
  'AREA_CLOSED': ('Area closed', 'Closed for another reason (strike, weather…).'),
  'SPECIAL_HOURS': ('Special hours', 'Replaces the weekly hours for that date.'),
  'CAPACITY_OVERRIDE': ('Temporary capacity', 'Different capacity that date (one slot or all).'),
  'SLOT_DISABLED': ('Disabled slot', 'One slot not offered that date.'),
};

class _ExceptionsTab extends StatefulWidget {
  const _ExceptionsTab(this.id, this.canEdit);
  final int id;
  final bool canEdit;
  @override
  State<_ExceptionsTab> createState() => _ExceptionsTabState();
}

class _ExceptionsTabState extends State<_ExceptionsTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _add() async {
    final slotsRes = await api.get('$_base/areas/${widget.id}/slots');
    final slots = slotsRes.list.where((s) => truthy(s['is_enabled'])).toList();
    if (!mounted) return;
    DateTime? date;
    var type = 'HOLIDAY';
    String? template;
    var open = '10:00', close = '16:00';
    final cap = TextEditingController();
    final reason = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Add an exception', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Gap(8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(date == null ? 'Pick date' : fmtDate(date)),
                  onPressed: () async {
                    final d = await showDatePicker(context: c, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) set(() => date = d);
                  },
                ),
                const Gap(8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in _exTypes.entries) ChoiceChip(label: Text(e.value.$1), selected: type == e.key, onSelected: (_) => set(() => type = e.key)),
                ]),
                Text(_exTypes[type]!.$2, style: const TextStyle(fontSize: 12, color: C.muted)),
                if (type == 'SPECIAL_HOURS')
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () async {
                      final v = await _pickTime(c, open);
                      if (v != null) set(() => open = v);
                    }, child: Text('Open ${fmtTime(open)}'))),
                    const Gap(8),
                    Expanded(child: OutlinedButton(onPressed: () async {
                      final v = await _pickTime(c, close);
                      if (v != null) set(() => close = v);
                    }, child: Text('Close ${fmtTime(close)}'))),
                  ]),
                if (type == 'CAPACITY_OVERRIDE' || type == 'SLOT_DISABLED') ...[
                  const Gap(8),
                  DropdownButtonFormField<String>(
                    initialValue: template,
                    decoration: InputDecoration(labelText: type == 'SLOT_DISABLED' ? 'Slot' : 'Slot (empty = all slots)'),
                    items: [
                      if (type == 'CAPACITY_OVERRIDE') const DropdownMenuItem(value: null, child: Text('All slots')),
                      for (final s in slots) DropdownMenuItem(value: '${s['template_id']}', child: Text('${fmtTime(s['start_time'])} – ${fmtTime(s['end_time'])}')),
                    ],
                    onChanged: (v) => set(() => template = v),
                  ),
                ],
                if (type == 'CAPACITY_OVERRIDE') ...[const Gap(8), TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity'))],
                const Gap(8),
                TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
                const Gap(),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add exception')),
              ]),
            ),
          )),
    );
    if (ok != true || !mounted) return;
    if (date == null) return toast('Pick a date', error: true);
    if (type == 'SLOT_DISABLED' && template == null) return toast('Pick the slot', error: true);
    if (type == 'CAPACITY_OVERRIDE' && int.tryParse(cap.text) == null) return toast('Enter the capacity', error: true);
    final r = await busy(context, () => api.post('$_base/areas/${widget.id}/exceptions', {
          'date': ymd(date!),
          'type': type,
          if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
          if (template != null) 'template_id': int.parse(template!),
          if (type == 'CAPACITY_OVERRIDE') 'capacity': int.parse(cap.text),
          if (type == 'SPECIAL_HOURS') ...{'open_time': open, 'close_time': close},
        }), success: 'Exception added');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _remove(Map e) async {
    if (!await confirm(context, 'Remove the ${humanize(e['exception_type']).toLowerCase()} on ${fmtDate(e['exception_date'])}?', message: 'The regular schedule applies again.', danger: true, ok: 'Remove')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.delete('$_base/areas/${widget.id}/exceptions/${e['exception_id']}'), success: 'Exception removed');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: ApiLoader(
        key: _key,
        load: () => api.get('$_base/areas/${widget.id}/exceptions', {'from': ymd(DateTime.now())}),
        builder: (c, res, reload) {
          final rows = res.list;
          if (rows.isEmpty) return ListView(children: const [EmptyView('No upcoming exceptions')]);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            for (final e in rows)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${fmtDate(e['exception_date'])} · ${_exTypes[e['exception_type']]?.$1 ?? humanize(e['exception_type'])}'),
                  subtitle: Text([
                    if (e['exception_type'] == 'SPECIAL_HOURS') '${_hm(e['open_time'])}–${_hm(e['close_time'])}',
                    if (e['exception_type'] == 'CAPACITY_OVERRIDE') 'capacity ${e['capacity']} · ${str(e['template_name'], 'all slots')}',
                    if (e['exception_type'] == 'SLOT_DISABLED') str(e['template_name'], 'slot #${e['template_id']}'),
                    if (e['reason'] != null) '${e['reason']}',
                  ].join(' · ')),
                  trailing: widget.canEdit ? IconButton(onPressed: () => _remove(e), icon: const Icon(Icons.delete_outline, color: C.red)) : null,
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: widget.canEdit ? FloatingActionButton.extended(heroTag: 'ex', onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add exception')) : null,
    );
  }
}

// ─── Pricing overrides ───────────────────────────────────────────────────────

class _PricingTab extends StatefulWidget {
  const _PricingTab(this.id, this.canEdit);
  final int id;
  final bool canEdit;
  @override
  State<_PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends State<_PricingTab> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  Future<void> _edit(Map p) async {
    final v = await prompt(context, 'Area price · ${p['service_name']}', label: 'Price (₹)', initial: p['area_override']?.toString(), hint: 'Empty = use the global price', keyboard: const TextInputType.numberWithOptions(decimal: true));
    if (v == null || !mounted) return;
    if (v.isNotEmpty && (double.tryParse(v) ?? -1) < 0) return toast('Enter a price of 0 or more, or leave empty to remove.', error: true);
    final r = await busy(context, () => api.put('$_base/areas/${widget.id}/services/${p['service_id']}', {'price': v.isEmpty ? null : double.parse(v)}), success: 'Price saved');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: TextField(decoration: const InputDecoration(hintText: 'Search service or category…', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
      ),
      Expanded(
        child: ApiLoader(
          key: _key,
          load: () => api.get('$_base/areas/${widget.id}/pricing'),
          builder: (c, res, reload) {
            final rows = res.list.where((p) => _q.isEmpty || '${p['service_name']} ${p['category_name']}'.toLowerCase().contains(_q)).toList();
            if (rows.isEmpty) return ListView(children: const [EmptyView('No enabled services')]);
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (c, i) {
                final p = rows[i];
                final slot = ApiRes.asMap(p['slot_override']);
                return RowTile(
                  title: str(p['service_name']),
                  subtitle: str(p['category_name'], ''),
                  lines: [
                    'Global ${p['global_price'] == null ? '—' : inr(p['global_price'])} · Area ${p['area_override'] == null ? '—' : inr(p['area_override'])}',
                    if (slot.isNotEmpty) 'Slot override ${inr(slot['min'])}–${inr(slot['max'])} on ${slot['slots']} slot(s)',
                    if (p['emergency'] != null || p['quick_service'] != null) 'Emergency ${inr(p['emergency'])} · Quick ${inr(p['quick_service'])}',
                    if (p['final_price'] == null && p['inspection_charge'] != null) 'Sold as an inspection visit (${inr(p['inspection_charge'])})',
                  ],
                  trailing: Text(p['final_price'] == null ? 'No price' : inr(p['final_price']), style: TextStyle(fontWeight: FontWeight.w800, color: p['final_price'] == null ? C.red : C.ink)),
                  onTap: widget.canEdit ? () => _edit(p) : null,
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ─── Technicians ─────────────────────────────────────────────────────────────

class _TechniciansTab extends StatelessWidget {
  const _TechniciansTab(this.id);
  final int id;

  @override
  Widget build(BuildContext context) {
    return ApiLoader(
      load: () => api.get('$_base/areas/$id/technicians'),
      builder: (c, res, reload) {
        final rows = res.list;
        if (rows.isEmpty) return ListView(children: const [EmptyView('No technician can serve this area')]);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Gap(8),
          itemBuilder: (c, i) {
            final t = rows[i];
            final av = ApiRes.asMap(t['availability_today']);
            return RowTile(
              leading: Avatar(name: str(t['name'], '')),
              title: str(t['name']),
              badge: StatusChip(truthy(t['is_online']) ? 'ACTIVE' : 'INACTIVE', label: truthy(t['is_online']) ? 'Online' : 'Offline'),
              subtitle: '${str(t['mobile_number'], '')} · ${(t['skills'] as List?)?.join(', ') ?? ''}',
              lines: [
                'Open jobs ${t['open_jobs'] ?? 0}${truthy(t['assigned_to_area']) ? ' · assigned to area' : ''}',
                if (av.isNotEmpty) 'Today: ${!truthy(av['working_hours_set']) ? 'any time' : ApiRes.asList(av['free']).map((f) => '${_hm(f['start'])}–${_hm(f['end'])}').join(', ').ifEmpty('no free time')} · ${av['busy'] ?? 0} busy',
              ],
              trailing: IconButton(icon: const Icon(Icons.call, color: C.primary), onPressed: () => callPhone(t['mobile_number'])),
            );
          },
        );
      },
    );
  }
}
