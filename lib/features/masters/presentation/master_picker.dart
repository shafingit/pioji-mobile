import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/context_ext.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/utils/formatters.dart';
import '../data/masters_repository.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/application/fresh_read.dart';

/// Opens the full garden list to pick a garden (used by list filters):
/// filters by `garden_id`, shows the garden name.
Future<({String value, String label})?> pickGarden(BuildContext context) async {
  final g = await showModalBottomSheet<MasterItem>(
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    builder: (_) => _RemoteSearchSheet(title: 'Garden', path: '/gardens', initial: gardensProvider),
  );
  return g == null ? null : (value: '${g.id}', label: g.name);
}

class _RemoteSearchSheet extends ConsumerStatefulWidget {
  const _RemoteSearchSheet({required this.title, required this.path, required this.initial, this.selectedId});

  final String title;
  final String path;
  final FutureProvider<List<MasterItem>> initial;
  final int? selectedId;

  @override
  ConsumerState<_RemoteSearchSheet> createState() => _RemoteSearchSheetState();
}

class _RemoteSearchSheetState extends ConsumerState<_RemoteSearchSheet> {
  /// The full list when it loaded; searched on the phone.
  List<MasterItem>? _all;
  List<MasterItem>? _results;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    ref.fresh(widget.initial).then((v) {
      if (!mounted) return;
      setState(() => (_all = v.isEmpty ? null : v, _results = v, _loading = false));
    });
  }

  Future<void> _search(String q) async {
    final all = _all;
    if (all != null) {
      final t = q.trim().toLowerCase();
      setState(() => _results = t.isEmpty
          ? all
          : [
              ...all.where((i) => i.name.toLowerCase().startsWith(t)),
              ...all.where((i) => !i.name.toLowerCase().startsWith(t) && i.name.toLowerCase().contains(t)),
            ]);
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await ref.read(mastersRepositoryProvider).search(widget.path, q);
    if (!mounted || seq != _seq) return;
    setState(() => (_results = r, _loading = false));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _results ?? const <MasterItem>[];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: AppText.title),
              const SizedBox(height: AppSpace.md),
              SearchField(hint: 'Search by name', onChanged: _search),
              if (_all != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${Fmt.number(items.length)} of ${Fmt.number(_all!.length)}',
                  style: AppText.footnote.copyWith(color: c.textTertiary),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: _loading && items.isEmpty
                    ? const Center(child: AppSpinner())
                    : items.isEmpty
                        ? Center(child: Text('No matches', style: AppText.callout.copyWith(color: c.textTertiary)))
                        : Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control)),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: items.length,
                              separatorBuilder: (_, _) => const Divider(height: 0.5),
                              itemBuilder: (_, n) {
                                final i = items[n];
                                return AppListRow(
                                  title: i.name,
                                  subtitle: i.subtitle,
                                  minHeight: 48,
                                  titleStyle: AppText.body,
                                  onTap: () => Navigator.pop(context, i),
                                  trailing: i.id == widget.selectedId
                                      ? AppIcon(AppIcons.check, color: c.accent, size: 20)
                                      : null,
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picker row for a master record. Uses the list endpoint when it has data,
/// otherwise asks for the numeric ID so forms keep working before the
/// backend adds lookup endpoints.
class MasterPickerRow extends ConsumerWidget {
  const MasterPickerRow({
    super.key,
    required this.label,
    required this.provider,
    required this.value,
    required this.onChanged,
    this.error,
    this.placeholder = 'Select',
    this.searchPath,
  });

  final String label;
  final FutureProvider<List<MasterItem>> provider;
  final MasterItem? value;
  final ValueChanged<MasterItem?> onChanged;
  final String? error;
  final String placeholder;

  /// For large lists: search this endpoint on the server as the user types.
  final String? searchPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueRow(
      label: label,
      value: value?.name,
      placeholder: placeholder,
      error: error,
      onTap: () async {
        if (searchPath != null) {
          final picked = await showModalBottomSheet<MasterItem>(
            useSafeArea: true,
            context: context,
            isScrollControlled: true,
            builder: (_) => _RemoteSearchSheet(title: label, path: searchPath!, initial: provider, selectedId: value?.id),
          );
          if (picked != null) onChanged(picked);
          return;
        }
        final items = await ref.fresh(provider);
        if (!context.mounted) return;
        final creatable = _creatable[provider];
        if (items.isEmpty && creatable == null) {
          final id = await _askId(context, label, value?.id);
          if (id != null) onChanged(MasterItem(id, '#$id'));
          return;
        }
        final picked = creatable != null
            ? await showModalBottomSheet<MasterItem>(
                useSafeArea: true,
                context: context,
                isScrollControlled: true,
                builder: (_) => _CreatableSheet(title: label, provider: provider, kind: creatable, selectedId: value?.id),
              )
            : await showPickerSheet<MasterItem>(
                context,
                title: label,
                selected: value == null ? null : items.where((i) => i.id == value!.id).firstOrNull,
                options: [for (final i in items) PickOption(i, i.name, subtitle: i.subtitle)],
              );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Lists whose picker can add a new record by name.
final _creatable = <FutureProvider<List<MasterItem>>, ({String noun, String path, String nameKey})>{
  buyersProvider: (noun: 'buyer', path: '/buyers', nameKey: 'buyer_name'),
  sellersProvider: (noun: 'seller', path: '/sellers', nameKey: 'seller_name'),
};

/// Search a buyer or seller list, or add the typed name as a new one.
class _CreatableSheet extends ConsumerStatefulWidget {
  const _CreatableSheet({required this.title, required this.provider, required this.kind, this.selectedId});

  final String title;
  final FutureProvider<List<MasterItem>> provider;
  final ({String noun, String path, String nameKey}) kind;
  final int? selectedId;

  @override
  ConsumerState<_CreatableSheet> createState() => _CreatableSheetState();
}

class _CreatableSheetState extends ConsumerState<_CreatableSheet> {
  String _q = '';
  bool _creating = false;

  Future<void> _create(String name) async {
    final noun = widget.kind.noun;
    final ok = await confirm(
      context,
      title: 'Add a new $noun?',
      body: '“$name” will be added to the ${noun}s list. Other details can be filled in later from the admin panel.',
      action: 'Add $noun',
    );
    if (!ok || !mounted) return;
    setState(() => _creating = true);
    try {
      final item = await ref.read(mastersRepositoryProvider).create(widget.kind.path, widget.kind.nameKey, name);
      ref.invalidate(widget.provider);
      if (mounted) Navigator.pop(context, item);
    } on AppFailure catch (f) {
      if (mounted) {
        setState(() => _creating = false);
        context.toast(f.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _creating = false);
        context.toast("Couldn't add the $noun. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final noun = widget.kind.noun;
    final list = ref.watch(widget.provider);
    final q = _q.trim();
    final all = list.value ?? const <MasterItem>[];
    final matches = q.isEmpty ? all : all.where((b) => b.name.toLowerCase().contains(q.toLowerCase())).toList();
    // The server accepts duplicate names, so only offer "add" when nothing matches exactly.
    final exact = all.any((b) => b.name.toLowerCase() == q.toLowerCase());
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: AppText.title),
              const SizedBox(height: AppSpace.md),
              SearchField(hint: 'Search ${noun}s or type a new name', onChanged: (s) => setState(() => _q = s)),
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (q.isNotEmpty && !exact)
                        GroupedSection(
                          children: [
                            AppListRow(
                              title: 'Add “$q” as a new $noun',
                              minHeight: 48,
                              titleStyle: AppText.body.copyWith(color: c.accent),
                              leading: _creating
                                  ? const AppSpinner()
                                  : AppIcon(AppIcons.addCircle, color: c.accent, size: 20),
                              onTap: _creating ? null : () => _create(q),
                            ),
                          ],
                        ),
                      if (list.isLoading && all.isEmpty)
                        const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: AppSpinner()))
                      else if (matches.isNotEmpty)
                        GroupedSection(
                          children: [
                            for (final i in matches)
                              AppListRow(
                                title: i.name,
                                subtitle: i.subtitle,
                                minHeight: 48,
                                titleStyle: AppText.body,
                                onTap: () => Navigator.pop(context, i),
                                trailing: i.id == widget.selectedId ? AppIcon(AppIcons.check, color: c.accent, size: 20) : null,
                              ),
                          ],
                        )
                      else if (q.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpace.xl),
                          child: Center(child: Text('No ${noun}s yet. Type a name above to add one.', style: AppText.callout.copyWith(color: c.textTertiary))),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grade picker from `GET /grades`, falling back to the built-in list.
class GradePickerRow extends ConsumerWidget {
  const GradePickerRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.error,
    this.label = 'Grade',
    this.gardenId,
    this.prefix,
    this.invoiceType,
    this.needsGarden = false,
  });

  /// Locked until a garden is chosen, so the list is that garden's grades.
  final bool needsGarden;

  final String? value;

  /// When set, only the grades set up for this garden are offered
  /// (`GET /gardens/{id}/options`), falling back to every grade if it has none.
  final int? gardenId;
  final ValueChanged<String> onChanged;
  final String? error;
  final String label;

  /// The invoice prefix and type already chosen: only grades of that type
  /// are listed ("Show all grades" lists the rest), and the grades this
  /// garden used before with the prefix come first.
  final String? prefix;
  final String? invoiceType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (needsGarden && gardenId == null) {
      return ValueRow(label: label, value: value, placeholder: 'Choose a garden first', error: error, showChevron: false);
    }
    return ValueRow(
      label: label,
      value: value,
      error: error,
      onTap: () async {
        var forGarden = gardenId == null ? const <GardenGrade>[] : (await ref.fresh(gardenOptionsProvider(gardenId!), isEmpty: (o) => o.grades.isEmpty)).grades;
        var grades = forGarden.isNotEmpty ? const <String>[] : await ref.fresh(gradesProvider);
        final links = await ref.fresh(typeLinksProvider, isEmpty: (l) => l.isEmpty);
        final history = gardenId == null ? GardenHistory.empty : await ref.fresh(gardenHistoryProvider(gardenId!)).catchError((_) => GardenHistory.empty);
        final p = prefix?.trim() ?? '';
        final type = (invoiceType ?? '').isEmpty ? null : invoiceType;

        // Only grades of the chosen type (a grade's real type, from the grade
        // master, else the garden's); without a type, the prefix's types.
        bool fits(String code, [String? gardenType]) {
          final t = links.effectiveTypes(code, gardenType);
          if (type != null) return t.contains(type);
          final pt = links.prefixTypes(p);
          return p.isEmpty || pt.isEmpty || t.intersection(pt).isNotEmpty;
        }

        // Grades used here before with this prefix first, latest first.
        final used = history.gradesFor(p);
        int rank(String code) {
          final i = used.indexOf(code.toUpperCase());
          return i < 0 ? used.length : i;
        }

        final allGarden = [...forGarden]..sort((x, y) => rank(x.code).compareTo(rank(y.code)));
        final allGrades = [...grades]..sort((x, y) => rank(x).compareTo(rank(y)));
        forGarden = allGarden;
        grades = allGrades;
        var narrowed = false;
        final g = allGarden.where((x) => fits(x.code, x.invoiceType)).toList();
        final a = allGrades.where(fits).toList();
        if ((g.length < allGarden.length || a.length < allGrades.length) && (g.isNotEmpty || a.isNotEmpty)) {
          forGarden = g;
          grades = a;
          narrowed = true;
        }
        final title = !narrowed
            ? null
            : type != null
                ? '${links.label(type)} grades'
                : '$label for prefix $p';
        if (!context.mounted) return;
        final picked = await _pick(context, forGarden, grades, title, links, used, p);
        if (picked == _other) {
          if (!context.mounted) return;
          final typed = await askOther(context, title: 'Other grade', label: 'Grade', current: value);
          if (typed != null) onChanged(typed);
        } else if (picked != null) {
          onChanged(picked);
        }
      },
    );
  }

  Future<String?> _pick(
    BuildContext context,
    List<GardenGrade> forGarden,
    List<String> grades,
    String? title,
    TypeLinks links,
    List<String> used,
    String prefix,
  ) {
    String? note(String code, [String? name, String? gardenType]) {
      final t = links.effectiveTypes(code, gardenType);
      return [
        if (name != null && name != code) name,
        if (t.isNotEmpty) t.map(links.label).join(' / '),
        if (used.contains(code.toUpperCase())) 'used here with $prefix',
      ].join(' · ');
    }

    return showPickerSheet<String>(
      context,
      title: title ?? (forGarden.isNotEmpty ? '$label for this garden' : label),
      selected: value,
      options: [
        ...forGarden.isNotEmpty
            ? [for (final g in forGarden) PickOption(g.code, g.code, subtitle: note(g.code, g.name, g.invoiceType))]
            : [for (final g in grades) PickOption(g, g, subtitle: note(g))],
        if (value != null && !forGarden.any((g) => g.code == value) && (forGarden.isNotEmpty || !grades.contains(value)))
          PickOption(value!, value!, subtitle: 'Other'),
        if (gardenId != null) const PickOption(_other, 'Other…', subtitle: 'A grade this garden has no set-up for'),
      ],
    );
  }
}

/// Invoice prefix and number. When the garden has prefixes set up
/// (`GET /gardens/{id}/options`), the prefix is picked from them, for the
/// grade's invoice type; otherwise it's typed.
class InvoiceNumberRow extends ConsumerWidget {
  const InvoiceNumberRow({
    super.key,
    required this.gardenId,
    required this.invoiceType,
    required this.prefix,
    required this.number,
    required this.onChanged,
    this.prefixError,
    this.numberError,
    this.prefixHint = 'SMP',
    this.numberHint = '2048',
    this.showNumber = true,
    this.grade,
    this.onTypeChanged,
    this.onGradeChanged,
    this.needsGarden = false,
  });

  /// The prefix is locked until a garden is chosen, so its choices are that
  /// garden's prefixes and types.
  final bool needsGarden;

  final int? gardenId;

  /// The lot's invoice type; shown with the prefix ("D · Dust").
  final String? invoiceType;
  final TextEditingController prefix;
  final TextEditingController number;
  final VoidCallback onChanged;
  final String? prefixError;
  final String? numberError;
  final String prefixHint;
  final String numberHint;

  /// False when the form shows the invoice number elsewhere (the offer form
  /// asks for it first, to find the lot).
  final bool showNumber;

  /// The lot's grade: picks the prefix used for its invoice type, or the
  /// one this garden last used with it.
  final String? grade;

  /// A prefix · type choice also sets the invoice type.
  final ValueChanged<String>? onTypeChanged;

  /// After a prefix · type choice, when the grade doesn't fit the new type
  /// (or there is none yet): the grade this garden has always used with that
  /// prefix and type when there is only one, otherwise null to clear it.
  final ValueChanged<String?>? onGradeChanged;

  /// The prefix this row filled in itself, per controller, so a later grade
  /// can replace it while a prefix the user chose is kept.
  static final _auto = Expando<String>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = gardenId == null ? GardenOptions.empty : ref.watch(gardenOptionsProvider(gardenId!)).value ?? GardenOptions.empty;
    final links = ref.watch(typeLinksProvider).value ?? TypeLinks.empty;
    final history = gardenId == null ? GardenHistory.empty : ref.watch(gardenHistoryProvider(gardenId!)).value ?? GardenHistory.empty;
    // Only prefix · type pairs this garden has grades of that type for, and
    // with a grade chosen, only the ones of its type.
    final gardenTypes = {for (final g in options.grades) ...links.effectiveTypes(g.code, g.invoiceType)};
    final all = links.pairs(options.prefixes);
    final withGrades = gardenTypes.isEmpty ? all : all.where((x) => gardenTypes.contains(x.type)).toList();
    final ofGrade = (grade ?? '').isEmpty
        ? withGrades
        : withGrades.where((x) => links.effectiveTypes(grade!, options.grade(grade)?.invoiceType).contains(x.type)).toList();
    final pairs = ofGrade.isNotEmpty ? ofGrade : withGrades;
    final garden = options.prefixesFor(invoiceType);
    final suggested = suggestPrefix(prefixes: garden, grade: grade, links: links, recent: history.prefixByGrade);
    final typed = prefix.text.trim();
    final auto = _auto[prefix];
    final untouched = typed.isEmpty || typed == auto;
    if (suggested != null && untouched && typed != suggested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = prefix.text.trim();
        if (now.isNotEmpty && now != _auto[prefix]) return;
        prefix.text = suggested;
        _auto[prefix] = suggested;
        // The grade's own type, when the prefix is used for it.
        final t = links.gradeType(grade);
        if (t != null && pairs.any((x) => x.prefix == suggested && x.type == t)) onTypeChanged?.call(t);
        onChanged();
      });
    }

    // Shown as "D · Dust" when the type is one this prefix stands for.
    final shownType = pairs.any((x) => x.prefix == typed && x.type == invoiceType) ? invoiceType : null;
    final gradeType = links.gradeType(grade);
    final ordered = [
      ...pairs.where((x) => gradeType != null && x.type == gradeType),
      ...pairs.where((x) => gradeType == null || x.type != gradeType),
    ];
    String key(({String prefix, String type}) x) => '${x.prefix}\u0001${x.type}';
    final selectedKey = shownType != null
        ? '$typed\u0001$shownType'
        : (typed.isNotEmpty && !pairs.any((x) => x.prefix == typed) ? typed : null);

    /// Applies a prefix · type choice ([picked] is a pair key, a typed
    /// prefix, or "Other…").
    Future<void> apply(String picked) async {
      if (picked == _other) {
        final other = await askOther(context, title: 'Other prefix', label: 'Prefix', current: typed);
        if (other == null) return;
        prefix.text = other;
        _auto[prefix] = null;
        onChanged();
        return;
      }
      final parts = picked.split('\u0001');
      prefix.text = parts.first;
      _auto[prefix] = null;
      if (parts.length > 1) {
        final type = parts[1];
        onTypeChanged?.call(type);
        // A grade of another type no longer fits: use the one grade this
        // garden has used with this prefix and type, or clear it.
        final current = grade ?? '';
        final known = links.gradeTypes(current);
        final fits = current.isNotEmpty && (known.isEmpty || known.contains(type));
        if (!fits) {
          final used = history.gradesFor(parts.first).where((g) => links.gradeTypes(g).isEmpty || links.gradeTypes(g).contains(type)).toList();
          final next = used.length == 1 ? used.single : null;
          if (next != null || current.isNotEmpty) onGradeChanged?.call(next);
        }
      }
      onChanged();
    }

    final c = context.colors;
    final Widget prefixField = needsGarden && gardenId == null
        ? ValueRow(
            label: showNumber ? 'Prefix' : 'Prefix · type',
            value: typed.isEmpty ? null : typed,
            placeholder: showNumber ? 'Garden first' : 'Choose a garden first',
            error: prefixError,
            showChevron: false,
          )
        : pairs.isEmpty
        ? FieldInput(label: 'Prefix', hint: prefixHint, controller: prefix, error: prefixError, textCapitalization: TextCapitalization.characters)
        : !showNumber
        // Full width: every prefix · type as a one-tap chip.
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Prefix · type', style: AppText.body.copyWith(color: prefixError != null ? c.danger : c.textPrimary)),
                const SizedBox(height: 8),
                ChoiceChips<String>(
                  options: {
                    for (final x in ordered) key(x): '${x.prefix} · ${links.label(x.type)}',
                    if (typed.isNotEmpty && !pairs.any((x) => x.prefix == typed)) typed: typed,
                    _other: 'Other…',
                  },
                  selected: selectedKey,
                  onSelected: apply,
                ),
                if (prefixError != null) ...[
                  const SizedBox(height: 4),
                  Text(prefixError!, style: AppText.footnote.copyWith(color: c.danger)),
                ],
              ],
            ),
          )
        : ValueRow(
            label: 'Prefix',
            value: typed.isEmpty ? null : typed,
            error: prefixError,
            onTap: () async {
              final picked = await showPickerSheet<String>(
                context,
                title: 'Invoice prefix and type',
                selected: selectedKey,
                searchable: ordered.length > 8,
                options: [
                  for (final x in ordered)
                    PickOption(
                      key(x),
                      '${x.prefix} · ${links.label(x.type)}',
                      subtitle: x.prefix == suggested && x.type == gradeType && (grade ?? '').isNotEmpty ? 'Suggested for $grade' : null,
                    ),
                  if (typed.isNotEmpty && !pairs.any((x) => x.prefix == typed)) PickOption(typed, typed, subtitle: 'Other'),
                  const PickOption(_other, 'Other…', subtitle: 'A prefix this garden has no set-up for'),
                ],
              );
              if (picked != null && context.mounted) await apply(picked);
            },
          );
    if (!showNumber) return prefixField;
    return Row(children: [
      SizedBox(width: 120, child: prefixField),
      Expanded(child: FieldInput(label: 'Invoice no', hint: numberHint, controller: number, error: numberError)),
    ]);
  }
}

/// Asks for a value the list doesn't have (an "Other" grade or prefix).
Future<String?> askOther(BuildContext context, {required String title, required String label, String? current}) {
  final ctl = TextEditingController(text: current ?? '');
  return showAppDialog<String>(
    context,
    builder: (ctx) => AppDialog(
      title: title,
      body: "Saved as typed, marked as Other, as on the website.",
      content: AppCard(child: FieldInput(label: label, controller: ctl, textCapitalization: TextCapitalization.characters)),
      actions: [
        AppDialogAction('Cancel', () => Navigator.pop(ctx)),
        AppDialogAction('Use', () {
          final v = ctl.text.trim();
          Navigator.pop(ctx, v.isEmpty ? null : v);
        }, primary: true),
      ],
    ),
  );
}

const _other = '\u0000other';

Future<int?> _askId(BuildContext context, String label, int? current) {
  final ctl = TextEditingController(text: current?.toString() ?? '');
  return showAppDialog<int>(
    context,
    builder: (ctx) => AppDialog(
      title: '$label ID',
      body: "The list isn't available yet. Enter the ID from the admin panel.",
      content: AppCard(
        child: FieldInput(label: 'ID', controller: ctl, keyboardType: TextInputType.number, inputFormatters: digitsOnly),
      ),
      actions: [
        AppDialogAction('Cancel', () => Navigator.pop(ctx)),
        AppDialogAction('Use', () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())), primary: true),
      ],
    ),
  );
}

/// A party is a buyer's name: pick one from `GET /buyers` or type any name
/// (the offer API stores parties as text). Returns '' to clear.
class PartyPickerRow extends ConsumerWidget {
  const PartyPickerRow({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = value?.trim();
    return ValueRow(
      label: label,
      value: v == null || v.isEmpty ? null : v,
      placeholder: 'Buyer or name',
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          useSafeArea: true,
          context: context,
          isScrollControlled: true,
          builder: (_) => _PartySheet(title: label, current: v),
        );
        if (picked != null) onChanged(picked.isEmpty ? null : picked);
      },
    );
  }
}

class _PartySheet extends ConsumerStatefulWidget {
  const _PartySheet({required this.title, this.current});
  final String title;
  final String? current;

  @override
  ConsumerState<_PartySheet> createState() => _PartySheetState();
}

class _PartySheetState extends ConsumerState<_PartySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final buyers = ref.watch(buyersProvider);
    final q = _q.trim();
    final all = buyers.value ?? const <MasterItem>[];
    final matches = q.isEmpty ? all : all.where((b) => b.name.toLowerCase().contains(q.toLowerCase())).toList();
    final exact = all.any((b) => b.name.toLowerCase() == q.toLowerCase());
    final hasCurrent = widget.current != null && widget.current!.isNotEmpty;
    // Clears the party; sits beside the Buyers heading, styled like the
    // other heading actions ("Remove" on contract items).
    final clear = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context, ''),
      child: Text('Clear', style: AppText.footnote.copyWith(color: c.danger)),
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: AppText.title),
              const SizedBox(height: AppSpace.md),
              SearchField(hint: 'Search buyers or type a name', onChanged: (s) => setState(() => _q = s)),
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (q.isNotEmpty && !exact)
                        GroupedSection(
                          children: [
                            AppListRow(
                              title: 'Use “$q”',
                              subtitle: 'Not in the buyers list',
                              minHeight: 48,
                              titleStyle: AppText.body.copyWith(color: c.accent),
                              leading: AppIcon(AppIcons.edit, color: c.accent, size: 20),
                              onTap: () => Navigator.pop(context, q),
                            ),
                          ],
                        ),
                      if (q.isNotEmpty && !exact && (matches.isNotEmpty || buyers.isLoading)) const SizedBox(height: AppSpace.xl),
                      // With no buyer list to sit beside, Clear gets its own row.
                      if (hasCurrent && matches.isEmpty && !buyers.isLoading)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.md),
                          child: Align(alignment: Alignment.centerLeft, child: clear),
                        ),
                      if (buyers.isLoading && all.isEmpty)
                        const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: AppSpinner()))
                      else if (matches.isNotEmpty)
                        GroupedSection(
                          label: 'Buyers',
                          trailingLabel: hasCurrent ? clear : null,
                          children: [
                            for (final b in matches)
                              AppListRow(
                                title: b.name,
                                subtitle: b.subtitle,
                                minHeight: 48,
                                titleStyle: AppText.body,
                                onTap: () => Navigator.pop(context, b.name),
                                trailing: b.name == widget.current ? AppIcon(AppIcons.check, color: c.accent, size: 20) : null,
                              ),
                          ],
                        )
                      else if (q.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpace.xl),
                          child: Center(child: Text('No buyers yet. Type a name above.', style: AppText.callout.copyWith(color: c.textTertiary))),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

