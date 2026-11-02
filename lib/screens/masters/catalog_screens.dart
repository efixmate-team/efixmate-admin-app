import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common/crud_screen.dart';
import 'geography_screens.dart' show publicLookups;

const _catPath = '/admin/masters/services-management/service-categories';
const _skillPath = '/admin/masters/services-management/skills';

/// Icon files bundled with the web app under /services-icons.
const kCategoryIcons = ['AC.webp', 'ELECTRIC.webp', 'PLUMBER.webp', 'APPLIANCE.webp', 'CLEANING.webp', 'CARPENTER.webp', 'PAINTING.webp', 'PEST.webp'];

String _normIcon(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return '';
  if (t.startsWith('/services-icons/')) return t;
  if (t.startsWith('services-icons/')) return '/$t';
  if (t.startsWith('/Services/Categories/')) return t.replaceFirst('/Services/Categories/', '/services-icons/');
  if (t.startsWith('http') || t.startsWith('/')) return t;
  return '/services-icons/$t';
}

class ServiceCategoriesScreen extends StatelessWidget {
  const ServiceCategoriesScreen({super.key});
  @override
  Widget build(BuildContext context) => CrudScreen(CrudConfig(
        title: 'Service Category',
        base: '/master/service-categories',
        idKey: 'category_id',
        menuPath: _catPath,
        filters: const {'All': {}, 'Active only': {'is_active': true}},
        deactivateMessage: 'This category will be hidden from the service list.',
        leadingOf: (r) => NetImage(r['category_icon'], size: 44),
        titleOf: (r) => str(r['category_name']),
        subtitleOf: (r) => '${r['service_count'] ?? r['total_services'] ?? 0} services',
        linesOf: (r) => [str(r['description'], '')],
        fields: (_) => [
          Field('category_name', 'Category Name', required: true),
          Field('category_icon', 'Icon', type: F.select, options: {for (final k in kCategoryIcons) '/services-icons/$k': k.replaceAll('.webp', '')}),
          Field('category_color', 'Color (hex)', type: F.color, hint: '#2563eb'),
          Field('description', 'Description', type: F.multiline),
          Field('is_active', 'Active', type: F.toggle),
        ],
        toInitial: (r) => {...r, 'category_icon': _normIcon(r['category_icon']?.toString())},
        toPayload: (v, _) => {
          'category_name': v['category_name'],
          'category_icon': _normIcon(v['category_icon']?.toString()),
          'category_color': str(v['category_color'], '#2563eb'),
          'description': v['description'] ?? '',
          'is_active': v['is_active'] != false,
        },
        onTap: (c, r) => Navigator.push(c, MaterialPageRoute(builder: (_) => ServicesScreen(category: r))),
      ));
}

// ─── Services in a category ──────────────────────────────────────────────────

const _fixedId = '1', _unitId = '2', _inspectionId = '4';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key, required this.category});
  final Map<String, dynamic> category;
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _list = GlobalKey<PagedListState>();
  bool _activeOnly = false;
  bool get _canEdit => Session.I.canOn(_catPath, 'EDIT') || Session.I.canOn(_catPath, 'CREATE');

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ServiceFormScreen(category: widget.category, row: row)));
    if (ok == true) _list.currentState?.reload();
  }

  Future<void> _toggle(Map r) async {
    final on = truthy(r['is_active']);
    if (on && !await confirm(context, 'Deactivate service?', message: 'This service will be hidden from all listings.', danger: true, ok: 'Deactivate')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.put('/master/services/${r['service_id']}', {'is_active': !on}));
    if (res.ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(str(widget.category['category_name'], 'Services'))),
      body: PagedList(
        key: _list,
        searchHint: 'Search services…',
        fetch: (p, l, s) => api.get('/master/services', {'category_id': widget.category['category_id'], 'page': p, 'limit': l, 'search': s, if (_activeOnly) 'is_active': true}),
        header: FilterChips<bool>(options: const {false: 'All', true: 'Active only'}, value: _activeOnly, onChanged: (v) {
          setState(() => _activeOnly = v);
          _list.currentState?.reload();
        }),
        itemBuilder: (c, r, i) => RowTile(
          leading: NetImage(r['image_url'] ?? r['service_icon'], size: 48),
          title: str(r['service']),
          badge: StatusChip(truthy(r['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(r['is_active']) ? 'Active' : 'Inactive'),
          subtitle: [
            if (r['base_price'] != null) 'Base ${inr(r['base_price'])}',
            if (r['inspection_charge'] != null) 'Inspection ${inr(r['inspection_charge'])}',
            if (r['warranty_days'] != null) 'Warranty ${r['warranty_days']}d',
          ].join(' · '),
          lines: [
            if (r['booking_types'] is List) (r['booking_types'] as List).map((b) => b is Map ? (b['name'] ?? b['booking_type']) : b).join(', '),
          ],
          trailing: !_canEdit
              ? null
              : PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? _edit(r) : _toggle(r),
                  itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(truthy(r['is_active']) ? 'Deactivate' : 'Activate'))],
                ),
          onTap: _canEdit ? () => _edit(r) : null,
        ),
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add service')) : null,
    );
  }
}

class _UnitRow {
  _UnitRow(String name, String price)
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price);
  final TextEditingController name;
  final TextEditingController price;
}

/// Create / edit a service: booking types decide which price inputs apply
/// (Fixed → base price, Unit-based → per-unit prices, Inspection → visit charge).
class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({super.key, required this.category, this.row});
  final Map<String, dynamic> category;
  final Map<String, dynamic>? row;
  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _color = TextEditingController(text: '#2563eb');
  final _warranty = TextEditingController();
  final _base = TextEditingController();
  final _inspection = TextEditingController();
  final _image = TextEditingController();
  final _units = <_UnitRow>[];
  Set<String> _types = {};
  Map<String, String> _typeNames = {};
  List<Map<String, dynamic>> _unitMaster = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final res = await Future.wait([
      publicLookups().then((l) => ApiRes({'status': true, 'data': l})),
      api.get('/master/units', {'limit': 500}),
      if (widget.row != null) api.get('/master/services/${widget.row!['service_id']}'),
    ]);
    _typeNames = {for (final b in ApiRes.asList(res[0].map['BOOKING_TYPES'])) '${b['id']}': str(b['name'])};
    _unitMaster = res[1].list;
    if (widget.row != null) {
      final m = {...widget.row!, ...(res[2].ok ? res[2].map : {})};
      _name.text = str(m['service'], '');
      _desc.text = str(m['description'], '').replaceAll(RegExp(r'<[^>]*>'), '');
      _color.text = str(m['service_color'], '#2563eb');
      _warranty.text = m['warranty_days']?.toString() ?? '';
      _base.text = m['base_price']?.toString() ?? '';
      _inspection.text = m['inspection_charge']?.toString() ?? '';
      _image.text = str(m['image_url'] ?? m['service_icon'], '');
      _types = {for (final id in (m['booking_type_ids'] as List?) ?? const []) '$id'};
      final prices = {for (final p in ApiRes.asList(m['unit_prices'])) toInt(p['unit_id']): p['price']};
      for (final id in (m['unit_ids'] as List?) ?? const []) {
        final u = _unitMaster.firstWhere((u) => toInt(u['unit_id']) == toInt(id), orElse: () => {});
        if (u.isEmpty) continue;
        _units.add(_UnitRow(str(u['unit_name']), prices[toInt(id)]?.toString() ?? ''));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Unit names → master unit ids, creating missing units (same as web).
  Future<List<Map<String, dynamic>>?> _resolveUnits() async {
    final byName = {for (final u in _unitMaster) str(u['unit_name'], '').toLowerCase(): toInt(u['unit_id'])};
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final r in _units) {
      final name = r.name.text.trim();
      if (name.isEmpty) continue;
      var id = byName[name.toLowerCase()];
      if (id == null) {
        final c = await api.post('/master/units', {'unit_name': name, 'is_active': true});
        if (!c.ok) {
          toast('Could not create unit "$name": ${c.message}', error: true);
          return null;
        }
        id = toInt(c.map['unit_id']);
        byName[name.toLowerCase()] = id;
      }
      if (id == null || !seen.add(id)) continue;
      out.add({'unit_id': id, 'price': double.tryParse(r.price.text) ?? 0});
    }
    return out;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast('Service name is required', error: true);
    final names = _units.map((u) => u.name.text.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    if (names.toSet().length != names.length) return toast('Duplicate unit names are not allowed.', error: true);
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'service': _name.text.trim(),
      'description': _desc.text.trim(),
      'service_color': _color.text.trim().isEmpty ? '#2563eb' : _color.text.trim(),
      'service_icon': _image.text.trim(),
      'image_url': _image.text.trim(),
      'booking_type_ids': _types.map(int.parse).toList(),
      'warranty_days': _warranty.text.trim().isEmpty ? null : int.tryParse(_warranty.text.trim()),
    };
    if (widget.row == null) payload['category_id'] = widget.category['category_id'];
    if (_types.contains(_fixedId)) payload['base_price'] = _base.text.trim().isEmpty ? null : double.tryParse(_base.text);
    if (_types.contains(_inspectionId)) payload['inspection_charge'] = _inspection.text.trim().isEmpty ? null : double.tryParse(_inspection.text);
    if (_types.contains(_unitId)) {
      final up = await _resolveUnits();
      if (up == null) return setState(() => _saving = false);
      payload['unit_ids'] = up.map((e) => e['unit_id']).toList();
      payload['unit_prices'] = up;
    } else if (widget.row == null) {
      payload['unit_ids'] = [];
      payload['unit_prices'] = [];
    }
    final res = widget.row == null ? await api.post('/master/services', payload) : await api.put('/master/services/${widget.row!['service_id']}', payload);
    if (!mounted) return;
    setState(() => _saving = false);
    final moved = toInt(res.map['area_prices_updated']) ?? 0;
    if (res.ok && moved > 0) toast('Base price applied to $moved area slot price(s) that matched the old price.');
    if (toastRes(res, success: 'Service saved.')) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.row == null ? 'Add service' : 'Edit service')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Service name *')),
              const Gap(),
              Row(children: [
                if (_image.text.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 10), child: NetImage(_image.text, size: 52)),
                Expanded(child: TextField(controller: _image, decoration: const InputDecoration(labelText: 'Image path', hintText: '/services-icons/AC.webp'), onChanged: (_) => setState(() {}))),
              ]),
              const Gap(),
              Row(children: [
                Expanded(child: TextField(controller: _color, decoration: const InputDecoration(labelText: 'Color (hex)'))),
                const Gap(),
                Expanded(child: TextField(controller: _warranty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Warranty (days)'))),
              ]),
              const Gap(),
              const Text('Booking type', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(spacing: 6, children: [
                for (final e in _typeNames.entries)
                  FilterChip(label: Text(e.value), selected: _types.contains(e.key), onSelected: (v) => setState(() => v ? _types.add(e.key) : _types.remove(e.key))),
              ]),
              if (_types.contains(_fixedId)) ...[
                const Gap(),
                TextField(controller: _base, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Base price (₹)', helperText: 'Price customers pay, set per area in Service configuration')),
              ],
              if (_types.contains(_inspectionId)) ...[
                const Gap(),
                TextField(controller: _inspection, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Inspection charge (₹)')),
              ],
              if (_types.contains(_unitId)) ...[
                const Gap(),
                const Text('Units', style: TextStyle(fontWeight: FontWeight.w600)),
                const Text('Add each unit customers can book, with its own price per unit.', style: TextStyle(fontSize: 12, color: C.muted)),
                for (var i = 0; i < _units.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(flex: 3, child: TextField(controller: _units[i].name, decoration: const InputDecoration(labelText: 'Unit name'))),
                      const Gap(8),
                      Expanded(flex: 2, child: TextField(controller: _units[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price ₹'))),
                      IconButton(onPressed: () => setState(() => _units.removeAt(i)), icon: const Icon(Icons.close, color: C.red)),
                    ]),
                  ),
                TextButton.icon(onPressed: () => setState(() => _units.add(_UnitRow('', ''))), icon: const Icon(Icons.add), label: const Text('Add unit')),
              ],
              const Gap(),
              TextField(controller: _desc, maxLines: 5, minLines: 3, decoration: const InputDecoration(labelText: 'Description', hintText: 'Describe this service in detail…')),
              const Gap(80),
            ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _saving || _loading ? null : _save, child: Text(_saving ? 'Saving…' : 'Save service')))),
    );
  }
}

// ─── Skills ──────────────────────────────────────────────────────────────────

/// Skills map technicians to the services they can be dispatched for —
/// /admin/skills-* endpoints.
class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});
  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final _list = GlobalKey<PagedListState>();
  bool get _canEdit => Session.I.canOn(_skillPath, 'EDIT') || Session.I.canOn(_skillPath, 'CREATE');

  Future<void> _edit([Map<String, dynamic>? row]) async {
    var serviceIds = <String>[];
    if (row != null) {
      final r = await api.get('/admin/skills-services', {'skillId': row['skill_id']});
      serviceIds = r.list.map((s) => '${s['service_id']}').toList();
    }
    if (!mounted) return;
    final ok = await openForm(
      context,
      title: row == null ? 'Add skill' : 'Edit skill',
      initial: row == null
          ? {'orderSeq': 0, 'skillColor': '#2563eb', 'serviceIds': <String>[]}
          : {
              'skillName': row['skill_name'],
              'categoryId': '${row['category_id']}',
              'description': row['description'],
              'skillColor': row['skill_color'] ?? '#2563eb',
              'orderSeq': row['order_seq'] ?? 0,
              'serviceIds': serviceIds,
            },
      fields: [
        Field('skillName', 'Skill name', required: true),
        Field('categoryId', 'Category', type: F.select, required: true, loader: optionsFrom('/master/service-categories', 'category_id', (c) => str(c['category_name']))),
        Field('serviceIds', 'Services this skill covers', type: F.multiSelect, dependsOn: const ['categoryId'],
            help: 'Technicians pick skills, not services — a service with no skill can never be dispatched.',
            loader: (v) async {
              if (v['categoryId'] == null) return {};
              final r = await api.get('/master/services', {'category_id': v['categoryId'], 'limit': 500});
              return {for (final s in r.list) '${s['service_id']}': str(s['service'])};
            }),
        Field('description', 'Description', type: F.multiline),
        Field('skillColor', 'Color (hex)', type: F.color),
        Field('orderSeq', 'Order', type: F.number),
      ],
      onSubmit: (v) async {
        final body = {
          if (row != null) 'skillId': row['skill_id'],
          'skillName': v['skillName'],
          'categoryId': toInt(v['categoryId']),
          'description': v['description'] ?? '',
          'skillColor': v['skillColor'] ?? '#2563eb',
          'orderSeq': v['orderSeq'] ?? 0,
        };
        final res = await api.post(row == null ? '/admin/skills-create' : '/admin/skills-update', body);
        if (!res.ok) return res;
        final skillId = row?['skill_id'] ?? res.map['skill_id'];
        final ids = ((v['serviceIds'] as List?) ?? const []).map((e) => toInt(e)).whereType<int>().toList();
        if (skillId != null) await api.post('/admin/skills-set-services', {'skillId': skillId, 'serviceIds': ids});
        return res;
      },
    );
    if (ok) _list.currentState?.reload();
  }

  Future<void> _toggle(Map r) async {
    final on = truthy(r['is_active']);
    if (on && !await confirm(context, 'Deactivate skill?', message: 'This skill will be hidden from technician profiles.', danger: true, ok: 'Deactivate')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.post('/admin/skills-toggle', {'skillId': r['skill_id'], 'isActive': !on}));
    if (res.ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search skills…',
        fetch: (p, l, s) => api.post('/admin/skills-list', {'page': p, 'limit': l, 'search': s}),
        itemBuilder: (c, r, i) => RowTile(
          title: str(r['skill_name']),
          badge: StatusChip(truthy(r['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(r['is_active']) ? 'Active' : 'Inactive'),
          subtitle: str(r['category_name'], ''),
          lines: [str(r['description'], ''), if (r['service_count'] != null) '${r['service_count']} services'],
          trailing: !_canEdit
              ? null
              : PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? _edit(r) : _toggle(r),
                  itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(truthy(r['is_active']) ? 'Deactivate' : 'Activate'))],
                ),
          onTap: _canEdit ? () => _edit(r) : null,
        ),
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(heroTag: 'skill', onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add skill')) : null,
    );
  }
}
