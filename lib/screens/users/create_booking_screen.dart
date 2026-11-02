import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../bookings/booking_detail_screen.dart';

class _CartItem {
  _CartItem({required this.service, required this.categoryId, required this.bookingType, this.unit, required this.price});
  final Map<String, dynamic> service;
  final int categoryId;
  final Map<String, dynamic> bookingType;
  final Map<String, dynamic>? unit;
  final double price;
  int qty = 1;
}

/// Book on behalf of a customer: services → address/date/slot → payment.
/// POST /admin/bookings/create. Slots come from the area availability engine
/// (/admin/scheduling/areas/:id/available-slots).
class CreateBookingScreen extends StatefulWidget {
  const CreateBookingScreen({super.key, required this.customerId});
  final int customerId;
  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  int _step = 0;
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _addresses = [];
  final _svcCache = <int, List<Map<String, dynamic>>>{};
  int? _cat;
  int? _addr;
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _slots = [];
  bool _slotsLoading = false;
  String? _slotsNote;
  int? _slot;
  int _payMode = 1;
  final _notes = TextEditingController();
  final _cart = <_CartItem>[];
  String _q = '';
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    api.post('/admin/users/service-categories', {'customerId': widget.customerId}).then((r) {
      if (!mounted) return;
      setState(() {
        _cats = ApiRes.asList(r['result'] ?? r.data);
        if (_cats.isNotEmpty) _cat = toInt(_cats.first['category_id']);
      });
      if (_cat != null) _loadServices(_cat!);
    });
    api.post('/admin/users/addresses', {'customerId': widget.customerId}).then((r) {
      if (!mounted) return;
      setState(() {
        _addresses = r.list;
        final sel = _addresses.firstWhere((a) => truthy(a['is_selected']), orElse: () => _addresses.isEmpty ? {} : _addresses.first);
        _addr = toInt(sel['address_id']);
      });
    });
  }

  Future<void> _loadServices(int cat) async {
    if (_svcCache.containsKey(cat)) return setState(() {});
    final r = await api.post('/admin/users/services/list', {'customerId': widget.customerId, 'category_id': cat});
    if (!mounted) return;
    setState(() => _svcCache[cat] = ApiRes.asList(r['result'] ?? r.data));
  }

  Map<String, dynamic> get _address => _addresses.firstWhere((a) => toInt(a['address_id']) == _addr, orElse: () => {});

  Future<void> _loadSlots() async {
    final area = _address['area_id'];
    setState(() {
      _slot = null;
      _slots = [];
      _slotsNote = null;
    });
    if (area == null) return setState(() => _slotsNote = 'This address is not within any service area.');
    setState(() => _slotsLoading = true);
    final r = await api.get('/admin/scheduling/areas/$area/available-slots', {'date': ymd(_date), 'serviceIds': _cart.map((c) => c.service['service_id']).toSet().join(',')});
    if (!mounted) return;
    setState(() {
      _slotsLoading = false;
      if (!r.ok) {
        _slotsNote = r.message;
      } else {
        _slots = ApiRes.asList(r.map['slots']);
        if (r.map['closed'] == true) _slotsNote = 'Closed: ${humanize(r.map['reason'])}';
        if (_slots.isEmpty) _slotsNote ??= 'No slots are configured for this date.';
      }
    });
  }

  Future<void> _add(Map<String, dynamic> s) async {
    final types = ApiRes.asList(s['booking_types']);
    final units = ApiRes.asList(s['units']);
    var bt = types.isNotEmpty ? types.first : {'id': 1, 'name': 'Standard'};
    Map<String, dynamic>? unit = units.isNotEmpty ? units.first : null;
    var qty = 1;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final price = unit != null && unit!['price_per_unit'] != null ? toNum(unit!['price_per_unit']) : toNum(s['price'] ?? s['base_price']);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(str(s['title']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const Gap(8),
            if (types.length > 1) ...[
              const Text('Booking type', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(spacing: 6, children: [for (final t in types) ChoiceChip(label: Text(str(t['name'])), selected: t['id'] == bt['id'], onSelected: (_) => set(() => bt = t))]),
            ],
            if (units.isNotEmpty) ...[
              const Text('Unit', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(spacing: 6, children: [
                for (final u in units) ChoiceChip(label: Text('${u['name']}${u['price_per_unit'] != null ? ' · ${inr(u['price_per_unit'])}' : ''}'), selected: u['unit_id'] == unit?['unit_id'], onSelected: (_) => set(() => unit = u)),
              ]),
            ],
            Row(children: [
              const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(onPressed: qty > 1 ? () => set(() => qty--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => set(() => qty++), icon: const Icon(Icons.add_circle_outline)),
            ]),
            Text('${inr(price)} × $qty = ${inr(price * qty)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const Gap(),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add to booking')),
          ]),
        );
      }),
    );
    if (ok != true) return;
    final price = unit != null && unit!['price_per_unit'] != null ? toNum(unit!['price_per_unit']) : toNum(s['price'] ?? s['base_price']);
    setState(() {
      final existing = _cart.where((c) => c.service['service_id'] == s['service_id'] && c.bookingType['id'] == bt['id'] && c.unit?['unit_id'] == unit?['unit_id']).firstOrNull;
      if (existing != null) {
        existing.qty += qty;
      } else {
        _cart.add(_CartItem(service: s, categoryId: _cat!, bookingType: bt, unit: unit, price: price)..qty = qty);
      }
    });
  }

  double get _subtotal => _cart.fold(0, (a, c) => a + c.price * c.qty);

  Future<void> _create() async {
    if (_cart.isEmpty) return setState(() => _error = 'Please add at least one service.');
    if (_addr == null) return setState(() => _error = 'Please select an address.');
    setState(() {
      _creating = true;
      _error = null;
    });
    final slot = _slots.firstWhere((s) => toInt(s['slot_id']) == _slot, orElse: () => {});
    final res = await api.post('/admin/bookings/create', {
      'customerId': widget.customerId,
      'addressId': _addr,
      'areaId': _address['area_id'],
      'slotId': _slot,
      'scheduledDate': ymd(_date),
      'scheduledTime': slot.isEmpty ? null : (slot['start_time'] ?? slot['label']),
      'paymentModeId': _payMode,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'services': [
        for (final c in _cart)
          {
            'serviceId': c.service['service_id'],
            'serviceCategoryId': c.categoryId,
            'serviceTitle': c.service['title'],
            'bookingTypeId': c.bookingType['id'],
            'bookingTypeName': c.bookingType['name'],
            'unitId': c.unit?['unit_id'],
            'unitName': c.unit?['name'],
            'quantity': c.qty,
            'price': c.price,
          },
      ],
    });
    if (!mounted) return;
    setState(() => _creating = false);
    if (!res.ok) return setState(() => _error = res.message.isEmpty ? 'Failed to create booking.' : res.message);
    final uid = res.map['booking_uid'];
    final id = res.map['booking_id'];
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: C.green, size: 40),
        title: Text('Booking ${uid ?? ''} created'),
        content: const Text('The booking has been placed and dispatch has been initiated.'),
        actions: [
          if (id != null)
            TextButton(onPressed: () {
              Navigator.pop(c);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: id)));
            }, child: const Text('Open booking')),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
    if (mounted && id == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(['Select services', 'Booking details', 'Confirm'][_step])),
      body: IndexedStack(index: _step, children: [_servicesStep(), _detailsStep(), _confirmStep()]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(children: [
            if (_step > 0) Expanded(child: OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Back'))),
            if (_step > 0) const Gap(8),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _creating
                    ? null
                    : () {
                        if (_step == 0) {
                          if (_cart.isEmpty) return toast('Add at least one service', error: true);
                          setState(() => _step = 1);
                          _loadSlots();
                        } else if (_step == 1) {
                          if (_addr == null) return toast('Select an address', error: true);
                          setState(() => _step = 2);
                        } else {
                          _create();
                        }
                      },
                child: Text(_step == 2 ? (_creating ? 'Creating…' : 'Create booking') : 'Continue${_step == 0 && _cart.isNotEmpty ? ' (${_cart.length})' : ''}'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _servicesStep() {
    if (_cats.isEmpty) return const EmptyView('No services available at this customer’s address.');
    final svcs = (_svcCache[_cat] ?? []).where((s) => _q.isEmpty || str(s['title'], '').toLowerCase().contains(_q)).toList();
    return Column(children: [
      FilterChips<int>(options: {for (final c in _cats) toInt(c['category_id'])!: str(c['category_name'])}, value: _cat ?? 0, onChanged: (v) {
        setState(() => _cat = v);
        _loadServices(v);
      }),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(decoration: const InputDecoration(hintText: 'Search services…', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
      ),
      Expanded(
        child: !_svcCache.containsKey(_cat)
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: svcs.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (c, i) {
                  final s = svcs[i];
                  final inCart = _cart.any((x) => x.service['service_id'] == s['service_id']);
                  return RowTile(
                    leading: NetImage(s['image'], size: 48),
                    title: str(s['title']),
                    subtitle: inr(s['price'] ?? s['base_price']),
                    lines: [if (s['duration_minutes'] != null) '${s['duration_minutes']} min'],
                    trailing: FilledButton.tonal(onPressed: () => _add(s), child: Text(inCart ? 'Add more' : 'Add')),
                  );
                },
              ),
      ),
      if (_cart.isNotEmpty)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(children: [
            for (var i = 0; i < _cart.length; i++)
              Row(children: [
                Expanded(child: Text('${_cart[i].service['title']}${_cart[i].unit != null ? ' · ${_cart[i].unit!['name']}' : ''}', overflow: TextOverflow.ellipsis)),
                IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _cart[i].qty > 1 ? _cart[i].qty-- : _cart.removeAt(i)), icon: const Icon(Icons.remove, size: 18)),
                Text('${_cart[i].qty}'),
                IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _cart[i].qty++), icon: const Icon(Icons.add, size: 18)),
                SizedBox(width: 70, child: Text(inr(_cart[i].price * _cart[i].qty), textAlign: TextAlign.right)),
              ]),
          ]),
        ),
    ]);
  }

  Widget _detailsStep() {
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(title: 'Address', children: [
        if (_addresses.isEmpty) const Text('No addresses found for this customer.', style: TextStyle(color: C.muted)),
        for (final a in _addresses)
          RadioListTile<int>(
            contentPadding: EdgeInsets.zero,
            value: toInt(a['address_id'])!,
            groupValue: _addr,
            onChanged: (v) {
              setState(() => _addr = v);
              _loadSlots();
            },
            title: Text(str(a['address'])),
            subtitle: Text('${[a['city'], a['pincode']].where((e) => e != null).join(' · ')}${a['area_id'] == null ? ' · outside service areas' : ''}'),
          ),
      ]),
      const Gap(),
      SectionCard(title: 'Service date', children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(fmtDate(_date)),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
            if (d != null) {
              setState(() => _date = d);
              _loadSlots();
            }
          },
        ),
      ]),
      const Gap(),
      SectionCard(title: 'Time slot', children: [
        if (_slotsLoading) const LinearProgressIndicator(),
        if (_slotsNote != null) Text(_slotsNote!, style: const TextStyle(color: C.amber)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _slots)
            ChoiceChip(
              label: Text('${str(s['label'], '${fmtTime(s['start_time'])}–${fmtTime(s['end_time'])}')}${s['available'] == false ? ' · ${humanize(s['reason'] ?? 'unavailable')}' : ''}'),
              selected: _slot == toInt(s['slot_id']),
              onSelected: s['available'] == false ? null : (_) => setState(() => _slot = toInt(s['slot_id'])),
            ),
        ]),
      ]),
      const Gap(),
      TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Technician notes', hintText: 'Any special instructions for the technician…')),
    ]);
  }

  Widget _confirmStep() {
    final tax = (_subtotal * 0.18).roundToDouble();
    final slot = _slots.firstWhere((s) => toInt(s['slot_id']) == _slot, orElse: () => {});
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(title: 'Selected services', children: [
        for (final c in _cart) KV('${c.service['title']} × ${c.qty}${c.unit != null ? ' (${c.unit!['name']})' : ''}\n${c.bookingType['name']}', inr(c.price * c.qty)),
        const Divider(),
        KV('Subtotal', inr(_subtotal)),
        KV('Tax (est. 18%)', inr(tax)),
        KV('Total (estimate)', inr(_subtotal + tax), bold: true),
        const Text('Final price is calculated by the server at checkout.', style: TextStyle(fontSize: 11.5, color: C.muted)),
      ]),
      const Gap(),
      SectionCard(title: 'When & where', children: [
        KV('Address', _address['address']),
        KV('Date', fmtDate(_date)),
        KV('Slot', slot.isEmpty ? 'Not selected' : str(slot['label'], '${fmtTime(slot['start_time'])}–${fmtTime(slot['end_time'])}')),
      ]),
      const Gap(),
      SectionCard(title: 'Payment', children: [
        for (final m in const [(1, 'Cash on Service', 'Customer pays cash to technician'), (2, 'Online / UPI', 'Customer pays via UPI or card'), (3, 'Already Paid', 'Mark as collected / admin override')])
          RadioListTile<int>(contentPadding: EdgeInsets.zero, value: m.$1, groupValue: _payMode, onChanged: (v) => setState(() => _payMode = v!), title: Text(m.$2), subtitle: Text(m.$3)),
      ]),
      if (_error != null) ...[const Gap(), Text(_error!, style: const TextStyle(color: C.red))],
    ]);
  }
}
