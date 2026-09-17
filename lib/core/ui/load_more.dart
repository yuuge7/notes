import 'package:flutter/widgets.dart';

/// Asks for the next page of a list once its end comes within two screens of
/// the visible part.
///
/// Listens to the scrollable below it: to scrolling, and to changes in its
/// size, so a first page too short to scroll still asks for more. Asks once
/// for each number of [loaded] items, so the frames before the next page
/// lands do not ask again.
class LoadMore extends StatefulWidget {
  const LoadMore({
    required this.loaded,
    required this.hasMore,
    required this.onMore,
    required this.child,
    super.key,
  });

  /// How many items are loaded now.
  final int loaded;
  final bool hasMore;
  final VoidCallback onMore;
  final Widget child;

  @override
  State<LoadMore> createState() => _LoadMoreState();
}

class _LoadMoreState extends State<LoadMore> {
  int? _askedAt;

  bool _check(ScrollMetrics metrics) {
    if (!widget.hasMore || _askedAt == widget.loaded) return false;
    if (metrics.extentAfter < metrics.viewportDimension * 2) {
      _askedAt = widget.loaded;
      widget.onMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _check(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _check(notification.metrics),
        child: widget.child,
      ),
    );
  }
}
