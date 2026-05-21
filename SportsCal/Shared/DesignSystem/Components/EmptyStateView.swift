//
//  EmptyStateView.swift
//  SportsCal — Design System v1.0
//
//  Generic empty-state primitive. Configurable: SF Symbol + headline +
//  message + optional CTA. Covers all 12 wireframed scenarios (Quiet day,
//  Off-season, Offline, etc.) by config alone.
//

import SwiftUI

public struct EmptyStateView: View {
    public let symbol: String
    public let headline: String
    public let message: String
    public var cta: CTA? = nil

    public struct CTA {
        public let label: String
        public let action: () -> Void
        public init(label: String, action: @escaping () -> Void) {
            self.label = label
            self.action = action
        }
    }

    public init(
        symbol: String,
        headline: String,
        message: String,
        cta: CTA? = nil
    ) {
        self.symbol = symbol
        self.headline = headline
        self.message = message
        self.cta = cta
    }

    public var body: some View {
        VStack(spacing: .appSpace4) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appInkSoft)
                .accessibilityHidden(true)

            VStack(spacing: .appSpace2) {
                Text(headline).font(.appHeadline)
                Text(message)
                    .font(.appCallout)
                    .foregroundStyle(Color.appInkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let cta {
                Button(cta.label) { cta.action() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(minHeight: .appHit)
            }
        }
        .padding(.appSpace7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(headline). \(message)"))
    }
}
