import 'package:flutter/material.dart';

import '../domain/models/word_pack_models.dart';
import '../logic/puzzle_generator.dart';
import '../ui/core/app_theme.dart';

/// Interactive square letter grid supporting smooth 8-direction finger drags
/// and semi-transparent pastel highlight pills.
class LetterGrid extends StatefulWidget {
  const LetterGrid({
    super.key,
    required this.grid,
    required this.foundHighlights,
    required this.activeHighlightColor,
    required this.onSelectionComplete,
    this.hintedCell,
    this.onStepCell,
  });

  final List<List<String>> grid;
  final List<FoundWordHighlight> foundHighlights;
  final Color activeHighlightColor;
  final void Function(List<GridCoord> cells, String word) onSelectionComplete;
  final GridCoord? hintedCell;
  final VoidCallback? onStepCell;

  @override
  State<LetterGrid> createState() => _LetterGridState();
}

class _LetterGridState extends State<LetterGrid> {
  GridCoord? _dragStart;
  List<GridCoord> _activeCells = const [];
  GridCoord? _lastSnappedEnd;

  int get _size => widget.grid.length;

  /// Converts a local pixel position inside the square grid to a cell coordinate.
  GridCoord? _coordFromOffset(Offset localPosition, double boardSize) {
    if (boardSize <= 0 || _size <= 0) return null;
    final cellSize = boardSize / _size;
    final col = (localPosition.dx / cellSize).floor();
    final row = (localPosition.dy / cellSize).floor();
    if (row < 0 || row >= _size || col < 0 || col >= _size) {
      return null;
    }
    return GridCoord(row, col);
  }

  void _handlePanStart(DragStartDetails details, double boardSize) {
    final coord = _coordFromOffset(details.localPosition, boardSize);
    if (coord == null) return;
    setState(() {
      _dragStart = coord;
      _lastSnappedEnd = coord;
      _activeCells = [coord];
    });
    widget.onStepCell?.call();
  }

  void _handlePanUpdate(DragUpdateDetails details, double boardSize) {
    final start = _dragStart;
    if (start == null) return;

    // Clamp drag coordinates to the board edge so fast swipes stay responsive.
    final clampedOffset = Offset(
      details.localPosition.dx.clamp(0.0, boardSize - 0.01),
      details.localPosition.dy.clamp(0.0, boardSize - 0.01),
    );
    final target = _coordFromOffset(clampedOffset, boardSize);
    if (target == null) return;

    final snapped = PuzzleGenerator.snappedLineCells(
      start: start,
      target: target,
      gridSize: _size,
    );

    final newEnd = snapped.isNotEmpty ? snapped.last : start;
    if (newEnd != _lastSnappedEnd) {
      widget.onStepCell?.call();
      setState(() {
        _lastSnappedEnd = newEnd;
        _activeCells = snapped;
      });
    }
  }

  void _handlePanEnd() {
    if (_activeCells.isNotEmpty) {
      final selectedWord = _activeCells
          .map((c) => widget.grid[c.row][c.col])
          .join();
      widget.onSelectionComplete(_activeCells, selectedWord);
    }
    setState(() {
      _dragStart = null;
      _lastSnappedEnd = null;
      _activeCells = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: WordNestTheme.gridCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: WordNestTheme.borderSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D1F2937),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = constraints.biggest.shortestSide;
            final cellSize = boardSize / _size;
            final fontSize = (cellSize * 0.48).clamp(14.0, 24.0);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _handlePanStart(d, boardSize),
              onPanUpdate: (d) => _handlePanUpdate(d, boardSize),
              onPanEnd: (_) => _handlePanEnd(),
              onPanCancel: _handlePanEnd,
              child: CustomPaint(
                painter: _HighlightPillPainter(
                  gridSize: _size,
                  foundHighlights: widget.foundHighlights,
                  activeCells: _activeCells,
                  activeColor: widget.activeHighlightColor,
                  hintedCell: widget.hintedCell,
                ),
                child: Column(
                  children: List.generate(_size, (row) {
                    return Expanded(
                      child: Row(
                        children: List.generate(_size, (col) {
                          return Expanded(
                            child: Center(
                              child: Text(
                                widget.grid[row][col],
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w800,
                                  color: WordNestTheme.letterSlate,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints rounded semi-transparent highlighter pills underneath letters.
class _HighlightPillPainter extends CustomPainter {
  const _HighlightPillPainter({
    required this.gridSize,
    required this.foundHighlights,
    required this.activeCells,
    required this.activeColor,
    required this.hintedCell,
  });

  final int gridSize;
  final List<FoundWordHighlight> foundHighlights;
  final List<GridCoord> activeCells;
  final Color activeColor;
  final GridCoord? hintedCell;

  @override
  void paint(Canvas canvas, Size size) {
    if (gridSize <= 0) return;
    final cellSize = size.width / gridSize;
    final strokeWidth = cellSize * 0.70;

    // 1. Draw hinted cell ring if the Hint Bulb was tapped.
    if (hintedCell != null) {
      final center = _cellCenter(hintedCell!, cellSize);
      final ringPaint = Paint()
        ..color = const Color(0xFFFDE047).withValues(alpha: 0.72)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, cellSize * 0.42, ringPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFFD97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2;
      canvas.drawCircle(center, cellSize * 0.42, borderPaint);
    }

    // 2. Draw already-found word highlight bars.
    for (final found in foundHighlights) {
      if (found.cells.isEmpty) continue;
      final baseColor = WordNestTheme.highlighterColors[
          found.colorIndex % WordNestTheme.highlighterColors.length];
      _drawPill(
        canvas: canvas,
        start: _cellCenter(found.cells.first, cellSize),
        end: _cellCenter(found.cells.last, cellSize),
        color: baseColor.withValues(alpha: 0.52),
        strokeWidth: strokeWidth,
      );
    }

    // 3. Draw active finger-drag highlight bar on top.
    if (activeCells.isNotEmpty) {
      _drawPill(
        canvas: canvas,
        start: _cellCenter(activeCells.first, cellSize),
        end: _cellCenter(activeCells.last, cellSize),
        color: activeColor.withValues(alpha: 0.65),
        strokeWidth: strokeWidth,
      );
    }
  }

  Offset _cellCenter(GridCoord coord, double cellSize) {
    return Offset(
      (coord.col + 0.5) * cellSize,
      (coord.row + 0.5) * cellSize,
    );
  }

  void _drawPill({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Color color,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw a dot if start == end so single-cell taps still show a round pill.
    if (start == end) {
      canvas.drawCircle(
        start,
        strokeWidth / 2,
        Paint()..color = color,
      );
    } else {
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HighlightPillPainter oldDelegate) {
    return oldDelegate.foundHighlights != foundHighlights ||
        oldDelegate.activeCells != activeCells ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.hintedCell != hintedCell ||
        oldDelegate.gridSize != gridSize;
  }
}
