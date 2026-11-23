//
//  MacAboutView.swift
//  SportsCal
//
//  Native macOS "About" surface — used both as the App-menu About panel
//  (via a dedicated Window scene + the .appInfo command) and as the About
//  tab in the Settings window. Purchase/restore affordances are hidden when
//  entitlements are managed externally (Setapp build) — see SubscriptionManager.
//

#if os(macOS)
import SwiftUI
import AppKit
import RevenueCat

struct MacAboutView: View {
    @Environment(\.openURL) private var openURL

    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var showPaywall = false
    /// The active plan's one-line status ("Renews Mar 3, 2027", "Lifetime") and
    /// where to manage it. RevenueCatUI's Customer Center is iOS-only, so the Mac
    /// links to the App Store's subscription page instead.
    @State private var planStatus: String?
    @State private var managementURL: URL?

    private static let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    private static let supportEmail = "support@komodollc.com"
    private static let privacyURL = URL(string: "https://sportscal.app/privacy")!
    private static let websiteURL = URL(string: "https://sportscal.app")!

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Scoreline")
                    .font(.title.bold())
                Text("Every game, every league — in one calendar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }

            Divider()

            if !SubscriptionManager.isManagedExternally {
                proSection
            }

            VStack(spacing: 8) {
                if !SubscriptionManager.isManagedExternally {
                    Button {
                        restore()
                    } label: {
                        HStack(spacing: 6) {
                            if isRestoring { ProgressView().controlSize(.small) }
                            Text("Restore Purchases")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isRestoring)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }

                Button("Contact Support") { contactSupport() }
                    .frame(maxWidth: .infinity)
                Button("Privacy Policy") { openURL(Self.privacyURL) }
                    .frame(maxWidth: .infinity)
                Button("Website") { openURL(Self.websiteURL) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("© 2026 Mighty Panda LLC")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 320)
        .animation(.default, value: restoreMessage)
        .sheet(isPresented: $showPaywall) {
            SubscriptionSheet(subscriptionPresented: $showPaywall)
        }
        .task(id: subscriptionManager.isPro) { await loadPlan() }
    }

    @ViewBuilder
    private var proSection: some View {
        if subscriptionManager.isPro {
            VStack(spacing: 6) {
                Label("Scoreline Pro", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                if let planStatus {
                    Text(planStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // A lifetime purchase has nothing to manage.
                if let managementURL {
                    Button("Manage Subscription…") { openURL(managementURL) }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        } else {
            Button {
                showPaywall = true
            } label: {
                Label("Upgrade to Scoreline Pro…", systemImage: "star.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func loadPlan() async {
        guard subscriptionManager.isPro,
              let info = try? await Purchases.shared.customerInfo(),
              let pro = info.entitlements["Pro"], pro.isActive else {
            planStatus = nil
            managementURL = nil
            return
        }
        if let expiry = pro.expirationDate {
            let date = expiry.formatted(date: .abbreviated, time: .omitted)
            planStatus = pro.willRenew ? "Renews \(date)" : "Ends \(date)"
            managementURL = info.managementURL ?? Self.subscriptionsURL
        } else {
            planStatus = "Lifetime"
            managementURL = nil
        }
    }

    private func restore() {
        isRestoring = true
        restoreMessage = nil
        Task {
            let restored = await SubscriptionManager.shared.restorePurchases()
            restoreMessage = restored
                ? "Your purchases have been restored."
                : "No previous purchases were found."
            isRestoring = false
        }
    }

    private func contactSupport() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let subject = "Scoreline for Mac Support (v\(version))"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(Self.supportEmail)?subject=\(subject)") {
            openURL(url)
        }
    }
}

#Preview {
    MacAboutView()
}
#endif
