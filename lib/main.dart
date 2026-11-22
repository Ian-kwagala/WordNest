import 'package:flutter/material.dart';

import 'domain/models/word_pack_models.dart';
import 'screens/packs_screen.dart';
import 'services/ad_service.dart';
import 'services/sound_service.dart';
import 'services/storage_service.dart';
import 'services/word_pack_service.dart';
import 'ui/core/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await StorageService.create();
  final sound = SoundService(enabled: storage.soundEnabled);
  final ads = AdService();
  // Load offline JSON packs immediately; ad initialization never blocks offline play.
  final themes = await const WordPackService().loadThemes();
  // Fire and forget AdMob + UMP consent setup so offline launch is instant.
  ads.initialize();

  runApp(
    WordNestApp(
      themes: themes,
      storage: storage,
      sound: sound,
      ads: ads,
    ),
  );
}

/// Root widget for WordNest: Offline Word Hunt.
class WordNestApp extends StatelessWidget {
  const WordNestApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WordNest',
      debugShowCheckedModeBanner: false,
      theme: WordNestTheme.buildThemeData(),
      home: PacksScreen(
        themes: themes,
        storage: storage,
        sound: sound,
        ads: ads,
      ),
    );
  }
}
