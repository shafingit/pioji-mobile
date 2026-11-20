import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/states.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/sheets.dart';
import '../../masters/data/form_options.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/samples_repository.dart';
import '../domain/sample.dart';
import '../../../core/widgets/detail.dart';

/// Records or edits a sample's tasting: seven scores from 0 to 10 and
/// comments (`POST /samples/{id}/tasting`).
class TastingFormScreen extends ConsumerStatefulWidget {
  const TastingFormScreen({super.key, required this.sample});
  final Sample? sample;

  @override
  ConsumerState<TastingFormScreen> createState() => _TastingFormScreenState();
}

class _TastingFormScreenState extends ConsumerState<TastingFormScreen> with FormSubmit {
  late final Sample? _s = widget.sample;
  late final _scores = {
    for (final k in Sample.scoreFields.keys) k: TextEditingController(text: Fmt.editable(_s?.scores[k])),
  };
  late final _comments = TextEditingController(text: _s?.comments);

  @override
  void dispose() {
    for (final c in [..._scores.values, _comments]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    final client = <String, String>{
      for (final e in _scores.entries)
        if (e.value.text.trim().isNotEmpty && ((Fmt.parse(e.value.text) ?? -1) < 0 || (Fmt.parse(e.value.text) ?? 11) > 10))
          e.key: 'Enter a score from 0 to 10.',
    };
    final ok = await submit<bool>(
      () async {
        await ref.read(samplesRepositoryProvider).saveTasting(s.id, {
          for (final e in _scores.entries) e.key: Fmt.parse(e.value.text),
          'evaluation_comments': _comments.text.trim(),
        });
        return true;
      },
      clientErrors: client,
    );
    if (ok == true && mounted) {
      ref.invalidate(samplesListProvider);
      refreshSummaries(ref);
      context.toast('Tasting saved');
      context.goNamed(Routes.samples);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const MissingItemScreen(what: 'sample');
    final keys = Sample.scoreFields.keys.toList();
    return FormScaffold(
      title: s.isTasted ? 'Edit tasting' : 'Tasting',
      submitLabel: 'Save tasting',
      submitting: submitting,
      onSubmit: _save,
      children: [
        if (banner != null) FormBanner(banner!),
        GroupedSection(
          label: '${s.title} · ${Fmt.invoice(s.invoicePrefix, s.invoiceNo)}',
          footer: const Text('Scores are 0 to 10. The overall score is worked out on the server.'),
          children: [
            for (var i = 0; i < keys.length; i += 2)
              Row(
                children: [
                  for (final k in keys.skip(i).take(2))
                    Expanded(
                      child: FieldInput(
                        label: Sample.scoreFields[k]!,
                        hint: '0–10',
                        controller: _scores[k]!,
                        error: err(k),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: decimalOnly,
                      ),
                    ),
                  if (i + 1 >= keys.length) const Expanded(child: SizedBox()),
                ],
              ),
          ],
        ),
        GroupedSection(
          children: [
            FieldInput(label: 'Comments', hint: 'Bright liquor, good strength', controller: _comments, maxLines: 4, error: err('evaluation_comments')),
          ],
        ),
      ],
    );
  }
}

/// Tasting card on the sample detail: scores when tasted, park state, and
/// the actions to record a tasting and park or unpark.
class SampleTastingSection extends ConsumerStatefulWidget {
  const SampleTastingSection({super.key, required this.sample});
  final Sample sample;

  @override
  ConsumerState<SampleTastingSection> createState() => _SampleTastingSectionState();
}

class _SampleTastingSectionState extends ConsumerState<SampleTastingSection> {
  late bool _parked = widget.sample.isParked;
  late bool _forTasting = J.boolOr(widget.sample.raw['mark_for_tasting'], false);
  late bool _direct = J.boolOr(widget.sample.raw['direct_allocation'], false);
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AppFailure catch (f) {
      if (mounted) context.toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `POST /samples/bulk-mark` with a mode the user picks from
  /// `form-options` → `sample_bulk_mark_modes`.
  Future<void> _mark() async {
    final options = await readFormOptions(ref);
    if (!mounted) return;
    final mode = await showPickerSheet<String>(
      context,
      title: 'Mark sample',
      searchable: false,
      options: [for (final m in options['sample_bulk_mark_modes']) PickOption(m.value, m.label)],
    );
    if (mode == null || !mounted) return;
    await _run(() async {
      final message = await ref.read(samplesRepositoryProvider).bulkMark([widget.sample.id], mode);
      final fresh = await ref.read(samplesRepositoryProvider).get(widget.sample.id);
      if (!mounted) return;
      setState(() {
        _forTasting = J.boolOr(fresh.raw['mark_for_tasting'], false);
        _direct = J.boolOr(fresh.raw['direct_allocation'], false);
      });
      ref.invalidate(samplesListProvider);
      refreshSummaries(ref);
      context.toast(message ?? 'Sample marked');
    });
  }

  /// Sends a tasted, batched sample for retesting with a reason from
  /// `form-options` → `sample_transfer_reasons`; the server makes a new
  /// sample from 10 g of it.
  Future<void> _retest() async {
    final options = await readFormOptions(ref);
    if (!mounted) return;
    final reason = await showPickerSheet<String>(
      context,
      title: 'Reason for retesting',
      searchable: false,
      options: [for (final r in options['sample_transfer_reasons']) PickOption(r.value, r.label)],
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      final message = await ref.read(samplesRepositoryProvider).transfer(widget.sample.id, reason);
      ref.invalidate(samplesListProvider);
      refreshSummaries(ref);
      if (mounted) context.toast(message ?? 'Sent for retesting');
    });
  }

  Future<void> _togglePark() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(samplesRepositoryProvider);
      _parked ? await repo.unpark(widget.sample.id) : await repo.park(widget.sample.id);
      if (!mounted) return;
      setState(() => _parked = !_parked);
      ref.invalidate(samplesListProvider);
      context.toast(_parked ? 'Sample parked' : 'Sample unparked');
    } catch (_) {
      if (mounted) context.toast("Couldn't update. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sample;
    final c = context.colors;
    return GroupedSection(
      label: 'Tasting',
      children: [
        if (s.isTasted) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Text('Overall', style: AppText.body),
                const Spacer(),
                Text(s.overallScore == null ? '–' : Fmt.editable(s.overallScore), style: AppText.metric.copyWith(color: c.accent)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                for (final e in Sample.scoreFields.entries)
                  if (s.scores[e.key] != null)
                    Text('${e.value} ${Fmt.editable(s.scores[e.key])}', style: AppText.footnote.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          if (s.comments != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(s.comments!, style: AppText.callout),
            ),
          if (s.evaluatedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                ['Tasted ${Fmt.day(s.evaluatedAt)}', ?s.evaluatedBy].join(' · '),
                style: AppText.footnote.copyWith(color: c.textTertiary),
              ),
            ),
        ],
        AppListRow(
          title: s.isTasted ? 'Edit tasting' : 'Record tasting',
          titleStyle: AppText.body.copyWith(color: c.accent),
          minHeight: 48,
          showChevron: true,
          onTap: () => context.pushNamed(Routes.sampleTasting, pathParameters: {'id': '${s.id}'}, extra: s),
        ),
        AppListRow(
          title: _parked ? 'Unpark sample' : 'Park sample',
          titleStyle: AppText.body.copyWith(color: _parked ? c.accent : c.textPrimary),
          minHeight: 48,
          trailing: _busy ? const AppSpinner(size: 18) : (_parked ? Text('Parked', style: AppText.footnote.copyWith(color: c.warning)) : null),
          onTap: _busy ? null : _togglePark,
        ),
        AppListRow(
          title: 'Mark sample',
          titleStyle: AppText.body,
          minHeight: 48,
          trailing: Text(
            [if (_forTasting) 'For tasting', if (_direct) 'Direct allocation'].join(' · '),
            style: AppText.footnote.copyWith(color: c.success),
          ),
          showChevron: true,
          onTap: _busy ? null : _mark,
        ),
        if (s.isTasted && s.batchRef != null)
          AppListRow(
            title: 'Send for retesting',
            titleStyle: AppText.body,
            minHeight: 48,
            showChevron: true,
            onTap: _busy ? null : _retest,
          ),
      ],
    );
  }
}

/// `GET /reports/tasting`: tasted samples by date range and mark, best
/// overall score first.
class TastingReportScreen extends ConsumerStatefulWidget {
  const TastingReportScreen({super.key});

  @override
  ConsumerState<TastingReportScreen> createState() => _TastingReportScreenState();
}

class _TastingReportScreenState extends ConsumerState<TastingReportScreen> {
  DateTime? _from;
  DateTime? _to;
  ({String value, String label})? _mark;
  late Future<List<Sample>> _future = _load();

  Future<List<Sample>> _load() => ref.read(samplesRepositoryProvider).tastingReport({
        'from': _from == null ? null : Fmt.api(_from!),
        'to': _to == null ? null : Fmt.api(_to!),
        'garden_id': _mark?.value,
        'per_page': 200,
      });

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScaffold(
      title: 'Tasting report',
      inTabs: false,
      onRefresh: () async {
        _reload();
        await _future.catchError((_) => <Sample>[]);
      },
      header: [
        GroupedSection(
          children: [
            DateRow(label: 'From', placeholder: 'Any', value: _from, onChanged: (d) => setState(() => (_from = d, _future = _load()))),
            DateRow(label: 'To', placeholder: 'Any', value: _to, onChanged: (d) => setState(() => (_to = d, _future = _load()))),
            ValueRow(
              label: 'Mark',
              value: _mark?.label,
              placeholder: 'Any',
              onTap: () async {
                final m = await pickMark(context);
                if (m != null) setState(() => (_mark = m, _future = _load()));
              },
            ),
          ],
        ),
        if (_from != null || _to != null || _mark != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => (_from = null, _to = null, _mark = null, _future = _load())),
              child: const Text('Clear filters'),
            ),
          ),
        const SizedBox(height: AppSpace.md),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: FutureBuilder<List<Sample>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingBlock(height: 160);
              if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
              final list = [...?snap.data]..sort((a, b) => (b.overallScore ?? -1).compareTo(a.overallScore ?? -1));
              if (list.isEmpty) {
                return const EmptyState(
                  icon: AppIcons.samples,
                  title: 'No tasted samples',
                  body: 'Samples show up here once their tasting is recorded.',
                );
              }
              return GroupedSection(
                label: '${list.length} ${list.length == 1 ? 'sample' : 'samples'}',
                children: [
                  for (final s in list)
                    AppListRow(
                      title: s.title,
                      subtitle: [
                        Fmt.invoice(s.invoicePrefix, s.invoiceNo),
                        if (s.arrivalDate != null) Fmt.dayShort(s.arrivalDate),
                        if (s.isParked) 'Parked',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      minHeight: 56,
                      onTap: () => context.pushNamed(Routes.sampleDetail, pathParameters: {'id': '${s.id}'}),
                      trailing: Text(
                        s.overallScore == null ? '–' : Fmt.editable(s.overallScore),
                        style: AppText.headline.copyWith(color: c.accent, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
