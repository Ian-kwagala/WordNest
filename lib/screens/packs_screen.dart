import 'package:flutter/material.dart';

import '../domain/models/word_pack_models.dart';
import '../services/ad_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../ui/core/app_theme.dart';
import 'puzzle_screen.dart';

/// Home screen displaying themed packs, completion progress bars, streaks,
/// and the 5-Minute Daily Sprint mode.
class PacksScreen extends StatefulWidget {
  const PacksScreen({
    super.key,
    required this.themes,
    required this.storage,
    required this.sound,
    required this.ads,
  });

  final List<WordThemePack> themes;
  final StorageService storage;
  final SoundService sound;
  final AdService ads;

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  Future<void> _openPuzzle({
    required int themeIndex,
    required int levelIndex,
    bool isDailySprint = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PuzzleScreen(
          themes: widget.themes,
          initialThemeIndex: themeIndex,
          initialLevelIndex: levelIndex,
          storage: widget.storage,
          sound: widget.sound,
          ads: widget.ads,
          isDailySprint: isDailySprint,
        ),
      ),
    );
    // Refresh progress bars, stars, and streak count when returning from a game.
    if (mounted) {
      setState(() {});
    }
  }

  /// Picks a daily starting theme/level based on the calendar day.
  (int themeIndex, int levelIndex) _todaySprintStart() {
    final now = DateTime.now();
    final dayHash = now.year * 372 + now.month * 31 + now.day;
    final themeIndex = dayHash % widget.themes.length;
    final levelIndex = dayHash % widget.themes[themeIndex].levels.length;
    return (themeIndex, levelIndex);
  }

  /// Finds the first uncompleted level in [theme], or level 0 if all are done.
  int _nextLevelIndexForTheme(WordThemePack theme) {
    for (var i = 0; i < theme.levels.length; i++) {
      final stars = widget.storage.starsForLevel(
        theme.id,
        theme.levels[i].levelNumber,
      );
      if (stars == 0) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.storage.streakCount;
    final hints = widget.storage.hintsRemaining;
    final sprintBest = widget.storage.sprintBestWords;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Cozy Coffee Shop Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'WordNest',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: WordNestTheme.letterSlate,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Offline Word Hunt • Cozy Morning Puzzles',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: WordNestTheme.subtleSlate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatPill(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: const Color(0xFFEA580C),
                      label: '${streak}d',
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      icon: Icons.lightbulb_outline_rounded,
                      iconColor: const Color(0xFFB45309),
                      label: '$hints',
                    ),
                  ],
                ),
              ),
            ),

            // Featured 5-Minute Daily Sprint Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    final (tIdx, lIdx) = _todaySprintStart();
                    _openPuzzle(
                      themeIndex: tIdx,
                      levelIndex: lIdx,
                      isDailySprint: true,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: WordNestTheme.coffeeAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '⚡',
                            style: TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '5-Minute Daily Sprint',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                sprintBest > 0
                                    ? 'Race the gentle timer • Best: $sprintBest words'
                                    : 'Find as many words as you can in 5:00!',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFD1FAE5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Section Title
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Text(
                  'Themed Word Packs',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: WordNestTheme.letterSlate,
                  ),
                ),
              ),
            ),

            // List of all themed packs with progress bars and level pills
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: widget.themes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, themeIndex) {
                  final theme = widget.themes[themeIndex];
                  final completed =
                      widget.storage.completedCountForTheme(theme.id);
                  final total = theme.levels.length;
                  final progress = total > 0 ? completed / total : 0.0;
                  final accent = WordNestTheme.parseHex(theme.accentColorHex);
                  final nextIdx = _nextLevelIndexForTheme(theme);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  theme.icon,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      theme.title,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w800,
                                        color: WordNestTheme.letterSlate,
                                      ),
                                    ),
                                    Text(
                                      theme.subtitle,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: WordNestTheme.subtleSlate,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: WordNestTheme.coffeeAccent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: () => _openPuzzle(
                                  themeIndex: themeIndex,
                                  levelIndex: nextIdx,
                                ),
                                child: Text('Lvl ${nextIdx + 1}'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Progress bar
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 7,
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$completed/$total',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: WordNestTheme.subtleSlate,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Quick level selector pills
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: List.generate(theme.levels.length, (lvlIdx) {
                              final lvlNum = theme.levels[lvlIdx].levelNumber;
                              final stars = widget.storage.starsForLevel(
                                theme.id,
                                lvlNum,
                              );
                              final done = stars > 0;
                              return InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _openPuzzle(
                                  themeIndex: themeIndex,
                                  levelIndex: lvlIdx,
                                ),
                                child: Container(
                                  width: 34,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: done
                                        ? accent.withValues(alpha: 0.35)
                                        : WordNestTheme.paperBackground,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: done
                                          ? accent
                                          : WordNestTheme.borderSoft,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    done ? '$lvlNum★' : '$lvlNum',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: WordNestTheme.letterSlate,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WordNestTheme.gridCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WordNestTheme.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: WordNestTheme.letterSlate,
            ),
          ),
        ],
      ),
    );
  }
}
