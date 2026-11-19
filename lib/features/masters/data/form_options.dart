import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/status_badge.dart';

/// One option of a website dropdown, as `GET /form-options` sends it.
class Choice {
  const Choice(this.value, this.label, {this.isDefault = false, this.extra = const {}});
  final String value;
  final String label;
  final bool isDefault;

  /// The option's other keys (`rbac_role`, `city`, `code`…).
  final Map<String, dynamic> extra;
}

/// Every website dropdown list, keyed by its `GET /form-options` name
/// (`sample_statuses`, `offer_for`, `currencies`…).
class FormOptions {
  const FormOptions(this._lists);
  static const empty = FormOptions({});

  final Map<String, List<Choice>> _lists;

  factory FormOptions.fromJson(Map<String, dynamic> data) => FormOptions({
        for (final e in data.entries)
          if (e.value is List)
            e.key: [
              for (final o in (e.value as List).whereType<Map<String, dynamic>>())
                if (J.str(o['value']) != null)
                  Choice(
                    J.str(o['value'])!,
                    J.str(o['label']) ?? J.str(o['value'])!,
                    isDefault: J.boolOr(o['default'], false),
                    extra: o,
                  ),
            ],
      });

  List<Choice> operator [](String list) => _lists[list] ?? const [];

  /// The option's label, or the raw value when the list doesn't have it.
  String? label(String list, String? value) {
    if (value == null || value.isEmpty) return null;
    for (final c in this[list]) {
      if (c.value == value) return c.label;
    }
    return value;
  }

  /// The option the website preselects, if the list marks one.
  String? defaultValue(String list) {
    for (final c in this[list]) {
      if (c.isDefault) return c.value;
    }
    return null;
  }

  /// What a new form starts with: the website default, else the first option.
  String? initial(String list) => defaultValue(list) ?? (this[list].isEmpty ? null : this[list].first.value);

  /// `{value: label}` for segments and filters, optionally led by an "All".
  Map<String, String> map(String list, {String? all}) => {
        '': ?all,
        for (final c in this[list]) c.value: c.label,
      };
}

final formOptionsProvider = FutureProvider<FormOptions>((ref) async {
  final data = J.map(await ref.read(apiProvider).getData('/form-options'));
  return data == null ? FormOptions.empty : FormOptions.fromJson(data);
});

/// The loaded lists, or [FormOptions.empty] while they load.
FormOptions watchFormOptions(WidgetRef ref) => ref.watch(formOptionsProvider).value ?? FormOptions.empty;

/// A form row that picks one option of a `GET /form-options` list.
class OptionRow extends ConsumerWidget {
  const OptionRow({
    super.key,
    required this.label,
    required this.list,
    required this.value,
    required this.onChanged,
    this.error,
    this.placeholder = 'Select',
  });

  final String label;
  final String list;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? error;
  final String placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = watchFormOptions(ref);
    return ValueRow(
      label: label,
      value: options.label(list, value),
      placeholder: placeholder,
      error: error,
      onTap: () async {
        final all = await ref.read(formOptionsProvider.future);
        if (!context.mounted) return;
        final picked = await showPickerSheet<String>(
          context,
          title: label,
          selected: value,
          searchable: all[list].length > 8,
          options: [for (final c in all[list]) PickOption(c.value, c.label)],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Side-by-side choice for a short `GET /form-options` list (two or three
/// options), shown once the list has loaded.
class OptionSegments extends ConsumerWidget {
  const OptionSegments({super.key, required this.list, required this.value, required this.onChanged, this.compact = false});

  final String list;
  final String? value;
  final ValueChanged<String> onChanged;

  /// Natural width, for a segment control next to a label in a row.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = watchFormOptions(ref).map(list);
    if (options.isEmpty) return const SizedBox.shrink();
    return Segmented<String>(
      options: options,
      selected: options.containsKey(value) ? value! : watchFormOptions(ref).initial(list)!,
      onChanged: onChanged,
      compact: compact,
    );
  }
}

/// A status badge whose text comes from a `GET /form-options` list.
class OptionBadge extends ConsumerWidget {
  const OptionBadge({super.key, required this.list, required this.value, this.short = false});

  final String list;
  final String? value;

  /// For tight rows: the label without its bracketed note, e.g.
  /// "Open (Negotiation Active)" → "Open".
  final bool short;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    final label = watchFormOptions(ref).label(list, value)!;
    final shown = short ? label.split(' (').first.trim() : label;
    return StatusBadge(shown.isEmpty ? label : shown, tone: statusTone(value));
  }
}
