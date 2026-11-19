import 'package:flutter/material.dart';

import '../design/app_icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'app_list_row.dart';
import 'one_line_text.dart';

/// Borderless, shadowless card with a soft same-hue diagonal gradient.
class TonalCard extends StatelessWidget {
  const TonalCard({super.key, required this.hue, required this.child, this.onTap, this.padding = const EdgeInsets.fromLTRB(14, 12, 12, 12)});

  final CardHue hue;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = hue.of(Theme.of(context).brightness);
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(gradient: t.gradient, shape: AppRadius.cardBorder),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

/// The label and icon line of a tonal card.
class TonalHeader extends StatelessWidget {
  const TonalHeader({super.key, required this.hue, required this.label, required this.icon, this.trailing});

  final CardHue hue;
  final String label;
  final AppIcons icon;

  /// Short text before the icon, e.g. "All time".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = hue.of(Theme.of(context).brightness);
    final soft = AppText.footnote.copyWith(color: t.inkSoft);
    return Row(
      children: [
        Expanded(child: OneLineText(label, style: soft)),
        if (trailing != null) ...[Text(trailing!, style: soft), const SizedBox(width: 8)],
        IconTile(icon: icon, size: 26, color: t.ink, background: t.tile),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.hue,
    required this.icon,
    this.onTap,
    this.loading = false,
    this.hint,
  });

  final String label;
  final String value;
  final CardHue hue;
  final AppIcons icon;
  final VoidCallback? onTap;
  final bool loading;

  /// Small text after the value, e.g. "28 in all".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = hue.of(Theme.of(context).brightness);
    return Semantics(
      button: onTap != null,
      label: hint == null ? '$label: $value' : '$label: $value, $hint',
      excludeSemantics: true,
      child: TonalCard(
        hue: hue,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TonalHeader(hue: hue, label: label, icon: icon),
            const SizedBox(height: 4),
            SizedBox(
              height: 30,
              child: loading
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Container(width: 40, height: 20, decoration: BoxDecoration(color: t.tile, borderRadius: BorderRadius.circular(6))),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(child: FitText(value, style: AppText.metric.copyWith(color: t.ink))),
                        if (hint != null) ...[
                          const SizedBox(width: 6),
                          Flexible(child: OneLineText(hint!, style: AppText.footnote.copyWith(color: t.inkSoft))),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
