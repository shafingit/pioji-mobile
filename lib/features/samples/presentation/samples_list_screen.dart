import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/context_ext.dart';
import '../../../core/design/typography.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/module_list.dart';
import '../../masters/presentation/master_picker.dart';
import '../data/samples_repository.dart';
import '../domain/sample.dart';
import '../../../core/design/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../masters/data/form_options.dart';

class SamplesListScreen extends ConsumerWidget {
  const SamplesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = watchFormOptions(ref);
    return ModuleListScreen<Sample>(
      title: 'Samples',
      listProvider: samplesListProvider,
      queryProvider: samplesQueryProvider,
      searchHint: 'Search garden, grade or invoice',
      emptyIcon: AppIcons.samples,
      emptyTitle: 'Add your first sample',
      emptyBody: 'Samples you receive show up here with their grade and weight.',
      newLabel: 'New sample',
      onNew: () => context.pushNamed(Routes.sampleNew),
      actions: [
        LinkButton(label: 'Batches', onPressed: () => context.pushNamed(Routes.batches)),
        AddButton(semanticLabel: 'New sample', onPressed: () => context.pushNamed(Routes.sampleNew)),
      ],
      segments: SegmentConfig(param: 'status', options: options.map('sample_statuses', all: 'All')),
      filters: [
        const DateFilter('arrival_date', 'Arrival'),
        const PickerFilter('garden_id', 'Mark', pickMark),
        ChoiceFilter('for_company', 'For', options.map('offer_for')),
        ChoiceFilter('sample_type', 'Type', options.map('sample_types')),
        const ChoiceFilter('evaluation_status', 'Tasting', {'completed': 'Tasted'}),
        const ChoiceFilter('parked', 'Parked', {'1': 'Parked only'}),
      ],
      sortField: 'arrival_date',
      grouping: ListGrouping(
        section: (s) => s.arrivalDate == null ? 'No arrival date' : Fmt.day(s.arrivalDate),
        subgroup: (s) => s.gardenName,
        order: (s) => s.invoiceNo,
      ),
      itemBuilder: (context, s) => SampleRow(sample: s),
    );
  }
}

class SampleRow extends StatelessWidget {
  const SampleRow({super.key, required this.sample});
  final Sample sample;

  @override
  Widget build(BuildContext context) {
    final s = sample;
    final sub = [
      Fmt.invoice(s.invoicePrefix, s.invoiceNo),
      if (s.packages != null && s.weight != null) '${s.packages} × ${Fmt.editable(s.weight)} kg',
      if (s.overallScore != null) 'Score ${Fmt.editable(s.overallScore)}',
      if (s.isParked) 'Parked',
    ].where((e) => e.isNotEmpty).join(' · ');
    return AppListRow(
      title: s.title,
      subtitle: sub.isEmpty ? Fmt.day(s.arrivalDate) : sub,
      minHeight: 64,
      onTap: () => context.pushNamed(Routes.sampleDetail, pathParameters: {'id': '${s.id}'}, extra: s),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Fmt.kg(s.totalKgs), style: AppText.callout.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: context.colors.textPrimary)),
          const SizedBox(height: 4),
          OptionBadge(list: 'sample_statuses', value: s.status),
        ],
      ),
    );
  }
}
