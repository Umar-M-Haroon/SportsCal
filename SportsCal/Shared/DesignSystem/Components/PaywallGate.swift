//
//  PaywallGate.swift
//  SportsCal — Design System v1.0 (edge-case primitive #1 of 4)
//
//  Locked-state card for Pro-only features. Shows what's behind the gate
//  + a CTA that opens the paywall sheet. Visually a hybrid of
//  EmptyStateView and a card — sits inline where the feature would.
//

import SwiftUI

public struct PaywallGate: View {
    public let feature: String          // "Live Activities"
    public let blurb: String            // "Get scores in your Dynamic Island."
    public let unlockAction: () -> Void

    public init(
        feature: String,
        blurb: String,
        unlockAction: @escaping () -> Void
    ) {
        self.feature = feature
        self.blurb = blurb
        self.unlockAction = unlockAction
    }

    public var body: some View {
        VStack(spacing: .appSpace3) {
            HStack(spacing: .appSpace2) {
                Image(systemName: "lock.fill")
                    .imageScale(.medium)
                    .foregroundStyle(Color.appStar)
                Text(feature.uppercased())
                    .appEyebrow()
                    .foregroundStyle(Color.appStar)
                Spacer()
                Text("PRO")
                    .font(.appFootnote)
                    .tracking(1.5)
                    .foregroundStyle(Color.appStar)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle.appShape(.appRadiusXS)
                            .fill(Color.appStar.opacity(0.12))
                    )
            }
            Text(blurb)
                .font(.appCallout)
                .foregroundStyle(Color.appInkSoft)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: unlockAction) {
                Text("Unlock Scoreline Pro")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: .appHit)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appStar)
        }
        .appCard(fill: Color.appStar.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(feature), Pro feature. \(blurb). Tap to unlock."))
        .accessibilityAddTraits(.isButton)
    }
}
