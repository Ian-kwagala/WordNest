import 'dart:math';

import '../domain/models/word_pack_models.dart';

/// Builds deterministic 8-direction word-search boards from a [PuzzleLevel].
class PuzzleGenerator {
  const PuzzleGenerator();

  /// All 8 valid word directions: horizontal, vertical, and 45-degree diagonals.
  static const List<GridCoord> directions = [
    GridCoord(0, 1), // Right
    GridCoord(0, -1), // Left
    GridCoord(1, 0), // Down
    GridCoord(-1, 0), // Up
    GridCoord(1, 1), // Down-Right
    GridCoord(1, -1), // Down-Left
    GridCoord(-1, 1), // Up-Right
    GridCoord(-1, -1), // Up-Left
  ];

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Generates a [GeneratedPuzzle] using [level.seed] so layouts stay consistent.
  GeneratedPuzzle generate(PuzzleLevel level) {
    final size = level.gridSize;
    // Place longest words first to minimize collisions inside smaller grids.
    final sortedWords = List<String>.from(level.words)
      ..sort((a, b) => b.length.compareTo(a.length));

    // Try deterministic seed offsets until every word fits cleanly.
    for (var attempt = 0; attempt < 24; attempt++) {
      final rng = Random(level.seed + attempt * 7919);
      final board = List.generate(size, (_) => List.filled(size, ''));
      final placed = <PlacedWord>[];
      var allPlaced = true;

      for (final word in sortedWords) {
        final coords = _tryPlaceWord(board, word, size, rng);
        if (coords == null) {
          allPlaced = false;
          break;
        }
        placed.add(
          PlacedWord(
            word: word,
            cells: coords,
            clue: level.clueForWord(word),
          ),
        );
      }

      if (allPlaced) {
        // Fill remaining empty cells with random uppercase letters.
        final fillRng = Random(level.seed ^ 0x5A5A5A5A);
        for (var r = 0; r < size; r++) {
          for (var c = 0; c < size; c++) {
            if (board[r][c].isEmpty) {
              board[r][c] = _alphabet[fillRng.nextInt(_alphabet.length)];
            }
          }
        }

        // Preserve original level word order for the word bank UI.
        final byWord = {for (final p in placed) p.word: p};
        final orderedPlaced = [
          for (final w in level.words) byWord[w]!,
        ];

        return GeneratedPuzzle(
          size: size,
          grid: board,
          placedWords: orderedPlaced,
        );
      }
    }

    throw StateError(
      'Unable to place all words for level ${level.levelNumber} on a ${size}x$size board.',
    );
  }

  /// Finds a valid start cell and direction for [word] and writes it into [board].
  List<GridCoord>? _tryPlaceWord(
    List<List<String>> board,
    String word,
    int size,
    Random rng,
  ) {
    // Build every (row, col, dir) candidate and shuffle for balanced direction spread.
    final candidates = <_PlacementCandidate>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        for (final dir in directions) {
          candidates.add(_PlacementCandidate(r, c, dir));
        }
      }
    }
    candidates.shuffle(rng);

    for (final candidate in candidates) {
      final cells = _cellsIfFits(
        board: board,
        word: word,
        startRow: candidate.row,
        startCol: candidate.col,
        dir: candidate.dir,
        size: size,
      );
      if (cells != null) {
        for (var i = 0; i < word.length; i++) {
          final cell = cells[i];
          board[cell.row][cell.col] = word[i];
        }
        return cells;
      }
    }
    return null;
  }

  /// Checks bounds and verifies empty cells or matching crossing letters.
  List<GridCoord>? _cellsIfFits({
    required List<List<String>> board,
    required String word,
    required int startRow,
    required int startCol,
    required GridCoord dir,
    required int size,
  }) {
    final endRow = startRow + dir.row * (word.length - 1);
    final endCol = startCol + dir.col * (word.length - 1);

    if (endRow < 0 || endRow >= size || endCol < 0 || endCol >= size) {
      return null;
    }

    final cells = <GridCoord>[];
    for (var i = 0; i < word.length; i++) {
      final r = startRow + dir.row * i;
      final c = startCol + dir.col * i;
      final existing = board[r][c];
      if (existing.isNotEmpty && existing != word[i]) {
        return null;
      }
      cells.add(GridCoord(r, c));
    }
    return cells;
  }

  /// Snaps a drag from [start] toward [target] onto the nearest 8-way ray inside [gridSize].
  static List<GridCoord> snappedLineCells({
    required GridCoord start,
    required GridCoord target,
    required int gridSize,
  }) {
    final dr = target.row - start.row;
    final dc = target.col - start.col;

    if (dr == 0 && dc == 0) {
      return [start];
    }

    // Snap angle to the closest multiple of 45 degrees (8 directions).
    final angle = atan2(dr.toDouble(), dc.toDouble());
    const sector = pi / 4;
    final snappedIndex = (angle / sector).round();
    final snappedAngle = snappedIndex * sector;

    final stepR = sin(snappedAngle).round();
    final stepC = cos(snappedAngle).round();

    if (stepR == 0 && stepC == 0) {
      return [start];
    }

    // Project drag distance onto the snapped unit vector to determine length.
    final steps = max(dr.abs(), dc.abs());
    final cells = <GridCoord>[];
    for (var i = 0; i <= steps; i++) {
      final r = start.row + stepR * i;
      final c = start.col + stepC * i;
      if (r < 0 || r >= gridSize || c < 0 || c >= gridSize) {
        break;
      }
      cells.add(GridCoord(r, c));
    }
    return cells;
  }
}

class _PlacementCandidate {
  const _PlacementCandidate(this.row, this.col, this.dir);
  final int row;
  final int col;
  final GridCoord dir;
}
