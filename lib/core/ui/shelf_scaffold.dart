import 'package:flutter/material.dart';

/// The scaffold for a shelf screen, with back handled the way Android 16 and
/// later need it.
///
/// From Android 16 the system takes a back press unless the app has claimed
/// it, and an open [Drawer] does not claim back on its own: its local history
/// entry tells the route "I can pop", not "don't pop", so nothing reaches the
/// platform. One back press with the drawer open left the app. This scaffold
/// refuses the pop while the drawer is open — which does claim back — and
/// closes the drawer instead.
class ShelfScaffold extends StatefulWidget {
  const ShelfScaffold({
    required this.drawer,
    required this.body,
    required this.canPop,
    this.onBlockedPop,
    super.key,
  });

  final Widget drawer;
  final Widget body;

  /// Whether back may leave this screen once the drawer is closed.
  final bool canPop;

  /// Runs when back is pressed with the drawer closed and [canPop] false,
  /// such as clearing a selection.
  final VoidCallback? onBlockedPop;

  @override
  State<ShelfScaffold> createState() => _ShelfScaffoldState();
}

class _ShelfScaffoldState extends State<ShelfScaffold> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.canPop && !_drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }
        widget.onBlockedPop?.call();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: widget.drawer,
        onDrawerChanged: (open) => setState(() => _drawerOpen = open),
        body: widget.body,
      ),
    );
  }
}
