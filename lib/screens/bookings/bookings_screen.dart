import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'booking_detail_screen.dart';

const kBookingStatuses = {
  'P': 'Pending', 'C': 'Confirmed', 'B': 'Broadcasted', 'A': 'Tech Accepted', 'O': 'On The Way', 'V': 'Arrived',
  'S': 'Started', 'I': 'In Progress', 'D': 'Completed', 'X': 'Cancelled', 'F': 'Failed', 'R': 'Refunded', 'N': 'No Service',
};

const kBookingStages = {
  '': 'All', '1': 'Unassigned / Confirmed', '2': 'Assigned', '3': 'On the way', '4': 'Started', '5': 'Completed', '6': 'Cancelled',
};

const kBulkActions = {'auto_assign': 'Auto-assign', 'escalate': 'Escalate', 'emergency': 'Mark emergency', 'complete': 'Force complete'};

/// Bookings queue — GET /admin/bookings/workflow (same filters as the web list).
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, this.overdue = false});
  final bool overdue;
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  static const path = '/admin/booking-management/bookings';
  final _list = GlobalKey<PagedListState>();
  String _stage = '';
  String? _status;
  bool _emergency = false;
  bool _special = false;
  late bool _overdue = widget.overdue;
  DateTimeRange? _dates;
  final _selected = <int>{};

  bool get _canEdit => Session.I.canOn(path, 'EDIT');

  Future<ApiRes> _fetch(int page, int limit, String search) async {
    final res = await api.get('/admin/bookings/workflow', {
      'page': page,
      'limit': limit,
      'search': search,
      'stage': _stage,
      'statusId': _status,
      'isEmergency': _emergency ? 'true' : null,
      'specialSlot': _special ? 'true' : null,
      'overdue': _overdue ? 'true' : null,
      'dateFrom': _dates == null ? null : ymd(_dates!.start),
      'dateTo': _dates == null ? null : ymd(_dates!.end),
    });
    return res;
  }

  void _reload() {
    _selected.clear();
    _list.currentState?.reload();
  }

  Future<void> _moreFilters() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        void upd(VoidCallback f) {
          set(f);
          setState(() {});
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Gap(8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Status'),
                trailing: Text(_status == null ? 'All' : kBookingStatuses[_status]!, style: const TextStyle(color: C.primary)),
                onTap: () async {
                  final v = await pickOne<String>(context, 'Status', {'': 'All', ...kBookingStatuses}, selected: _status ?? '');
                  if (v != null) upd(() => _status = v.isEmpty ? null : v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scheduled date'),
                trailing: Text(_dates == null ? 'Any' : '${fmtDate(_dates!.start)} – ${fmtDate(_dates!.end)}', style: const TextStyle(color: C.primary)),
                onTap: () async {
                  final r = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime(2100), initialDateRange: _dates);
                  upd(() => _dates = r);
                },
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Marked emergency by admin'), value: _emergency, onChanged: (v) => upd(() => _emergency = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Emergency / Under 30 Min only'), value: _special, onChanged: (v) => upd(() => _special = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Overdue (past scheduled time)'), value: _overdue, onChanged: (v) => upd(() => _overdue = v)),
              const Gap(8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      upd(() {
                        _status = null;
                        _dates = null;
                        _emergency = _special = _overdue = false;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ),
                const Gap(10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Apply'))),
              ]),
            ]),
          ),
        );
      }),
    );
    _reload();
  }

  Future<void> _bulk() async {
    final action = await pickOne<String>(context, 'Bulk action on ${_selected.length} booking(s)', kBulkActions);
    if (action == null || !mounted) return;
    final ok = await confirm(
      context,
      '${kBulkActions[action]} ${_selected.length} booking(s)?',
      message: action == 'complete' ? "These bookings will be marked completed even if the work isn't finished. This can't be undone." : 'This applies to every selected booking.',
      danger: action == 'complete',
      ok: kBulkActions[action]!,
    );
    if (!ok || !mounted) return;
    final res = await busy(context, () => api.post('/admin/bookings/bulk', {'bookingIds': _selected.toList(), 'action': action}), success: 'Processed ${_selected.length} booking(s)');
    if (res.ok) _reload();
  }

  int get _activeFilters => [_status != null, _dates != null, _emergency, _special, _overdue].where((e) => e).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PagedList(
        key: _list,
        searchHint: 'Search booking ID, customer, mobile…',
        fetch: _fetch,
        empty: 'No bookings match these filters',
        header: Row(children: [
          Expanded(
            child: FilterChips<String>(
              options: kBookingStages,
              value: _stage,
              onChanged: (v) {
                setState(() => _stage = v);
                _reload();
              },
            ),
          ),
          IconButton(
            onPressed: _moreFilters,
            icon: Badge(isLabelVisible: _activeFilters > 0, label: Text('$_activeFilters'), child: const Icon(Icons.tune)),
          ),
        ]),
        itemBuilder: (c, b, i) {
          final id = toInt(b['booking_id'])!;
          final sel = _selected.contains(id);
          final overdue = truthy(b['sla_breached']);
          return RowTile(
            leading: _canEdit && _selected.isNotEmpty
                ? Checkbox(value: sel, onChanged: (_) => setState(() => sel ? _selected.remove(id) : _selected.add(id)))
                : null,
            title: '${str(b['booking_uid'])} · ${str(b['service_name'])}${(toInt(b['service_count']) ?? 1) > 1 ? ' +${toInt(b['service_count'])! - 1}' : ''}',
            badge: StatusChip(b['status_name'] ?? b['booking_status_id'], label: kBookingStatuses[b['booking_status_id']] ?? humanize(b['status_name'])),
            subtitle: '${str(b['customer_name'])} · ${str(b['customer_mobile'], '')}',
            lines: [
              '${fmtDate(b['scheduled_date'])} ${fmtTime(b['scheduled_time'])}',
              'Technician: ${str(b['technician_name'], 'Unassigned')}',
            ],
            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(inr(b['final_price']), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (b['booking_speed'] == 'EMERGENCY' || truthy(b['is_emergency'])) const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip('EMERGENCY', label: 'Emergency')),
              if (b['booking_speed'] == 'UNDER_30_MIN') const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip('PROCESS', label: 'Under 30 min')),
              if (overdue) const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip('BREACHED', label: 'Overdue')),
            ]),
            onTap: _selected.isNotEmpty
                ? () => setState(() => sel ? _selected.remove(id) : _selected.add(id))
                : () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: id)));
                    _list.currentState?.reload();
                  },
          );
        },
      ),
      floatingActionButton: !_canEdit
          ? null
          : _selected.isEmpty
              ? FloatingActionButton.extended(
                  heroTag: 'bulk',
                  onPressed: () {
                    final rows = _list.currentState?.rows ?? [];
                    if (rows.isEmpty) return;
                    setState(() => _selected.add(toInt(rows.first['booking_id'])!));
                    toast('Tap bookings to select them');
                  },
                  icon: const Icon(Icons.checklist),
                  label: const Text('Select'),
                )
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  FloatingActionButton.small(heroTag: 'x', onPressed: () => setState(_selected.clear), child: const Icon(Icons.close)),
                  const Gap(8),
                  FloatingActionButton.extended(heroTag: 'go', onPressed: _bulk, icon: const Icon(Icons.bolt), label: Text('Action (${_selected.length})')),
                ]),
    );
  }
}
