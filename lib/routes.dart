import 'package:flutter/material.dart';

import 'core/session.dart';
import 'screens/bookings/bookings_screen.dart';
import 'screens/bookings/disputes_screen.dart';
import 'screens/bookings/warranty_screen.dart';
import 'screens/common/crud_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/masters/catalog_screens.dart';
import 'screens/masters/geography_screens.dart';
import 'screens/masters/masters_basic.dart';
import 'screens/admin/admin_screens.dart';
import 'screens/finance/finance_screens.dart';
import 'screens/guides_screen.dart';
import 'screens/marketing/marketing_screens.dart';
import 'screens/operations/operations_screens.dart';
import 'screens/settings/settings_screens.dart';
import 'screens/support/support_screens.dart';
import 'screens/technicians/technicians_screens.dart';
import 'screens/users/customers_screen.dart';
import 'ui/widgets.dart';

/// One native screen per web admin route. `path` is the web menu_path so the
/// same DB-driven menu visibility and privileges apply on mobile.
class AppRoute {
  const AppRoute(this.path, this.title, this.icon, this.builder, {this.group});
  final String path;
  final String title;
  final IconData icon;
  final WidgetBuilder builder;
  final String? group;
}

final List<AppRoute> kRoutes = [
  AppRoute('/admin/dashboard', 'Dashboard', Icons.dashboard_outlined, (_) => const DashboardScreen(), group: 'Overview'),
  // Bookings
  AppRoute('/admin/booking-management/bookings', 'Bookings', Icons.event_note_outlined, (_) => const BookingsScreen(), group: 'Booking Management'),
  AppRoute('/admin/booking-management/warranty-claims', 'Warranty Claims', Icons.verified_outlined, (_) => const WarrantyClaimsScreen(), group: 'Booking Management'),
  AppRoute('/admin/booking-management/disputes', 'Complaints & Disputes', Icons.report_gmailerrorred_outlined, (_) => const DisputesScreen(), group: 'Booking Management'),
  // Support
  AppRoute('/admin/chat', 'Support Chat', Icons.support_agent, (_) => const ChatQueueScreen(), group: 'Support'),
  AppRoute('/admin/contact-inquiries', 'Contact Inquiries', Icons.mark_email_unread_outlined, (_) => const InquiriesScreen(), group: 'Support'),
  // Users
  AppRoute('/admin/user-management/users', 'Customers', Icons.people_alt_outlined, (_) => const CustomersScreen(), group: 'User Management'),
  AppRoute('/admin/user-management/feedbacks', 'Feedbacks', Icons.reviews_outlined, (_) => CrudScreen(feedbacksConfig()), group: 'User Management'),
  // Technicians
  AppRoute('/admin/technician-management/applications', 'Technician Applications', Icons.assignment_ind_outlined, (_) => const ApplicationsScreen(), group: 'Technician Management'),
  AppRoute('/admin/technician-management/technicians', 'Technicians', Icons.engineering_outlined, (_) => const TechniciansScreen(), group: 'Technician Management'),
  AppRoute('/admin/technician-management/technicians/map', 'Live Technician Map', Icons.map_outlined, (_) => const TechnicianMapScreen(), group: 'Technician Management'),
  AppRoute('/admin/technician-management/skill-requests', 'Skill Requests', Icons.rule, (_) => const SkillRequestsScreen(), group: 'Technician Management'),
  AppRoute('/admin/technician-management/referrals', 'Referrals', Icons.share_outlined, (_) => const ReferralsScreen(), group: 'Technician Management'),
  // Finance
  AppRoute('/admin/finance', 'Finance Center', Icons.account_balance_outlined, (_) => const FinanceCenterScreen(), group: 'Finance'),
  AppRoute('/admin/finance/payments', 'Payments', Icons.payments_outlined, (_) => const PaymentsScreen(), group: 'Finance'),
  AppRoute('/admin/finance/invoices', 'Invoices', Icons.description_outlined, (_) => const InvoicesScreen(), group: 'Finance'),
  AppRoute('/admin/finance/payouts', 'Payouts & Settlements', Icons.account_balance_wallet_outlined, (_) => const PayoutsScreen(), group: 'Finance'),
  AppRoute('/admin/finance/refunds', 'Refunds', Icons.undo, (_) => const RefundsScreen(), group: 'Finance'),
  AppRoute('/admin/finance/taxes', 'Transaction Taxes', Icons.percent, (_) => CrudScreen(transactionTaxesConfig()), group: 'Finance'),
  AppRoute('/admin/finance/failed', 'Failed Payments', Icons.error_outline, (_) => const FailedPaymentsScreen(), group: 'Finance'),
  AppRoute('/admin/finance/wallet', 'Wallet Ledger', Icons.wallet_outlined, (_) => const WalletLedgerScreen(), group: 'Finance'),
  AppRoute('/admin/finance/reports', 'Financial Reports', Icons.insights_outlined, (_) => const FinanceReportsScreen(), group: 'Finance'),
  // Marketing
  AppRoute('/admin/masters/announcement-management/promotions', 'Promotions', Icons.campaign_outlined, (_) => const PromotionsScreen(), group: 'Marketing'),
  AppRoute('/admin/masters/announcement-management/notification', 'Push Notifications', Icons.notifications_active_outlined, (_) => const NotificationsBroadcastScreen(), group: 'Marketing'),
  // Masters
  AppRoute('/admin/lookups/document-types', 'Document Types', Icons.badge_outlined, (_) => CrudScreen(documentTypesConfig()), group: 'Masters'),
  AppRoute('/admin/masters/services-management/service-categories', 'Service Categories', Icons.category_outlined, (_) => const ServiceCategoriesScreen(), group: 'Masters'),
  AppRoute('/admin/masters/services-management/skills', 'Skills', Icons.handyman_outlined, (_) => const SkillsScreen(), group: 'Masters'),
  AppRoute('/admin/masters/geography/countries', 'Geography & Areas', Icons.public, (_) => const CountriesScreen(), group: 'Masters'),
  AppRoute('/admin/masters/finance-management/charges', 'Charges', Icons.receipt_long_outlined, (_) => CrudScreen(chargesConfig()), group: 'Masters'),
  AppRoute('/admin/masters/finance-management/taxes', 'Taxes', Icons.percent, (_) => CrudScreen(taxesConfig()), group: 'Masters'),
  AppRoute('/admin/masters/finance-management/discounts', 'Discounts', Icons.discount_outlined, (_) => CrudScreen(discountsConfig()), group: 'Masters'),
  AppRoute('/admin/masters/finance-management/commissions', 'Commissions', Icons.account_balance_outlined, (_) => CrudScreen(commissionsConfig()), group: 'Masters'),
  AppRoute('/admin/masters/coupon-management/coupons', 'Coupons', Icons.confirmation_number_outlined, (_) => CrudScreen(couponsConfig()), group: 'Masters'),
  // Operations & reports
  AppRoute('/admin/operations/sla', 'SLA Monitor', Icons.timer_outlined, (_) => const SlaMonitorScreen(), group: 'Operations'),
  AppRoute('/admin/operations/audit', 'Audit Logs', Icons.history, (_) => const AuditLogsScreen(), group: 'Operations'),
  AppRoute('/admin/reports', 'Reports', Icons.summarize_outlined, (_) => const ReportsScreen(), group: 'Operations'),
  // Administration
  AppRoute('/admin/admin-management/admins', 'Administrators', Icons.admin_panel_settings_outlined, (_) => const AdminsScreen(), group: 'Administration'),
  AppRoute('/admin/admin-management/roles', 'Roles', Icons.shield_outlined, (_) => const RolesScreen(), group: 'Administration'),
  AppRoute('/admin/admin-management/permissions', 'Permissions', Icons.lock_outline, (_) => const PermissionsScreen(), group: 'Administration'),
  // Settings
  AppRoute('/admin/settings', 'General Settings', Icons.settings_outlined, (_) => const GeneralSettingsScreen(), group: 'Settings'),
  AppRoute('/admin/settings/notifications', 'Notification Channels', Icons.notifications_outlined, (_) => const NotificationSettingsScreen(), group: 'Settings'),
  AppRoute('/admin/settings/payments', 'Payment Gateways', Icons.credit_card, (_) => const PaymentSettingsScreen(), group: 'Settings'),
  AppRoute('/admin/settings/referral', 'Referral Rewards', Icons.card_giftcard, (_) => const ReferralSettingsScreen(), group: 'Settings'),
  AppRoute('/admin/settings/profile', 'My Profile & Security', Icons.person_outline, (_) => const ProfileScreen(), group: 'Settings'),
  AppRoute('/admin/guides', 'Help & Guides', Icons.menu_book_outlined, (_) => const GuidesScreen(), group: 'Settings'),
];

AppRoute? routeFor(String path) {
  for (final r in kRoutes) {
    if (r.path == path) return r;
  }
  return null;
}

/// Open a route by its web path, respecting menu visibility.
void openRoute(BuildContext context, String path) {
  final r = routeFor(path);
  if (r == null) return;
  if (!Session.I.canOpen(path)) {
    toast('You don’t have access to ${r.title}', error: true);
    return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(appBar: AppBar(title: Text(r.title)), body: SafeArea(top: false, child: r.builder(c)))));
}

/// Routes the signed-in admin can open, in registry order.
List<AppRoute> visibleRoutes() => kRoutes.where((r) => Session.I.canOpen(r.path)).toList();
