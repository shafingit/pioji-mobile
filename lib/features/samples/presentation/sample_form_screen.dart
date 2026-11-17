import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/weight_fields.dart';
import '../../../core/widgets/detail.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters_repository.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/samples_repository.dart';
import '../domain/sample.dart';
import '../../../core/widgets/extra_fields.dart';


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
  late String _type = (_e?.sampleType ?? 'original').toLowerCase();
  late String? _forCompany = _e?.forCompany;
  late MasterItem? _party = _e?.partyId == null ? null : MasterItem(_e!.partyId!, _e.partyName ?? '#${_e.partyId}');
  late SampleStatus _status =
      _e == null || _e.status == SampleStatus.unknown ? SampleStatus.received : _e.status;
  late final _prefix = TextEditingController(text: _e?.invoicePrefix);
  late final _inv = TextEditingController(text: _e?.invoiceNo);
  late final _pkgs = TextEditingController(text: _e?.packages?.toString());
  late final _nett = TextEditingController(text: Fmt.editable(_e?.weight));
  late final _total = TextEditingController(text: Fmt.editable(_e?.totalKgs));
  late final _remarks = TextEditingController(text: _e?.remarks);

  @override
  void dispose() {
    _x.dispose();
    for (final c in [_prefix, _inv, _pkgs, _nett, _total, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _body({bool duplicate = false}) => {
        ..._x.body(),
        'arrival_date': Fmt.api(_arrival),
        'garden_id': _garden?.id,
        'grade': _grade,
        'invoice_prefix': _prefix.text.trim(),
        'inv_no': _inv.text.trim(),
        'packages': int.tryParse(_pkgs.text),
        'weight': Fmt.parse(_nett.text),
        'total_kgs': Fmt.parse(_total.text),
        'sample_type': _type,
        'for_company': _forCompany,
        'party_id': _party?.id,
        'status': _status.api,
        'remarks': _remarks.text.trim(),
        if (duplicate) 'is_duplicate': true,
      };

  Future<void> _save() async {
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
      context.toast(_e == null ? 'Sample saved' : 'Sample updated');
      // After an edit, go back to the list so the detail isn't stale.
      if (_e == null) {
        context.pop();
      } else {
        context.goNamed(Routes.samples);
      }
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
            MasterPickerRow(label: 'Garden', provider: gardensProvider, searchPath: '/gardens', value: _garden, onChanged: (g) => setState(() => _garden = g), error: err('garden_id')),
            GradePickerRow(gardenId: _garden?.id, value: _grade, onChanged: (g) => setState(() => _grade = g), error: err('grade')),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: FieldInput(label: 'Prefix', hint: 'SMP', controller: _prefix, error: err('invoice_prefix'), textCapitalization: TextCapitalization.characters),
                ),
                Expanded(child: FieldInput(label: 'Invoice no', hint: '2048', controller: _inv, error: err('inv_no'))),
              ],
            ),
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
                  Segmented<String>(
                    compact: true,
                    options: const {'original': 'Original', 'standard': 'Standard'},
                    selected: _type,
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ],
              ),
            ),
            _ForCompanyRow(value: _forCompany, error: err('for_company'), onChanged: (v) => setState(() => _forCompany = v)),
            MasterPickerRow(
              label: 'Party (outgoing)',
              placeholder: 'None',
              provider: buyersProvider,
              value: _party,
              onChanged: (b) => setState(() => _party = b),
              error: err('party_id'),
            ),
            ValueRow(
              label: 'Status',
              value: _status.label,
              onTap: () async {
                final s = await showPickerSheet<SampleStatus>(
                  context,
                  title: 'Status',
                  selected: _status,
                  options: [for (final s in SampleStatus.pickable) PickOption(s, s.label)],
                );
                if (s != null) setState(() => _status = s);
              },
            ),
            FieldInput(label: 'Remarks', hint: 'Clean liquor sample', controller: _remarks, maxLines: 3, error: err('remarks')),
          ],
        ),
      ],
    );
  }
}

/// Who the sample is for: one billing company (by code) or all of them.
class _ForCompanyRow extends ConsumerWidget {
  const _ForCompanyRow({required this.value, required this.onChanged, this.error});
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(billingCompaniesProvider).value ?? const [];
    String? shown = value == 'all' ? 'All companies' : value;
    for (final c in companies) {
      if (c.code == value) shown = c.name;
    }
    return ValueRow(
      label: 'For',
      value: shown,
      placeholder: 'Not set',
      error: error,
      onTap: () async {
        final list = await ref.read(billingCompaniesProvider.future);
        if (!context.mounted) return;
        final picked = await showPickerSheet<String>(
          context,
          title: 'Sample is for',
          selected: value,
          options: [
            const PickOption('', 'Not set'),
            const PickOption('all', 'All companies'),
            for (final c in list) PickOption(c.code, c.name, subtitle: c.code == c.name ? null : c.code),
          ],
        );
        if (picked != null) onChanged(picked.isEmpty ? null : picked);
      },
    );
  }
}
