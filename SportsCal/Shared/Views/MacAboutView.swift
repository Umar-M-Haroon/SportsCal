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

struct MacAboutView: View {
    @Environment(\.openURL) private var openURL

    @State private var restoreMessage: String?
    @State private var isRestoring = false

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

            Text("© Komodo LLC")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 320)
        .animation(.default, value: restoreMessage)
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
