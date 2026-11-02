import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/crud_screen.dart';
import 'area_config_screen.dart';

const _geoPath = '/admin/masters/geography/countries';

/// /public/lookups is cached once per app run (area types, booking types…).
Map<String, dynamic>? _lookups;
Future<Map<String, dynamic>> publicLookups() async {
  if (_lookups != null) return _lookups!;
  final r = await api.get('/public/lookups');
  if (r.ok) _lookups = r.map;
  return _lookups ?? {};
}

class CountriesScreen extends StatelessWidget {
  const CountriesScreen({super.key});
  @override
  Widget build(BuildContext context) => CrudScreen(CrudConfig(
        title: 'Country',
        base: '/master/countries',
        idKey: 'country_id',
        menuPath: _geoPath,
        filters: const {'All': {}, 'Active only': {'is_active': true}},
        deactivateMessage: 'Its states, cities and areas stop being offered for new bookings.',
        titleOf: (r) => str(r['country_name']),
        subtitleOf: (r) => str(r['country_code'], ''),
        fields: (_) => [
          Field('country_name', 'Country Name', required: true),
          Field('country_code', 'Country Code', required: true),
          Field('is_active', 'Active', type: F.toggle),
        ],
        onTap: (c, r) => Navigator.push(c, MaterialPageRoute(builder: (_) => StatesScreen(country: r))),
      ));
}

class StatesScreen extends StatelessWidget {
  const StatesScreen({super.key, required this.country});
  final Map<String, dynamic> country;
  @override
  Widget build(BuildContext context) => CrudScreen(
        CrudConfig(
          title: 'State',
          base: '/master/states',
          idKey: 'state_id',
          menuPath: _geoPath,
          query: {'country_id': country['country_id']},
          deactivateMessage: 'Its cities and areas stop being offered for new bookings.',
          titleOf: (r) => str(r['state_name']),
          subtitleOf: (r) => str(r['state_code'], ''),
          fields: (_) => [
            Field('state_name', 'State Name', required: true),
            Field('state_code', 'State Code'),
            Field('is_active', 'Active', type: F.toggle),
          ],
          toPayload: (v, _) => {...v, 'country_id': country['country_id']},
          onTap: (c, r) => Navigator.push(c, MaterialPageRoute(builder: (_) => CitiesScreen(state: r, country: country))),
        ),
        embedded: false,
      );
}

class CitiesScreen extends StatelessWidget {
  const CitiesScreen({super.key, required this.state, required this.country});
  final Map<String, dynamic> state;
  final Map<String, dynamic> country;
  @override
  Widget build(BuildContext context) => CrudScreen(
        CrudConfig(
          title: 'City',
          base: '/master/cities',
          idKey: 'city_id',
          menuPath: _geoPath,
          query: {'state_id': state['state_id']},
          deactivateMessage: 'Its areas stop being offered for new bookings.',
          titleOf: (r) => str(r['city_name']),
          subtitleOf: (r) => '${str(state['state_name'], '')}, ${str(country['country_name'], '')}',
          fields: (_) => [
            Field('city_name', 'City Name', required: true),
            Field('is_active', 'Active', type: F.toggle),
          ],
          toPayload: (v, _) => {...v, 'state_id': state['state_id']},
          onTap: (c, r) => Navigator.push(c, MaterialPageRoute(builder: (_) => AreasScreen(city: r))),
        ),
        embedded: false,
      );
}

// ─── Service areas ───────────────────────────────────────────────────────────

class AreasScreen extends StatefulWidget {
  const AreasScreen({super.key, required this.city});
  final Map<String, dynamic> city;
  @override
  State<AreasScreen> createState() => _AreasScreenState();
}

class _AreasScreenState extends State<AreasScreen> {
  final _list = GlobalKey<PagedListState>();
  bool get _canEdit => Session.I.canOn(_geoPath, 'EDIT') || Session.I.canOn(_geoPath, 'CREATE');

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AreaFormScreen(cityId: toInt(widget.city['city_id'])!, row: row)));
    if (ok == true) _list.currentState?.reload();
  }

  Future<void> _toggle(Map<String, dynamic> r) async {
    final on = truthy(r['is_active']);
    if (on && !await confirm(context, 'Deactivate this area?', message: 'Customers in this area can no longer book.', danger: true, ok: 'Deactivate')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.put('/master/areas/${r['area_id']}', {'is_active': !on}));
    if (res.ok) _list.currentState?.reload();
  }

  Future<void> _inherit(Map<String, dynamic> target) async {
    final all = await api.get('/master/areas', {'page': 1, 'limit': 500});
    if (!mounted) return;
    final sources = all.list.where((a) => a['area_id'] != target['area_id']).toList();
    final src = await pickOne<int>(context, 'Inherit configuration from…', {for (final a in sources) toInt(a['area_id'])!: '${a['area_name']} · ${str(a['city_name'], '')}'});
    if (src == null || !mounted) return;
    if (!await confirm(context, 'Copy area setup?',
        message: 'Services, operating hours, time slots, capacity and pricing of the selected area replace this area’s setup. Everything is inherited as-is.', ok: 'Copy setup')) {
      return;
    }
    if (!mounted) return;
    final res = await busy(context, () => api.post('/admin/areas-copy-setup', {'sourceAreaId': src, 'targetAreaId': target['area_id']}), toastIt: false);
    if (!res.ok) {
      toastRes(res);
      return;
    }
    final stats = ApiRes.asMap(res['stats']);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Setup copied'),
        content: Text(stats.isEmpty ? 'Done.' : stats.entries.map((e) => '${humanize(e.key)}: ${e.value}').join('\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Areas · ${str(widget.city['city_name'])}')),
      body: PagedList(
        key: _list,
        searchHint: 'Search areas…',
        fetch: (p, l, s) => api.get('/master/areas', {'city_id': widget.city['city_id'], 'page': p, 'limit': l, 'search': s}),
        itemBuilder: (c, r, i) => RowTile(
          title: str(r['area_name']),
          badge: StatusChip(truthy(r['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(r['is_active']) ? 'Active' : 'Inactive'),
          subtitle: '${str(r['area_type_name'] ?? r['area_type'], 'Area')} · radius ${toNum(r['radius_km']).toStringAsFixed(2)} km',
          lines: [
            [if (truthy(r['emergency_available'])) 'Emergency +${inr(r['emergency_charge'])}', if (truthy(r['under_30_min_available'])) 'Under 30 min +${inr(r['under_30_min_charge'])}'].join(' · '),
          ],
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'config') Navigator.push(context, MaterialPageRoute(builder: (_) => AreaConfigScreen(area: r)));
              if (v == 'edit') _edit(r);
              if (v == 'toggle') _toggle(r);
              if (v == 'inherit') _inherit(r);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'config', child: Text('Configure')),
              if (_canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit area / boundary')),
              if (_canEdit) const PopupMenuItem(value: 'inherit', child: Text('Inherit setup from another area')),
              if (_canEdit) PopupMenuItem(value: 'toggle', child: Text(truthy(r['is_active']) ? 'Deactivate' : 'Activate')),
            ],
          ),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AreaConfigScreen(area: r))),
        ),
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add area')) : null,
    );
  }
}

/// Create / edit an area: name, type, boundary polygon, emergency and
/// under-30-min availability with surcharges.
class AreaFormScreen extends StatefulWidget {
  const AreaFormScreen({super.key, required this.cityId, this.row});
  final int cityId;
  final Map<String, dynamic>? row;
  @override
  State<AreaFormScreen> createState() => _AreaFormScreenState();
}

class _AreaFormScreenState extends State<AreaFormScreen> {
  late final _name = TextEditingController(text: str(widget.row?['area_name'], ''));
  late final _emCharge = TextEditingController(text: widget.row?['emergency_charge']?.toString() ?? '');
  late final _u30Charge = TextEditingController(text: widget.row?['under_30_min_charge']?.toString() ?? '');
  late String? _type = widget.row?['area_type_id']?.toString();
  late bool _active = widget.row == null ? true : truthy(widget.row!['is_active']);
  late bool _em = truthy(widget.row?['emergency_available']);
  late bool _u30 = truthy(widget.row?['under_30_min_available']);
  late List<LatLng> _poly = _parsePoly(widget.row?['polygon_coordinates']);
  Map<String, String> _types = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    publicLookups().then((l) {
      if (!mounted) return;
      setState(() => _types = {for (final t in ApiRes.asList(l['AREA_TYPES'])) '${t['id']}': str(t['name'])});
    });
  }

  static List<LatLng> _parsePoly(dynamic v) {
    if (v is! List) return [];
    return v.whereType<List>().where((p) => p.length >= 2).map((p) => LatLng(toNum(p[0]), toNum(p[1]))).toList();
  }

  Future<void> _draw() async {
    final r = await Navigator.push<List<LatLng>>(context, MaterialPageRoute(builder: (_) => PolygonDrawScreen(initial: _poly, excludeAreaId: toInt(widget.row?['area_id']))));
    if (r != null) setState(() => _poly = r);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast('Area name is required.', error: true);
    if (_type == null) return toast('Please select an area type.', error: true);
    if (_poly.length < 3) return toast('Please draw the boundary on the map.', error: true);
    final cLat = _poly.map((p) => p.latitude).reduce((a, b) => a + b) / _poly.length;
    final cLng = _poly.map((p) => p.longitude).reduce((a, b) => a + b) / _poly.length;
    final radius = _poly.map((p) => haversineKm(cLat, cLng, p.latitude, p.longitude)).reduce(math.max);
    final body = {
      'area_name': _name.text.trim(),
      'city_id': widget.cityId,
      'area_type_id': int.parse(_type!),
      'latitude': cLat,
      'longitude': cLng,
      'radius_km': double.parse(radius.toStringAsFixed(2)),
      'polygon_coordinates': [for (final p in _poly) [p.latitude, p.longitude]],
      'is_active': _active,
      'emergency_available': _em,
      'emergency_charge': _emCharge.text.trim().isEmpty ? null : double.tryParse(_emCharge.text),
      'under_30_min_available': _u30,
      'under_30_min_charge': _u30Charge.text.trim().isEmpty ? null : double.tryParse(_u30Charge.text),
    };
    setState(() => _saving = true);
    final res = widget.row == null ? await api.post('/master/areas', body) : await api.put('/master/areas/${widget.row!['area_id']}', body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (toastRes(res, success: 'Area saved.')) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.row == null ? 'Add area' : 'Edit area')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Area name *', hintText: 'e.g. Koramangala')),
        const Gap(),
        InkWell(
          onTap: () async {
            final v = await pickOne<String>(context, 'Area type', _types, selected: _type);
            if (v != null) setState(() => _type = v);
          },
          child: InputDecorator(decoration: const InputDecoration(labelText: 'Area type *', suffixIcon: Icon(Icons.expand_more)), child: Text(_types[_type] ?? (_type ?? 'Select'))),
        ),
        const Gap(),
        Card(
          child: ListTile(
            leading: const Icon(Icons.polyline, color: C.primary),
            title: Text(_poly.length < 3 ? 'Draw boundary on map' : 'Boundary: ${_poly.length} points'),
            subtitle: const Text('Tap the map to place the corners of the service area'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _draw,
          ),
        ),
        const Gap(),
        Card(child: SwitchListTile(title: const Text('Active'), value: _active, onChanged: (v) => setState(() => _active = v))),
        const Gap(8),
        Card(
          child: Column(children: [
            SwitchListTile(title: const Text('Emergency bookings'), value: _em, onChanged: (v) => setState(() => _em = v)),
            if (_em) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: TextField(controller: _emCharge, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Emergency surcharge (₹)'))),
          ]),
        ),
        const Gap(8),
        Card(
          child: Column(children: [
            SwitchListTile(title: const Text('Under 30 min (instant) services'), value: _u30, onChanged: (v) => setState(() => _u30 = v)),
            if (_u30) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: TextField(controller: _u30Charge, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Under-30-min surcharge (₹)'))),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save area'))),
      ),
    );
  }
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Tap-to-draw polygon editor. Other areas are shown in grey for reference.
class PolygonDrawScreen extends StatefulWidget {
  const PolygonDrawScreen({super.key, required this.initial, this.excludeAreaId});
  final List<LatLng> initial;
  final int? excludeAreaId;
  @override
  State<PolygonDrawScreen> createState() => _PolygonDrawScreenState();
}

class _PolygonDrawScreenState extends State<PolygonDrawScreen> {
  late final List<LatLng> _pts = [...widget.initial];
  final Set<Polygon> _others = {};
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    api.get('/master/areas', {'page': 1, 'limit': 500}).then((r) {
      if (!mounted) return;
      setState(() {
        for (final a in r.list) {
          if (toInt(a['area_id']) == widget.excludeAreaId) continue;
          final poly = _AreaFormScreenState._parsePoly(a['polygon_coordinates']);
          if (poly.length < 3) continue;
          _others.add(Polygon(polygonId: PolygonId('a${a['area_id']}'), points: poly, strokeWidth: 1, strokeColor: C.muted, fillColor: C.muted.withValues(alpha: .15)));
        }
      });
      if (_pts.isEmpty && r.list.isNotEmpty) {
        final a = r.list.first;
        if (a['latitude'] != null) _map?.moveCamera(CameraUpdate.newLatLngZoom(LatLng(toNum(a['latitude']), toNum(a['longitude'])), 12));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = _pts.isNotEmpty ? _pts.first : const LatLng(21.2514, 81.6296);
    return Scaffold(
      appBar: AppBar(title: const Text('Draw boundary'), actions: [
        IconButton(tooltip: 'Undo', onPressed: _pts.isEmpty ? null : () => setState(_pts.removeLast), icon: const Icon(Icons.undo)),
        IconButton(tooltip: 'Clear', onPressed: _pts.isEmpty ? null : () => setState(_pts.clear), icon: const Icon(Icons.delete_outline)),
      ]),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: start, zoom: 13),
          onMapCreated: (c) => _map = c,
          onTap: (p) => setState(() => _pts.add(p)),
          polygons: {
            ..._others,
            if (_pts.length >= 3) Polygon(polygonId: const PolygonId('me'), points: _pts, strokeWidth: 2, strokeColor: C.primary, fillColor: C.primary.withValues(alpha: .18)),
          },
          polylines: {if (_pts.length == 2) Polyline(polylineId: const PolylineId('l'), points: _pts, color: C.primary, width: 2)},
          markers: {
            for (var i = 0; i < _pts.length; i++)
              Marker(
                markerId: MarkerId('p$i'),
                position: _pts[i],
                draggable: true,
                onDragEnd: (p) => setState(() => _pts[i] = p),
                icon: BitmapDescriptor.defaultMarkerWithHue(i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure),
              ),
          },
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Card(child: Padding(padding: const EdgeInsets.all(10), child: Text('${_pts.length} points · tap to add, drag a pin to move it', textAlign: TextAlign.center))),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(onPressed: _pts.length < 3 ? null : () => Navigator.pop(context, _pts), child: const Text('Use this boundary')),
        ),
      ),
    );
  }
}
