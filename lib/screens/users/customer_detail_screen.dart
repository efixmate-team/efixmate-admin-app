import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../bookings/booking_detail_screen.dart';
import 'create_booking_screen.dart';
import 'customers_screen.dart';

/// Customer profile with every tab of the web page: profile, addresses (map
/// pin + auto-fill), bookings, offers, serviceable catalog, activity log.
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final dynamic id;

  int get cid => toInt(id) ?? 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Profile'), Tab(text: 'Addresses'), Tab(text: 'Bookings'), Tab(text: 'Offers'), Tab(text: 'Services'), Tab(text: 'Activity'),
          ]),
        ),
        body: TabBarView(children: [
          _Profile(cid),
          _Addresses(cid),
          _Bookings(cid),
          _Offers(cid),
          _Services(cid),
          _Activity(cid),
        ]),
        floatingActionButton: Session.I.canOn(kUsersPath, 'CREATE') || Session.I.canOn(kUsersPath, 'EDIT')
            ? FloatingActionButton.extended(
                heroTag: 'newbooking',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateBookingScreen(customerId: cid))),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Create booking'),
              )
            : null,
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile(this.id);
  final int id;
  @override
  Widget build(BuildContext context) {
    return ApiLoader(
      load: () => api.post('/admin/users/get', {'customerId': id}),
      builder: (c, res, reload) {
        final d = res.data is List ? ApiRes.asList(res.data).firstOrNull ?? {} : res.map;
        return ListView(padding: const EdgeInsets.all(12), children: [
          SectionCard(children: [
            Row(children: [
              Avatar(url: d['profile_pitcher'] ?? d['profile'], name: fullName(d), size: 56),
              const Gap(),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fullName(d), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(str(d['customer_uid'], ''), style: const TextStyle(color: C.muted)),
                ]),
              ),
              StatusChip(truthy(d['is_active']) ? 'ACTIVE' : 'INACTIVE', label: truthy(d['is_active']) ? 'Active' : 'Inactive'),
            ]),
            const Gap(),
            KV('Mobile', d['mobile_number']),
            KV('Email', d['email']),
            KV('Mobile verified', truthy(d['mobile_verified']) ? 'Yes' : 'No'),
            KV('Email verified', truthy(d['email_verified']) ? 'Yes' : 'No'),
            KV('Customer ID', d['customer_id']),
            KV('Registered on', fmtDateTime(d['created_at'])),
            const Gap(8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(d['mobile_number']), icon: const Icon(Icons.call, size: 18), label: const Text('Call'))),
              const Gap(8),
              Expanded(child: OutlinedButton.icon(onPressed: () => whatsapp(d['mobile_number']), icon: const Icon(Icons.chat, size: 18), label: const Text('WhatsApp'))),
            ]),
          ]),
        ]);
      },
    );
  }
}

// ─── Addresses ───────────────────────────────────────────────────────────────

class _Addresses extends StatefulWidget {
  const _Addresses(this.id);
  final int id;
  @override
  State<_Addresses> createState() => _AddressesState();
}

class _AddressesState extends State<_Addresses> with AutomaticKeepAliveClientMixin {
  final _key = GlobalKey<ApiLoaderState>();
  @override
  bool get wantKeepAlive => true;
  bool get _canEdit => Session.I.canOn(kUsersPath, 'EDIT');

  Future<void> _edit([Map<String, dynamic>? a]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddressFormScreen(customerId: widget.id, address: a)));
    if (ok == true) _key.currentState?.reload();
  }

  Future<void> _activate(Map a) async {
    final r = await busy(context, () => api.post('/admin/users/address/activate', {'customerId': widget.id, 'addressId': a['address_id']}), success: 'Address set as active');
    if (r.ok) _key.currentState?.reload();
  }

  Future<void> _delete(Map a) async {
    if (!await confirm(context, 'Delete address?', danger: true, ok: 'Delete')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.post('/admin/users/address/delete', {'customerId': widget.id, 'addressId': a['address_id']}), success: 'Address deleted');
    if (r.ok) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: ApiLoader(
        key: _key,
        load: () => api.post('/admin/users/addresses', {'customerId': widget.id}),
        builder: (c, res, reload) {
          final rows = res.list;
          if (rows.isEmpty) return ListView(children: const [EmptyView('No addresses found.')]);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            for (final a in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowTile(
                  leading: Icon(Icons.location_on, color: truthy(a['is_selected']) ? C.green : C.muted),
                  title: str(a['address']),
                  badge: truthy(a['is_selected']) ? const StatusChip('ACTIVE', label: 'Selected') : null,
                  subtitle: [a['city'], a['state'], a['pincode']].where((e) => e != null && '$e'.isNotEmpty).join(', '),
                  lines: [if (a['area_name'] != null) 'Service area: ${a['area_name']}' else if (a['area_id'] == null) 'Not within any service area'],
                  trailing: !_canEdit
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _edit(a);
                            if (v == 'active') _activate(a);
                            if (v == 'delete') _delete(a);
                            if (v == 'map') openUrl('https://www.google.com/maps/search/?api=1&query=${a['latitude']},${a['longitude']}');
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            if (!truthy(a['is_selected'])) const PopupMenuItem(value: 'active', child: Text('Set as selected')),
                            if (a['latitude'] != null) const PopupMenuItem(value: 'map', child: Text('Open in Maps')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.small(heroTag: 'addr', onPressed: () => _edit(), child: const Icon(Icons.add_location_alt)) : null,
    );
  }
}

/// Add / edit an address. Pin the location on the map; street, city, state
/// and pincode auto-fill from the pin (OpenStreetMap reverse geocoding, as on
/// the web panel).
class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, required this.customerId, this.address});
  final int customerId;
  final Map<String, dynamic>? address;
  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  late final _street = TextEditingController(text: str(widget.address?['address'], ''));
  late final _city = TextEditingController(text: str(widget.address?['city'], ''));
  late final _state = TextEditingController(text: str(widget.address?['state'], ''));
  late final _country = TextEditingController(text: str(widget.address?['country'], 'India'));
  late final _pin = TextEditingController(text: str(widget.address?['pincode'], ''));
  LatLng? _pos;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    if (a?['latitude'] != null && a?['longitude'] != null) _pos = LatLng(toNum(a!['latitude']), toNum(a['longitude']));
  }

  Future<void> _reverse(LatLng p) async {
    try {
      final r = await Dio().get('https://nominatim.openstreetmap.org/reverse',
          queryParameters: {'format': 'jsonv2', 'lat': p.latitude, 'lon': p.longitude, 'addressdetails': 1},
          options: Options(headers: {'User-Agent': 'eFixMate-Admin/1.0'}));
      final a = Map<String, dynamic>.from(r.data['address'] ?? {});
      setState(() {
        final road = [a['house_number'], a['road'], a['neighbourhood'] ?? a['suburb']].where((e) => e != null).join(', ');
        if (road.isNotEmpty) _street.text = road;
        _city.text = str(a['city'] ?? a['town'] ?? a['village'] ?? a['county'], _city.text);
        _state.text = str(a['state'], _state.text);
        _country.text = str(a['country'], _country.text);
        _pin.text = str(a['postcode'], _pin.text);
      });
    } catch (_) {/* manual entry still works */}
  }

  Future<void> _pickOnMap() async {
    final p = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => MapPinScreen(initial: _pos)));
    if (p == null) return;
    setState(() => _pos = p);
    _reverse(p);
  }

  Future<void> _save() async {
    if (_street.text.trim().isEmpty || _pos == null) return toast('Pin the location and enter the street / locality', error: true);
    setState(() => _saving = true);
    final body = {
      'customerId': widget.customerId,
      if (widget.address != null) 'addressId': widget.address!['address_id'],
      'address': _street.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'country': _country.text.trim(),
      'pincode': _pin.text.trim(),
      'latitude': _pos!.latitude.toString(),
      'longitude': _pos!.longitude.toString(),
    };
    final r = await api.post(widget.address == null ? '/admin/users/address' : '/admin/users/address/update', body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (toastRes(r, success: 'Address saved')) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.address == null ? 'Add address' : 'Edit address')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.pin_drop, color: C.primary),
            title: Text(_pos == null ? 'Pin a location on the map' : '${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}'),
            subtitle: const Text('Fields auto-fill from the pin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickOnMap,
          ),
        ),
        const Gap(),
        TextField(controller: _street, decoration: const InputDecoration(labelText: 'Street / Locality *', hintText: 'e.g. 123, MG Road, Near Park')),
        const Gap(),
        Row(children: [
          Expanded(child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
          const Gap(),
          Expanded(child: TextField(controller: _pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pincode'))),
        ]),
        const Gap(),
        Row(children: [
          Expanded(child: TextField(controller: _state, decoration: const InputDecoration(labelText: 'State'))),
          const Gap(),
          Expanded(child: TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country'))),
        ]),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save address')))),
    );
  }
}

class MapPinScreen extends StatefulWidget {
  const MapPinScreen({super.key, this.initial});
  final LatLng? initial;
  @override
  State<MapPinScreen> createState() => _MapPinScreenState();
}

class _MapPinScreenState extends State<MapPinScreen> {
  late LatLng _center = widget.initial ?? const LatLng(21.2514, 81.6296);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin location')),
      body: Stack(alignment: Alignment.center, children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _center, zoom: 16),
          onCameraMove: (p) => _center = p.target,
          myLocationButtonEnabled: false,
        ),
        const Padding(padding: EdgeInsets.only(bottom: 36), child: Icon(Icons.location_pin, size: 44, color: C.red)),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: () => Navigator.pop(context, _center), child: const Text('Use this location')))),
    );
  }
}

// ─── Bookings / offers / services / activity ─────────────────────────────────

class _Bookings extends StatelessWidget {
  const _Bookings(this.id);
  final int id;
  @override
  Widget build(BuildContext context) {
    return ApiLoader(
      load: () => api.post('/admin/users/bookings', {'customerId': id}),
      builder: (c, res, reload) {
        final rows = res.list;
        if (rows.isEmpty) return ListView(children: const [EmptyView('No bookings yet')]);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Gap(8),
          itemBuilder: (c, i) {
            final b = rows[i];
            return RowTile(
              title: '${str(b['booking_uid'])} · ${str(b['service'])}',
              badge: StatusChip(b['status']),
              subtitle: 'Scheduled ${fmtDate(b['scheduled_date'])} · booked ${fmtDate(b['created_at'])}',
              trailing: Text(inr(b['total_amount']), style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: b['booking_id']))),
            );
          },
        );
      },
    );
  }
}

class _Offers extends StatelessWidget {
  const _Offers(this.id);
  final int id;
  @override
  Widget build(BuildContext context) {
    return ApiLoader(
      load: () => api.post('/admin/users/promotions/home', {'customerId': id}),
      builder: (c, res, reload) {
        final rows = res['offers'] is List ? ApiRes.asList(res['offers']) : (res['offer'] is Map ? [ApiRes.asMap(res['offer'])] : res.list);
        if (rows.isEmpty) return ListView(children: const [EmptyView('No active offers available.')]);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Gap(8),
          itemBuilder: (c, i) {
            final o = rows[i];
            return RowTile(
              leading: const Icon(Icons.local_offer, color: C.violet),
              title: str(o['title']),
              subtitle: str(o['subtitle'], ''),
              lines: [
                if (o['coupon_code'] != null) 'Code ${o['coupon_code']} · ${o['discount_type'] == 'PERCENTAGE' ? '${o['discount_value']}%' : inr(o['discount_value'])} off${o['max_discount'] != null ? ' (max ${inr(o['max_discount'])})' : ''}',
                if (o['minimum_order_amount'] != null) 'Min order ${inr(o['minimum_order_amount'])}',
                if (o['expiry_date'] != null) 'Expires ${fmtDate(o['expiry_date'])}',
              ],
            );
          },
        );
      },
    );
  }
}

class _Services extends StatefulWidget {
  const _Services(this.id);
  final int id;
  @override
  State<_Services> createState() => _ServicesState();
}

class _ServicesState extends State<_Services> {
  int? _cat;
  @override
  Widget build(BuildContext context) {
    return ApiLoader(
      load: () => api.post('/admin/users/service-categories', {'customerId': widget.id}),
      builder: (c, res, reload) {
        final cats = ApiRes.asList(res['result'] ?? res.data);
        if (cats.isEmpty) return ListView(children: [EmptyView(res.message.isNotEmpty ? res.message : 'No services at the customer’s selected address.')]);
        _cat ??= toInt(cats.first['category_id']);
        return Column(children: [
          FilterChips<int>(options: {for (final x in cats) toInt(x['category_id'])!: '${x['category_name']} (${x['service_count'] ?? ''})'}, value: _cat!, onChanged: (v) => setState(() => _cat = v)),
          Expanded(
            child: ApiLoader(
              key: ValueKey(_cat),
              load: () => api.post('/admin/users/services/list', {'customerId': widget.id, 'category_id': _cat}),
              builder: (c, r, _) {
                final svcs = ApiRes.asList(r['result'] ?? r.data);
                if (svcs.isEmpty) return ListView(children: const [EmptyView('No services found')]);
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: svcs.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (c, i) {
                    final s = svcs[i];
                    return RowTile(
                      leading: NetImage(s['image'], size: 48),
                      title: str(s['title'] ?? s['service']),
                      subtitle: ApiRes.asList(s['booking_types']).map((b) => b['name']).join(', '),
                      lines: [ApiRes.asList(s['units']).map((u) => '${u['name']} ${u['price_per_unit'] != null ? inr(u['price_per_unit']) : ''}').join(' · ')],
                      trailing: Text(inr(s['price'] ?? s['base_price']), style: const TextStyle(fontWeight: FontWeight.w800)),
                    );
                  },
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity(this.id);
  final int id;
  @override
  Widget build(BuildContext context) {
    return PagedList(
      searchHint: 'Search by path or summary…',
      fetch: (p, l, s) => api.post('/admin/users/activity-logs', {'customerId': id, 'page': p, 'limit': l, if (s.isNotEmpty) 'search': s}),
      empty: 'No activity logs found.',
      itemBuilder: (c, r, i) => RowTile(
        title: str(r['summary'], '${r['http_method']} ${r['request_path']}'),
        subtitle: '${str(r['http_method'], '')} ${str(r['request_path'], '')} · ${r['status_code'] ?? ''}',
        lines: ['${fmtDateTime(r['created_at'])} · ${str(r['ip_address'], '')}'],
      ),
    );
  }
}
