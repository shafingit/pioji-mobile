import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_icons.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/storage/current_branch.dart';
import '../../../core/widgets/sheets.dart';
import '../../masters/data/form_options.dart';

/// Home's top-right branch name: tapping it switches the branch
/// this phone works from, like the website's Switch Branch. The branches
/// are `GET /form-options` → `offices`.
class BranchSwitcher extends ConsumerWidget {
  const BranchSwitcher({super.key});

  static const _none = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final offices = ref.watch(formOptionsProvider).value?['offices'] ?? const <Choice>[];
    final current = ref.watch(currentBranchProvider);
    final branch = offices.where((o) => o.value == '$current').firstOrNull;
    final picked = branch != null;

    Future<void> pick() async {
      if (offices.isEmpty) {
        ref.invalidate(formOptionsProvider);
        context.toast('Branches are still loading. Try again.');
        return;
      }
      final picked = await showPickerSheet<String>(
        context,
        title: 'Branch',
        selected: current == null ? _none : '$current',
        searchable: false,
        options: [
          for (final o in offices)
            PickOption(o.value, o.label, subtitle: [o.extra['city'], o.extra['code']].whereType<Object>().join(' · ')),
          const PickOption(_none, 'No branch', subtitle: 'New records are saved without one'),
        ],
      );
      if (picked == null) return;
      // Lists and Home numbers watch the branch and load again by themselves.
      await ref.read(currentBranchProvider.notifier).set(picked == _none ? null : int.tryParse(picked));
    }

    return Semantics(
      button: true,
      label: branch == null ? 'Choose branch' : 'Branch: ${branch.label}. Switch branch',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: pick,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  branch?.label ?? 'Choose branch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.footnote.copyWith(
                    fontSize: 15,
                    color: picked ? c.accent : c.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppIcon(AppIcons.chevronDown, size: 16, color: picked ? c.accent : c.textTertiary),
              // Lines the chevron up with the page's right edge.
              const SizedBox(width: AppSpace.screenH - AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }
}
