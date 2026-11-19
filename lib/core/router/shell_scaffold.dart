import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/context_ext.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../design/app_icons.dart';

class _Tab {
  const _Tab(this.label, this.icon);
  final String label;
  final AppIcons icon;
}

const _tabs = [
  _Tab('Home', AppIcons.home),
  _Tab('Samples', AppIcons.samples),
  _Tab('Offers', AppIcons.offers),
  _Tab('Bids', AppIcons.bids),
  _Tab('More', AppIcons.more),
];

/// Tab shell: bottom bar on phones, a left rail on tablets. Home is the first
/// tab and is selected on launch.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.shortestSide >= 600;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(current: shell.currentIndex, onTap: _go),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: _BottomBar(current: shell.currentIndex, onTap: _go),
    );
  }
}

/// Solid bar in the surface colour with a hairline on top. Content ends
/// above it instead of scrolling underneath.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.onTap});
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final safe = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.separator, width: 0.5)),
      ),
      padding: EdgeInsets.only(top: 6, bottom: safe > 0 ? safe : 6),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(child: _TabButton(tab: _tabs[i], active: i == current, onTap: () => onTap(i))),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.active, required this.onTap});
  final _Tab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.accent : c.textTertiary;
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            _TileIcon(icon: tab.icon, color: color, tinted: active),
            const SizedBox(height: 3),
            Text(tab.label, style: AppText.tabLabel.copyWith(color: color), maxLines: 1),
          ],
        ),
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, required this.color, required this.tinted});
  final AppIcons icon;
  final Color color;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 30,
      decoration: ShapeDecoration(
        color: tinted ? context.colors.accentTint : Colors.transparent,
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      child: AppIcon(icon, size: 21, color: color),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.current, required this.onTap});
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      right: false,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.xxl),
            for (var i = 0; i < _tabs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.lg),
                child: _TabButton(tab: _tabs[i], active: i == current, onTap: () => onTap(i)),
              ),
          ],
        ),
      ),
    );
  }
}
