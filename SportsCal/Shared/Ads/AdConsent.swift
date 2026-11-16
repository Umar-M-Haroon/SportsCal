//
//  AdConsent.swift
//  SportsCal
//
//  Google's consent flow (UMP) in front of AdMob. Where consent is required (the
//  EEA, the UK, Switzerland and the US states AdMob's messages cover), the form is
//  shown once and the ads SDK starts only after it; everywhere else the update
//  comes back "not required" and ads start straight away. Which messages exist is
//  configured in the AdMob console (Privacy & messaging), not here.
//

#if os(iOS)
import Foundation
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
enum AdConsent {
    private static var gathering: Task<Bool, Never>?
    private static var didStartAds = false

    /// Whether ads may be requested now: last session's answer until this
    /// launch's update comes back.
    nonisolated static var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }

    /// Whether Settings should offer "Privacy Choices" (required wherever a
    /// consent message applies, so users can change their answer).
    static var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Refreshes consent, shows the form if it's needed and not yet answered, then
    /// starts the ads SDK. Runs once per launch however many windows ask; returns
    /// whether ads may be requested.
    @discardableResult
    static func gather() async -> Bool {
        if let gathering { return await gathering.value }
        let task = Task<Bool, Never> { @MainActor in
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: nil)
                try await ConsentForm.loadAndPresentIfRequired(from: nil)
            } catch {
                // Offline or no form: fall back to the stored answer.
                AppLogger.general.error("Ad consent update failed: \(error.localizedDescription)")
            }
            startAdsIfAllowed()
            return canRequestAds
        }
        gathering = task
        return await task.value
    }

    /// The form behind Settings → Privacy Choices.
    static func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            AppLogger.general.error("Privacy options form failed: \(error.localizedDescription)")
        }
        startAdsIfAllowed()
    }

    private static func startAdsIfAllowed() {
        guard canRequestAds, !didStartAds else { return }
        didStartAds = true
        Task.detached(priority: .utility) {
            await MobileAds.shared.start()
        }
    }
}
#endif
