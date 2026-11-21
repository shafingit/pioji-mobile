import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/states.dart';
import '../../masters/data/masters_repository.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/bid_book_repository.dart';
import '../../../core/utils/json.dart';

class _LotDraft {
  String? grade;
  final invoice = TextEditingController();
  final invoiceFocus = FocusNode();

  /// Garden and invoice last looked up in the offer list.
  String? lookedUp;
  final pkgs = TextEditingController();
  final incoming = TextEditingController();
  final maxBid = TextEditingController();
  String? error;

  bool get isBlank => grade == null && [invoice, pkgs, incoming, maxBid].every((c) => c.text.trim().isEmpty);

  void dispose() {
    invoiceFocus.dispose();
    for (final c in [invoice, pkgs, incoming, maxBid]) {
      c.dispose();
    }
  }
}

/// Bulk work on the bid book: add many lots of one mark at once
/// (`POST /bid-book/bulk`), or set the asking price and max bid on several
/// open lots (`PATCH /bid-book/bulk`).
class BidBulkScreen extends ConsumerStatefulWidget {
  const BidBulkScreen({super.key});

  @override
  ConsumerState<BidBulkScreen> createState() => _BidBulkScreenState();
}

class _BidBulkScreenState extends ConsumerState<BidBulkScreen> with FormSubmit {
  String _tab = 'add';

  // Add lots
  MasterItem? _garden;
  late final _lots = <_LotDraft>[_newLot(), _newLot(), _newLot()];

  /// A lot row that fills grade, packages and asking price from the offer
  /// list once its invoice is entered.
  _LotDraft _newLot() {
    final lot = _LotDraft();
    lot.invoiceFocus.addListener(() {
      if (!lot.invoiceFocus.hasFocus) _fillLot(lot);
    });
    return lot;
  }

  Future<void> _fillLot(_LotDraft lot) async {
    final garden = _garden?.name, inv = lot.invoice.text.trim();
    if (garden == null || garden.startsWith('#') || inv.isEmpty) return;
    final key = '$garden|$inv'.toUpperCase();
    if (key == lot.lookedUp) return;
    lot.lookedUp = key;
    final found = await ref.read(bidBookRepositoryProvider).searchOfferList(garden, inv);
    if (found == null || !mounted || !_lots.contains(lot)) return;
    setState(() {
      lot.grade ??= J.str(found['grade']) ?? J.str(found['tea_grade']);
      if (lot.pkgs.text.trim().isEmpty && J.integer(found['packages']) != null) lot.pkgs.text = '${J.integer(found['packages'])}';
      if (lot.incoming.text.trim().isEmpty && J.dbl(found['price']) != null) lot.incoming.text = Fmt.editable(J.dbl(found['price']));
    });
  }

  // Set prices
  late Future<List<Bid>> _open = ref.read(bidBookRepositoryProvider).listForPicking('open');
  final _picked = <int>{};
  final _incoming = TextEditingController();
  final _maxBid = TextEditingController();

  @override
  void dispose() {
    for (final l in _lots) {
      l.dispose();
    }
    _incoming.dispose();
    _maxBid.dispose();
    super.dispose();
  }

  Future<void> _addLots() async {
    final rows = [for (var i = 0; i < _lots.length; i++) if (!_lots[i].isBlank) i];
    final client = <String, String>{
      if (_garden == null) 'garden_id': 'Choose the mark.',
      if (rows.isEmpty) 'lots': 'Enter at least one lot.',
    };
    for (final i in rows) {
      final l = _lots[i];
      l.error = l.grade == null || l.invoice.text.trim().isEmpty ? 'Grade and invoice are needed.' : null;
    }
    if (rows.any((i) => _lots[i].error != null)) client['lots'] = 'Check the highlighted lots.';
    final result = await submit(
      () => ref.read(bidBookRepositoryProvider).bulkCreate([
        for (final i in rows)
          {
            'garden_id': _garden!.id,
            'garden_name': _garden!.name,
            'grade': _lots[i].grade,
            'invoice_number': _lots[i].invoice.text.trim(),
            'packages': int.tryParse(_lots[i].pkgs.text),
            'seller_incoming_price': Fmt.parse(_lots[i].incoming.text),
            'max_bid': Fmt.parse(_lots[i].maxBid.text),
            'status': 'open',
          },
      ]),
      clientErrors: client,
    );
    if (result == null || !mounted) return;
    ref.invalidate(bidBookListProvider);
    refreshSummaries(ref);
    // Keep only the rows that failed, with their errors.
    setState(() {
      final keep = <_LotDraft>[];
      for (var n = 0; n < rows.length; n++) {
        final lot = _lots[rows[n]];
        final e = result.errors[n];
        if (e != null) {
          lot.error = e;
          keep.add(lot);
        } else {
          lot.dispose();
        }
      }
      for (final l in _lots) {
        if (l.isBlank) l.dispose();
      }
      _lots
        ..clear()
        ..addAll(keep);
      if (_lots.isEmpty) _lots.add(_newLot());
      _open = ref.read(bidBookRepositoryProvider).listForPicking('open');
    });
    final made = result.created.length;
    context.toast(result.errors.isEmpty ? '$made ${made == 1 ? 'lot' : 'lots'} added' : '$made added, ${result.errors.length} need fixing');
  }

  Future<void> _setPrices() async {
    final incoming = Fmt.parse(_incoming.text);
    final maxBid = Fmt.parse(_maxBid.text);
    final ok = await submit<bool>(
      () async {
        await ref.read(bidBookRepositoryProvider).bulkUpdate(_picked.toList(), incoming: incoming, maxBid: maxBid);
        return true;
      },
      clientErrors: {
        if (_picked.isEmpty) 'ids': 'Tick the lots to update.',
        if (incoming == null && maxBid == null) 'price': 'Enter an asking price or a max bid.',
      },
    );
    if (ok != true || !mounted) return;
    ref.invalidate(bidBookListProvider);
    context.toast('${_picked.length} ${_picked.length == 1 ? 'lot' : 'lots'} updated');
    setState(() {
      _picked.clear();
      _incoming.clear();
      _maxBid.clear();
      _open = ref.read(bidBookRepositoryProvider).listForPicking('open');
    });
  }

  @override
  Widget build(BuildContext context) {
    final add = _tab == 'add';
    return FormScaffold(
      title: 'Bulk lots',
      submitLabel: add ? 'Add lots' : (_picked.isEmpty ? 'Set prices' : 'Set prices on ${_picked.length}'),
      submitting: submitting,
      onSubmit: add ? _addLots : _setPrices,
      children: [
        Segmented<String>(
          options: const {'add': 'Add lots', 'prices': 'Set prices'},
          selected: _tab,
          onChanged: (v) => setState(() => (_tab = v, banner = null, errors = const {})),
        ),
        if (banner != null) FormBanner(banner!),
        if (add) ..._addChildren(context) else ..._priceChildren(context),
      ],
    );
  }

  List<Widget> _addChildren(BuildContext context) {
    final c = context.colors;
    return [
      GroupedSection(
        footer: const Text('All lots below are for this mark. Grade and invoice are needed; the rest can be filled later.'),
        children: [
          MasterPickerRow(label: 'Garden', provider: gardensProvider, searchPath: '/gardens', value: _garden, onChanged: (g) => setState(() => _garden = g), error: err('garden_id')),
        ],
      ),
      if (err('lots') != null) Text(err('lots')!, style: AppText.footnote.copyWith(color: c.danger)),
      for (var i = 0; i < _lots.length; i++)
        GroupedSection(
          label: 'Lot ${i + 1}',
          trailingLabel: _lots.length > 1
              ? GestureDetector(
                  onTap: () => setState(() => _lots.removeAt(i).dispose()),
                  child: Text('Remove', style: AppText.footnote.copyWith(color: c.danger)),
                )
              : null,
          footer: _lots[i].error == null ? null : Text(_lots[i].error!, style: AppText.footnote.copyWith(color: c.danger)),
          children: [
            GradePickerRow(gardenId: _garden?.id, needsGarden: true, value: _lots[i].grade, onChanged: (g) => setState(() => _lots[i].grade = g)),
            Row(children: [
              Expanded(
                child: FieldInput(
                  label: 'Invoice',
                  hint: '1045',
                  controller: _lots[i].invoice,
                  focusNode: _lots[i].invoiceFocus,
                  onSubmitted: (_) => _fillLot(_lots[i]),
                ),
              ),
              SizedBox(width: 120, child: FieldInput(label: 'Packages', hint: '20', controller: _lots[i].pkgs, keyboardType: TextInputType.number, inputFormatters: digitsOnly)),
            ]),
            Row(children: [
              Expanded(child: FieldInput(label: 'Asking', hint: '250', suffix: '₹', controller: _lots[i].incoming, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly)),
              Expanded(child: FieldInput(label: 'Max bid', hint: '280', suffix: '₹', controller: _lots[i].maxBid, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly)),
            ]),
          ],
        ),
      SecondaryButton(label: 'Add another lot', icon: AppIcons.add, onPressed: () => setState(() => _lots.add(_newLot()))),
    ];
  }

  List<Widget> _priceChildren(BuildContext context) {
    final c = context.colors;
    return [
      GroupedSection(
        footer: const Text('Leave one empty to keep it as it is on each lot.'),
        children: [
          Row(children: [
            Expanded(child: FieldInput(label: 'Asking', hint: '250', suffix: '₹', controller: _incoming, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly, error: err('price'))),
            Expanded(child: FieldInput(label: 'Max bid', hint: '280', suffix: '₹', controller: _maxBid, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimalOnly)),
          ]),
        ],
      ),
      if (err('ids') != null) Text(err('ids')!, style: AppText.footnote.copyWith(color: c.danger)),
      FutureBuilder<List<Bid>>(
        future: _open,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingBlock(height: 120);
          if (snap.hasError) {
            return ErrorState(error: snap.error!, onRetry: () => setState(() => _open = ref.read(bidBookRepositoryProvider).listForPicking('open')));
          }
          final lots = snap.data ?? const <Bid>[];
          if (lots.isEmpty) {
            return const EmptyState(icon: AppIcons.bids, title: 'No open lots', body: 'Open lots show up here to price several at once.');
          }
          final byMark = <String, List<Bid>>{};
          for (final b in lots) {
            byMark.putIfAbsent(b.gardenName, () => []).add(b);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in byMark.entries) ...[
                GroupedSection(
                  label: '${e.key} · ${e.value.length}',
                  trailingLabel: GestureDetector(
                    onTap: () => setState(() {
                      final ids = e.value.map((b) => b.id);
                      ids.every(_picked.contains) ? _picked.removeAll(ids) : _picked.addAll(ids);
                    }),
                    child: Text(e.value.every((b) => _picked.contains(b.id)) ? 'Clear' : 'Select all', style: AppText.footnote.copyWith(color: c.accent)),
                  ),
                  children: [
                    for (final b in e.value)
                      AppListRow(
                        title: '${b.grade} · ${b.invoiceNumber}',
                        titleStyle: AppText.callout.copyWith(fontWeight: FontWeight.w500),
                        subtitle: 'Ask ${b.incoming == null ? '–' : '₹${Fmt.number(b.incoming)}'} · Max ${b.maxBid == null ? '–' : '₹${Fmt.number(b.maxBid)}'}',
                        minHeight: 52,
                        onTap: () => setState(() => _picked.contains(b.id) ? _picked.remove(b.id) : _picked.add(b.id)),
                        trailing: AppIcon(
                          _picked.contains(b.id) ? AppIcons.checkCircleFill : AppIcons.circle,
                          size: 22,
                          color: _picked.contains(b.id) ? c.accent : c.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
              ],
            ],
          );
        },
      ),
    ];
  }
}
