import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordnest/domain/models/word_pack_models.dart';
import 'package:wordnest/logic/puzzle_generator.dart';
import 'package:wordnest/services/storage_service.dart';

void main() {
  group('Offline word_packs.json & PuzzleGenerator', () {
    test('all 110 levels load and generate valid deterministic grids', () {
      final file = File('assets/data/word_packs.json');
      expect(file.existsSync(), isTrue);

      // Verify offline JSON stays well under the 200 KB blueprint budget.
      expect(file.lengthSync(), lessThan(200 * 1024));

      final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final rawThemes =
          (decoded['themes'] as List<dynamic>).cast<Map<String, dynamic>>();
      final themes = rawThemes.map(WordThemePack.fromJson).toList();

      expect(themes.length, greaterThanOrEqualTo(10));

      const generator = PuzzleGenerator();
      var totalLevels = 0;

      for (final theme in themes) {
        for (final level in theme.levels) {
          totalLevels++;
          final puzzle = generator.generate(level);

          expect(puzzle.size, equals(level.gridSize));
          expect(puzzle.grid.length, equals(level.gridSize));
          expect(puzzle.placedWords.length, equals(level.words.length));
          expect(level.mysteryClues.length, inInclusiveRange(1, 2));

          // Every cell must contain a single A-Z character.
          for (final row in puzzle.grid) {
            expect(row.length, equals(level.gridSize));
            for (final cell in row) {
              expect(RegExp(r'^[A-Z]$').hasMatch(cell), isTrue);
            }
          }

          // Every placed word must match the letters on the generated board.
          for (final placed in puzzle.placedWords) {
            final letters = placed.cells
                .map((c) => puzzle.grid[c.row][c.col])
                .join();
            expect(letters, equals(placed.word));
          }

          // Deterministic check: second generation produces the exact same board.
          final second = generator.generate(level);
          expect(second.grid, equals(puzzle.grid));
        }
      }

      expect(totalLevels, greaterThanOrEqualTo(100));
    });

    test('snappedLineCells snaps drags cleanly to 8 directions', () {
      final diagonal = PuzzleGenerator.snappedLineCells(
        start: const GridCoord(1, 1),
        target: const GridCoord(4, 3), // Close to down-right 45 degrees
        gridSize: 8,
      );
      expect(diagonal.first, equals(const GridCoord(1, 1)));
      expect(diagonal[1], equals(const GridCoord(2, 2)));
      expect(diagonal[2], equals(const GridCoord(3, 3)));
      expect(diagonal.length, equals(4));
    });
  });

  group('StorageService', () {
    test('defaults to 3 free hints and persists level stars and progress', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();

      expect(storage.hintsRemaining, equals(3));
      expect(storage.soundEnabled, isTrue);

      await storage.saveActiveFoundWords(
        themeId: 'animals',
        levelNumber: 1,
        words: ['CAT', 'OWL'],
      );
      expect(storage.getActiveFoundWords('animals', 1), equals(['CAT', 'OWL']));

      final total = await storage.markLevelCompleted(
        themeId: 'animals',
        levelNumber: 1,
        stars: 3,
      );
      expect(total, equals(1));
      expect(storage.starsForLevel('animals', 1), equals(3));
      expect(storage.streakCount, equals(1));
      expect(storage.getActiveFoundWords('animals', 1), isEmpty);
    });
  });
}
