import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/typography.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/delete_record_button.dart';
import '../../../core/widgets/detail.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/module_list.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/states.dart';
import '../../ex_factory/data/ex_factory_repository.dart';
import '../../masters/data/form_options.dart';
import '../../masters/data/masters_repository.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/sales_repository.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/widgets/extra_fields.dart';

class SalesListScreen extends ConsumerWidget {
  const SalesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ModuleListScreen<SaleEntry>(
      title: 'Sales register',
      inTabs: false,
      listProvider: salesListProvider,
      sortField: 'deal_date',
      queryProvider: salesQueryProvider,
      searchHint: 'Search mark, invoice, buyer or entry',
      emptyIcon: AppIcons.sales,
      emptyTitle: 'Record your first sale',
      emptyBody: 'Deals with buyers show up here and are matched against ex-factory bills.',
      newLabel: 'New entry',
      onNew: () => context.pushNamed(Routes.salesNew),
      actions: [AddButton(semanticLabel: 'New sales entry', onPressed: () => context.pushNamed(Routes.salesNew))],
      segments: SegmentConfig(param: 'status', options: watchFormOptions(ref).map('sale_statuses', all: 'All')),
      filters: [
        const DateFilter('start_date', 'From'),
        const DateFilter('end_date', 'To'),
        ChoiceFilter('tea_grade', 'Grade', {for (final g in ref.watch(gradesProvider).value ?? const <String>[]) g: g}),
      ],
      itemBuilder: (context, s) => AppListRow(
        title: [?s.mark, ?s.grade].join(' · ').isEmpty ? 'Sale #${s.id}' : [?s.mark, ?s.grade].join(' · '),
        subtitle: [s.buyerName, Fmt.invoice(s.invoicePrefix, s.invoiceNo), '${Fmt.kg(s.allQuantity)} × ${Fmt.money(s.rate)}', if (s.isSplit) 'Split ${s.splitCount} ways']
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .join(' · '),
        onTap: () => context.pushNamed(Routes.salesDetail, pathParameters: {'id': '${s.id}'}, extra: s),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Fmt.money(s.allAmount), style: AppText.callout.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            OptionBadge(list: 'sale_statuses', value: s.status),
          ],
        ),
      ),
    );
  }
}


/// Website form fields the API saves (dropdowns load from their own APIs).
const kSaleExtraFields = <ExtraField>[
  ExtraField('nett', 'Nett per pkg', ExtraKind.number, suffix: 'kg'),
  ExtraField('total_lot_pkgs', 'Total lot pkgs', ExtraKind.integer),
  ExtraField('pencil_rate', 'Pencil rate', ExtraKind.money),
  ExtraField('net_price', 'Net price', ExtraKind.money),
  ExtraField('sub_party', 'Sub party', ExtraKind.text),
  ExtraField('location', 'Location', ExtraKind.text),
  ExtraField('pkg_date', 'Packing date', ExtraKind.date),
  ExtraField('lab_date', 'Lab date', ExtraKind.date),
  ExtraField('sample_date', 'Sample date', ExtraKind.date),
  ExtraField('samples_recd', 'Samples received', ExtraKind.date),
  ExtraField('dispatch_date', 'Dispatch date', ExtraKind.date),
];

class SalesFormScreen extends ConsumerStatefulWidget {
  const SalesFormScreen({super.key, this.editing});

  /// The sale being edited, or null for a new one.
  final SaleEntry? editing;

  @override
  ConsumerState<SalesFormScreen> createState() => _SalesFormScreenState();
}

class _SalesFormScreenState extends ConsumerState<SalesFormScreen> with FormSubmit {
  late final _x = ExtraFieldsController(kSaleExtraFields, widget.editing?.raw ?? const {});
  late final SaleEntry? _e = widget.editing;
  late MasterItem? _buyer = _e?.buyerId == null ? null : MasterItem(_e!.buyerId!, _e.buyerName ?? '#${_e.buyerId}');
  late String? _grade = _e?.grade;
  late DateTime _deal = _e?.dealDate ?? DateTime.now();
  late DateTime? _cnDate = _e?.cnDate;
  late final _rate = TextEditingController(text: Fmt.editable(_e?.rate));
  late final _mark = TextEditingController(text: _e?.mark);
  late final _prefix = TextEditingController(text: _e?.invoicePrefix);
  late final _inv = TextEditingController(text: _e?.invoiceNo);
  late final _pkgs = TextEditingController(text: _e?.pkgs?.toString());
  late final _qty = TextEditingController(text: Fmt.editable(_e?.quantity));
  late final _cn = TextEditingController(text: _e?.cnNumber);
  late final _transport = TextEditingController(text: _e?.transport);
  late final _discount = TextEditingController(text: Fmt.editable(_e?.discount));
  late final _remarks = TextEditingController(text: _e?.remarks);
  late final _incharge = TextEditingController(text: J.str(_e?.raw['incharge']));
  late String? _category = J.str(_e?.raw['category']);
  late MasterItem? _garden = J.integer(_e?.raw['garden_id']) == null ? null : MasterItem(J.integer(_e!.raw['garden_id'])!, _e.mark ?? '#${_e.raw['garden_id']}');
  bool _looking = false;

  /// Mark and invoice last looked up; leaving the invoice field looks the
  /// lot up by itself (new entries only).
  String? _lookedUp;
  final _invFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (_e == null) {
      _invFocus.addListener(() {
        if (!_invFocus.hasFocus) _lookupLot(auto: true);
      });
    }
  }

  /// Picking a garden fills the mark and what the website fills from
  /// `garden-info`: incharge, category and location.
  Future<void> _setGarden(MasterItem? g) async {
    setState(() {
      _garden = g;
      if (g != null) _mark.text = g.name;
    });
    if (g == null) return;
    final info = await ref.read(salesRepositoryProvider).gardenInfo(g.id);
    if (info == null || !mounted) return;
    setState(() {
      if (J.str(info['garden_name']) case final name?) _mark.text = name;
      if (J.str(info['incharge']) case final v?) _incharge.text = v;
      if (J.str(info['category']) case final v?) _category = v;
      _x.fill({'location': info['location']});
    });
  }

  /// Fills the lot from its samples and offers, by mark and invoice
  /// (`lookup-lot`), like the website.
  Future<void> _lookupLot({bool auto = false}) async {
    final key = '${_mark.text.trim()}|${_inv.text.trim()}'.toUpperCase();
    if (_looking || _mark.text.trim().isEmpty || _inv.text.trim().isEmpty) return;
    if (auto && key == _lookedUp) return;
    _lookedUp = key;
    setState(() => _looking = true);
    final lot = await ref.read(salesRepositoryProvider).lookupLot(_mark.text.trim(), _inv.text.trim());
    if (!mounted) return;
    setState(() => _looking = false);
    if (lot == null) {
      if (!auto) context.toast('No lot found for this mark and invoice.');
      return;
    }
    final buyers = ref.read(buyersProvider).value ?? const <MasterItem>[];
    setState(() {
      if (J.str(lot['tea_grade']) case final v?) _grade = v;
      if (J.str(lot['invoice_prefix']) case final v?) _prefix.text = v;
      if (J.integer(lot['pkgs']) case final v? when v > 0) _pkgs.text = '$v';
      if (J.dbl(lot['quantity_kg']) case final v? when v > 0) _qty.text = Fmt.editable(v);
      if (J.dbl(lot['rate_per_kg']) case final v? when v > 0) _rate.text = Fmt.editable(v);
      if (J.str(lot['transport']) case final v?) _transport.text = v;
      if (J.str(lot['category']) case final v?) _category = v;
      if (J.integer(lot['buyer_id']) case final id?) {
        _buyer = buyers.where((b) => b.id == id).firstOrNull ?? MasterItem(id, J.str(lot['billing_company']) ?? '#$id');
      }
      _x.fill(lot);
    });
    final remaining = J.integer(lot['remaining_pkgs']);
    final splits = J.integer(lot['existing_splits_count']) ?? 0;
    context.toast([
      'Filled from ${J.str(lot['source']) ?? 'the lot'}',
      if (splits > 0) '$splits earlier ${splits == 1 ? 'split' : 'splits'}',
      if (remaining != null) '$remaining pkgs left',
    ].join(' · '));
  }

  @override
  void dispose() {
    _invFocus.dispose();
    _x.dispose();
    for (final c in [_rate, _mark, _prefix, _inv, _pkgs, _qty, _cn, _transport, _discount, _remarks, _incharge]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await submit<bool>(
      () async {
        final body = {
          ..._x.body(),
          'buyer_id': _buyer?.id,
          'garden_id': _garden?.id,
          'category': _category,
          'incharge': _incharge.text.trim(),
          'tea_grade': _grade,
          'rate_per_kg': Fmt.parse(_rate.text),
          'pkgs': int.tryParse(_pkgs.text),
          'quantity_kg': Fmt.parse(_qty.text),
          'mark': _mark.text.trim(),
          'invoice_prefix': _prefix.text.trim(),
          'invoice_no': _inv.text.trim(),
          'deal_date': Fmt.api(_deal),
          'cn_number': _cn.text.trim(),
          'cn_date': _cnDate == null ? null : Fmt.api(_cnDate!),
          'transport': _transport.text.trim(),
          'discount': Fmt.parse(_discount.text),
          'remarks': _remarks.text.trim(),
        };
        final repo = ref.read(salesRepositoryProvider);
        if (_e == null) {
          await repo.create(body);
        } else {
          await repo.update(_e.id, body);
        }
        return true;
      },
      clientErrors: {
        if (_buyer == null) 'buyer_id': 'Choose a buyer.',
        if (_grade == null) 'tea_grade': 'Choose a grade.',
        if (Fmt.parse(_rate.text) == null) 'rate_per_kg': 'Enter the rate per kg.',
      },
    );
    if (ok == true && mounted) {
      ref.invalidate(salesListProvider);
      ref.invalidate(exFactoryListProvider);
      refreshSummaries(ref);
      context.toast(_e == null ? 'Sale saved' : 'Sale updated');
      if (_e == null) {
        context.pop();
      } else {
        context.goNamed(Routes.sales);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = Fmt.parse(_rate.text);
    final qty = Fmt.parse(_qty.text);
    final amount = rate == null || qty == null ? null : rate * qty - (Fmt.parse(_discount.text) ?? 0);
    TextInputType dec() => const TextInputType.numberWithOptions(decimal: true);
    return FormScaffold(
      title: _e == null ? 'New sale' : 'Edit sale',
      submitLabel: _e == null ? 'Save sale' : 'Save changes',
      submitting: submitting,
      onSubmit: _save,
      children: [
        if (banner != null) FormBanner(banner!),
        GroupedSection(
          label: 'Deal',
          children: [
            MasterPickerRow(label: 'Buyer', provider: buyersProvider, value: _buyer, onChanged: (b) => setState(() => _buyer = b), error: err('buyer_id')),
            GradePickerRow(value: _grade, onChanged: (g) => setState(() => _grade = g), error: err('tea_grade')),
            FieldInput(label: 'Rate per kg', hint: '310.00', suffix: '₹', controller: _rate, error: err('rate_per_kg'), onChanged: (_) => setState(() {}), keyboardType: dec(), inputFormatters: decimalOnly),
            DateRow(label: 'Deal date', value: _deal, onChanged: (d) => setState(() => _deal = d)),
            OptionRow(label: 'Category', list: 'tea_categories', value: _category, placeholder: 'Not set', error: err('category'), onChanged: (v) => setState(() => _category = v)),
            FieldInput(label: 'Incharge', hint: 'Sanjay Agarwal', controller: _incharge, error: err('incharge')),
          ],
        ),
        GroupedSection(
          label: 'Lot',
          children: [
            MasterPickerRow(label: 'Garden', provider: gardensProvider, searchPath: '/gardens', value: _garden, placeholder: 'Pick to fill the mark', onChanged: _setGarden, error: err('garden_id')),
            FieldInput(label: 'Mark', hint: 'Assam Valley Mark', controller: _mark, error: err('mark'), onChanged: (_) => setState(() {})),
            Row(children: [
              SizedBox(width: 120, child: FieldInput(label: 'Prefix', hint: 'IVP', controller: _prefix, textCapitalization: TextCapitalization.characters)),
              Expanded(
                child: FieldInput(
                  label: 'Invoice no',
                  hint: '9812',
                  controller: _inv,
                  focusNode: _invFocus,
                  error: err('invoice_no'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _lookupLot(auto: true),
                ),
              ),
            ]),
            LookupButton(
              label: 'Fill from lot',
              busy: _looking,
              onPressed: _mark.text.trim().isEmpty || _inv.text.trim().isEmpty ? null : () => _lookupLot(),
            ),
            Row(children: [
              Expanded(child: FieldInput(label: 'Packages', hint: '25', controller: _pkgs, error: err('pkgs'), keyboardType: TextInputType.number, inputFormatters: digitsOnly)),
              Expanded(child: FieldInput(label: 'Quantity', hint: '875', suffix: 'kg', controller: _qty, onChanged: (_) => setState(() {}), keyboardType: dec(), inputFormatters: decimalOnly)),
            ]),
          ],
        ),
        GroupedSection(
          label: 'Dispatch',
          children: [
            FieldInput(label: 'CN number', hint: 'CN-44129', controller: _cn),
            DateRow(label: 'CN date', value: _cnDate, placeholder: 'Not set', todayShortcut: true, onChanged: (d) => setState(() => _cnDate = d)),
            FieldInput(label: 'Transport', hint: 'V-Trans Logistics', controller: _transport),
          ],
        ),
        ExtraFieldsSection(label: 'Lot and dates', controller: _x, errors: errors, onChanged: () => setState(() {})),
        GroupedSection(
          label: 'Other',
          footer: Text('Amount ${Fmt.money(amount)}'),
          children: [
            FieldInput(label: 'Discount', hint: '0', suffix: '₹', controller: _discount, onChanged: (_) => setState(() {}), keyboardType: dec(), inputFormatters: decimalOnly),
            FieldInput(label: 'Remarks', hint: 'Dispatched directly from factory', controller: _remarks, maxLines: 3),
          ],
        ),
      ],
    );
  }
}

class SalesDetailScreen extends StatelessWidget {
  const SalesDetailScreen({super.key, required this.entry});
  final SaleEntry? entry;

  @override
  Widget build(BuildContext context) {
    final s = entry;
    if (s == null) return const MissingItemScreen(what: 'sale');
    final c = context.colors;
    return DetailScaffold(
      title: s.mark ?? 'Sale',
      actions: [
        LinkButton(label: 'Edit', onPressed: () => context.pushNamed(Routes.salesEdit, pathParameters: {'id': '${s.id}'}, extra: s)),
      ],
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Fmt.money(s.allAmount), style: AppText.metric),
                Text('${Fmt.kg(s.allQuantity)} × ${Fmt.money(s.rate)}', style: AppText.footnote.copyWith(color: c.textTertiary)),
              ]),
            ),
            OptionBadge(list: 'sale_statuses', value: s.status),
          ]),
        ),
        GroupedSection(
          children: [
            InfoRow('Buyer', s.buyerName),
            InfoRow('Grade', s.grade),
            InfoRow('Invoice', Fmt.invoice(s.invoicePrefix, s.invoiceNo)),
            InfoRow('Packages', s.allPkgs?.toString()),
            if (s.isSplit) InfoRow('Split', '${s.splitCount} ways · this entry ${Fmt.kg(s.quantity)}, ${s.pkgs ?? 0} pkgs'),
            InfoRow('Deal date', Fmt.day(s.dealDate)),
            InfoRow('CN', [s.cnNumber, if (s.cnDate != null) Fmt.day(s.cnDate)].whereType<String>().join(' · ')),
            InfoRow('Transport', s.transport),
            InfoRow('Category', J.str(s.raw['category'])),
            InfoRow('Incharge', J.str(s.raw['incharge'])),
            InfoRow('Discount', Fmt.money(s.discount)),
            if (s.remarks != null) InfoBlock('Remarks', s.remarks!),
          ],
        ),
        if (extraInfoRows(kSaleExtraFields, s.raw).isNotEmpty) GroupedSection(label: 'More details', children: extraInfoRows(kSaleExtraFields, s.raw)),
        DeleteRecordButton(
          what: 'sale',
          name: [s.mark, Fmt.invoice(s.invoicePrefix, s.invoiceNo)].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
          onDelete: (ref) => ref.read(salesRepositoryProvider).delete(s.id),
          onDeleted: (ref) {
            ref.invalidate(salesListProvider);
            ref.invalidate(exFactoryListProvider);
          },
        ),
      ],
    );
  }
}
