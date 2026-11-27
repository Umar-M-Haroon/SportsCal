//
//  SubscriptionSheet.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/20/22.
//

import SwiftUI
import RevenueCat

struct SubscriptionSheet: View {
    @Binding var subscriptionPresented: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Our own paywall on every platform. RevenueCatUI's can't render the
        // dashboard (legacy) paywall on macOS at all, and on iOS its template only
        // said "Get the ultimate experience" without saying what Pro includes.
        ProPaywallView(onFinish: close)
    }

    /// Hosts drive this sheet either with this binding or with an enum
    /// (`sheetType`), where the binding is a stand-in; dismiss covers both.
    private func close() {
        subscriptionPresented = false
        dismiss()
    }
}

// MARK: - Paywall

/// Scoreline Pro paywall: what Pro includes, then plans from the current
/// RevenueCat offering. Two panes on the Mac, one scrolling column on iPhone and
/// iPad. Purchases go through RevenueCat, so entitlements and receipts are the same
/// as with RevenueCatUI.
struct ProPaywallView: View {
    var onFinish: () -> Void

    @State private var packages: [Package] = []
    @State private var selectedID: String?
    @State private var loadFailed = false
    @State private var isLoading = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var message: String?
    /// Why this paywall opened (taken from `UpsellCoordinator` on appear).
    @State private var trigger: UpsellTrigger = .direct
    @State private var didAppear = false
    @State private var purchased = false

    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://sportscal.app/privacy")!

    private var selected: Package? {
        packages.first { $0.identifier == selectedID } ?? packages.first
    }

    var body: some View {
        content
            .task { await loadOffering() }
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                trigger = UpsellCoordinator.shared.takePendingTrigger()
                MonetizationTelemetry.paywallShown(trigger: trigger.rawValue,
                                                   featured: featured?.rawValue ?? "none")
            }
            .onDisappear {
                MonetizationTelemetry.paywallDismissed(trigger: trigger.rawValue, purchased: purchased)
            }
    }

    #if os(macOS)
    private var content: some View {
        HStack(spacing: 0) {
            benefitsPane
                .frame(width: 330)
            plansPane
                .frame(maxWidth: .infinity)
        }
        .frame(width: 760, height: 540)
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(14)
        }
    }
    #else
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                benefitsPane
                planChoices
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                purchaseButton
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(.bar)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.25), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(16)
        }
    }
    #endif

    // MARK: Benefits

    private var benefitsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            appIcon
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .padding(.bottom, 14)

            Text("Scoreline Pro")
                .font(.system(size: 26, weight: .bold))
            Text(featured?.pitch ?? "More from every game you follow.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 2)
            #else
            // iPhone: icon beside the title and one line per benefit, so every plan
            // sits above the purchase button without scrolling.
            HStack(spacing: 14) {
                appIcon
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scoreline Pro")
                        .font(.system(size: 26, weight: .bold))
                    Text(featured?.pitch ?? "More from every game you follow.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.trailing, 36) // clear of the close button
            #endif

            VStack(alignment: .leading, spacing: Self.benefitSpacing) {
                ForEach(orderedFeatures, id: \.self) { feature in
                    benefit(feature, isFeatured: feature == featured)
                }
            }
            .padding(.top, Self.benefitSpacing + 8)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        #if os(macOS)
        .padding(28)
        .padding(.top, 8)
        #else
        .padding(20)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.mix(with: .black, by: 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        #if os(macOS)
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
        #else
        AppIconThumbnail(icon: .standard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        #endif
    }

    /// The feature this paywall leads with, from its trigger (a theme tap → Themes).
    private var featured: PaywallFeature? {
        trigger.featured.flatMap { PaywallFeature.forPlatform.contains($0) ? $0 : nil }
    }

    /// This platform's benefits, the featured one first.
    private var orderedFeatures: [PaywallFeature] {
        let all = PaywallFeature.forPlatform
        guard let featured else { return all }
        return [featured] + all.filter { $0 != featured }
    }

    private func benefit(_ feature: PaywallFeature, isFeatured: Bool) -> some View {
        benefit(feature.symbol, feature.title, feature.detail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, isFeatured ? 6 : 0)
            .padding(.horizontal, isFeatured ? 8 : 0)
            .background {
                if isFeatured {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.16))
                }
            }
            .padding(.horizontal, isFeatured ? -8 : 0)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                #if os(macOS)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                #endif
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }

    #if os(macOS)
    private static var benefitSpacing: CGFloat { 14 }
    #else
    private static var benefitSpacing: CGFloat { 10 }
    #endif

    // MARK: Plans

    /// "Choose your plan" and the plan rows, shared by both layouts.
    private var planChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your plan")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 14)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if loadFailed || packages.isEmpty {
                loadErrorView
            } else {
                VStack(spacing: 10) {
                    ForEach(packages, id: \.identifier) { package in
                        planRow(package)
                    }
                }
            }
        }
    }

    #if os(macOS)
    private var plansPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            planChoices
                .frame(maxHeight: .infinity, alignment: .top)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }

            purchaseButton

            footer
                .padding(.top, 12)
        }
        .padding(28)
        .padding(.top, 8)
    }
    #endif

    private var loadErrorView: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Couldn't load plans")
                .font(.headline)
            Text("Check your connection and try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again") { Task { await loadOffering() } }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func planRow(_ package: Package) -> some View {
        let isSelected = package.identifier == selected?.identifier
        let badge = badgeText(for: package)
        return Button {
            guard package.identifier != selectedID else { return }
            selectedID = package.identifier
            MonetizationTelemetry.paywallPlanSelected(plan: Self.planKey(package))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title(for: package))
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(subtitle(for: package))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.headline)
                        .monospacedDigit()
                    Text(periodLabel(for: package))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            ZStack {
                Text(ctaTitle).opacity(isPurchasing ? 0 : 1)
                if isPurchasing { ProgressView().controlSize(.small) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(selected == nil || isPurchasing || isRestoring)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(renewalDisclosure)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button(isRestoring ? "Restoring…" : "Restore Purchases") {
                    Task { await restore() }
                }
                .disabled(isRestoring || isPurchasing)
                Link("Terms of Use", destination: Self.termsURL)
                Link("Privacy Policy", destination: Self.privacyURL)
            }
            #if os(macOS)
            .buttonStyle(.link)
            #else
            .buttonStyle(.borderless)
            #endif
            .font(.caption)
        }
    }

    // MARK: Copy

    private func title(for package: Package) -> String {
        switch package.packageType {
        case .lifetime: return "Lifetime"
        case .annual: return "Yearly"
        case .sixMonth: return "6 Months"
        case .threeMonth: return "3 Months"
        case .twoMonth: return "2 Months"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        default: return package.storeProduct.localizedTitle
        }
    }

    private func periodLabel(for package: Package) -> String {
        switch package.packageType {
        case .lifetime: return "once"
        case .annual: return "per year"
        case .monthly: return "per month"
        case .weekly: return "per week"
        default: return package.storeProduct.subscriptionPeriod.map { "per \($0.value) \(unitName($0.unit))" } ?? ""
        }
    }

    private func unitName(_ unit: SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "days"
        case .week: return "weeks"
        case .month: return "months"
        case .year: return "years"
        @unknown default: return ""
        }
    }

    private func subtitle(for package: Package) -> String {
        if let trial = freeTrialText(for: package) {
            return "\(trial), then \(package.storeProduct.localizedPriceString) \(periodLabel(for: package))"
        }
        switch package.packageType {
        case .lifetime: return "Pay once, keep Pro forever"
        case .annual:
            if let monthly = package.storeProduct.localizedPricePerMonth {
                return "Just \(monthly) a month"
            }
            return "Billed yearly"
        case .monthly: return "Cancel anytime"
        default: return "Auto-renews"
        }
    }

    private func badgeText(for package: Package) -> String? {
        guard package.packageType == .annual,
              let monthly = packages.first(where: { $0.packageType == .monthly }) else { return nil }
        let yearAtMonthly = monthly.storeProduct.price * 12
        guard yearAtMonthly > 0 else { return nil }
        let saving = (1 - package.storeProduct.price / yearAtMonthly) * 100
        // Via Double: NSDecimalNumber.intValue misreads long-mantissa decimals.
        let percent = Int(NSDecimalNumber(decimal: saving).doubleValue.rounded(.down))
        return percent >= 10 ? "SAVE \(percent)%" : "BEST VALUE"
    }

    private func freeTrialText(for package: Package) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: return nil
        }
        return "\(period.value) \(unit) free"
    }

    private var ctaTitle: String {
        guard let selected else { return "Continue" }
        if freeTrialText(for: selected) != nil { return "Start Free Trial" }
        return selected.packageType == .lifetime ? "Unlock Pro Forever" : "Subscribe"
    }

    private var renewalDisclosure: String {
        if selected?.packageType == .lifetime {
            return "One-time purchase. No subscription."
        }
        return "Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage them in App Store settings."
    }

    // MARK: Actions

    /// Telemetry key for a package: monthly / annual / lifetime (anything else: other).
    private static func planKey(_ package: Package) -> String {
        switch package.packageType {
        case .monthly: return "monthly"
        case .annual: return "annual"
        case .lifetime: return "lifetime"
        default: return "other"
        }
    }

    private func loadOffering() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let offering = try await SubscriptionManager.shared.purchases.offerings().current
            let order: [PackageType] = [.monthly, .annual, .lifetime]
            packages = (offering?.availablePackages ?? []).sorted {
                (order.firstIndex(of: $0.packageType) ?? order.count)
                    < (order.firstIndex(of: $1.packageType) ?? order.count)
            }
            // Lead with the yearly plan: the best deal for anyone staying past a few months.
            selectedID = (packages.first { $0.packageType == .annual } ?? packages.first)?.identifier
        } catch {
            AppLogger.general.error("Mac paywall: offerings failed: \(error.localizedDescription)")
            loadFailed = true
        }
    }

    private func purchase() async {
        guard let package = selected else { return }
        let plan = Self.planKey(package)
        message = nil
        isPurchasing = true
        defer { isPurchasing = false }
        MonetizationTelemetry.paywallPurchaseStarted(plan: plan, trigger: trigger.rawValue)
        do {
            let result = try await SubscriptionManager.shared.purchases.purchase(package: package)
            if result.userCancelled {
                MonetizationTelemetry.paywallPurchaseEnded(plan: plan, cancelled: true)
                return
            }
            // Sends purchase_completed / trial_started (with plan + trigger) on the
            // false→true flip.
            SubscriptionManager.shared.updateProStatus(from: result.customerInfo)
            if SubscriptionManager.shared.isPro {
                purchased = true
                onFinish()
            }
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            MonetizationTelemetry.paywallPurchaseEnded(plan: plan, cancelled: true)
        } catch {
            MonetizationTelemetry.paywallPurchaseEnded(plan: plan, cancelled: false)
            message = error.localizedDescription
        }
    }

    private func restore() async {
        message = nil
        isRestoring = true
        defer { isRestoring = false }
        let restored = await SubscriptionManager.shared.restorePurchases()
        MonetizationTelemetry.paywallRestore(restored: restored)
        if restored {
            onFinish()
        } else {
            message = "No active Scoreline Pro purchase was found for this Apple Account."
        }
    }
}

// MARK: - Benefits

/// A Pro benefit as the paywall lists it. Raw values are the `featured` telemetry
/// field (matching `ProFeature` where one exists), so keep them stable.
enum PaywallFeature: String, CaseIterable {
    case scoreAlerts = "goalAlerts"
    case adFree
    case menuBar
    case customAlerts
    case reminders = "preGameReminders"
    case themes
    case fantasy = "fantasyLeagues"
    case proSettings

    /// What this platform's paywall lists, in order. The Mac has no ads and no
    /// score alerts (no Live Activities), but has the menu bar.
    static var forPlatform: [PaywallFeature] {
        #if os(macOS)
        return [.menuBar, .customAlerts, .fantasy, .reminders, .themes, .proSettings]
        #else
        return [.scoreAlerts, .adFree, .customAlerts, .fantasy, .reminders, .themes, .proSettings]
        #endif
    }

    var symbol: String {
        switch self {
        case .scoreAlerts: return "bell.and.waves.left.and.right"
        case .adFree: return "nosign"
        case .menuBar: return "menubar.rectangle"
        case .customAlerts: return "bell.badge.waveform"
        case .reminders: return "alarm"
        case .themes: return "paintpalette"
        case .fantasy: return "football"
        case .proSettings: return "slider.horizontal.3"
        }
    }

    var title: String {
        switch self {
        case .scoreAlerts: return ProFeature.goalAlerts.displayName
        case .adFree: return "No Ads"
        case .menuBar: return "Live scores in the menu bar"
        case .customAlerts: return ProFeature.customAlerts.displayName
        case .reminders: return ProFeature.preGameReminders.displayName
        case .themes: return ProFeature.themes.displayName
        case .fantasy: return "Fantasy Leagues"
        case .proSettings: return ProFeature.proSettings.displayName
        }
    }

    var detail: String {
        switch self {
        case .scoreAlerts: return "Your phone buzzes the moment your team scores."
        case .adFree: return "Scores and schedules without ads."
        case .menuBar: return "Every game you follow, one glance away."
        case .customAlerts: return ProFeature.customAlerts.blurb
        case .reminders: return "Reminders before kickoff, for every team you follow."
        case .themes: return "Accent colors, team colors and app icons."
        case .fantasy: return "Your Sleeper or ESPN league's scoring and roster, live."
        case .proSettings: return ProFeature.proSettings.blurb
        }
    }

    /// The header line when the paywall leads with this feature.
    var pitch: String {
        switch self {
        case .scoreAlerts: return "Feel every goal, even with your phone locked."
        case .adFree: return "Keep the scores, lose the ads."
        case .menuBar: return "Live scores, right in your menu bar."
        case .customAlerts: return "Alerts for every player and moment you care about."
        case .reminders: return "Never miss kickoff for any team you follow."
        case .themes: return "Make Scoreline yours."
        case .fantasy: return "Your fantasy league, scored live."
        case .proSettings: return "Shape the schedule the way you like it."
        }
    }
}

#Preview {
    SubscriptionSheet(subscriptionPresented: .constant(true))
}
