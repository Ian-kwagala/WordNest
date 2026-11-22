import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/models/word_pack_models.dart';

/// Loads themed word packs and levels from the offline JSON asset.
class WordPackService {
  const WordPackService({
    this.assetPath = 'assets/data/word_packs.json',
  });

  final String assetPath;

  /// Reads and parses all themes and levels directly from the app bundle.
  Future<List<WordThemePack>> loadThemes() async {
    final jsonString = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final rawThemes =
        (decoded['themes'] as List<dynamic>).cast<Map<String, dynamic>>();
    return rawThemes.map(WordThemePack.fromJson).toList();
  }
}
