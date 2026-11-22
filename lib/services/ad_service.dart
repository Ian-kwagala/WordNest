import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Manages Google AdMob Banner, Rewarded Hint, and Level-Clear Interstitial ads.
///
/// Uses Google's official Test Ad Unit IDs by default so development and testing
/// never risk violating AdMob policies. Replace with real IDs only at release.
class AdService {
  AdService();

  // Official Google AdMob Android Test Ad Unit IDs.
  static const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewardedId =
      'ca-app-pub-3940256099942544/5224354917';

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _initialized = false;

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Initializes the Mobile Ads SDK and requests UMP privacy consent when needed.
  Future<void> initialize() async {
    if (_initialized || !_isMobilePlatform) return;
    _initialized = true;

    try {
      await _requestConsentIfNeeded();
      await MobileAds.instance.initialize();
      _preloadInterstitial();
      _preloadRewarded();
    } catch (_) {
      // Fail quietly when offline so the game remains 100% playable.
    }
  }

  /// Requests Europe/UK UMP privacy consent when online; skips safely if offline.
  Future<void> _requestConsentIfNeeded() async {
    final completer = Completer<void>();
    final params = ConsentRequestParameters();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          if (await ConsentInformation.instance.isConsentFormAvailable()) {
            ConsentForm.loadAndShowConsentFormIfRequired((_) {
              if (!completer.isCompleted) completer.complete();
            });
            return;
          }
        } catch (_) {
          // Ignore form errors in offline mode.
        }
        if (!completer.isCompleted) completer.complete();
      },
      (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Never block app startup longer than 2 seconds if offline.
    await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  /// Creates an adaptive banner ad. Calls [onLoaded] only when ready to display,
  /// ensuring nothing shows when offline (zero blank broken box).
  BannerAd? createAdaptiveBanner({
    required int widthPx,
    required void Function(BannerAd ad) onLoaded,
    required VoidCallback onFailed,
  }) {
    if (!_isMobilePlatform) return null;

    final ad = BannerAd(
      adUnitId: _testBannerId,
      size: AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(widthPx),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) => onLoaded(loadedAd as BannerAd),
        onAdFailedToLoad: (failedAd, _) {
          failedAd.dispose();
          onFailed();
        },
      ),
    );
    ad.load();
    return ad;
  }

  void _preloadInterstitial() {
    if (!_isMobilePlatform) return;
    InterstitialAd.load(
      adUnitId: _testInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }

  void _preloadRewarded() {
    if (!_isMobilePlatform) return;
    RewardedAd.load(
      adUnitId: _testRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (_) => _rewardedAd = null,
      ),
    );
  }

  /// Shows a full-screen interstitial only every 2 completed levels,
  /// after a 1-second safety delay so players don't tap it by mistake.
  Future<void> maybeShowLevelClearInterstitial(int totalCompleted) async {
    if (!_isMobilePlatform) return;
    if (totalCompleted <= 0 || totalCompleted % 2 != 0) return;

    final ad = _interstitialAd;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    // Required 1-second safety pause before presenting full-screen ad.
    await Future<void>.delayed(const Duration(seconds: 1));

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (closedAd) {
        closedAd.dispose();
        _interstitialAd = null;
        _preloadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (failedAd, _) {
        failedAd.dispose();
        _interstitialAd = null;
        _preloadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
    );

    await ad.show();
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
  }

  /// Shows a Rewarded Video ad to refill hints (+2 hints on reward).
  /// Returns true if the player earned the reward.
  Future<bool> showRewardedHintAd() async {
    if (!_isMobilePlatform) return false;
    final ad = _rewardedAd;
    if (ad == null) {
      _preloadRewarded();
      return false;
    }

    var earned = false;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (closedAd) {
        closedAd.dispose();
        _rewardedAd = null;
        _preloadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (failedAd, _) {
        failedAd.dispose();
        _rewardedAd = null;
        _preloadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    await ad.show(
      onUserEarnedReward: (_, _) {
        earned = true;
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => earned,
    );
  }

  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
  }
}
