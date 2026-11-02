import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/widgets.dart';
import 'customer_detail_screen.dart';

const kUsersPath = '/admin/user-management/users';

/// Customers — POST /admin/users/paginated.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _list = GlobalKey<PagedListState>();
  bool _activeOnly = false;

  bool get _canEdit => Session.I.canOn(kUsersPath, 'EDIT');

  Future<void> _edit(Map<String, dynamic> r) async {
    final ok = await openForm(
      context,
      title: 'Edit customer',
      initial: r,
      fields: [
        Field('first_name', 'First Name', required: true),
        Field('last_name', 'Last Name'),
        Field('email', 'Email', type: F.email),
        Field('is_active', 'Active Account', type: F.toggle),
      ],
      onSubmit: (v) => api.post('/admin/users/update', {
        'customerId': r['customer_id'],
        'firstName': v['first_name'],
        'lastName': v['last_name'],
        'email': v['email'],
        'isActive': v['is_active'],
      }),
    );
    if (ok) _list.currentState?.reload();
  }

  Future<void> _toggle(Map r) async {
    final on = truthy(r['is_active']);
    if (on && !await confirm(context, 'Deactivate this customer?', message: "They can't log in or book until you activate them again.", danger: true, ok: 'Deactivate')) return;
    if (!mounted) return;
    final res = await busy(context, () => api.post('/admin/users/update', {'customerId': r['customer_id'], 'isActive': !on}), success: 'User updated.');
    if (res.ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      searchHint: 'Search name, mobile, email…',
      fetch: (p, l, s) => api.post('/admin/users/paginated', {'page': p, 'limit': l, 'search': s, if (_activeOnly) 'isActive': true}),
      header: FilterChips<bool>(options: const {false: 'All', true: 'Active only'}, value: _activeOnly, onChanged: (v) {
        setState(() => _activeOnly = v);
        _list.currentState?.reload();
      }),
      itemBuilder: (c, r, i) => RowTile(
        leading: Avatar(url: r['profile_pitcher'] ?? r['profile'], name: fullName(r)),
        title: fullName(r),
        badge: StatusChip(truthy(r['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(r['is_active']) ? 'Active' : 'Inactive'),
        subtitle: '${str(r['mobile_number'], '')}  ${str(r['email'], '')}',
        lines: ['${str(r['customer_uid'] ?? r['customer_code'], '')} · joined ${fmtDate(r['created_at'])}'],
        trailing: !_canEdit
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _edit(r) : _toggle(r),
                itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(truthy(r['is_active']) ? 'Deactivate' : 'Activate'))],
              ),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: r['customer_id'])));
          _list.currentState?.reload();
        },
      ),
    );
  }
}
