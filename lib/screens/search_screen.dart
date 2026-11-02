import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../routes.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'bookings/booking_detail_screen.dart';
import 'technicians/technician_detail_screen.dart';
import 'users/customer_detail_screen.dart';

/// Search across menus, customers, bookings, services, technicians and admins
/// (same sources as the web command palette).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  Map<String, List<Map<String, dynamic>>> _res = {};

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) return setState(() => _res = {});
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      final body = {'search': q.trim(), 'limit': 5, 'page': 1};
      final r = await Future.wait([
        Session.I.canOpen('/admin/user-management/users') ? api.post('/admin/users/paginated', body) : Future.value(ApiRes({'status': false})),
        Session.I.canOpen('/admin/booking-management/bookings') ? api.get('/admin/bookings/workflow', body) : Future.value(ApiRes({'status': false})),
        api.get('/master/services', {'search': q.trim(), 'limit': 5}),
        Session.I.canOpen('/admin/technician-management/technicians') ? api.post('/admin/technicians/paginated', body) : Future.value(ApiRes({'status': false})),
        Session.I.canOpen('/admin/admin-management/admins') ? api.post('/admin/admin-paginated', body) : Future.value(ApiRes({'status': false})),
      ]);
      if (!mounted || _q.text.trim() != q.trim()) return;
      setState(() {
        _loading = false;
        _res = {
          'Customers': r[0].ok ? r[0].list : [],
          'Bookings': r[1].ok ? r[1].list : [],
          'Services': r[2].ok ? r[2].list : [],
          'Technicians': r[3].ok ? r[3].list : [],
          'Admins': r[4].ok ? r[4].list : [],
        };
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final menus = q.isEmpty ? <AppRoute>[] : visibleRoutes().where((r) => r.title.toLowerCase().contains(q) || (r.group ?? '').toLowerCase().contains(q)).take(6).toList();
    final any = menus.isNotEmpty || _res.values.any((l) => l.isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search users, bookings, services…', border: InputBorder.none, filled: false),
          onChanged: (v) {
            setState(() {});
            _search(v);
          },
        ),
      ),
      body: ListView(children: [
        if (_loading) const LinearProgressIndicator(),
        if (q.isNotEmpty && !_loading && !any) const EmptyView('No results. Try a different keyword', icon: Icons.search_off),
        if (menus.isNotEmpty) _header('Navigation'),
        for (final m in menus) ListTile(leading: Icon(m.icon, color: C.primary), title: Text(m.title), subtitle: Text(m.group ?? ''), onTap: () => openRoute(context, m.path)),
        for (final e in _res.entries)
          if (e.value.isNotEmpty) ...[
            _header(e.key),
            for (final r in e.value) _tile(e.key, r),
          ],
      ]),
    );
  }

  Widget _header(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w700)));

  Widget _tile(String kind, Map<String, dynamic> r) {
    switch (kind) {
      case 'Customers':
        return ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(fullName(r)),
          subtitle: Text('${str(r['mobile_number'], '')} ${str(r['email'], '')}'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: r['customer_id']))),
        );
      case 'Bookings':
        return ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: Text('${str(r['booking_uid'])} · ${str(r['service_name'])}'),
          subtitle: Text(str(r['customer_name'], '')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: r['booking_id']))),
        );
      case 'Services':
        return ListTile(leading: const Icon(Icons.home_repair_service_outlined), title: Text(str(r['service'])), subtitle: Text(str(r['category_name'], '')), onTap: () => openRoute(context, '/admin/masters/services-management/service-categories'));
      case 'Technicians':
        return ListTile(
          leading: const Icon(Icons.engineering_outlined),
          title: Text(fullName(r)),
          subtitle: Text('${str(r['technician_unique_id'], '')} ${str(r['mobile_number'], '')}'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TechnicianDetailScreen(id: r['technician_id']))),
        );
      default:
        return ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: Text(fullName(r)), subtitle: Text(str(r['email'], '')), onTap: () => openRoute(context, '/admin/admin-management/admins'));
    }
  }
}
