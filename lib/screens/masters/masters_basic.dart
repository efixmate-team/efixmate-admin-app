import '../../core/format.dart';
import '../../ui/form.dart';
import '../common/crud_screen.dart';

const _pctFixed = {'PERCENTAGE': 'Percentage (%)', 'FIXED': 'Fixed amount'};
const _activeFilters = {'All': <String, dynamic>{}, 'Active only': {'is_active': true}};

/// Document Types (technician KYC) — /lookup/document-types.
CrudConfig documentTypesConfig() => CrudConfig(
      title: 'Document Type',
      base: '/lookup/document-types',
      idKey: 'document_type_id',
      menuPath: '/admin/lookups/document-types',
      filters: _activeFilters,
      titleOf: (r) => str(r['document_type']),
      subtitleOf: (r) => '${const {'SINGLE': 'Single page', 'FRONT': 'Front page', 'BACK': 'Back page'}[r['page_type'] ?? 'SINGLE'] ?? r['page_type']} · ${truthy(r['is_mandatory']) ? 'Mandatory' : 'Optional'}',
      linesOf: (r) => ['Applies to: ${_appliesTo(r['applies_to']).map((e) => e == 'CUSTOMER' ? 'User' : humanize(e)).join(', ')}'],
      fields: (_) => [
        Field('document_type', 'Document Name', required: true),
        Field('page_type', 'Page Type', type: F.select, options: const {'SINGLE': 'Single Page', 'FRONT': 'Front Page', 'BACK': 'Back Page (no document number required)'}, initial: 'SINGLE'),
        Field('applies_to', 'Applicable For', type: F.multiSelect, options: const {'TECHNICIAN': 'Technician', 'CUSTOMER': 'User'}),
        Field('is_mandatory', 'Mandatory', type: F.toggle),
        Field('is_active', 'Active', type: F.toggle),
      ],
      toInitial: (r) => {...r, 'applies_to': _appliesTo(r['applies_to'])},
      toPayload: (v, _) => {...v, 'applies_to': ((v['applies_to'] as List?) ?? const []).join(',')},
    );

List<String> _appliesTo(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => e.toString()).toList();
  final s = v.toString().replaceAll(RegExp(r'[\[\]"]'), '');
  return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

CrudConfig chargesConfig() => CrudConfig(
      title: 'Charge',
      base: '/master/charges',
      idKey: 'charge_id',
      menuPath: '/admin/masters/finance-management/charges',
      filters: _activeFilters,
      titleOf: (r) => str(r['charge_name']),
      subtitleOf: (r) => r['charge_type'] == 'Percentage' ? '${r['charge_value']}%' : inr(r['charge_value'], paise: true),
      fields: (_) => [
        Field('charge_name', 'Name', required: true),
        Field('charge_type', 'Type', type: F.select, options: const {'Fixed': 'Fixed', 'Percentage': 'Percentage'}, required: true, initial: 'Fixed'),
        Field('charge_value', 'Value', type: F.decimal, required: true),
        Field('is_active', 'Active', type: F.toggle),
      ],
    );

CrudConfig taxesConfig() => CrudConfig(
      title: 'Tax',
      base: '/master/taxes',
      idKey: 'tax_id',
      menuPath: '/admin/masters/finance-management/taxes',
      filters: _activeFilters,
      titleOf: (r) => str(r['tax_name']),
      subtitleOf: (r) => 'Rate ${r['tax_percentage']}%',
      fields: (_) => [
        Field('tax_name', 'Name', required: true),
        Field('tax_percentage', 'Rate (%)', type: F.decimal, required: true),
        Field('is_active', 'Active', type: F.toggle),
      ],
    );

CrudConfig discountsConfig() => CrudConfig(
      title: 'Discount',
      base: '/master/discounts',
      idKey: 'discount_id',
      menuPath: '/admin/masters/finance-management/discounts',
      filters: _activeFilters,
      titleOf: (r) => str(r['discount_title']),
      subtitleOf: (r) => r['discount_type'] == 'PERCENTAGE' ? '${r['discount_value']}%' : inr(r['discount_value'], paise: true),
      fields: (_) => [
        Field('discount_title', 'Name', required: true),
        Field('discount_type', 'Type', type: F.select, options: _pctFixed, required: true, initial: 'PERCENTAGE'),
        Field('discount_value', 'Value', type: F.decimal, required: true),
        Field('is_active', 'Active', type: F.toggle),
      ],
    );

/// Commission rules — TDS is opt-in, GST on commission defaults on.
CrudConfig commissionsConfig() => CrudConfig(
      title: 'Commission',
      base: '/master/commissions',
      idKey: 'rule_id',
      menuPath: '/admin/masters/finance-management/commissions',
      filters: _activeFilters,
      titleOf: (r) => str(r['rule_name']),
      subtitleOf: (r) => r['commission_mode'] == 'FIXED' ? '${inr(r['commission_value'], paise: true)} per job' : '${r['commission_value']}% of job value',
      linesOf: (r) => [
        'GST on commission: ${r['gst_applicable'] == false ? 'Off' : '${r['gst_rate'] ?? 0}%'}',
        'TDS: ${truthy(r['tds_applicable']) ? '${r['tds_rate'] ?? 0}%' : 'Off'}',
      ],
      fields: (_) => [
        Field('rule_name', 'Name', required: true),
        Field('commission_mode', 'Type', type: F.select, options: _pctFixed, required: true, initial: 'PERCENTAGE'),
        Field('commission_value', 'Value', type: F.decimal, required: true),
        Field('gst_applicable', 'GST on commission', type: F.toggle, initial: true),
        Field('gst_rate', 'GST rate (%)', type: F.decimal, initial: 18, visibleIf: (v) => truthy(v['gst_applicable'])),
        Field('tds_applicable', 'Deduct TDS from technician', type: F.toggle, initial: false),
        Field('tds_rate', 'TDS rate (%) — used only when TDS is on', type: F.decimal, visibleIf: (v) => truthy(v['tds_applicable'])),
        Field('is_active', 'Active', type: F.toggle),
      ],
      toInitial: (r) => {...r, 'gst_applicable': r['gst_applicable'] != false, 'tds_applicable': truthy(r['tds_applicable'])},
      toPayload: (v, _) => {
        ...v,
        'tds_rate': truthy(v['tds_applicable']) ? (v['tds_rate'] ?? 0) : 0,
        'gst_rate': truthy(v['gst_applicable']) ? (v['gst_rate'] ?? 0) : 0,
      },
    );

CrudConfig couponsConfig() => CrudConfig(
      title: 'Coupon',
      base: '/master/coupons',
      idKey: 'coupon_id',
      menuPath: '/admin/masters/coupon-management/coupons',
      filters: {
        'All': {},
        'Active only': {'is_active': true},
        'Percentage': {'discount_type': 'PERCENTAGE'},
        'Fixed': {'discount_type': 'FIXED'},
      },
      searchHint: 'Search coupon code…',
      deactivateMessage: 'This coupon will no longer be redeemable.',
      titleOf: (r) => str(r['coupon_code']),
      subtitleOf: (r) => '${r['discount_type'] == 'PERCENTAGE' ? '${r['discount_value']}% off' : '${inr(r['discount_value'])} off'}'
          '${r['max_discount_amount'] != null ? ' · max ${inr(r['max_discount_amount'])}' : ''} · ${humanize(r['scope'] ?? 'ALL')}',
      linesOf: (r) => [
        'Min order ${inr(r['min_order_amount'])} · Uses ${(toInt(r['max_uses']) ?? 0) == 0 ? '∞' : r['max_uses']} (${r['max_uses_per_user'] ?? '-'}/user)',
        'Valid ${fmtDate(r['valid_from'])} – ${fmtDate(r['valid_until'])}',
      ],
      fields: (_) => [
        Field('coupon_code', 'Coupon Code', required: true),
        Field('discount_type', 'Discount Type', type: F.select, options: const {'PERCENTAGE': 'Percentage (%)', 'FIXED': 'Fixed Amount (₹)'}, required: true, initial: 'PERCENTAGE'),
        Field('discount_value', 'Value', type: F.decimal, required: true),
        Field('max_discount_amount', 'Max Discount Cap', type: F.decimal),
        Field('min_order_amount', 'Min Order Amount', type: F.decimal),
        Field('max_uses', 'Max Total Uses (0 = Unlimited)', type: F.number),
        Field('max_uses_per_user', 'Max Uses Per User', type: F.number),
        Field('valid_from', 'Valid From', type: F.date),
        Field('valid_until', 'Valid Until', type: F.date),
        Field('scope', 'Scope', type: F.select, options: const {'ALL': 'All', 'CATEGORY': 'Category', 'SERVICE': 'Service', 'USER': 'User'}, required: true, initial: 'ALL'),
        Field('is_active', 'Active', type: F.toggle),
      ],
      toInitial: (r) => {
        ...r,
        'valid_from': r['valid_from']?.toString().split('T').first,
        'valid_until': r['valid_until']?.toString().split('T').first,
        'scope': r['scope'] ?? 'ALL',
      },
    );

/// User feedback — /master/feedbacks.
CrudConfig feedbacksConfig() => CrudConfig(
      title: 'Feedback',
      base: '/master/feedbacks',
      idKey: 'feedback_id',
      menuPath: '/admin/user-management/feedbacks',
      filters: {
        'All': {},
        'Pending': {'status': 'PENDING'},
        'Approved': {'status': 'APPROVED'},
        'Resolved': {'status': 'RESOLVED'},
        'Rejected': {'status': 'REJECTED'},
      },
      titleOf: (r) => '${'★' * (toInt(r['rating']) ?? 0)}${'☆' * (5 - (toInt(r['rating']) ?? 0)).clamp(0, 5)}  ${str(r['first_name'] ?? r['user_name'] ?? r['customer_name'], 'User #${r['user_id']}')}',
      subtitleOf: (r) => str(r['comment'], 'No comment'),
      linesOf: (r) => ['${humanize(r['status'])} · ${fmtDate(r['created_at'])}'],
      fields: (_) => [
        Field('user_id', 'User', type: F.select, required: true, loader: optionsFrom('/master/users', 'customer_id', (u) => '${fullName(u)} · ${str(u['mobile_number'], '')}')),
        Field('rating', 'Rating', type: F.select, options: const {'1': '1 ★', '2': '2 ★', '3': '3 ★', '4': '4 ★', '5': '5 ★'}, required: true),
        Field('comment', 'Comment', type: F.multiline),
        Field('status', 'Status', type: F.select, options: const {'PENDING': 'Pending', 'APPROVED': 'Approved', 'REJECTED': 'Rejected', 'RESOLVED': 'Resolved'}, initial: 'PENDING'),
        Field('is_active', 'Active', type: F.toggle),
      ],
      toInitial: (r) => {...r, 'user_id': r['user_id']?.toString(), 'rating': r['rating']?.toString()},
      toPayload: (v, _) => {...v, 'user_id': toInt(v['user_id']), 'rating': toInt(v['rating'])},
    );
