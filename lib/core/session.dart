import 'package:flutter/foundation.dart';

import 'api.dart';

class MenuItem {
  MenuItem({required this.name, required this.path, required this.group, required this.permissions});
  final String name;
  final String path;
  final String group;
  final List<String> permissions;
}

/// Signed-in admin, their menus and privileges.
/// Mirrors client/src/providers/AdminPermissionProvider.tsx so button-level
/// checks behave the same as on the web panel.
class Session extends ChangeNotifier {
  Session._();
  static final Session I = Session._();

  Map<String, dynamic>? profile;
  List<MenuItem> menus = [];
  List<String> permissions = [];
  List<String> denied = [];
  bool isSuperAdmin = false;
  bool loaded = false;

  bool get signedIn => profile != null;

  String get displayName {
    final p = profile ?? const {};
    final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    return n.isEmpty ? 'Admin' : n;
  }

  /// Load profile + menus. Returns false when the cookie is missing/expired.
  Future<bool> restore() async {
    final res = await api.get('/admin/profile');
    if (!res.ok || res.data is! Map) {
      profile = null;
      loaded = true;
      notifyListeners();
      return false;
    }
    profile = res.map;
    await loadMenus();
    loaded = true;
    notifyListeners();
    return true;
  }

  /// Re-fetch menus/privileges (pull-to-refresh on the Menu tab).
  Future<void> refreshMenus() async {
    await loadMenus();
    notifyListeners();
  }

  Future<void> loadMenus() async {
    final res = await api.get('/admin/menus');
    if (!res.ok) return;
    isSuperAdmin = res['isSuperAdmin'] == true;
    permissions = List<String>.from((res['permissions'] ?? res['privileges'] ?? const []).map((e) => e.toString().toUpperCase()));
    denied = List<String>.from((res['deniedPermissions'] ?? res['deniedPrivileges'] ?? const []).map((e) => e.toString().toUpperCase()));
    final out = <MenuItem>[];
    for (final g in ApiRes.asList(res['group'] ?? res['groups'])) {
      final groupName = (g['menu_group'] ?? g['group_name'] ?? g['group'] ?? '').toString();
      for (final m in ApiRes.asList(g['menus'])) {
        final path = _norm((m['menu_path'] ?? '').toString());
        if (path.isEmpty) continue;
        out.add(MenuItem(
          name: (m['menu_name'] ?? '').toString(),
          path: path,
          group: groupName,
          permissions: List<String>.from((m['permissions'] ?? const []).map((e) => e.toString().toUpperCase())),
        ));
      }
    }
    menus = out;
  }

  static String _norm(String p) {
    var b = p.split('?').first.split('#').first;
    if (b.length > 1 && b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  /// Same allow-list the web layout keeps reachable without a menu row.
  static const _alwaysAllowed = ['/admin/guides', '/admin/settings/profile', '/admin/finance', '/admin/reports'];

  /// Is this admin route visible to the signed-in admin?
  bool canOpen(String path) {
    if (isSuperAdmin) return true;
    final p = _norm(path);
    if (_alwaysAllowed.any((a) => p == a || p.startsWith('$a/'))) {
      if (p.startsWith('/admin/finance')) return can('FINANCE_VIEW');
      return true;
    }
    return menus.any((m) => p == m.path || p.startsWith('${m.path}/'));
  }

  /// Menu-level privilege, e.g. can('/admin/booking-management/bookings', 'EDIT').
  bool canOn(String path, String action) {
    if (isSuperAdmin) return true;
    final p = _norm(path);
    final sorted = [...menus]..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final m in sorted) {
      if (p == m.path || p.startsWith('${m.path}/')) return m.permissions.contains(action.toUpperCase());
    }
    return false;
  }

  /// Global permission code check (e.g. FINANCE_VIEW, REPORTS_EXPORT).
  bool can(String permission) {
    if (isSuperAdmin) return true;
    final p = permission.toUpperCase();
    if (denied.contains(p)) return false;
    if (permissions.contains(p)) return true;
    // A category grant (e.g. "FINANCE") implies its children.
    final cat = p.split('_').first;
    return permissions.contains(cat) && !denied.contains(cat);
  }

  Future<ApiRes> login({required String uid, required String email, required String password}) =>
      api.post('/admin/login', {'device_ip': '0.0.0.0', 'username': email, 'password': password, 'admin_uid': uid});

  Future<ApiRes> verify2fa(String pendingToken, String code) =>
      api.post('/admin/login/verify-2fa', {'pendingToken': pendingToken, 'code': code});

  Future<void> logout() async {
    await api.post('/logout', {});
    await api.clearCookies();
    profile = null;
    menus = [];
    permissions = [];
    isSuperAdmin = false;
    notifyListeners();
  }

  void expire() {
    if (profile == null) return;
    profile = null;
    notifyListeners();
  }
}
