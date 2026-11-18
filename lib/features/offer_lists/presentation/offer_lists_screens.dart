import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/typography.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/delete_record_button.dart';
import '../../../core/widgets/detail.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/module_list.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/weight_fields.dart';
import '../../masters/data/form_options.dart';
import '../../masters/data/masters_repository.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/offer_lists_repository.dart';
import '../../../core/design/app_icons.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/widgets/extra_fields.dart';
import '../../../core/utils/json.dart';

class OfferListsScreen extends ConsumerWidget {
  const OfferListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(currentUserProvider)?.can('offer_lists.create') ?? true;
    return ModuleListScreen<OfferList>(
      title: 'Offer lists',
      listProvider: offerListsListProvider,
      queryProvider: offerListsQueryProvider,
      searchHint: 'Search garden, grade, AWR no or key',
      emptyIcon: AppIcons.offers,
      emptyTitle: 'Add your first offer',
      emptyBody: 'Lots offered to buyers show up here with their price.',
      newLabel: canCreate ? 'New offer' : null,
      onNew: canCreate ? () => context.pushNamed(Routes.offerNew) : null,
      actions: [
        LinkButton(label: 'Offered today', onPressed: () => context.pushNamed(Routes.offeredToday)),
        if (canCreate) AddButton(semanticLabel: 'New offer', onPressed: () => context.pushNamed(Routes.offerNew)),
      ],
      filters: [
        const DateFilter('date_from', 'From'),
        const DateFilter('date_to', 'To'),
        ChoiceFilter('grade', 'Grade', {for (final g in ref.watch(gradesProvider).value ?? const <String>[]) g: g}),
        ChoiceFilter('type', 'Type', {for (final t in ref.watch(invoiceTypesProvider).value ?? const []) t.value: t.label}),
        ChoiceFilter('for', 'For', watchFormOptions(ref).map('offer_for')),
        const PickerFilter('garden_id', 'Mark', pickMark),
      ],
      sortField: 'date',
      grouping: ListGrouping(
        section: (o) => o.date == null ? 'No date' : Fmt.day(o.date),
        subgroup: (o) => o.gardenName,
        order: (o) => o.invNo,
      ),
      itemBuilder: (context, o) => AppListRow(
        title: o.title,
        subtitle: [
          Fmt.invoice(o.invPrefix, o.invNo),
          if (o.pkgs != null && o.nett != null) '${Fmt.editable(o.pkgs)} × ${Fmt.editable(o.nett)} kg',
        ].where((e) => e.isNotEmpty).join(' · '),
        onTap: () => context.pushNamed(Routes.offerDetail, pathParameters: {'id': '${o.id}'}, extra: o),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(o.price != null ? Fmt.money(o.price) : Fmt.kg(o.totalKgs), style: AppText.callout.copyWith(fontWeight: o.price != null ? FontWeight.w600 : FontWeight.w400)),
            // The date is the group heading, so the second line is the weight.
            if (o.price != null) ...[
              const SizedBox(height: 2),
              Text(Fmt.kg(o.totalKgs), style: AppText.footnote.copyWith(color: context.colors.textTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}


/// Website form fields the API saves (dropdowns load from their own APIs).
const kOfferExtraFields = <ExtraField>[
  ExtraField('year', 'Year', ExtraKind.integer, hint: '2026'),
  ExtraField('center', 'Center', ExtraKind.text, hint: 'Guwahati'),
  ExtraField('awr_no', 'AWR no', ExtraKind.text, hint: 'AWR-1045'),
  ExtraField('list_date', 'List date', ExtraKind.date),
];

class OfferFormScreen extends ConsumerStatefulWidget {
  const OfferFormScreen({super.key, this.editing});

  /// The offer being edited, or null for a new one.
  final OfferList? editing;

  @override
  ConsumerState<OfferFormScreen> createState() => _OfferFormScreenState();
}

class _OfferFormScreenState extends ConsumerState<OfferFormScreen> with FormSubmit {
  late final _x = ExtraFieldsController(kOfferExtraFields, widget.editing?.raw ?? const {});
  late String? _invoiceType = J.str(widget.editing?.raw['type']);
  late String? _for = J.str(widget.editing?.raw['for']);
  late String? _ofrSas = J.str(widget.editing?.raw['ofr_sas']);
  late String? _currency = J.str(widget.editing?.raw['currency']);
  late String? _courier = J.str(widget.editing?.raw['courier_name']);
  late final OfferList? _e = widget.editing;
  late DateTime _date = _e?.date ?? DateTime.now();
  late DateTime? _packing = _e?.packingDate;
  late MasterItem? _garden = _e?.gardenId == null ? null : MasterItem(_e!.gardenId!, _e.gardenName ?? '#${_e.gardenId}');
  late String? _grade = _e?.grade;
  late final _prefix = TextEditingController(text: _e?.invPrefix);
  late final _inv = TextEditingController(text: _e?.invNo);
  late final _pkgs = TextEditingController(text: Fmt.editable(_e?.pkgs));
  late final _nett = TextEditingController(text: Fmt.editable(_e?.nett));
  late final _total = TextEditingController(text: Fmt.editable(_e?.totalKgs));
  late final _gross = TextEditingController(text: Fmt.editable(_e?.grossWeight));
  late final _price = TextEditingController(text: Fmt.editable(_e?.price));
  late final _prompt = TextEditingController(text: _e?.promptDays?.toString());
  /// The offer API has party_1 … party_10.
  static const _maxParties = 10;
  late final _parties = <String?>[...?_e?.parties, if (_e == null || _e.parties.isEmpty) null];

  @override
  void dispose() {
    _x.dispose();
    for (final c in [_prefix, _inv, _pkgs, _nett, _total, _gross, _price, _prompt]) {
      c.dispose();
    }
    super.dispose();
  }

  GardenGrade? get _gardenGrade => _garden == null ? null : ref.read(gardenOptionsProvider(_garden!.id)).value?.grade(_grade);

  /// A different garden has its own grades and prefixes, so those reset.
  void _setGarden(MasterItem? g) => setState(() {
        if (g?.id != _garden?.id) {
          _grade = null;
          _prefix.clear();
        }
        _garden = g;
      });

  /// The garden's grade sets the invoice type, as on the website.
  void _setGrade(String g) => setState(() {
        _grade = g;
        _invoiceType = _gardenGrade?.invoiceType ?? _invoiceType;
      });

  Map<String, Object?> _body([String? duplicateAction]) => {
        'date': Fmt.api(_date),
        'garden_id': _garden?.id,
        'garden_name': _garden?.name.startsWith('#') == true ? null : _garden?.name,
        'grade': _grade,
        'grade_id': _gardenGrade?.id,
        'inv_prefix': _prefix.text.trim(),
        'inv_no': _inv.text.trim(),
        'pkgs': Fmt.parse(_pkgs.text),
        'nett': Fmt.parse(_nett.text),
        'ttl_kgs': Fmt.parse(_total.text),
        'gross_weight': Fmt.parse(_gross.text),
        'd_o_packing': _packing == null ? null : Fmt.api(_packing!),
        ..._x.body(),
        // From GET /invoice-types; left out when not chosen.
        'type': _invoiceType,
        'price': Fmt.parse(_price.text),
        'currency': _currency ?? ref.read(formOptionsProvider).value?.initial('currencies'),
        'for': _for,
        'ofr_sas': _ofrSas,
        'courier_name': _courier,
        'prompt_days': int.tryParse(_prompt.text),
        for (final (i, p) in _parties.whereType<String>().where((p) => p.trim().isNotEmpty).indexed) 'party_${i + 1}': p.trim(),
        if (_e == null) 'duplicate_action': duplicateAction,
      };

  Future<void> _save() async {
    final repo = ref.read(offerListsRepositoryProvider);
    final ok = await submit<bool>(
      () async {
        if (_e == null) {
          await repo.create(_body());
        } else {
          await repo.update(_e.id, _body());
        }
        return true;
      },
      clientErrors: {
        if (_garden == null) 'garden_id': 'Choose a garden.',
        if (_inv.text.trim().isEmpty) 'inv_no': 'Enter the invoice number.',
      },
      onDuplicate: (f) async {
        final choice = await chooseAction(
          context,
          title: 'This invoice already exists',
          message: f.serverMessage,
          actions: const {'override': 'Override the existing offer', 'reoffer': 'Re-offer and keep both'},
        );
        if (choice == null) return null;
        return submit<bool>(() async {
          await repo.create(_body(choice));
          return true;
        });
      },
    );
    if (ok == true && mounted) {
      ref.invalidate(offerListsListProvider);
      refreshSummaries(ref);
      context.toast(_e == null ? 'Offer saved' : 'Offer updated');
      if (_e == null) {
        context.pop();
      } else {
        context.goNamed(Routes.offers);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: _e == null ? 'New offer' : 'Edit offer',
      submitLabel: _e == null ? 'Save offer' : 'Save changes',
      submitting: submitting,
      onSubmit: _save,
      children: [
        if (banner != null) FormBanner(banner!),
        GroupedSection(
          label: 'Lot',
          children: [
            DateRow(label: 'Date', value: _date, onChanged: (d) => setState(() => _date = d), error: err('date')),
            MasterPickerRow(label: 'Garden', provider: gardensProvider, searchPath: '/gardens', value: _garden, onChanged: _setGarden, error: err('garden_id')),
            GradePickerRow(gardenId: _garden?.id, value: _grade, onChanged: _setGrade, error: err('grade')),
            InvoiceNumberRow(
              gardenId: _garden?.id,
              invoiceType: _invoiceType,
              prefix: _prefix,
              number: _inv,
              onChanged: () => setState(() {}),
              prefixHint: 'IVP',
              numberHint: '1045',
              prefixError: err('inv_prefix'),
              numberError: err('inv_no'),
            ),
          ],
        ),
        WeightFields(pkgs: _pkgs, nett: _nett, total: _total, errors: errors),
        GroupedSection(
          children: [
            FieldInput(label: 'Gross weight', hint: '720', controller: _gross, suffix: 'kg', keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly),
            DateRow(label: 'Date of packing', value: _packing, onChanged: (d) => setState(() => _packing = d)),
          ],
        ),
        GroupedSection(
          label: 'Price',
          children: [
            FieldInput(label: 'Price per kg', hint: '280.00', controller: _price, suffix: '₹', error: err('price'), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly),
            OptionRow(label: 'Currency', list: 'currencies', value: _currency ?? watchFormOptions(ref).initial('currencies'), error: err('currency'), onChanged: (v) => setState(() => _currency = v)),
            FieldInput(label: 'Prompt days', hint: '14', controller: _prompt, keyboardType: TextInputType.number, inputFormatters: digitsOnly),
          ],
        ),
        GroupedSection(
          label: 'Offer',
          children: [
            OptionRow(label: 'For', list: 'offer_for', value: _for, placeholder: 'Not set', error: err('for'), onChanged: (v) => setState(() => _for = v)),
            OptionRow(label: 'OFR / SAS', list: 'offer_ofr_sas', value: _ofrSas, placeholder: 'Not set', error: err('ofr_sas'), onChanged: (v) => setState(() => _ofrSas = v)),
            OptionRow(label: 'Courier', list: 'courier_companies', value: _courier, placeholder: 'Not set', error: err('courier_name'), onChanged: (v) => setState(() => _courier = v)),
          ],
        ),
        ExtraFieldsSection(controller: _x, errors: errors, onChanged: () => setState(() {})),
        GroupedSection(children: [
          InvoiceTypeRow(value: _invoiceType, error: err('type'), onChanged: (v) => setState(() => _invoiceType = v)),
        ]),
        GroupedSection(
          label: 'Parties',
          footer: const Text('Pick a buyer or type any name. Up to $_maxParties.'),
          children: [
            for (var i = 0; i < _parties.length; i++)
              PartyPickerRow(
                label: 'Party ${i + 1}',
                value: _parties[i],
                onChanged: (v) => setState(() {
                  if (v == null && _parties.length > 1) {
                    _parties.removeAt(i);
                  } else {
                    _parties[i] = v;
                  }
                }),
              ),
          ],
        ),
        if (_parties.length < _maxParties)
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              label: 'Add party',
              icon: AppIcons.add,
              onPressed: () => setState(() => _parties.add(null)),
            ),
          ),
      ],
    );
  }
}

class OfferDetailScreen extends ConsumerWidget {
  const OfferDetailScreen({super.key, required this.offer});
  final OfferList? offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = watchFormOptions(ref);
    final o = offer;
    if (o == null) return const MissingItemScreen(what: 'offer');
    return DetailScaffold(
      title: o.gardenName ?? 'Offer',
      actions: [
        LinkButton(label: 'Edit', onPressed: () => context.pushNamed(Routes.offerEdit, pathParameters: {'id': '${o.id}'}, extra: o)),
      ],
      children: [
        GroupedSection(
          label: 'Lot',
          children: [
            InfoRow('Date', Fmt.day(o.date)),
            InfoRow('Grade', o.grade),
            InfoRow('Invoice', Fmt.invoice(o.invPrefix, o.invNo)),
            InfoRow('Type', o.type),
          ],
        ),
        GroupedSection(
          label: 'Weight',
          children: [
            InfoRow('Packages', Fmt.number(o.pkgs)),
            InfoRow('Nett per package', Fmt.kg(o.nett)),
            InfoRow('Total', Fmt.kg(o.totalKgs)),
            InfoRow('Gross weight', Fmt.kg(o.grossWeight)),
            InfoRow('Date of packing', Fmt.day(o.packingDate)),
          ],
        ),
        GroupedSection(
          label: 'Price',
          children: [
            InfoRow('Price per kg', Fmt.money(o.price)),
            InfoRow('Prompt days', o.promptDays?.toString()),
            InfoRow('Currency', J.str(o.raw['currency'])),
            InfoRow('For', options.label('offer_for', J.str(o.raw['for']))),
            InfoRow('OFR / SAS', options.label('offer_ofr_sas', J.str(o.raw['ofr_sas']))),
            InfoRow('Courier', options.label('courier_companies', J.str(o.raw['courier_name']))),
          ],
        ),
        if (o.parties.isNotEmpty)
          GroupedSection(label: 'Parties', children: [for (final (i, p) in o.parties.indexed) InfoRow('Party ${i + 1}', p)]),
        if (o.buyers.isNotEmpty)
          GroupedSection(label: 'Allocated buyers', children: [for (final b in o.buyers) InfoRow(b, null)]),
        if (extraInfoRows(kOfferExtraFields, o.raw).isNotEmpty) GroupedSection(label: 'More details', children: extraInfoRows(kOfferExtraFields, o.raw)),
        DeleteRecordButton(
          what: 'offer',
          name: '${o.title} (${Fmt.invoice(o.invPrefix, o.invNo)})',
          onDelete: (ref) => ref.read(offerListsRepositoryProvider).delete(o.id),
          onDeleted: (ref) => ref.invalidate(offerListsListProvider),
        ),
      ],
    );
  }
}
