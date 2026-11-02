import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Region + financial-year scope, same as the web header's ScopeSelector.
/// The server stores this preference per admin and applies it to every
/// /admin request, so saving it is enough to filter the whole app.
class ScopeScreen extends StatefulWidget {
  const ScopeScreen({super.key});
  @override
  State<ScopeScreen> createState() => _ScopeScreenState();
}

class _ScopeScreenState extends State<ScopeScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _fys = [];
  final _opts = <String, Map<int, String>>{'country': {}, 'state': {}, 'city': {}, 'area': {}};
  final _sel = <String, int?>{'country': null, 'state': null, 'city': null, 'area': null, 'fy': null};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<Map<int, String>> _list(String path, String id, String name, Map<String, dynamic> q) async {
    final r = await api.get(path, {'limit': 'all', 'is_active': true, ...q});
    return {for (final x in r.list) toInt(x[id])!: str(x[name])};
  }

  Future<void> _init() async {
    final meta = await api.get('/admin/scope/meta');
    final pref = ApiRes.asMap(meta.map['saved_preference'] ?? meta.map['resolved_scope']);
    _fys = ApiRes.asList(meta.map['financial_years']);
    _sel['country'] = toInt(pref['country_id']);
    _sel['state'] = toInt(pref['state_id']);
    _sel['city'] = toInt(pref['city_id']);
    _sel['area'] = toInt(pref['area_id']);
    _sel['fy'] = toInt(pref['fy_id'] ?? ApiRes.asMap(meta.map['default_fy'])['fy_id']);
    _opts['country'] = await _list('/master/countries', 'country_id', 'country_name', {});
    await _cascade();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cascade() async {
    _opts['state'] = _sel['country'] == null ? {} : await _list('/master/states', 'state_id', 'state_name', {'country_id': _sel['country']});
    _opts['city'] = _sel['state'] == null ? {} : await _list('/master/cities', 'city_id', 'city_name', {'state_id': _sel['state']});
    _opts['area'] = _sel['city'] == null ? {} : await _list('/master/areas', 'area_id', 'area_name', {'city_id': _sel['city']});
    if (mounted) setState(() {});
  }

  Future<void> _pick(String level, String label) async {
    final v = await pickOne<int>(context, label, {0: 'All', ..._opts[level]!}, selected: _sel[level] ?? 0);
    if (v == null) return;
    setState(() {
      _sel[level] = v == 0 ? null : v;
      const order = ['country', 'state', 'city', 'area'];
      for (final l in order.skip(order.indexOf(level) + 1)) {
        _sel[l] = null;
      }
    });
    await _cascade();
  }

  Future<void> _apply() async {
    final r = await busy(context, () => api.post('/admin/scope/preference', {
          'country_id': _sel['country'], 'state_id': _sel['state'], 'city_id': _sel['city'], 'area_id': _sel['area'], 'fy_id': _sel['fy'],
        }), success: 'Scope applied');
    if (r.ok && mounted) Navigator.pop(context, true);
  }

  Widget _row(String level, String label) {
    final disabled = level != 'country' && _opts[level]!.isEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: !disabled,
        title: Text(label),
        subtitle: Text(_sel[level] == null ? 'All' : (_opts[level]![_sel[level]] ?? '#${_sel[level]}')),
        trailing: const Icon(Icons.expand_more),
        onTap: () => _pick(level, label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Region & financial year')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              const Text('Dashboards, bookings, finance and reports are filtered to this scope.', style: TextStyle(color: C.body)),
              const Gap(),
              _row('country', 'Country'),
              _row('state', 'State'),
              _row('city', 'City'),
              _row('area', 'Area'),
              if (_fys.isNotEmpty)
                Card(
                  child: ListTile(
                    title: const Text('Financial year'),
                    subtitle: Text(str(_fys.firstWhere((f) => toInt(f['fy_id']) == _sel['fy'], orElse: () => {'fy_label': 'Current'})['fy_label'])),
                    trailing: const Icon(Icons.expand_more),
                    onTap: () async {
                      final v = await pickOne<int>(context, 'Financial year', {for (final f in _fys) toInt(f['fy_id'])!: str(f['fy_label'])}, selected: _sel['fy']);
                      if (v != null) setState(() => _sel['fy'] = v);
                    },
                  ),
                ),
              const Gap(),
              OutlinedButton(
                onPressed: () {
                  setState(() => _sel.updateAll((k, v) => k == 'fy' ? v : null));
                  _cascade();
                },
                child: const Text('Reset to global'),
              ),
            ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _loading ? null : _apply, child: const Text('Apply')))),
    );
  }
}
