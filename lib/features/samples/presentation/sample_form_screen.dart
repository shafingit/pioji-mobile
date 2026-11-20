import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/weight_fields.dart';
import '../../../core/widgets/detail.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/form_options.dart';
import '../../masters/data/masters_repository.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/samples_repository.dart';
import '../domain/sample.dart';
import '../../../core/widgets/extra_fields.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/storage/prefs.dart';


/// Website form fields the API saves (dropdowns load from their own APIs).
const kSampleExtraFields = <ExtraField>[
  ExtraField('gross_weight', 'Gross weight', ExtraKind.number, suffix: 'kg'),
  ExtraField('d_o_packing', 'Date of packing', ExtraKind.date),
  ExtraField('requests_purchased_sample', 'Requests purchased sample', ExtraKind.flag),
];

class SampleFormScreen extends ConsumerStatefulWidget {
  const SampleFormScreen({super.key, this.editing});

  /// The sample to edit; null creates a new one.
  final Sample? editing;

  @override
  ConsumerState<SampleFormScreen> createState() => _SampleFormScreenState();
}

class _SampleFormScreenState extends ConsumerState<SampleFormScreen> with FormSubmit {
  late final _x = ExtraFieldsController(kSampleExtraFields, widget.editing?.raw ?? const {});
  late final Sample? _e = widget.editing;
  late DateTime _arrival = _e?.arrivalDate ?? DateTime.now();

  late MasterItem? _garden =
      _e?.gardenId == null ? null : MasterItem(_e!.gardenId!, _e.gardenName ?? '#${_e.gardenId}');
  late String? _grade = _e?.grade;

  /// The invoice type picked with the prefix ("D · Dust"); narrows grades.
  String? _lotType;
  late String? _type = _e?.sampleType?.toLowerCase();
  late String? _forCompany = _e?.forCompany;
  late MasterItem? _party = _e?.partyId == null ? null : MasterItem(_e!.partyId!, _e.partyName ?? '#${_e.partyId}');
  late String? _status = _e?.status;
  late final _prefix = TextEditingController(text: _e?.invoicePrefix);
  late final _inv = TextEditingController(text: _e?.invoiceNo);
  late final _pkgs = TextEditingController(text: _e?.packages?.toString());
  late final _nett = TextEditingController(text: Fmt.editable(_e?.weight));
  late final _total = TextEditingController(text: Fmt.editable(_e?.totalKgs));
  late final _remarks = TextEditingController(text: _e?.remarks);

  late final _last = ref.read(lastUsedProvider('sample'));

  @override
  void initState() {
    super.initState();
    if (_e == null) {
      // Start from the user's last sample.
      _type = _last['sample_type'];
      _forCompany = _last['for_company'];
      final partyId = int.tryParse(_last['party_id'] ?? '');
      if (partyId != null) _party = MasterItem(partyId, _last['party_name'] ?? '#$partyId');
    }
  }

  @override
  void dispose() {
    _x.dispose();
    for (final c in [_prefix, _inv, _pkgs, _nett, _total, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The chosen grade as the garden has it set up (id and invoice type).
  GardenGrade? get _gardenGrade => _garden == null ? null : ref.read(gardenOptionsProvider(_garden!.id)).value?.grade(_grade);

  /// The grade and prefix as the API takes them: a value the garden has no
  /// set-up for goes as "Other" with the typed text (`grade_custom`,
  /// `invoice_prefix_custom`), as on the website.
  Map<String, Object?> _gradeAndPrefix() {
    final options = _garden == null ? null : ref.read(gardenOptionsProvider(_garden!.id)).value;
    final prefix = _prefix.text.trim();
    final otherGrade = options != null && _grade != null && options.grade(_grade) == null;
    final otherPrefix = options != null && prefix.isNotEmpty && !options.prefixesFor(null).contains(prefix);
    return {
      'grade': otherGrade ? 'Other' : _grade,
      if (otherGrade) 'grade_custom': _grade,
      'grade_id': _gardenGrade?.id,
      'invoice_prefix': otherPrefix ? 'Other' : prefix,
      if (otherPrefix) 'invoice_prefix_custom': prefix,
    };
  }

  /// A different garden has its own grades and prefixes, so those reset.
  void _setGarden(MasterItem? g) => setState(() {
        if (g?.id != _garden?.id) {
          _grade = null;
          _lotType = null;
          _prefix.clear();
        }
        _garden = g;
      });

  /// Set when the user saves knowingly over an earlier sample of this lot.
  int? _parentId;

  Map<String, Object?> _body({bool duplicate = false}) => {
        ..._x.body(),
        'arrival_date': Fmt.api(_arrival),
        'garden_id': _garden?.id,
        ..._gradeAndPrefix(),
        'inv_no': _inv.text.trim(),
        'packages': int.tryParse(_pkgs.text),
        'weight': Fmt.parse(_nett.text),
        'total_kgs': Fmt.parse(_total.text),
        'sample_type': _type ?? ref.read(formOptionsProvider).value?.initial('sample_types'),
        'for_company': _forCompany,
        'party_id': _party?.id,
        'status': _status,
        'remarks': _remarks.text.trim(),
        if (duplicate || _parentId != null) 'is_duplicate': true,
        'parent_sample_id': _parentId ?? J.integer(_e?.raw['parent_sample_id']),
      };

  /// Warns, like the website, when this garden, grade, prefix and invoice
  /// were already received. Returns false to stop saving.
  Future<bool> _checkDuplicates() async {
    final garden = _garden?.name, inv = _inv.text.trim();
    if (garden == null || garden.startsWith('#') || inv.isEmpty) return true;
    final repo = ref.read(samplesRepositoryProvider);
    final found = (await repo.duplicates(gardenName: garden, grade: _grade, prefix: _prefix.text.trim(), invoiceNo: inv))
        .where((d) => d.id != _e?.id)
        .toList();
    if (found.isEmpty || !mounted) {
      _parentId = null;
      return true;
    }
    final ok = await confirm(
      context,
      title: 'Already received',
      body: 'This lot matches ${found.length == 1 ? 'an earlier sample' : '${found.length} earlier samples'}:\n${found.take(3).map((d) => d.label).join('\n')}\n\nSave this one as a duplicate?',
      action: 'Save as duplicate',
    );
    _parentId = ok ? found.first.id : null;
    return ok;
  }

  /// [another]: keep the date, garden, prefix and details and clear the
  /// lot, ready for the next sample from the same garden.
  Future<void> _save({bool another = false}) async {
    if (_e == null && !await _checkDuplicates()) return;
    if (!mounted) return;
    final repo = ref.read(samplesRepositoryProvider);
    final ok = await submit<bool>(
      () async {
        if (_e == null) {
          await repo.create(_body());
        } else {
          await repo.update(_e.id, _body());
        }
        return true;
      },
      onDuplicate: (f) async {
        final again = await confirm(
          context,
          title: 'This invoice already exists',
          body: '${f.serverMessage}\n\nSave this sample anyway?',
          action: 'Save anyway',
        );
        if (!again) return null;
        return submit<bool>(() async {
          if (_e == null) {
            await repo.create(_body(duplicate: true));
          } else {
            await repo.update(_e.id, _body(duplicate: true));
          }
          return true;
        });
      },
    );
    if (ok == true && mounted) {
      ref.invalidate(samplesListProvider);
      refreshSummaries(ref);
      if (_e != null) {
        context.toast('Sample updated');
        // After an edit, go back to the list so the detail isn't stale.
        context.goNamed(Routes.samples);
        return;
      }
      await _last.save({
        'sample_type': _type,
        'for_company': _forCompany,
        'party_id': _party?.id,
        'party_name': _party?.name,
      });
      if (!mounted) return;
      if (!another) {
        context.toast('Sample saved');
        context.pop();
        return;
      }
      setState(() {
        _grade = null;
        _parentId = null;
        for (final c in [_inv, _pkgs, _nett, _total, _remarks]) {
          c.clear();
        }
        _x.text['gross_weight']!.clear();
        _x.dates['d_o_packing'] = null;
        _x.flags['requests_purchased_sample'] = false;
      });
      context.toast('Sample saved. Enter the next one.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: _e == null ? 'New sample' : 'Edit sample',
      submitLabel: _e == null ? 'Save sample' : 'Save changes',
      submitting: submitting,
      onSubmit: _save,
      children: [
        if (banner != null) FormBanner(banner!),
        GroupedSection(
          label: 'Lot',
          children: [
            // Without `samples.edit_arrival_date` the arrival date is today and
            // can't be changed (the server enforces it too).
            if (ref.watch(currentUserProvider)?.can('samples.edit_arrival_date') ?? true)
              DateRow(label: 'Arrival date', value: _arrival, onChanged: (d) => setState(() => _arrival = d), error: err('arrival_date'))
            else
              InfoRow('Arrival date', '${Fmt.day(_arrival)} · locked'),
            MasterPickerRow(label: 'Garden', provider: gardensProvider, searchPath: '/gardens', value: _garden, onChanged: _setGarden, error: err('garden_id')),
            InvoiceNumberRow(
              gardenId: _garden?.id,
              invoiceType: _lotType ?? (ref.watch(typeLinksProvider).value ?? TypeLinks.empty).gradeType(_grade) ?? _gardenGrade?.invoiceType,
              grade: _grade,
              prefix: _prefix,
              number: _inv,
              showNumber: false,
              onChanged: () => setState(() {}),
              onTypeChanged: (t) => setState(() => _lotType = t),
              onGradeChanged: (g) => setState(() => _grade = g),
              prefixError: err('invoice_prefix'),
              needsGarden: true,
            ),
            GradePickerRow(
              gardenId: _garden?.id,
              prefix: _prefix.text,
              invoiceType: _lotType,
              needsGarden: true,
              value: _grade,
              onChanged: (g) => setState(() => _grade = g),
              error: err('grade'),
            ),
            FieldInput(label: 'Invoice no', hint: '2048', controller: _inv, error: err('inv_no')),
          ],
        ),
        WeightFields(
          pkgs: _pkgs,
          nett: _nett,
          total: _total,
          errors: errors,
          keys: (pkgs: 'packages', nett: 'weight', total: 'total_kgs'),
        ),
        ExtraFieldsSection(controller: _x, errors: errors, onChanged: () => setState(() {})),
        GroupedSection(
          label: 'Details',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Sample type')),
                  OptionSegments(compact: true, list: 'sample_types', value: _type, onChanged: (v) => setState(() => _type = v)),
                ],
              ),
            ),
            OptionChipsRow(label: 'For', list: 'offer_for', value: _forCompany, error: err('for_company'), onChanged: (v) => setState(() => _forCompany = v)),
            MasterPickerRow(
              label: 'Party (outgoing)',
              placeholder: 'None',
              provider: buyersProvider,
              value: _party,
              onChanged: (b) => setState(() => _party = b),
              error: err('party_id'),
            ),
            OptionRow(label: 'Status', list: 'sample_statuses', value: _status, error: err('status'), onChanged: (v) => setState(() => _status = v)),
            FieldInput(label: 'Remarks', hint: 'Clean liquor sample', controller: _remarks, maxLines: 3, error: err('remarks')),
          ],
        ),
        if (_e == null)
          SecondaryButton(
            label: 'Save and add another',
            icon: AppIcons.add,
            onPressed: submitting ? null : () => _save(another: true),
          ),
      ],
    );
  }
}

