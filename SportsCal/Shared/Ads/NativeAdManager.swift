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
    private var pendingAdCount: Int = 0

    private let adUnitID: String

    init(adUnitID: String = NativeAdManager.defaultAdUnitID) {
        self.adUnitID = adUnitID
        super.init()
    }

    /// Pre-load a batch of native ads so they're ready when scrolled into view.
    func preloadAds(count: Int = 3) {
        guard loadedAds.count < count else { return }
        pendingAdCount = count - loadedAds.count

        let multipleAdsOptions = MultipleAdsAdLoaderOptions()
        multipleAdsOptions.numberOfAds = pendingAdCount

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

    /// Return a cached ad for a given slot index. Returns nil if none available.
    func adForSlot(_ slot: Int) -> NativeAd? {
        guard !loadedAds.isEmpty else { return nil }
        return loadedAds[slot % loadedAds.count]
    }
}

// MARK: - NativeAdLoaderDelegate

extension NativeAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        loadedAds.append(nativeAd)
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        AppLogger.general.error("Native ad failed to load: \(error.localizedDescription)")
    }
}
#endif
