import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class RowAction {
  RowAction(this.label, this.icon, this.onTap, {this.danger = false});
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, Map<String, dynamic> row, VoidCallback reload) onTap;
  final bool danger;
}

/// Config-driven list + create/edit/activate screen for any `/master/<x>` or
/// `/lookup/<x>` resource (GET list, POST create, PUT /:id update, DELETE /:id).
class CrudConfig {
  CrudConfig({
    required this.title,
    required this.base,
    required this.idKey,
    required this.menuPath,
    required this.fields,
    required this.titleOf,
    this.subtitleOf,
    this.linesOf,
    this.leadingOf,
    this.query = const {},
    this.filters,
    this.toPayload,
    this.toInitial,
    this.activeKey = 'is_active',
    this.canDelete = false,
    this.canCreate = true,
    this.actions = const [],
    this.onTap,
    this.searchHint = 'Search…',
    this.deactivateMessage,
    this.upload,
  });

  final String title;

  /// e.g. "/master/charges"
  final String base;
  final String idKey;

  /// Web route used for permission checks (EDIT / DELETE).
  final String menuPath;
  final List<Field> Function(Map<String, dynamic>? row) fields;
  final String Function(Map<String, dynamic> row) titleOf;
  final String Function(Map<String, dynamic> row)? subtitleOf;
  final List<String> Function(Map<String, dynamic> row)? linesOf;
  final Widget Function(Map<String, dynamic> row)? leadingOf;
  final Map<String, dynamic> query;

  /// Optional quick filters: label → extra query.
  final Map<String, Map<String, dynamic>>? filters;
  final Map<String, dynamic> Function(Map<String, dynamic> values, Map<String, dynamic>? row)? toPayload;
  final Map<String, dynamic> Function(Map<String, dynamic> row)? toInitial;
  final String? activeKey;
  final bool canDelete;
  final bool canCreate;
  final List<RowAction> actions;
  final void Function(BuildContext context, Map<String, dynamic> row)? onTap;
  final String searchHint;
  final String? deactivateMessage;

  /// Custom save (e.g. multipart). Defaults to JSON POST/PUT.
  final Future<ApiRes> Function(Map<String, dynamic> payload, Map<String, dynamic>? row)? upload;
}

class CrudScreen extends StatefulWidget {
  const CrudScreen(this.cfg, {super.key, this.embedded = true});
  final CrudConfig cfg;

  /// When false it renders its own Scaffold/AppBar (for drill-down pages).
  final bool embedded;
  @override
  State<CrudScreen> createState() => CrudScreenState();
}

class CrudScreenState extends State<CrudScreen> {
  final _list = GlobalKey<PagedListState>();
  late String _filter = widget.cfg.filters?.keys.first ?? '';

  CrudConfig get c => widget.cfg;
  bool get _canEdit => Session.I.canOn(c.menuPath, 'EDIT') || Session.I.canOn(c.menuPath, 'CREATE');
  bool get _canDel => c.canDelete && Session.I.canOn(c.menuPath, 'DELETE');

  void reload() => _list.currentState?.reload();

  Future<ApiRes> _fetch(int page, int limit, String search) {
    return api.get(c.base, {...c.query, ...?c.filters?[_filter], 'page': page, 'limit': limit, 'search': search});
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final initial = row == null ? <String, dynamic>{if (c.activeKey != null) c.activeKey!: true} : (c.toInitial?.call(row) ?? row);
    final ok = await openForm(
      context,
      title: row == null ? 'Add ${c.title}' : 'Edit ${c.title}',
      fields: c.fields(row),
      initial: initial,
      submitLabel: row == null ? 'Create' : 'Save changes',
      onSubmit: (v) {
        final payload = c.toPayload?.call(v, row) ?? v;
        if (c.upload != null) return c.upload!(payload, row);
        return row == null ? api.post(c.base, payload) : api.put('${c.base}/${row[c.idKey]}', payload);
      },
    );
    if (ok) reload();
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final on = truthy(row[c.activeKey]);
    if (on && !await confirm(context, 'Deactivate this record?', message: c.deactivateMessage, ok: 'Deactivate', danger: true)) return;
    if (!mounted) return;
    final res = await busy(context, () => api.put('${c.base}/${row[c.idKey]}', {c.activeKey!: !on}), success: on ? 'Deactivated' : 'Activated');
    if (res.ok) reload();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!await confirm(context, 'Delete this record?', message: 'This cannot be undone.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    final res = await busy(context, () => api.delete('${c.base}/${row[c.idKey]}'), success: 'Deleted');
    if (res.ok) reload();
  }

  void _menu(Map<String, dynamic> row) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(c.titleOf(row), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          if (c.onTap != null)
            ListTile(leading: const Icon(Icons.open_in_new), title: const Text('Open'), onTap: () {
              Navigator.pop(s);
              c.onTap!(context, row);
            }),
          for (final a in c.actions)
            ListTile(
              leading: Icon(a.icon, color: a.danger ? C.red : null),
              title: Text(a.label, style: TextStyle(color: a.danger ? C.red : null)),
              onTap: () {
                Navigator.pop(s);
                a.onTap(context, row, reload);
              },
            ),
          if (_canEdit) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () {
            Navigator.pop(s);
            _edit(row);
          }),
          if (_canEdit && c.activeKey != null && row.containsKey(c.activeKey))
            ListTile(
              leading: Icon(truthy(row[c.activeKey]) ? Icons.block : Icons.check_circle_outline, color: truthy(row[c.activeKey]) ? C.red : C.green),
              title: Text(truthy(row[c.activeKey]) ? 'Deactivate' : 'Activate'),
              onTap: () {
                Navigator.pop(s);
                _toggle(row);
              },
            ),
          if (_canDel)
            ListTile(leading: const Icon(Icons.delete_outline, color: C.red), title: const Text('Delete', style: TextStyle(color: C.red)), onTap: () {
              Navigator.pop(s);
              _delete(row);
            }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = PagedList(
      key: _list,
      searchHint: c.searchHint,
      fetch: _fetch,
      header: c.filters == null
          ? null
          : FilterChips<String>(
              options: {for (final k in c.filters!.keys) k: k},
              value: _filter,
              onChanged: (v) {
                setState(() => _filter = v);
                reload();
              },
            ),
      itemBuilder: (ctx, row, i) {
        final active = c.activeKey == null || !row.containsKey(c.activeKey) ? null : truthy(row[c.activeKey]);
        return RowTile(
          leading: c.leadingOf?.call(row),
          title: c.titleOf(row),
          subtitle: c.subtitleOf?.call(row),
          lines: c.linesOf?.call(row) ?? const [],
          badge: active == null ? null : StatusChip(active ? 'ACTIVE' : 'INACTIVE', label: active ? 'Active' : 'Inactive'),
          trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _menu(row)),
          onTap: c.onTap != null ? () => c.onTap!(context, row) : () => _menu(row),
        );
      },
    );
    final fab = c.canCreate && _canEdit
        ? FloatingActionButton.extended(heroTag: c.base, onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add'))
        : null;
    if (widget.embedded) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(appBar: AppBar(title: Text(c.title)), body: body, floatingActionButton: fab);
  }
}

/// Dropdown options from any list endpoint: value=idKey, label=labelOf(row).
OptionsLoader optionsFrom(String path, String idKey, String Function(Map<String, dynamic>) labelOf, {Map<String, dynamic> Function(Map<String, dynamic> values)? query}) {
  return (values) async {
    final res = await api.get(path, {'limit': 'all', ...?query?.call(values)});
    return {for (final r in res.list) '${r[idKey]}': labelOf(r)};
  };
}
