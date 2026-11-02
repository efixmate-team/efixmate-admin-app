import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/form.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _promoPath = '/admin/masters/announcement-management/promotions';
const _notifPath = '/admin/masters/announcement-management/notification';

const _promoTypes = {'BANNER': 'Banner', 'CAROUSEL': 'Carousel Slide', 'OFFER_BANNER': 'Offer Banner'};
const _scopeTypes = {'GLOBAL': 'Global', 'COUNTRY': 'Country', 'STATE': 'State', 'CITY': 'City', 'AREA': 'Area'};
const _audiences = {'USER': 'User app', 'TECHNICIAN': 'Technician app', 'BOTH': 'Both'};
const _ctaActions = {'SEARCH': 'Open service search', 'CATEGORY': 'Open a category', 'URL': 'Go to a link'};

Map<String, String> _screens(String? audience) => switch ((audience ?? 'USER').toUpperCase()) {
      'TECHNICIAN' => const {'HOME': 'Home', 'JOBS': 'Jobs', 'EARNINGS': 'Earnings', 'SCHEDULE': 'Schedule', 'PROFILE': 'Profile'},
      'BOTH' => const {'HOME': 'Home', 'PROFILE': 'Profile'},
      _ => const {'HOME': 'Home', 'SERVICES': 'Services', 'BOOKINGS': 'Bookings', 'OFFERS': 'Offers', 'WALLET': 'Wallet', 'PROFILE': 'Profile'},
    };

/// Promotions — banners, carousel slides and offer banners shown in the apps.
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});
  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = '';
  String _type = '';
  Map<String, dynamic> _stats = {};
  bool get _canEdit => Session.I.canOn(_promoPath, 'EDIT') || Session.I.canOn(_promoPath, 'CREATE');

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final r = await api.get('/admin/promotions/analytics');
    if (mounted && r.ok) setState(() => _stats = r.map);
  }

  void _reload() {
    _list.currentState?.reload();
    _loadStats();
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final initial = row == null
        ? <String, dynamic>{'promo_type': 'BANNER', 'scope_type': 'GLOBAL', 'target_audience': 'USER', 'target_screen': 'HOME', 'priority': 0, 'is_active': true, 'background_color': '#0D47A1', 'cta_action_type': 'SEARCH'}
        : {
            ...row,
            'mobile_banner_file': row['mobile_image_url'],
            'scope_ids': ((row['scope_ids'] as List?) ?? const []).map((e) => '$e').toList(),
            'cta_action_type': row['cta_action_type'] ?? 'SEARCH',
            'cta_value': row['cta_value']?.toString(),
          };
    bool hero(Map v) => v['promo_type'] == 'BANNER' || v['promo_type'] == 'CAROUSEL';
    final ok = await openForm(
      context,
      title: row == null ? 'New promotion' : 'Edit promotion',
      initial: initial,
      fields: [
        Field('title', 'Promotion Title', required: true),
        Field('subtitle', 'Subtitle'),
        Field('description', 'Description', type: F.multiline),
        Field('promo_type', 'Promotion Type', type: F.select, options: _promoTypes, required: true),
        Field('mobile_banner_file', 'Banner image', type: F.image, help: 'Up to 10 MB. Leave unchanged to keep the current image.'),
        Field('mobile_image_url', 'Image URL (optional)', hint: 'https://cdn.example.com/banner.jpg'),
        Field('target_audience', 'Audience', type: F.select, options: _audiences, required: true),
        Field('target_screen', 'Target Screen', type: F.select, dependsOn: const ['target_audience'], loader: (v) async => _screens(v['target_audience'])),
        Field('scope_type', 'Target Scope', type: F.select, options: _scopeTypes, required: true),
        Field('scope_ids', 'Where', type: F.multiSelect, dependsOn: const ['scope_type'], visibleIf: (v) => v['scope_type'] != null && v['scope_type'] != 'GLOBAL', loader: (v) async {
          final t = v['scope_type'];
          final (path, id, name) = switch (t) {
            'COUNTRY' => ('/master/countries', 'country_id', 'country_name'),
            'STATE' => ('/master/states', 'state_id', 'state_name'),
            'CITY' => ('/master/cities', 'city_id', 'city_name'),
            'AREA' => ('/master/areas', 'area_id', 'area_name'),
            _ => ('', '', ''),
          };
          if (path.isEmpty) return {};
          final r = await api.get(path, {'limit': 'all'});
          return {for (final x in r.list) '${x[id]}': str(x[name])};
        }),
        Field('priority', 'Priority', type: F.number),
        Field('start_at', 'Start Date & Time', type: F.dateTime),
        Field('end_at', 'End Date & Time', type: F.dateTime),
        Field('background_color', 'Background colour', type: F.color, hint: '#0D47A1', visibleIf: hero),
        Field('cta_text', 'Button text', hint: 'Explore services', visibleIf: hero),
        Field('cta_action_type', 'Button opens', type: F.select, options: _ctaActions, visibleIf: hero),
        Field('cta_value', 'Category', type: F.select, visibleIf: (v) => hero(v) && v['cta_action_type'] == 'CATEGORY',
            loader: (v) async {
              final r = await api.get('/master/service-categories', {'limit': 200});
              return {for (final c in r.list) '${c['category_id']}': str(c['category_name'])};
            }),
        Field('cta_link', 'Link', hint: '/offers or https://…', visibleIf: (v) => hero(v) && v['cta_action_type'] == 'URL', initial: row?['cta_action_type'] == 'URL' ? row!['cta_value'] : null),
        Field('is_active', 'Active', type: F.toggle),
      ],
      onSubmit: (v) async {
        final isHero = hero(v);
        if (v['start_at'] != null && v['end_at'] != null && !parseDate(v['start_at'])!.isBefore(parseDate(v['end_at'])!)) {
          return ApiRes({'status': false, 'message': 'End date must be after start date'});
        }
        if (isHero && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(str(v['background_color'], ''))) {
          return ApiRes({'status': false, 'message': 'Background colour must be a hex value like #0D47A1'});
        }
        final cta = v['cta_action_type'] ?? 'SEARCH';
        final fields = <String, dynamic>{
          'title': v['title'],
          'subtitle': v['subtitle'] ?? '',
          'description': v['description'] ?? '',
          'promo_type': v['promo_type'],
          'scope_type': v['scope_type'],
          'scope_ids': ((v['scope_ids'] as List?) ?? const []).join(','),
          'target_audience': v['target_audience'],
          'target_screen': v['target_screen'] ?? 'HOME',
          'priority': v['priority'] ?? 0,
          'is_active': v['is_active'] == true,
          'is_disabled': v['is_active'] != true,
          if (str(v['mobile_image_url'], '').isNotEmpty) 'mobile_image_url': v['mobile_image_url'],
          if (v['start_at'] != null) 'start_at': parseDate(v['start_at'])!.toUtc().toIso8601String(),
          if (v['end_at'] != null) 'end_at': parseDate(v['end_at'])!.toUtc().toIso8601String(),
          if (isHero) ...{
            'background_color': v['background_color'],
            'cta_text': v['cta_text'] ?? '',
            'cta_action_type': cta,
            'cta_value': cta == 'SEARCH' ? '' : (cta == 'URL' ? (v['cta_link'] ?? '') : (v['cta_value'] ?? '')),
          },
        };
        if (isHero && cta == 'CATEGORY' && str(fields['cta_value'], '').isEmpty) return ApiRes({'status': false, 'message': 'Choose the category the button opens'});
        if (isHero && cta == 'URL' && str(fields['cta_value'], '').isEmpty) return ApiRes({'status': false, 'message': 'Enter the link the button opens'});
        final file = v['mobile_banner_file'];
        return api.upload(
          row == null ? '/admin/promotions' : '/admin/promotions/${row['promo_id']}',
          method: row == null ? 'POST' : 'PUT',
          fields: fields,
          files: file is XFile ? {'mobile_banner_file': file.path} : const {},
        );
      },
    );
    if (ok) _reload();
  }

  Future<void> _act(String what, Map r) async {
    switch (what) {
      case 'toggle':
        final next = !truthy(r['is_active']);
        if (!next && !await confirm(context, 'Turn off this promotion?', message: 'It stops showing to customers.', ok: 'Turn off')) return;
        if (!mounted) return;
        final res = await busy(context, () => api.put('/admin/promotions/${r['promo_id']}', {'is_active': next, 'is_disabled': !next}));
        if (res.ok) _reload();
      case 'duplicate':
        final res = await busy(context, () => api.post('/admin/promotions/${r['promo_id']}/duplicate'), success: 'Duplicated');
        if (res.ok) _reload();
      case 'priority':
        final v = await prompt(context, 'Priority', initial: '${r['priority'] ?? 0}', keyboard: TextInputType.number, required: true);
        if (v == null || !mounted) return;
        final res = await busy(context, () => api.post('/admin/promotions/reorder', {'items': [{'id': r['promo_id'], 'priority': int.tryParse(v) ?? 0}]}), success: 'Priority updated');
        if (res.ok) _reload();
      case 'delete':
        if (!await confirm(context, 'Delete this promotion?', message: 'This cannot be undone.', danger: true, ok: 'Delete')) return;
        if (!mounted) return;
        final res = await busy(context, () => api.delete('/admin/promotions/${r['promo_id']}'), success: 'Deleted');
        if (res.ok) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search promotions…',
        fetch: (p, l, s) => api.post('/admin/promotions/paginated', {'page': p, 'limit': l, 'search': s, 'status': _status, 'promoType': _type}),
        header: Column(children: [
          if (_stats.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
                for (final e in const {'active': 'Active', 'scheduled': 'Scheduled', 'expired': 'Expired', 'global_count': 'Global', 'regional_count': 'Regional'}.entries)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${_stats[e.key] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(e.value, style: const TextStyle(fontSize: 11, color: C.muted)),
                    ]),
                  ),
              ]),
            ),
          FilterChips<String>(options: const {'': 'All', 'ACTIVE': 'Active', 'SCHEDULED': 'Scheduled', 'EXPIRED': 'Expired', 'DISABLED': 'Disabled'}, value: _status, onChanged: (v) {
            setState(() => _status = v);
            _list.currentState?.reload();
          }),
          FilterChips<String>(options: {'': 'All types', ..._promoTypes}, value: _type, onChanged: (v) {
            setState(() => _type = v);
            _list.currentState?.reload();
          }),
        ]),
        itemBuilder: (c, r, i) => RowTile(
          leading: NetImage(r['mobile_image_url'], size: 56),
          title: str(r['title']),
          badge: StatusChip(r['status'] ?? (truthy(r['is_active']) ? 'ACTIVE' : 'DISABLED')),
          subtitle: '${_promoTypes[r['promo_type']] ?? r['promo_type']} · ${_audiences[r['target_audience']] ?? r['target_audience']} · ${_scopeTypes[r['scope_type']] ?? r['scope_type']}',
          lines: ['Priority ${r['priority'] ?? 0} · ${fmtDate(r['start_at'], fallback: 'now')} → ${fmtDate(r['end_at'], fallback: 'no end')}'],
          trailing: !_canEdit
              ? null
              : PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? _edit(r) : _act(v, r),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'toggle', child: Text(truthy(r['is_active']) ? 'Turn off' : 'Turn on')),
                    const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    const PopupMenuItem(value: 'priority', child: Text('Change priority')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
          onTap: _canEdit ? () => _edit(r) : null,
        ),
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(heroTag: 'promo', onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New promotion')) : null,
    );
  }
}

/// Push notification broadcasts — send, history with delivery counts, resend.
class NotificationsBroadcastScreen extends StatefulWidget {
  const NotificationsBroadcastScreen({super.key});
  @override
  State<NotificationsBroadcastScreen> createState() => _NotificationsBroadcastScreenState();
}

class _NotificationsBroadcastScreenState extends State<NotificationsBroadcastScreen> {
  final _list = GlobalKey<PagedListState>();
  bool get _canSend => Session.I.canOn(_notifPath, 'CREATE') || Session.I.canOn(_notifPath, 'EDIT') || Session.I.can('NOTIFICATION_SEND');

  Future<void> _send() async {
    final ok = await openForm(
      context,
      title: 'Send notification',
      submitLabel: 'Send now',
      initial: {'target_audience': 'USER'},
      fields: [
        Field('title', 'Title', required: true),
        Field('body', 'Message', type: F.multiline, hint: 'Write the notification message…'),
        Field('target_audience', 'Audience', type: F.select, options: _audiences, required: true, help: 'Sends immediately to every active account in the selected audience. This cannot be undone or scheduled for later.'),
      ],
      onSubmit: (v) => api.post('/admin/notifications/send', v),
    );
    if (ok) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search notifications…',
        fetch: (p, l, s) => api.post('/admin/notifications/paginated', {'page': p, 'limit': l, 'search': s}),
        itemBuilder: (c, r, i) => RowTile(
          title: str(r['title']),
          badge: StatusChip(r['status']),
          subtitle: str(r['body'], ''),
          lines: [
            '${_audiences[r['target_audience']] ?? r['target_audience']} · ${r['recipient_count'] ?? 0} recipients · ${r['success_count'] ?? 0} delivered · ${r['failure_count'] ?? 0} failed',
            '${str(r['created_by'], '')} · ${fmtDateTime(r['created_at'])}',
          ],
          trailing: _canSend
              ? IconButton(
                  tooltip: 'Resend',
                  icon: const Icon(Icons.replay),
                  onPressed: () async {
                    if (!await confirm(context, 'Resend this notification?', ok: 'Resend')) return;
                    if (!context.mounted) return;
                    final res = await busy(context, () => api.post('/admin/notifications/${r['broadcast_id']}/resend'), success: 'Notification resent');
                    if (res.ok) _list.currentState?.reload();
                  },
                )
              : null,
        ),
      ),
      floatingActionButton: _canSend ? FloatingActionButton.extended(heroTag: 'notif', onPressed: _send, icon: const Icon(Icons.campaign), label: const Text('Send')) : null,
    );
  }
}
