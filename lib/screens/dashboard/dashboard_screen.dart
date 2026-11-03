import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../routes.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../bookings/booking_detail_screen.dart';

/// GET /admin/dashboard/stats?range= + /admin/dashboard/recent-bookings
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _range = '7d';
  final _key = GlobalKey<ApiLoaderState>();

  Future<ApiRes> _load() async {
    final r = await Future.wait([
      api.get('/admin/dashboard/stats', {'range': _range}),
      api.get('/admin/dashboard/recent-bookings', {'limit': 8}),
    ]);
    if (!r[0].ok) return r[0];
    return ApiRes({'status': true, 'data': r[0].data, 'recent': r[1].ok ? r[1].data : []});
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      FilterChips<String>(
        options: const {'7d': '7 days', '30d': '30 days', '90d': '90 days', 'year': 'Year'},
        value: _range,
        onChanged: (v) {
          setState(() => _range = v);
          _key.currentState?.reload();
        },
      ),
      Expanded(
        child: ApiLoader(
          key: _key,
          load: _load,
          builder: (context, res, reload) {
            final d = res.map;
            final k = ApiRes.asMap(d['kpis']);
            final rev = ApiRes.asMap(k['revenue']);
            final bk = ApiRes.asMap(k['bookings']);
            final tech = ApiRes.asMap(k['technicians']);
            final cust = ApiRes.asMap(k['customers']);
            final alerts = ApiRes.asMap(d['alerts']);
            final chart = ApiRes.asMap(d['chart']);
            final breakdown = ApiRes.asList(d['statusBreakdown']);
            final recent = ApiRes.asList(res['recent']);
            return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
              Text('${_greeting()}, ${Session.I.profile?['first_name'] ?? 'Admin'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
              const Gap(10),
              StatGrid([
                StatTile(label: 'Revenue', value: inr(rev['value']), sub: '${inr(rev['totalAllTime'])} all-time ${str(rev['change'], '')}', icon: Icons.currency_rupee, color: C.green, onTap: () => openRoute(context, '/admin/finance')),
                StatTile(label: 'Bookings', value: '${toInt(bk['value']) ?? 0}', sub: 'in period ${str(bk['change'], '')}', icon: Icons.event_available, onTap: () => openRoute(context, '/admin/booking-management/bookings')),
                StatTile(label: 'Technicians', value: '${toInt(tech['value']) ?? 0}', sub: '+${toInt(tech['newInPeriod']) ?? 0} new', icon: Icons.engineering, color: C.violet, onTap: () => openRoute(context, '/admin/technician-management/technicians')),
                StatTile(label: 'Customers', value: '${toInt(cust['value']) ?? 0}', sub: '+${toInt(cust['newInPeriod']) ?? 0} new', icon: Icons.people_alt_outlined, color: C.sky, onTap: () => openRoute(context, '/admin/user-management/users')),
              ]),
              const Gap(),
              SectionCard(title: 'Needs attention', children: [
                _alert(Icons.assignment_ind_outlined, 'Pending technician applications', alerts['pendingApplications'], () => openRoute(context, '/admin/technician-management/applications')),
                _alert(Icons.timer_off_outlined, 'Overdue / delayed bookings', alerts['delayedBookings'], () => openRoute(context, '/admin/operations/sla')),
                _alert(Icons.today_outlined, 'Bookings today', alerts['todayBookings'], () => openRoute(context, '/admin/booking-management/bookings')),
              ]),
              const Gap(),
              SectionCard(title: 'Booking activity', children: [SizedBox(height: 180, child: _Trend(chart))]),
              const Gap(),
              if (breakdown.isNotEmpty) ...[
                SectionCard(title: 'Service status breakdown', children: [
                  for (final b in breakdown) _bar(b, breakdown.fold<int>(0, (a, e) => a + (toInt(e['count']) ?? 0))),
                ]),
                const Gap(),
              ],
              SectionCard(
                title: 'Recent bookings',
                trailing: TextButton(onPressed: () => openRoute(context, '/admin/booking-management/bookings'), child: const Text('View all')),
                children: [
                  if (recent.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No bookings yet', style: TextStyle(color: C.muted))),
                  for (final b in recent)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${str(b['id'])} · ${str(b['service'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      subtitle: Text('${str(b['customer'])} · ${fmtDate(b['date'])}', style: const TextStyle(fontSize: 12)),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(inr(b['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        StatusChip(b['status']),
                      ]),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(id: b['bookingId'] ?? b['booking_id']))),
                    ),
                ],
              ),
            ]);
          },
        ),
      ),
    ]);
  }

  Widget _alert(IconData icon, String label, dynamic count, VoidCallback onTap) {
    final n = toInt(count) ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: n > 0 ? C.amber : C.muted),
      title: Text(label),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: n > 0 ? C.amber : C.body, fontSize: 16)),
        const Icon(Icons.chevron_right, color: C.muted),
      ]),
      onTap: onTap,
    );
  }

  Widget _bar(Map<String, dynamic> b, int total) {
    final n = toInt(b['count']) ?? 0;
    final (_, fg) = statusColors(str(b['status'], ''));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(humanize(b['status']), style: const TextStyle(fontSize: 13))), Text('$n', style: const TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: total == 0 ? 0 : n / total, minHeight: 6, color: fg, backgroundColor: C.bg),
        ),
      ]),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend(this.chart);
  final Map<String, dynamic> chart;

  @override
  Widget build(BuildContext context) {
    final labels = List<String>.from((chart['labels'] as List?)?.map((e) => e.toString()) ?? const []);
    final values = List<double>.from((chart['bookings'] as List?)?.map(toNum) ?? const []);
    if (values.isEmpty) return const Center(child: Text('No bookings for this period', style: TextStyle(color: C.muted)));
    final step = (labels.length / 5).ceil().clamp(1, 1000);
    return LineChart(LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: chartAxisLabel)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (v, m) {
              final i = v.toInt();
              if (i < 0 || i >= labels.length || i % step != 0) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i], style: const TextStyle(fontSize: 9.5, color: C.muted)));
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
          isCurved: true,
          color: C.primary,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: C.primary.withValues(alpha: .08)),
        ),
      ],
    ));
  }
}
