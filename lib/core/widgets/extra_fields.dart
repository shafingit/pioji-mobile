import 'package:flutter/material.dart';

import '../utils/formatters.dart';
import '../utils/json.dart';
import 'app_card.dart';
import 'detail.dart';
import 'fields.dart';

/// How an extra API field is entered and shown.
enum ExtraKind { text, integer, number, money, date, flag }

/// A plain API field the website form has and the API saves (text, number,
/// date or yes/no). Dropdown fields are not declared here: their options
/// come from their own APIs.
class ExtraField {
  const ExtraField(this.key, this.label, this.kind, {this.hint, this.suffix});
  final String key;
  final String label;
  final ExtraKind kind;
  final String? hint;
  final String? suffix;
}

/// Holds the inputs for a set of [ExtraField]s, prefilled from the record's
/// API map, and turns them back into request body values.
class ExtraFieldsController {
  ExtraFieldsController(this.fields, [Map<String, dynamic> raw = const {}]) {
    for (final f in fields) {
      final v = raw[f.key];
      switch (f.kind) {
        case ExtraKind.date:
          dates[f.key] = J.date(v);
        case ExtraKind.flag:
          flags[f.key] = J.boolOr(v, false);
        case ExtraKind.integer || ExtraKind.number || ExtraKind.money:
          text[f.key] = TextEditingController(text: Fmt.editable(J.dbl(v)));
        case ExtraKind.text:
          text[f.key] = TextEditingController(text: J.str(v));
      }
    }
  }

  final List<ExtraField> fields;
  final text = <String, TextEditingController>{};
  final dates = <String, DateTime?>{};
  final flags = <String, bool>{};

  /// Request body values; empty inputs are left out by the repositories'
  /// `cleanBody`.
  Map<String, Object?> body() => {
        for (final f in fields)
          f.key: switch (f.kind) {
            ExtraKind.date => dates[f.key] == null ? null : Fmt.api(dates[f.key]!),
            ExtraKind.flag => flags[f.key] ?? false,
            ExtraKind.integer => int.tryParse(text[f.key]!.text.trim()),
            ExtraKind.number || ExtraKind.money => Fmt.parse(text[f.key]!.text),
            ExtraKind.text => text[f.key]!.text.trim(),
          },
      };

  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
  }
}

/// The inputs for an [ExtraFieldsController], two short fields per row.
class ExtraFieldsSection extends StatelessWidget {
  const ExtraFieldsSection({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label,
    this.footer,
    this.errors = const {},
  });

  final ExtraFieldsController controller;
  final VoidCallback onChanged;
  final String? label;
  final Widget? footer;
  final Map<String, String> errors;

  Widget _input(ExtraField f) {
    final c = controller;
    switch (f.kind) {
      case ExtraKind.date:
        return DateRow(label: f.label, placeholder: 'Not set', value: c.dates[f.key], error: errors[f.key], onChanged: (d) {
          c.dates[f.key] = d;
          onChanged();
        });
      case ExtraKind.flag:
        return SwitchRow(label: f.label, value: c.flags[f.key] ?? false, onChanged: (v) {
          c.flags[f.key] = v;
          onChanged();
        });
      case ExtraKind.integer:
        return FieldInput(label: f.label, hint: f.hint, suffix: f.suffix, controller: c.text[f.key]!, error: errors[f.key], keyboardType: TextInputType.number, inputFormatters: digitsOnly);
      case ExtraKind.number:
        return FieldInput(label: f.label, hint: f.hint, suffix: f.suffix, controller: c.text[f.key]!, error: errors[f.key], keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly);
      case ExtraKind.money:
        return FieldInput(label: f.label, hint: f.hint, suffix: f.suffix ?? '₹', controller: c.text[f.key]!, error: errors[f.key], keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly);
      case ExtraKind.text:
        return FieldInput(label: f.label, hint: f.hint, suffix: f.suffix, controller: c.text[f.key]!, error: errors[f.key]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final pending = <ExtraField>[];
    void flush() {
      if (pending.isEmpty) return;
      rows.add(Row(children: [for (final f in pending) Expanded(child: _input(f)), if (pending.length == 1) const Expanded(child: SizedBox())]));
      pending.clear();
    }

    // Numbers pair up side by side; text, dates and switches take a full row.
    for (final f in controller.fields) {
      final short = f.kind == ExtraKind.integer || f.kind == ExtraKind.number || f.kind == ExtraKind.money;
      if (!short) {
        flush();
        rows.add(_input(f));
        continue;
      }
      pending.add(f);
      if (pending.length == 2) flush();
    }
    flush();
    return GroupedSection(label: label, footer: footer, children: rows);
  }
}

/// Detail rows for the [fields] that have a value in the record's API map.
List<Widget> extraInfoRows(List<ExtraField> fields, Map<String, dynamic> raw) => [
      for (final f in fields)
        if (_shown(f, raw[f.key]) case final text?) InfoRow(f.label, text),
    ];

String? _shown(ExtraField f, Object? v) {
  switch (f.kind) {
    case ExtraKind.date:
      final d = J.date(v);
      return d == null ? null : Fmt.day(d);
    case ExtraKind.flag:
      return J.boolOr(v, false) ? 'Yes' : null;
    case ExtraKind.money:
      final n = J.dbl(v);
      return n == null ? null : Fmt.money(n);
    case ExtraKind.integer || ExtraKind.number:
      final n = J.dbl(v);
      return n == null ? null : '${Fmt.editable(n)}${f.suffix == null ? '' : ' ${f.suffix}'}';
    case ExtraKind.text:
      return J.str(v);
  }
}
