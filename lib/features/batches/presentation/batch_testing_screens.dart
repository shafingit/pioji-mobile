import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/detail.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_badge.dart';
import '../../masters/data/form_options.dart';
import '../../samples/data/samples_repository.dart';
import '../data/batch_testing.dart';
import '../data/batches_repository.dart';

/// Batch detail section: status, testing (start, continue, results) and the
/// samples export.
class BatchActionsSection extends ConsumerStatefulWidget {
  const BatchActionsSection({super.key, required this.batch});
  final Batch batch;

  @override
  ConsumerState<BatchActionsSection> createState() => _BatchActionsSectionState();
}

class _BatchActionsSectionState extends ConsumerState<BatchActionsSection> {
  late String? _status = widget.batch.status;
  bool _busy = false;

  Batch get _b => widget.batch;

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

  Future<void> _setStatus(String s) => _run(() async {
        await ref.read(batchTestingRepositoryProvider).setStatus(_b.id, s);
        if (!mounted) return;
        setState(() => _status = s);
        ref.invalidate(batchesListProvider);
        refreshSummaries(ref);
        context.toast('Status changed to ${ref.read(formOptionsProvider).value?.label('batch_statuses', s) ?? s}');
      });

  /// Testers are the points of contact (`form-options` → `pocs`).
  Future<void> _start() async {
    final FormOptions options;
    try {
      options = await readFormOptions(ref);
    } catch (e) {
      if (mounted) context.toast(e is AppFailure ? e.message : "Couldn't load the testers. Try again.");
      return;
    }
    if (!mounted) return;
    final pocs = options['pocs'];
    final picked = await showMultiPickerSheet<int>(
      context,
      title: 'Testers',
      selected: const {},
      options: [
        for (final p in pocs)
          if (int.tryParse(p.value) case final id?) PickOption(id, p.label, subtitle: p.extra['designation']?.toString()),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _run(() async {
      await ref.read(batchTestingRepositoryProvider).initiate(_b.id, picked.toList());
      ref.invalidate(testingSessionProvider(_b.id));
      if (mounted) context.pushNamed(Routes.batchTesting, pathParameters: {'id': '${_b.id}'}, extra: _b.name);
    });
  }

  Future<void> _export() => _run(() async {
        final path = await ref.read(batchTestingRepositoryProvider).export(batchId: _b.id);
        await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: 'text/csv')]));
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = ref.watch(testingSessionProvider(_b.id));
    final open = session.value;
    final testing = open != null && !open.allTested;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedSection(
          children: [
            OptionRow(label: 'Status', list: 'batch_statuses', value: _status, onChanged: _setStatus),
          ],
        ),
        const SizedBox(height: AppSpace.lg + 2),
        GroupedSection(
          label: 'Testing',
          footer: Text(testing
              ? '${Fmt.number(open.progress)}% tested by ${open.testers.map((t) => t.name).join(', ')}.'
              : 'Testers score each sample 0–100 for C, T, S and B.'),
          children: [
            if (session.isLoading)
              const Padding(padding: EdgeInsets.all(AppSpace.md), child: Center(child: AppSpinner()))
            else if (testing)
              AppListRow(
                title: 'Continue testing',
                titleStyle: AppText.body.copyWith(color: c.accent),
                showChevron: true,
                onTap: () => context.pushNamed(Routes.batchTesting, pathParameters: {'id': '${_b.id}'}, extra: _b.name),
              )
            else
              AppListRow(
                title: _busy ? 'Starting…' : 'Start testing',
                titleStyle: AppText.body.copyWith(color: c.accent),
                showChevron: true,
                onTap: _busy || _b.count == 0 ? null : _start,
              ),
            AppListRow(
              title: 'Results',
              titleStyle: AppText.body,
              showChevron: true,
              onTap: () => context.pushNamed(Routes.batchResults, pathParameters: {'id': '${_b.id}'}, extra: _b.name),
            ),
            AppListRow(
              title: 'Export samples',
              titleStyle: AppText.body,
              trailing: _busy ? const AppSpinner(size: 16) : null,
              onTap: _busy ? null : _export,
            ),
          ],
        ),
      ],
    );
  }
}

/// Scores the current sample of a batch's testing session, one row of
/// C / T / S / B per tester, then moves to the next sample.
class TestingSessionScreen extends ConsumerStatefulWidget {
  const TestingSessionScreen({super.key, required this.batchId, this.batchName});
  final int batchId;
  final String? batchName;

  @override
  ConsumerState<TestingSessionScreen> createState() => _TestingSessionScreenState();
}

class _TestingSessionScreenState extends ConsumerState<TestingSessionScreen> with FormSubmit {
  static const _letters = ['C', 'T', 'S', 'B'];

  /// Inputs per tester id, per letter; rebuilt for each sample.
  final _inputs = <int, Map<String, TextEditingController>>{};

  /// Colour, leaf, report and CH choices per tester id.
  final _extras = <int, Map<String, String>>{};
  final _remarks = TextEditingController();
  int? _forResult;

  @override
  void dispose() {
    _clearInputs();
    _remarks.dispose();
    super.dispose();
  }

  void _clearInputs() {
    for (final m in _inputs.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _inputs.clear();
    _extras.clear();
  }

  /// New inputs when the session moves to another sample.
  void _prepare(TestingSession s) {
    final current = s.current;
    if (current == null || current.id == _forResult) return;
    _clearInputs();
    _remarks.text = current.remarks ?? '';
    for (final t in s.testers) {
      final existing = current.scores.where((x) => x.testerId == t.id).firstOrNull;
      _extras[t.id] = {...?existing?.extras};
      _inputs[t.id] = {
        for (final l in _letters)
          l: TextEditingController(text: existing == null ? '' : Fmt.editable(switch (l) { 'C' => existing.c, 'T' => existing.t, 'S' => existing.s, _ => existing.b })),
      };
    }
    _forResult = current.id;
  }

  Future<void> _save(TestingSession s) async {
    final missing = <String, String>{};
    final scores = <TesterScore>[];
    for (final t in s.testers) {
      final m = _inputs[t.id]!;
      final v = {for (final l in _letters) l: Fmt.parse(m[l]!.text)};
      for (final l in _letters) {
        final x = v[l];
        if (x == null || x < 0 || x > 100) missing['${t.id}.$l'] = '0–100';
      }
      scores.add(TesterScore(testerId: t.id, c: v['C'] ?? 0, t: v['T'] ?? 0, s: v['S'] ?? 0, b: v['B'] ?? 0, extras: {..._extras[t.id]!}));
    }
    final hasNext = await submit<bool>(
      () => ref.read(batchTestingRepositoryProvider).saveScores(widget.batchId, scores, remarks: _remarks.text.trim()),
      clientErrors: missing,
    );
    if (hasNext == null || !mounted) return;
    ref.invalidate(testingResultsProvider(widget.batchId));
    ref.invalidate(samplesListProvider);
    if (hasNext) {
      context.toast('Scores saved');
      ref.invalidate(testingSessionProvider(widget.batchId));
    } else {
      ref.invalidate(testingSessionProvider(widget.batchId));
      ref.invalidate(batchesListProvider);
      refreshSummaries(ref);
      context.toast('All samples tested');
      context.pushReplacementNamed(Routes.batchResults, pathParameters: {'id': '${widget.batchId}'}, extra: widget.batchName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(testingSessionProvider(widget.batchId));
    final s = async.value;
    if (s == null) {
      return PageScaffold(
        title: 'Testing',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: async.isLoading
                ? const Center(child: AppSpinner())
                : async.hasError
                    ? ErrorState(error: async.error!, onRetry: () => ref.invalidate(testingSessionProvider(widget.batchId)))
                    : const EmptyState(icon: AppIcons.batches, title: 'No testing session', body: 'Start testing from the batch page.'),
          ),
        ],
      );
    }
    _prepare(s);
    final current = s.current;
    final c = context.colors;
    final position = current == null ? null : s.samples.indexWhere((x) => x.id == current.id) + 1;
    return FormScaffold(
      title: widget.batchName ?? 'Testing',
      submitLabel: 'Save and next',
      submitting: submitting,
      onSubmit: current == null ? null : () => _save(s),
      children: [
        if (banner != null) FormBanner(banner!),
        if (current == null)
          const EmptyState(icon: AppIcons.batches, title: 'All samples tested', body: 'See the results from the batch page.')
        else ...[
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(current.title ?? current.sampleCode ?? 'Sample', style: AppText.headline)),
                  if (position != null && position > 0) Text('$position of ${s.samples.length}', style: AppText.callout.copyWith(color: c.textSecondary)),
                ]),
                const SizedBox(height: 4),
                Text([?current.invoice, ?current.sampleCode].join(' · '), style: AppText.callout.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          for (final t in s.testers)
            GroupedSection(
              label: t.name,
              children: [
                Row(children: [
                  for (final l in _letters)
                    Expanded(
                      child: FieldInput(
                        label: l,
                        hint: '0–100',
                        controller: _inputs[t.id]![l]!,
                        error: err('${t.id}.$l'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: decimalOnly,
                      ),
                    ),
                ]),
                for (final e in TesterScore.extraFields.entries)
                  OptionRow(
                    label: e.value.label,
                    list: e.value.list,
                    value: _extras[t.id]![e.key],
                    placeholder: 'Not set',
                    onChanged: (v) => setState(() => _extras[t.id]![e.key] = v),
                  ),
              ],
            ),
          GroupedSection(children: [FieldInput(label: 'Remarks', hint: 'Bright liquor', controller: _remarks, maxLines: 2)]),
        ],
      ],
    );
  }
}

/// A batch's testing results: progress, average C/T/S/B and each sample.
class TestingResultsScreen extends ConsumerWidget {
  const TestingResultsScreen({super.key, required this.batchId, this.batchName});
  final int batchId;
  final String? batchName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(testingResultsProvider(batchId));
    final r = async.value;
    final c = context.colors;
    return DetailScaffold(
      title: batchName == null ? 'Results' : 'Results · $batchName',
      children: [
        if (async.isLoading && r == null)
          const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: AppSpinner()))
        else if (r == null)
          const EmptyState(icon: AppIcons.batches, title: 'No results yet', body: 'Results appear once testing has started.')
        else ...[
          GroupedSection(
            children: [
              InfoRow('Session', r.statusLabel),
              InfoRow('Tested', '${r.completed ?? 0} of ${r.total ?? 0}'),
              for (final e in r.averages.entries) InfoRow('Average ${e.key}', Fmt.editable(double.parse(e.value.toStringAsFixed(1)))),
            ],
          ),
          GroupedSection(
            label: 'Samples',
            children: [
              for (final x in r.results)
                AppListRow(
                  title: x.title ?? x.sampleCode ?? 'Sample',
                  subtitle: [?x.invoice, if (x.done) 'C-T-S-B ${x.average ?? '–'}'].join(' · '),
                  trailing: x.done
                      ? Text(Fmt.editable(x.overall), style: AppText.callout.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary))
                      : StatusBadge(x.statusLabel ?? 'Pending', tone: statusTone(x.status)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
