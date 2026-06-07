//
//  NativeAdManager.swift
//  SportsCal
//
//  Created by Umar Haroon on 2026-04-08.
//

#if os(iOS)
import Foundation
import GoogleMobileAds
import os

@Observable
class NativeAdManager: NSObject {
    /// Google's public test native ad unit ID. Always safe to click.
    /// https://developers.google.com/admob/ios/test-ads
    static let testNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"

    /// The ad unit ID actually used at runtime. In DEBUG builds we always use Google's test
    /// unit so accidental clicks during development can't get the AdMob account flagged.
    static var defaultAdUnitID: String {
        #if DEBUG
        return testNativeAdUnitID
        #else
        return Constants.nativeAdUnitID
        #endif
    }

    private(set) var loadedAds: [NativeAd] = []
    private var adLoader: AdLoader?
    private var isLoading = false
    private var lastLoadStarted: Date?

    /// How long a cached batch stays "fresh". After this, the next feed
    /// appearance discards it and loads new creatives so a long session isn't
    /// stuck showing the same handful of ads.
    private let refreshInterval: TimeInterval = 5 * 60

    private let adUnitID: String

    init(adUnitID: String = NativeAdManager.defaultAdUnitID) {
        self.adUnitID = adUnitID
        super.init()
    }

    /// Pre-load a batch of native ads so they're ready when scrolled into view.
    func preloadAds(count: Int = 3) {
        guard !isLoading, loadedAds.count < count else { return }
        startLoad(count: count - loadedAds.count)
    }

    /// Call from a feed's `onAppear`. Tops up after partial-fill failures, and
    /// when the cached batch has gone stale it discards and reloads fresh
    /// creatives to avoid ad fatigue over a long session.
    func refreshOnAppear(target: Int = 5) {
        guard !isLoading else { return }
        let isStale = lastLoadStarted.map { Date().timeIntervalSince($0) > refreshInterval } ?? true
        if isStale && !loadedAds.isEmpty {
            loadedAds.removeAll()
        }
        guard loadedAds.count < target else { return }
        startLoad(count: target - loadedAds.count)
    }

    private func startLoad(count: Int) {
        guard count > 0 else { return }
        isLoading = true
        lastLoadStarted = Date()

        let multipleAdsOptions = MultipleAdsAdLoaderOptions()
        multipleAdsOptions.numberOfAds = count

        let adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [multipleAdsOptions]
        )
        adLoader.delegate = self
        self.adLoader = adLoader
        adLoader.load(Request())
    }

    /// Return the cached creative for a given slot index. Non-recycling: returns
    /// nil once the slot exceeds available inventory, so a feed never shows the
    /// same creative twice (the old modulo behavior caused duplicates).
    func adForSlot(_ slot: Int) -> NativeAd? {
        guard slot >= 0, slot < loadedAds.count else { return nil }
        return loadedAds[slot]
    }
}

// MARK: - NativeAdLoaderDelegate

extension NativeAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        loadedAds.append(nativeAd)
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        AppLogger.general.error("Native ad failed to load: \(error.localizedDescription)")
        isLoading = false
    }

    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        isLoading = false
    }
}
#endif
