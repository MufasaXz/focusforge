import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// The four tabs as pages side by side: a horizontal swipe moves to the next
/// or previous tab, the way a tap on the bar does.
///
/// Every tab stays alive, as it did in the indexed stack this replaces, so a
/// swipe away and back keeps each tab's scroll position and any screen pushed
/// inside it. Only the tab in view runs its animations. A tap on the bar jumps
/// straight to its tab rather than sliding past the ones between, because the
/// shell already plays its own short fade for that.
class SwipeableBranches extends StatefulWidget {
  const SwipeableBranches({
    super.key,
    required this.shell,
    required this.children,
  });

  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  State<SwipeableBranches> createState() => _SwipeableBranchesState();
}

class _SwipeableBranchesState extends State<SwipeableBranches> {
  late final PageController _pages = PageController(
    initialPage: widget.shell.currentIndex,
  );

  @override
  void didUpdateWidget(covariant SwipeableBranches oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.shell.currentIndex;
    if (!_pages.hasClients) return;
    // A swipe has already put the pages where the shell now is. Anything
    // else changed the branch from outside, such as the bar or a deep link.
    if ((_pages.page ?? target).round() != target) _pages.jumpToPage(target);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _settle(int index) {
    if (index == widget.shell.currentIndex) return;
    HapticFeedback.selectionClick();
    widget.shell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.shell.currentIndex;
    return PageView(
      controller: _pages,
      onPageChanged: _settle,
      children: [
        for (final (index, child) in widget.children.indexed)
          _KeepAlive(
            child: TickerMode(enabled: index == current, child: child),
          ),
      ],
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
