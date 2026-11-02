import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Live technician location, polled every 15s like the web tracking page:
/// GET /admin/technicians/live-location?technician_id= + booking overview for
/// the service location.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, required this.technicianId, this.bookingId});
  final int technicianId;
  final int? bookingId;
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  Map<String, dynamic>? _tech;
  Map<String, dynamic> _booking = {};
  Timer? _timer;
  GoogleMapController? _map;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) {
      api.get('/admin/bookings/${widget.bookingId}/overview').then((r) {
        if (mounted && r.ok) setState(() => _booking = ApiRes.asMap(r.map['booking']));
      });
    }
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final r = await api.get('/admin/technicians/live-location', {'technician_id': widget.technicianId});
    if (!mounted) return;
    if (r.ok) {
      setState(() => _tech = r.map);
      _fit();
    } else if (_tech == null) {
      setState(() => _tech = {'error': r.message});
    }
  }

  LatLng? get _techPos {
    final lat = _tech?['latitude'], lng = _tech?['longitude'];
    if (lat == null || lng == null) return null;
    return LatLng(toNum(lat), toNum(lng));
  }

  LatLng? get _dest {
    final lat = _booking['service_lat'], lng = _booking['service_lng'];
    if (lat == null || lng == null) return null;
    return LatLng(toNum(lat), toNum(lng));
  }

  void _fit() {
    final a = _techPos, b = _dest;
    if (_map == null || a == null) return;
    if (b == null) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(a, 15));
      return;
    }
    if (_fitted) return;
    _fitted = true;
    final sw = LatLng(a.latitude < b.latitude ? a.latitude : b.latitude, a.longitude < b.longitude ? a.longitude : b.longitude);
    final ne = LatLng(a.latitude > b.latitude ? a.latitude : b.latitude, a.longitude > b.longitude ? a.longitude : b.longitude);
    _map!.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80));
  }

  @override
  Widget build(BuildContext context) {
    final t = _tech ?? {};
    final pos = _techPos;
    return Scaffold(
      appBar: AppBar(title: Text(str(t['name'], 'Live tracking')), actions: [IconButton(onPressed: _poll, icon: const Icon(Icons.refresh))]),
      body: _tech == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              if (pos == null && _dest == null)
                EmptyView(str(t['error'], 'No location reported by this technician yet.'), icon: Icons.location_off_outlined)
              else
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: pos ?? _dest!, zoom: 14),
                  onMapCreated: (c) {
                    _map = c;
                    _fit();
                  },
                  markers: {
                    if (pos != null) Marker(markerId: const MarkerId('tech'), position: pos, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: InfoWindow(title: str(t['name']))),
                    if (_dest != null) Marker(markerId: const MarkerId('dest'), position: _dest!, infoWindow: InfoWindow(title: 'Service location', snippet: str(_booking['service_address'], ''))),
                  },
                  myLocationButtonEnabled: false,
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: SafeArea(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Avatar(url: t['avatar'], name: str(t['name'], '')),
                        const Gap(10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(str(t['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(truthy(t['is_online']) ? 'Online' : 'Offline', style: TextStyle(color: truthy(t['is_online']) ? C.green : C.muted, fontSize: 12)),
                            Text('Updated ${ago(t['position_updated_at'])}', style: const TextStyle(color: C.muted, fontSize: 12)),
                          ]),
                        ),
                        IconButton(onPressed: () => callPhone(t['mobile_number']), icon: const Icon(Icons.call, color: C.primary)),
                        IconButton(onPressed: () => whatsapp(t['mobile_number']), icon: const Icon(Icons.chat, color: C.green)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }
}
