import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session.dart';
import '../routes.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Bilingual admin help (English / Hindi) — same content as the web
/// /admin/guides page, exported to assets/admin_guides.json.
class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key});
  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  List<dynamic>? _cats;
  late String _lang = Session.I.profile?['preferred_language'] == 'hi' ? 'hi' : 'en';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/admin_guides.json').then((s) {
      if (mounted) setState(() => _cats = jsonDecode(s) as List);
    });
  }

  String _t(dynamic m) => m is Map ? (m[_lang] ?? m['en'] ?? '').toString() : '$m';

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    if (cats == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      FilterChips<String>(options: const {'en': 'English', 'hi': 'हिन्दी'}, value: _lang, onChanged: (v) => setState(() => _lang = v)),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
          for (final c in cats) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(_t(c['label']).toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted))),
            Card(
              child: Column(children: [
                for (final a in c['articles'] as List)
                  ExpansionTile(
                    title: Text(_t(a['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(_t(a['summary']), style: const TextStyle(fontSize: 12, color: C.body)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in ((a['body'] as Map)[_lang] ?? (a['body'] as Map)['en']) as List)
                        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('$p', style: const TextStyle(height: 1.4))),
                      if (a['path'] != null && routeFor(a['path']) != null)
                        TextButton.icon(onPressed: () => openRoute(context, a['path']), icon: const Icon(Icons.open_in_new, size: 16), label: Text(_t(a['pathLabel']).isEmpty ? 'Open ${routeFor(a['path'])!.title}' : _t(a['pathLabel']))),
                    ],
                  ),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }
}
