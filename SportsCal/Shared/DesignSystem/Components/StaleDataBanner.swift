//
//  StaleDataBanner.swift
//  SportsCal — Design System v1.0 (edge-case primitive #4 of 4)
//
//  Top-of-screen banner shown when we're displaying cached data while
//  offline (or after a fetch failure). Compact pill; tap to retry.
//

import SwiftUI

public struct StaleDataBanner: View {
    public let lastUpdatedAgo: String   // "4m ago"
    public let retryAction: () -> Void

    public init(lastUpdatedAgo: String, retryAction: @escaping () -> Void) {
        self.lastUpdatedAgo = lastUpdatedAgo
        self.retryAction = retryAction
    }

    public var body: some View {
        Button(action: retryAction) {
            HStack(spacing: .appSpace2) {
                Image(systemName: "wifi.slash")
                    .imageScale(.small)
                Text("Showing data from \(lastUpdatedAgo)")
                    .font(.appCallout)
                Spacer(minLength: .appSpace2)
                Text("Retry")
                    .font(.appFootnote)
                    .tracking(1)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, .appSpace4)
            .padding(.vertical, .appSpace2)
            .frame(maxWidth: .infinity, minHeight: .appHit)
            .foregroundStyle(Color.appLive)
            .background(
                RoundedRectangle.appShape(.appRadiusSM)
                    .fill(Color.appLive.opacity(0.12))
            )
            .overlay(
                RoundedRectangle.appShape(.appRadiusSM)
                    .strokeBorder(Color.appLive.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Showing data from \(lastUpdatedAgo). Tap to retry."))
        .accessibilityAddTraits(.isButton)
    }
}
