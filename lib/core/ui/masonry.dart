import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Cards in equal-width columns, each placed under whichever column is
/// shortest so far, the way a masonry grid fills.
///
/// A box, not a sliver. The grid and search stack several groups of cards
/// under their own headers, and `SliverMasonryGrid` from
/// flutter_staggered_grid_view cannot be stacked like that: once a group was
/// scrolled a cache extent past the top of the screen it pulled the scroll
/// position back, so the page stopped short of its end. A group laid out here
/// can be one item of a lazy list instead, so groups far off screen are still
/// not built.
class MasonryColumns extends MultiChildRenderObjectWidget {
  const MasonryColumns({
    required this.columns,
    required this.spacing,
    required super.children,
    super.key,
  }) : assert(columns > 0, 'MasonryColumns needs at least one column');

  final int columns;

  /// The gap between columns, and between cards in a column.
  final double spacing;

  @override
  RenderMasonryColumns createRenderObject(BuildContext context) =>
      RenderMasonryColumns(columns: columns, spacing: spacing);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMasonryColumns renderObject,
  ) {
    renderObject
      ..columns = columns
      ..spacing = spacing;
  }
}

class MasonryColumnsParentData extends ContainerBoxParentData<RenderBox>;

class RenderMasonryColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MasonryColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MasonryColumnsParentData> {
  RenderMasonryColumns({required this._columns, required this._spacing});

  int get columns => _columns;
  int _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  double get spacing => _spacing;
  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MasonryColumnsParentData) {
      child.parentData = MasonryColumnsParentData();
    }
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth,
      'MasonryColumns needs a bounded width to divide into columns',
    );
    final width = constraints.maxWidth;
    final columnWidth = math.max(
      0,
      (width - spacing * (columns - 1)) / columns,
    ).toDouble();
    // Each column's filled height, counting the gap under its last card.
    final heights = List<double>.filled(columns, 0);

    var child = firstChild;
    while (child != null) {
      // The shortest column, leftmost on a tie.
      var column = 0;
      for (var i = 1; i < columns; i++) {
        if (heights[i] < heights[column]) column = i;
      }
      child.layout(
        BoxConstraints.tightFor(width: columnWidth),
        parentUsesSize: true,
      );
      final parentData = child.parentData! as MasonryColumnsParentData
        ..offset = Offset(column * (columnWidth + spacing), heights[column]);
      heights[column] += child.size.height + spacing;
      child = parentData.nextSibling;
    }

    final tallest = heights.reduce(math.max);
    size = constraints.constrain(
      Size(width, math.max(0, tallest - spacing).toDouble()),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
