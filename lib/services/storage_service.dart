import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Saves level progress, stars, hints, sound settings, and streaks locally.
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyHintsRemaining = 'hints_remaining';
  static const String _keyCompletedStars = 'completed_stars_map';
  static const String _keyActiveFoundWords = 'active_found_words_map';
  static const String _keyStreakCount = 'streak_count';
  static const String _keyLastPlayedDate = 'last_played_date';
  static const String _keyTotalCompletedCount = 'total_completed_count';
  static const String _keySprintBestWords = 'sprint_best_words';

  /// Creates a ready-to-use [StorageService] backed by [SharedPreferences].
  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  /// Whether sound effects are turned on (defaults to true).
  bool get soundEnabled => _prefs.getBool(_keySoundEnabled) ?? true;

  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs.setBool(_keySoundEnabled, enabled);
  }

  /// Remaining Hint Bulb uses. New installs start with 3 free hints.
  int get hintsRemaining => _prefs.getInt(_keyHintsRemaining) ?? 3;

  Future<void> setHintsRemaining(int count) async {
    await _prefs.setInt(_keyHintsRemaining, count.clamp(0, 999));
  }

  /// Best score (words found) in 5-Minute Daily Sprint mode.
  int get sprintBestWords => _prefs.getInt(_keySprintBestWords) ?? 0;

  Future<void> recordSprintScore(int wordsFound) async {
    if (wordsFound > sprintBestWords) {
      await _prefs.setInt(_keySprintBestWords, wordsFound);
    }
  }

  /// Total levels completed across all themes (used for every-2-levels ad pacing).
  int get totalLevelsCompleted => _prefs.getInt(_keyTotalCompletedCount) ?? 0;

  /// Current daily play streak in days.
  int get streakCount => _prefs.getInt(_keyStreakCount) ?? 0;

  /// Builds a consistent key for a specific theme level.
  static String levelKey(String themeId, int levelNumber) =>
      '${themeId}_$levelNumber';

  /// Returns a map of `themeId_levelNumber -> bestStars` (1 to 3).
  Map<String, int> getCompletedStars() {
    final raw = _prefs.getString(_keyCompletedStars);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  /// Returns stars earned for one level, or 0 if not yet completed.
  int starsForLevel(String themeId, int levelNumber) {
    return getCompletedStars()[levelKey(themeId, levelNumber)] ?? 0;
  }

  /// Counts how many levels have been completed in [themeId].
  int completedCountForTheme(String themeId) {
    final prefix = '${themeId}_';
    final stars = getCompletedStars();
    return stars.keys.where((k) => k.startsWith(prefix)).length;
  }

  /// Marks a level complete, updates star rating, daily streak, and clears mid-level save.
  Future<int> markLevelCompleted({
    required String themeId,
    required int levelNumber,
    required int stars,
  }) async {
    final map = getCompletedStars();
    final key = levelKey(themeId, levelNumber);
    final previousStars = map[key] ?? 0;
    if (stars > previousStars) {
      map[key] = stars.clamp(1, 3);
      await _prefs.setString(_keyCompletedStars, jsonEncode(map));
    }

    // Clear saved in-progress words now that the level is finished.
    await saveActiveFoundWords(themeId: themeId, levelNumber: levelNumber, words: []);

    // Increment total completions and update daily streak.
    final nextTotal = totalLevelsCompleted + 1;
    await _prefs.setInt(_keyTotalCompletedCount, nextTotal);
    await _updateStreakForToday();
    return nextTotal;
  }

  /// Returns words already found on an unfinished board so players never lose progress.
  List<String> getActiveFoundWords(String themeId, int levelNumber) {
    final raw = _prefs.getString(_keyActiveFoundWords);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded[levelKey(themeId, levelNumber)];
    if (list is List) {
      return list.cast<String>();
    }
    return [];
  }

  /// Saves in-progress found words for a level, or removes the entry if empty.
  Future<void> saveActiveFoundWords({
    required String themeId,
    required int levelNumber,
    required List<String> words,
  }) async {
    final raw = _prefs.getString(_keyActiveFoundWords);
    final decoded = raw == null || raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final key = levelKey(themeId, levelNumber);
    if (words.isEmpty) {
      decoded.remove(key);
    } else {
      decoded[key] = words;
    }
    await _prefs.setString(_keyActiveFoundWords, jsonEncode(decoded));
  }

  Future<void> _updateStreakForToday() async {
    final now = DateTime.now();
    final today = _dateString(now);
    final lastDate = _prefs.getString(_keyLastPlayedDate);

    if (lastDate == today) {
      return;
    }

    final yesterday = _dateString(now.subtract(const Duration(days: 1)));
    final nextStreak = (lastDate == yesterday) ? streakCount + 1 : 1;
    await _prefs.setInt(_keyStreakCount, nextStreak);
    await _prefs.setString(_keyLastPlayedDate, today);
  }

  String _dateString(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }
}
