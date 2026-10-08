import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

const _header = YenkoColors.charcoal;
const _divider = Color(0xFFF9B900);
const _rowBorder = Color(0xFFE0E6ED);
const _selectedRow = Color(0xFFFFF4D1);
const _minColumn = 70.0;
const _maxColumn = 360.0;
const _checkboxWidth = 40.0;
const _headerHeight = 30.0;
const _rowHeight = 32.0;

/// One column of an [AdminTable]. [width] is the starting width; people can
/// drag the handle on the right edge of the header to change it.
class AdminColumn<T> {
  const AdminColumn({
    required this.label,
    required this.width,
    required this.cell,
    this.sortKey,
  });

  final String label;
  final double width;

  /// Builds the cell content; keep it to a single line (rows are 32 px high).
  final Widget Function(T row) cell;

  /// Value the column sorts by. A column without one is not sortable.
  final Object Function(T row)? sortKey;
}

/// Compact, Onboard-style data table: a frozen header, 32 px rows, columns
/// that sort when tapped and resize when their right edge is dragged, a
/// tri-state select-all checkbox, and horizontal scrolling when the columns
/// are wider than the screen. The table must be given a bounded height.
class AdminTable<T> extends StatefulWidget {
  const AdminTable({
    super.key,
    required this.rows,
    required this.idOf,
    required this.columns,
    required this.selected,
    required this.onSelectionChanged,
    required this.onTap,
    this.onLongPress,
    this.onRefresh,
    this.initialSortColumn = 0,
  });

  final List<T> rows;
  final String Function(T row) idOf;
  final List<AdminColumn<T>> columns;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<T> onTap;

  /// Long press (or right click): typically a context menu for the row.
  final void Function(T row, Offset globalPosition)? onLongPress;

  /// Pull-to-refresh on the body.
  final Future<void> Function()? onRefresh;
  final int initialSortColumn;

  @override
  State<AdminTable<T>> createState() => _AdminTableState<T>();
}

class _AdminTableState<T> extends State<AdminTable<T>> {
  late final List<double> _widths = [
    for (final column in widget.columns) column.width,
  ];
  late int _sortColumn = widget.initialSortColumn;
  bool _ascending = true;
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  int _compare(Object a, Object b) {
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
  }

  List<T> get _sorted {
    final key = widget.columns[_sortColumn].sortKey;
    if (key == null) return widget.rows;
    final copy = [...widget.rows]..sort((a, b) => _compare(key(a), key(b)));
    return _ascending ? copy : copy.reversed.toList();
  }

  void _sortBy(int column) {
    if (widget.columns[column].sortKey == null) return;
    setState(() {
      if (_sortColumn == column) {
        _ascending = !_ascending;
      } else {
        _sortColumn = column;
        _ascending = true;
      }
    });
  }

  void _resize(int column, double delta) {
    setState(
      () => _widths[column] = (_widths[column] + delta)
          .clamp(_minColumn, _maxColumn)
          .toDouble(),
    );
  }

  void _toggle(String id) {
    final next = {...widget.selected};
    if (!next.remove(id)) next.add(id);
    widget.onSelectionChanged(next);
  }

  void _toggleAll(List<T> rows, bool? value) {
    final ids = rows.map(widget.idOf).toSet();
    widget.onSelectionChanged(
      value == true
          ? {...widget.selected, ...ids}
          : {...widget.selected}.difference(ids),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return LayoutBuilder(
      builder: (context, constraints) {
        final natural =
            _checkboxWidth +
            _widths.fold<double>(0, (sum, width) => sum + width);
        // Let the last column absorb spare width so the table fills the screen.
        final extra = (constraints.maxWidth - 24 - natural)
            .clamp(0, double.infinity)
            .toDouble();
        final widths = [..._widths];
        widths[widths.length - 1] += extra;
        final tableWidth = natural + extra;
        final visibleSelected = rows
            .where((row) => widget.selected.contains(widget.idOf(row)))
            .length;
        final allValue = rows.isEmpty || visibleSelected == 0
            ? false
            : (visibleSelected == rows.length ? true : null);

        Widget body = ListView.builder(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          itemExtent: _rowHeight,
          itemCount: rows.length,
          itemBuilder: (context, index) => _buildRow(rows[index], widths),
        );
        if (widget.onRefresh != null) {
          // The list sits inside the horizontal scroller, so its scroll
          // notifications arrive one level deep.
          body = RefreshIndicator(
            color: _divider,
            notificationPredicate: (notification) => notification.depth == 1,
            onRefresh: widget.onRefresh!,
            child: body,
          );
        }
        return Scrollbar(
          controller: _horizontal,
          notificationPredicate: (notification) => notification.depth == 0,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  _buildHeader(widths, allValue, rows),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(List<double> widths, bool? allValue, List<T> rows) =>
      Container(
        height: _headerHeight,
        decoration: const BoxDecoration(
          color: _header,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _checkboxWidth,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: _divider, width: 2)),
                ),
                child: Checkbox(
                  value: allValue,
                  tristate: true,
                  onChanged: (value) => _toggleAll(rows, value),
                  fillColor: const WidgetStatePropertyAll(Colors.transparent),
                  checkColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            for (var i = 0; i < widget.columns.length; i++)
              _headerCell(i, widths[i], last: i == widget.columns.length - 1),
          ],
        ),
      );

  Widget _headerCell(int index, double width, {required bool last}) {
    final column = widget.columns[index];
    final active = _sortColumn == index && column.sortKey != null;
    return SizedBox(
      width: width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label:
                '${column.label}, ${!active ? 'not sorted' : (_ascending ? 'sorted ascending' : 'sorted descending')}',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: column.sortKey == null ? null : () => _sortBy(index),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 6, right: 14),
                  decoration: last
                      ? null
                      : const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: _divider, width: 2),
                          ),
                        ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          column.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: .25,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 2),
                        Icon(
                          _ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Resize handle. The eager recognizer claims the pointer at once so
          // the horizontal scroller cannot turn a resize into a scroll.
          Positioned(
            top: 1,
            right: 0,
            bottom: 1,
            child: Semantics(
              label: 'Resize ${column.label} column',
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(EagerGestureRecognizer.new, (_) {}),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerMove: (event) => _resize(index, event.delta.dx),
                  child: SizedBox(
                    width: 18,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: _divider.withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(T row, List<double> widths) {
    final id = widget.idOf(row);
    final selected = widget.selected.contains(id);
    return _HoverRow(
      color: selected ? _selectedRow : Colors.white,
      hoverColor: _header.withValues(alpha: .06),
      onTap: () => widget.onTap(row),
      onLongPress: widget.onLongPress == null
          ? null
          : (position) => widget.onLongPress!(row, position),
      child: Container(
        height: _rowHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _rowBorder)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _checkboxWidth,
              child: Checkbox(
                value: selected,
                onChanged: (_) => _toggle(id),
                fillColor: const WidgetStatePropertyAll(Colors.transparent),
                checkColor: _header,
                side: const BorderSide(color: _header, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            for (var i = 0; i < widget.columns.length; i++)
              SizedBox(
                width: widths[i],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.columns[i].cell(row),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.color,
    required this.hoverColor,
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  final Color color;
  final Color hoverColor;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onLongPress;
  final Widget child;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovering = false;
  Offset _lastPosition = Offset.zero;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    cursor: SystemMouseCursors.click,
    child: Listener(
      onPointerDown: (event) => _lastPosition = event.position,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () => widget.onLongPress!(_lastPosition),
        onSecondaryTapDown: widget.onLongPress == null
            ? null
            : (details) => widget.onLongPress!(details.globalPosition),
        child: Container(
          color: _hovering ? widget.hoverColor : widget.color,
          child: widget.child,
        ),
      ),
    ),
  );
}

/// Plain single-line cell text in the table's 11 px type.
class AdminCellText extends StatelessWidget {
  const AdminCellText(
    this.text, {
    super.key,
    this.bold = false,
    this.muted = false,
  });

  final String text;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 11,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: muted ? YenkoColors.gray : YenkoColors.charcoal,
    ),
  );
}

/// Tiny tinted status chip, like the status column in Onboard's table.
class AdminCellChip extends StatelessWidget {
  const AdminCellChip(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

/// Avatar + name cell.
class AdminNameCell extends StatelessWidget {
  const AdminNameCell(this.name, {super.key, this.dim = false});

  final String name;
  final bool dim;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 10,
        backgroundColor: dim
            ? const Color(0xFFF2D6D7)
            : const Color(0xFFFFE8A3),
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 10,
            color: YenkoColors.charcoal,
          ),
        ),
      ),
      const SizedBox(width: 5),
      Expanded(child: AdminCellText(name, bold: true)),
    ],
  );
}
