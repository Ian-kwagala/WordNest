import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordnest/domain/models/word_pack_models.dart';
import 'package:wordnest/main.dart';
import 'package:wordnest/services/ad_service.dart';
import 'package:wordnest/services/sound_service.dart';
import 'package:wordnest/services/storage_service.dart';

void main() {
  testWidgets('WordNestApp renders packs and opens a puzzle board', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    final sound = SoundService(enabled: false);
    final ads = AdService();

    final rawJson = File('assets/data/word_packs.json').readAsStringSync();
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final themes = (decoded['themes'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(WordThemePack.fromJson)
        .toList();

    await tester.pumpWidget(
      WordNestApp(
        themes: themes,
        storage: storage,
        sound: sound,
        ads: ads,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WordNest'), findsOneWidget);
    expect(find.text('5-Minute Daily Sprint'), findsOneWidget);
    expect(find.text('Animals'), findsOneWidget);

    // Open Level 1 of the first theme pack (Animals)
    await tester.tap(find.text('Lvl 1').first);
    await tester.pumpAndSettle();

    expect(find.text('Animals • Level 1'), findsOneWidget);
    expect(find.textContaining('Mystery Clue:'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // 3 free hints on install
  });
}
