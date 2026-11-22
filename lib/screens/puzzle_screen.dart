import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../domain/models/word_pack_models.dart';
import '../logic/puzzle_generator.dart';
import '../services/ad_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../ui/core/app_theme.dart';
import '../widgets/letter_grid.dart';

/// Main word-search puzzle screen supporting Classic Theme Packs and
/// 5-Minute Daily Sprint mode.
class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({
    super.key,
    required this.themes,
    required this.initialThemeIndex,
    required this.initialLevelIndex,
    required this.storage,
    required this.sound,
    required this.ads,
    this.isDailySprint = false,
  });

  final List<WordThemePack> themes;
  final int initialThemeIndex;
  final int initialLevelIndex;
  final StorageService storage;
  final SoundService sound;
  final AdService ads;
  final bool isDailySprint;

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  static const _generator = PuzzleGenerator();
  static const int _sprintDurationSeconds = 300; // 5 minutes

  late int _themeIndex;
  late int _levelIndex;
  late GeneratedPuzzle _puzzle;

  final List<FoundWordHighlight> _foundHighlights = [];
  final Set<String> _foundWords = {};
  GridCoord? _hintedCell;
  int _hintsUsedThisLevel = 0;

  late bool _soundEnabled;
  late int _hintsRemaining;
  bool _levelCompletedDialogOpen = false;

  // Daily Sprint timer & score tracking.
  Timer? _sprintTimer;
  int _sprintSecondsLeft = _sprintDurationSeconds;
  int _sprintWordsFound = 0;

  // Adaptive banner ad (stays hidden when offline or failed to load).
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  bool _bannerRequested = false;

  WordThemePack get _currentTheme => widget.themes[_themeIndex];
  PuzzleLevel get _currentLevel => _currentTheme.levels[_levelIndex];

  Color get _nextHighlightColor {
    return WordNestTheme.highlighterColors[
        _foundHighlights.length % WordNestTheme.highlighterColors.length];
  }

  @override
  void initState() {
    super.initState();
    _themeIndex = widget.initialThemeIndex;
    _levelIndex = widget.initialLevelIndex;
    _soundEnabled = widget.storage.soundEnabled;
    _hintsRemaining = widget.storage.hintsRemaining;

    _loadBoard(restoreProgress: !widget.isDailySprint);

    if (widget.isDailySprint) {
      _startSprintTimer();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bannerRequested) {
      _bannerRequested = true;
      final width = MediaQuery.sizeOf(context).width.truncate();
      if (width > 0) {
        _bannerAd = widget.ads.createAdaptiveBanner(
          widthPx: width,
          onLoaded: (ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _bannerAd = ad;
              _isBannerLoaded = true;
            });
          },
          onFailed: () {
            if (mounted) {
              setState(() {
                _bannerAd = null;
                _isBannerLoaded = false;
              });
            }
          },
        );
      }
    }
  }

  @override
  void dispose() {
    _sprintTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _startSprintTimer() {
    _sprintTimer?.cancel();
    _sprintSecondsLeft = _sprintDurationSeconds;
    _sprintTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_sprintSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _sprintSecondsLeft = 0);
        _showSprintFinishedDialog();
      } else {
        setState(() => _sprintSecondsLeft--);
      }
    });
  }

  void _loadBoard({required bool restoreProgress}) {
    _puzzle = _generator.generate(_currentLevel);
    _foundHighlights.clear();
    _foundWords.clear();
    _hintedCell = null;
    _hintsUsedThisLevel = 0;

    if (restoreProgress) {
      final saved = widget.storage.getActiveFoundWords(
        _currentTheme.id,
        _currentLevel.levelNumber,
      );
      for (final word in saved) {
        final match = _puzzle.placedWords
            .where((p) => p.word == word)
            .firstOrNull;
        if (match != null) {
          _foundWords.add(word);
          _foundHighlights.add(
            FoundWordHighlight(
              word: word,
              cells: match.cells,
              colorIndex: _foundHighlights.length,
            ),
          );
        }
      }
    }
  }

  Future<void> _onSelectionComplete(List<GridCoord> cells, String rawWord) async {
    if (cells.length < 3 || _levelCompletedDialogOpen) return;

    final reversed = rawWord.split('').reversed.join();
    PlacedWord? matched;

    for (final target in _puzzle.placedWords) {
      if (_foundWords.contains(target.word)) continue;
      if (target.word == rawWord || target.word == reversed) {
        matched = target;
        break;
      }
    }

    if (matched == null) {
      await widget.sound.playWrongSwipe();
      return;
    }

    await widget.sound.playWordFound();

    setState(() {
      _foundWords.add(matched!.word);
      _foundHighlights.add(
        FoundWordHighlight(
          word: matched.word,
          cells: cells,
          colorIndex: _foundHighlights.length,
        ),
      );
      // Clear hint ring once that hinted cell's word is found.
      if (_hintedCell != null && matched.cells.contains(_hintedCell)) {
        _hintedCell = null;
      }
      if (widget.isDailySprint) {
        _sprintWordsFound++;
      }
    });

    if (!widget.isDailySprint) {
      await widget.storage.saveActiveFoundWords(
        themeId: _currentTheme.id,
        levelNumber: _currentLevel.levelNumber,
        words: _foundWords.toList(),
      );
    }

    if (_foundWords.length == _puzzle.placedWords.length) {
      await _handleBoardCleared();
    }
  }

  Future<void> _handleBoardCleared() async {
    await widget.sound.playLevelComplete();

    if (widget.isDailySprint) {
      // Advance immediately to the next themed puzzle while the sprint timer runs.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || _sprintSecondsLeft <= 0) return;
      setState(() {
        _advanceNextLevelIndex();
        _loadBoard(restoreProgress: false);
      });
      return;
    }

    final stars = _hintsUsedThisLevel == 0
        ? 3
        : _hintsUsedThisLevel == 1
            ? 2
            : 1;

    final totalCompleted = await widget.storage.markLevelCompleted(
      themeId: _currentTheme.id,
      levelNumber: _currentLevel.levelNumber,
      stars: stars,
    );

    if (!mounted) return;
    _levelCompletedDialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LevelCompleteDialog(
        themeTitle: _currentTheme.title,
        levelNumber: _currentLevel.levelNumber,
        stars: stars,
        hasNextLevel: _hasNextLevel(),
        onNextLevel: () async {
          Navigator.of(ctx).pop();
          _levelCompletedDialogOpen = false;
          // Show interstitial cleanly every 2 levels completed with 1s safety pause.
          await widget.ads.maybeShowLevelClearInterstitial(totalCompleted);
          if (!mounted) return;
          setState(() {
            _advanceNextLevelIndex();
            _loadBoard(restoreProgress: true);
          });
        },
        onBackToPacks: () {
          Navigator.of(ctx).pop();
          _levelCompletedDialogOpen = false;
          Navigator.of(context).pop();
        },
      ),
    );
  }

  bool _hasNextLevel() {
    if (_levelIndex + 1 < _currentTheme.levels.length) return true;
    return _themeIndex + 1 < widget.themes.length;
  }

  void _advanceNextLevelIndex() {
    if (_levelIndex + 1 < _currentTheme.levels.length) {
      _levelIndex++;
    } else {
      _themeIndex = (_themeIndex + 1) % widget.themes.length;
      _levelIndex = 0;
    }
  }

  Future<void> _onHintTapped() async {
    final remaining = _puzzle.placedWords
        .where((p) => !_foundWords.contains(p.word))
        .toList();
    if (remaining.isEmpty) return;

    if (_hintsRemaining <= 0) {
      await _promptRewardedHintRefill();
      return;
    }

    // Prefer hinting a mystery clue word first if one is still unfound.
    final target = remaining.firstWhere(
      (p) => p.isMystery,
      orElse: () => remaining.first,
    );

    await widget.sound.playHintSparkle();
    final nextHints = _hintsRemaining - 1;
    await widget.storage.setHintsRemaining(nextHints);

    if (!mounted) return;
    setState(() {
      _hintsRemaining = nextHints;
      _hintsUsedThisLevel++;
      _hintedCell = target.start;
    });
  }

  Future<void> _promptRewardedHintRefill() async {
    final watchAd = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WordNestTheme.gridCard,
        title: const Text('Out of Hints'),
        content: const Text(
          'Watch a short video ad to refill +2 Hint Bulbs and reveal a hidden starting letter!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: WordNestTheme.coffeeAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Get +2 Hints'),
          ),
        ],
      ),
    );

    if (watchAd != true) return;
    final rewarded = await widget.ads.showRewardedHintAd();
    if (!mounted) return;

    if (rewarded) {
      final updated = _hintsRemaining + 2;
      await widget.storage.setHintsRemaining(updated);
      if (!mounted) return;
      setState(() => _hintsRemaining = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nice! +2 Hints added.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video ad is unavailable right now (connect to internet to refill hints).',
          ),
        ),
      );
    }
  }

  Future<void> _toggleSound() async {
    final next = !_soundEnabled;
    widget.sound.setEnabled(next);
    await widget.storage.setSoundEnabled(next);
    if (mounted) {
      setState(() => _soundEnabled = next);
    }
  }

  Future<void> _showSprintFinishedDialog() async {
    await widget.storage.recordSprintScore(_sprintWordsFound);
    final best = widget.storage.sprintBestWords;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: WordNestTheme.gridCard,
        title: const Text('⏱️ Daily Sprint Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Words Found: $_sprintWordsFound',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: WordNestTheme.letterSlate,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Personal Best: $best words',
              style: const TextStyle(color: WordNestTheme.subtleSlate),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Back to Packs'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WordNestTheme.coffeeAccent,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _sprintWordsFound = 0;
                _advanceNextLevelIndex();
                _loadBoard(restoreProgress: false);
                _startSprintTimer();
              });
            },
            child: const Text('Sprint Again'),
          ),
        ],
      ),
    );
  }

  String _formatTimer(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final plainWords =
        _puzzle.placedWords.where((p) => !p.isMystery).toList();
    final mysteryWords =
        _puzzle.placedWords.where((p) => p.isMystery).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Bar: Back, Theme & Level (or Sprint Timer), Hint Bulb, Sound toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to Packs',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isDailySprint
                              ? '⚡ 5-Min Daily Sprint'
                              : '${_currentTheme.title} • Level ${_currentLevel.levelNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: WordNestTheme.letterSlate,
                          ),
                        ),
                        Text(
                          widget.isDailySprint
                              ? 'Time: ${_formatTimer(_sprintSecondsLeft)} • $_sprintWordsFound words'
                              : '${_foundWords.length} / ${_puzzle.placedWords.length} words found',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: WordNestTheme.subtleSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Hint Bulb button with remaining count badge
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _onHintTapped,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: WordNestTheme.warmCream,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFDE047)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 18,
                            color: Color(0xFFB45309),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_hintsRemaining',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _soundEnabled ? 'Mute sound' : 'Unmute sound',
                    onPressed: _toggleSound,
                    icon: Icon(
                      _soundEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                    ),
                  ),
                ],
              ),
            ),

            // 2. Center: Square Letter Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: LetterGrid(
                  grid: _puzzle.grid,
                  foundHighlights: _foundHighlights,
                  activeHighlightColor: _nextHighlightColor,
                  hintedCell: _hintedCell,
                  onStepCell: widget.sound.playLetterTick,
                  onSelectionComplete: _onSelectionComplete,
                ),
              ),
            ),

            // 3. Word Bank Area: Clean 2/3-column words + Mystery Clue cards
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Plain Word Bank in a clean multi-column layout
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: plainWords.map((placed) {
                        final isFound = _foundWords.contains(placed.word);
                        return _WordChip(
                          word: placed.word,
                          isFound: isFound,
                        );
                      }).toList(),
                    ),

                    // Mystery Clue Words section
                    if (mysteryWords.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...mysteryWords.map((placed) {
                        final isFound = _foundWords.contains(placed.word);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _MysteryClueBanner(
                            word: placed.word,
                            clue: placed.clue ?? '',
                            isFound: isFound,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            // 4. Bottom: AdMob Adaptive Banner (hidden cleanly if offline)
            if (_isBannerLoaded && _bannerAd != null)
              Container(
                color: WordNestTheme.paperBackground,
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.isFound,
  });

  final String word;
  final bool isFound;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isFound ? const Color(0xFFECFDF5) : WordNestTheme.gridCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFound ? const Color(0xFF6EE7B7) : WordNestTheme.borderSoft,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFound) ...[
            const Icon(
              Icons.check_circle_rounded,
              size: 15,
              color: Color(0xFF059669),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            word,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isFound
                  ? WordNestTheme.subtleSlate
                  : WordNestTheme.letterSlate,
              decoration: isFound ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MysteryClueBanner extends StatelessWidget {
  const _MysteryClueBanner({
    required this.word,
    required this.clue,
    required this.isFound,
  });

  final String word;
  final String clue;
  final bool isFound;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isFound ? const Color(0xFFECFDF5) : WordNestTheme.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFound ? const Color(0xFF6EE7B7) : const Color(0xFFFDE047),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFound ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
            size: 17,
            color: isFound ? const Color(0xFF059669) : const Color(0xFFB45309),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isFound ? '$word — $clue' : 'Mystery Clue: $clue',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isFound
                    ? WordNestTheme.subtleSlate
                    : const Color(0xFF78350F),
                decoration: isFound ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelCompleteDialog extends StatelessWidget {
  const _LevelCompleteDialog({
    required this.themeTitle,
    required this.levelNumber,
    required this.stars,
    required this.hasNextLevel,
    required this.onNextLevel,
    required this.onBackToPacks,
  });

  final String themeTitle;
  final int levelNumber;
  final int stars;
  final bool hasNextLevel;
  final VoidCallback onNextLevel;
  final VoidCallback onBackToPacks;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: WordNestTheme.gridCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text(
        'Puzzle Complete!',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$themeTitle • Level $levelNumber',
            style: const TextStyle(
              color: WordNestTheme.subtleSlate,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final earned = index < stars;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  earned ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 38,
                  color: earned
                      ? const Color(0xFFF59E0B)
                      : WordNestTheme.borderSoft,
                ),
              );
            }),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: onBackToPacks,
          child: const Text('Packs'),
        ),
        if (hasNextLevel)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WordNestTheme.coffeeAccent,
            ),
            onPressed: onNextLevel,
            child: const Text('Next Level'),
          ),
      ],
    );
  }
}
