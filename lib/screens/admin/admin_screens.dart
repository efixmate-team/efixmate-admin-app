import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _adminsPath = '/admin/admin-management/admins';
const _rolesPath = '/admin/admin-management/roles';
const _permsPath = '/admin/admin-management/permissions';

Future<Map<String, String>> _roleOptions(Map<String, dynamic> _) async {
  final r = await api.get('/admin/roles-dropdown');
  return {for (final x in r.list) '${x['id'] ?? x['role_id']}': str(x['label'] ?? x['role_name'])};
}


// ─── Admins ──────────────────────────────────────────────────────────────────

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});
  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  final _list = GlobalKey<PagedListState>();
  bool _activeOnly = false;
  bool get _canEdit => Session.I.canOn(_adminsPath, 'EDIT') || Session.I.can('ADMIN_MANAGE') || Session.I.can('ADMIN_EDIT');

  Future<void> _edit([Map<String, dynamic>? a]) async {
    final ok = await openForm(
      context,
      title: a == null ? 'Add administrator' : 'Edit administrator',
      initial: a == null ? {'admin_type': 'A', 'is_active': true} : {...a, 'role_id': a['role_id']?.toString()},
      fields: [
        Field('first_name', 'First Name', required: true),
        Field('last_name', 'Last Name'),
        Field('email', 'Email Address', type: F.email, required: true),
        Field('mobile_number', 'Mobile Number', type: F.phone, required: true),
        if (a == null) Field('password', 'Temporary Password', type: F.password, required: true),
        Field('admin_type', 'Admin Type', type: F.select, options: const {'A': 'Administrator', 'S': 'Super Admin'}),
        Field('role_id', 'Role', type: F.select, loader: _roleOptions),
        if (a != null) Field('is_active', 'Active', type: F.toggle),
      ],
      onSubmit: (v) => a == null
          ? api.post('/admin/create', {
              'firstName': v['first_name'], 'lastName': v['last_name'], 'email': v['email'], 'mobileNumber': v['mobile_number'],
              'password': v['password'], 'adminType': v['admin_type'], 'createdBy': Session.I.profile?['admin_id'], 'roleId': toInt(v['role_id']),
            })
          : api.post('/admin/update', {
              'adminId': a['admin_id'], 'firstName': v['first_name'], 'lastName': v['last_name'], 'mobileNumber': v['mobile_number'], 'email': v['email'],
              'adminType': v['admin_type'], 'isActive': v['is_active'], 'updatedBy': Session.I.profile?['admin_id'], 'roleId': toInt(v['role_id']),
            }),
    );
    if (ok) _list.currentState?.reload();
  }

  Future<void> _act(String what, Map a) async {
    switch (what) {
      case 'toggle':
        final on = truthy(a['is_active']);
        if (on && !await confirm(context, 'Deactivate admin?', message: 'This administration account will lose system access.', danger: true, ok: 'Deactivate')) return;
        if (!mounted) return;
        final r = await busy(context, () => api.post('/admin/toggle-status', {'adminId': a['admin_id'], 'isActive': !on}));
        if (r.ok) _list.currentState?.reload();
      case 'password':
        final p = await prompt(context, 'Change admin password', label: 'New password (min 8 chars)', required: true, obscure: true, ok: 'Update');
        if (p == null || !mounted) return;
        if (p.length < 8) return toast('Password must be at least 8 characters', error: true);
        await busy(context, () => api.post('/admin/reset-password', {'adminId': a['admin_id'], 'newPassword': p}), success: 'Password updated');
      case 'view':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AdminDetailScreen(id: a['admin_id'])));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search name, email…',
        fetch: (p, l, s) => api.post('/admin/admin-paginated', {'page': p, 'limit': l, 'search': s, if (_activeOnly) 'isActive': true}),
        header: FilterChips<bool>(options: const {false: 'All', true: 'Active only'}, value: _activeOnly, onChanged: (v) {
          setState(() => _activeOnly = v);
          _list.currentState?.reload();
        }),
        itemBuilder: (c, a, i) => RowTile(
          leading: Avatar(url: a['profile_image'], name: fullName(a)),
          title: fullName(a),
          badge: StatusChip(truthy(a['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(a['is_active']) ? 'Active' : 'Inactive'),
          subtitle: '${str(a['email'], '')} · ${str(a['mobile_number'], '')}',
          lines: ['${a['admin_type'] == 'S' ? 'Super Admin' : 'Administrator'} · ${str(a['role_name'], 'No role assigned')}'],
          trailing: !_canEdit
              ? null
              : PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? _edit(a) : _act(v, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'view', child: Text('View details')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'password', child: Text('Change password')),
                    PopupMenuItem(value: 'toggle', child: Text(truthy(a['is_active']) ? 'Deactivate' : 'Activate')),
                  ],
                ),
          onTap: () => _act('view', a),
        ),
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(heroTag: 'admin', onPressed: () => _edit(), icon: const Icon(Icons.person_add), label: const Text('Add admin')) : null,
    );
  }
}

class AdminDetailScreen extends StatelessWidget {
  const AdminDetailScreen({super.key, required this.id});
  final dynamic id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrator details')),
      body: ApiLoader(
        load: () => api.post('/admin/get', {'adminId': id}),
        builder: (c, res, reload) {
          final a = res.data is List ? (ApiRes.asList(res.data).firstOrNull ?? {}) : res.map;
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(children: [
              Row(children: [
                Avatar(url: a['profile_image'], name: fullName(a), size: 56),
                const Gap(),
                Expanded(child: Text(fullName(a), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                StatusChip(truthy(a['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(a['is_active']) ? 'Active' : 'Inactive'),
              ]),
              const Gap(),
              KV('Admin ID', a['admin_id']),
              KV('Email', a['email']),
              KV('Email verified', truthy(a['email_verified']) ? 'Yes' : 'No'),
              KV('Mobile', a['mobile_number']),
              KV('Mobile verified', truthy(a['mobile_verified']) ? 'Yes' : 'No'),
              KV('Type', a['admin_type'] == 'S' ? 'Super Admin' : 'Administrator'),
              KV('Role', a['role_name']),
              KV('Created at', fmtDateTime(a['created_at'])),
              KV('Login ID', SelectableText(str(a['admin_uid']), style: const TextStyle(color: C.primary, fontSize: 12.5))),
              const Text('Admins sign in with this ID (web: /login/<id>, or paste it in this app).', style: TextStyle(fontSize: 11.5, color: C.muted)),
            ]),
          ]);
        },
      ),
    );
  }
}

// ─── Roles ───────────────────────────────────────────────────────────────────

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});
  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  final _list = GlobalKey<PagedListState>();
  bool get _canEdit => Session.I.canOn(_rolesPath, 'EDIT') || Session.I.can('ROLE_MANAGE');
  int? get _me => toInt(Session.I.profile?['admin_id']);

  Future<void> _edit([Map<String, dynamic>? r]) async {
    final ok = await openForm(
      context,
      title: r == null ? 'Add role' : 'Edit role',
      initial: r ?? {'is_active': true},
      fields: [Field('role_name', 'Role Name', required: true), Field('is_active', 'Active', type: F.toggle)],
      onSubmit: (v) => r == null
          ? api.post('/admin/roles-create', {'roleName': v['role_name'], 'isActive': v['is_active'], 'createdBy': _me})
          : api.post('/admin/roles-update', {'roleId': r['role_id'], 'roleName': v['role_name'], 'isActive': v['is_active'], 'updatedBy': _me}),
    );
    if (ok) _list.currentState?.reload();
  }

  Future<void> _act(String what, Map r) async {
    if (what == 'toggle') {
      final on = truthy(r['is_active']);
      if (on && !await confirm(context, 'Deactivate role?', message: 'This will suspend any admins linked to this role.', danger: true, ok: 'Deactivate')) return;
      if (!mounted) return;
      final res = await busy(context, () => api.post('/admin/roles-toggle', {'roleId': r['role_id'], 'isActive': !on, 'updatedBy': _me}));
      if (res.ok) _list.currentState?.reload();
    } else if (what == 'delete') {
      if (!await confirm(context, 'Delete role?', message: 'This cannot be undone.', danger: true, ok: 'Delete')) return;
      if (!mounted) return;
      final res = await busy(context, () => api.post('/admin/roles-delete', {'roleId': r['role_id']}), success: 'Role deleted');
      if (res.ok) _list.currentState?.reload();
    } else if (what == 'perms') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text('Permissions · ${r['role_name']}')), body: PermissionsScreen(roleId: '${r['role_id']}'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search roles…',
        fetch: (p, l, s) => api.post('/admin/role-paginated', {'page': p, 'limit': l, 'search': s}),
        itemBuilder: (c, r, i) => RowTile(
          leading: const Icon(Icons.shield_outlined, color: C.primary),
          title: str(r['role_name']),
          badge: StatusChip(truthy(r['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(r['is_active']) ? 'Active' : 'Inactive'),
          subtitle: str(r['role_code'], ''),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? _edit(r) : _act(v, r),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'perms', child: Text('View / edit permissions')),
              if (_canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (_canEdit) PopupMenuItem(value: 'toggle', child: Text(truthy(r['is_active']) ? 'Deactivate' : 'Activate')),
              if (_canEdit) const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          onTap: () => _act('perms', r),
        ),
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(heroTag: 'role', onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add role')) : null,
    );
  }
}

// ─── Permission matrix ───────────────────────────────────────────────────────

/// Role × menu × privilege matrix with Allow / Deny, plus privilege
/// definitions per menu (add / rename / delete).
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, this.roleId});
  final String? roleId;
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  Map<String, String> _roles = {};
  String? _role;
  bool _defineMode = false;
  final _key = GlobalKey<ApiLoaderState>();
  bool get _canEdit => Session.I.canOn(_permsPath, 'EDIT') || Session.I.can('PRIVILEGE_MANAGE');

  @override
  void initState() {
    super.initState();
    _roleOptions(const {}).then((r) {
      if (!mounted) return;
      setState(() {
        _roles = r;
        _role = widget.roleId ?? (r.isNotEmpty ? r.keys.first : null);
      });
    });
  }

  Future<ApiRes> _load() async {
    if (_defineMode) {
      final r = await Future.wait([api.post('/admin/menu-paginated', {'limit': 1000, 'isActive': true}), api.post('/admin/privileges-list-with-menu', {})]);
      if (!r[0].ok) return r[0];
      return ApiRes({'status': true, 'menus': r[0].data, 'privs': r[1].ok ? r[1].data : []});
    }
    if (_role == null) return ApiRes({'status': true, 'data': []});
    return api.post('/admin/role-permissions', {'roleId': int.parse(_role!)});
  }

  Future<void> _toggle(Map p, String type, bool current) async {
    final r = await api.post('/admin/role-permissions-toggle', {'roleId': int.parse(_role!), 'privilegeId': p['privilege_id'], 'permissionType': type, 'isAssigned': !current});
    if (!toastRes(r, success: 'Permissions updated.')) return;
    _key.currentState?.reload();
  }

  Future<void> _addPriv(int menuId) async {
    final n = await prompt(context, 'Add privilege', label: 'Privilege name', hint: 'e.g. EXPORT', required: true, ok: 'Add');
    if (n == null || !mounted) return;
    final r = await busy(context, () => api.post('/admin/privileges-create', {'menuId': menuId, 'privilegeName': n.toUpperCase()}), success: 'Privilege added');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _editPriv(Map p) async {
    final n = await prompt(context, 'Rename privilege', initial: str(p['privilege_name']), required: true);
    if (n == null || !mounted) return;
    final r = await busy(context, () => api.post('/admin/privileges-update', {'privilegeId': p['privilege_id'], 'privilegeName': n.toUpperCase(), 'isActive': p['is_active'] != false}), success: 'Updated');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _deletePriv(Map p) async {
    if (!await confirm(context, 'Delete ${p['privilege_name']}?', message: 'This removes it from all roles.', danger: true, ok: 'Delete')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.post('/admin/privileges-delete', {'privilegeId': p['privilege_id']}), success: 'Deleted');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      FilterChips<bool>(options: const {false: 'Assign to role', true: 'Defined privileges'}, value: _defineMode, onChanged: (v) {
        setState(() => _defineMode = v);
        _key.currentState?.reload();
      }),
      if (!_defineMode && _roles.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: InkWell(
            onTap: () async {
              final v = await pickOne<String>(context, 'Role', _roles, selected: _role);
              if (v != null) {
                setState(() => _role = v);
                _key.currentState?.reload();
              }
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: 'Role', suffixIcon: Icon(Icons.expand_more)), child: Text(_roles[_role] ?? 'Select a role')),
          ),
        ),
      Expanded(
        child: ApiLoader(
          key: _key,
          load: _load,
          builder: (c, res, reload) {
            if (_defineMode) {
              final menus = ApiRes.asList(res['menus']);
              final privs = ApiRes.asList(res['privs']);
              return ListView(padding: const EdgeInsets.all(12), children: [
                for (final m in menus)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      title: str(m['menu_name']),
                      trailing: _canEdit ? IconButton(onPressed: () => _addPriv(toInt(m['menu_id'])!), icon: const Icon(Icons.add)) : null,
                      children: [
                        Text('${str(m['menu_group'], '')} · ${str(m['menu_path'], '')}', style: const TextStyle(fontSize: 11.5, color: C.muted)),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final p in privs.where((p) => p['menu_id'] == m['menu_id']))
                            InputChip(
                              label: Text(str(p['privilege_name'])),
                              onPressed: _canEdit ? () => _editPriv(p) : null,
                              onDeleted: _canEdit ? () => _deletePriv(p) : null,
                            ),
                        ]),
                      ],
                    ),
                  ),
              ]);
            }
            final rows = res.list;
            if (rows.isEmpty) return ListView(children: const [EmptyView('Select a role to view its permission matrix')]);
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final m in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SectionCard(
                    title: str(m['menu_name']),
                    trailing: Text('${ApiRes.asList(m['privileges']).where((p) => truthy(p['is_allowed'] ?? p['is_assigned'])).length}/${ApiRes.asList(m['privileges']).length}', style: const TextStyle(color: C.muted)),
                    children: [
                      if (ApiRes.asList(m['privileges']).isEmpty) const Text('Not applicable', style: TextStyle(color: C.muted)),
                      for (final p in ApiRes.asList(m['privileges']))
                        Row(children: [
                          Expanded(child: Text(str(p['privilege_name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                          FilterChip(
                            label: const Text('Allow'),
                            selected: truthy(p['is_allowed'] ?? p['is_assigned']),
                            selectedColor: C.greenSoft,
                            onSelected: _canEdit ? (_) => _toggle(p, 'ALLOW', truthy(p['is_allowed'] ?? p['is_assigned'])) : null,
                          ),
                          const Gap(6),
                          FilterChip(
                            label: const Text('Deny'),
                            selected: truthy(p['is_denied']),
                            selectedColor: C.redSoft,
                            onSelected: _canEdit ? (_) => _toggle(p, 'DENY', truthy(p['is_denied'])) : null,
                          ),
                        ]),
                    ],
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}
