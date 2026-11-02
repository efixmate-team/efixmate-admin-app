import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../routes.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'dashboard/dashboard_screen.dart';
import 'scope_screen.dart';
import 'search_screen.dart';

/// Bottom tabs for the screens used all day (Home, Bookings, Support), plus a
/// Menu tab listing every module the admin's role can open.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  /// Bumped after the region scope changes so every tab reloads its data.
  int _gen = 0;

  static const _bookings = '/admin/booking-management/bookings';
  static const _chat = '/admin/chat';

  @override
  Widget build(BuildContext context) {
    context.watch<Session>();
    final tabs = <(String, IconData, Widget)>[
      ('Home', Icons.space_dashboard_outlined, const DashboardScreen()),
      if (Session.I.canOpen(_bookings) && routeFor(_bookings) != null) ('Bookings', Icons.event_note_outlined, routeFor(_bookings)!.builder(context)),
      if (Session.I.canOpen(_chat) && routeFor(_chat) != null) ('Support', Icons.support_agent, routeFor(_chat)!.builder(context)),
      ('Menu', Icons.apps, const MenuScreen()),
    ];
    if (_tab >= tabs.length) _tab = 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'eFixMate Admin' : tabs[_tab].$1),
        actions: [
          IconButton(
            tooltip: 'Region & financial year',
            icon: const Icon(Icons.public),
            onPressed: () async {
              final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ScopeScreen()));
              if (changed == true) setState(() => _gen++);
            },
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
        ],
      ),
      body: KeyedSubtree(key: ValueKey(_gen), child: IndexedStack(index: _tab, children: [for (final t in tabs) t.$3])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)],
      ),
    );
  }
}

/// Every module grouped like the web sidebar, filtered by the admin's menus.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final groups = <String, List<AppRoute>>{};
    for (final r in visibleRoutes()) {
      if (r.path == '/admin/dashboard') continue;
      groups.putIfAbsent(r.group ?? 'Other', () => []).add(r);
    }
    return RefreshIndicator(
      onRefresh: s.refreshMenus,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        Card(
          child: ListTile(
            leading: Avatar(url: s.profile?['profile_image'], name: s.displayName),
            title: Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${s.profile?['email'] ?? ''}${s.isSuperAdmin ? ' · Super Admin' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openRoute(context, '/admin/settings/profile'),
          ),
        ),
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(g.key.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: .6)),
          ),
          Card(
            child: Column(children: [
              for (var i = 0; i < g.value.length; i++) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  leading: Icon(g.value[i].icon, color: C.primary),
                  title: Text(g.value[i].title),
                  trailing: const Icon(Icons.chevron_right, color: C.muted),
                  onTap: () => openRoute(context, g.value[i].path),
                ),
              ],
            ]),
          ),
        ],
        const Gap(20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: C.red),
          onPressed: () async {
            if (await confirm(context, 'Log out?', ok: 'Log out', danger: true)) await Session.I.logout();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ]),
    );
  }
}
