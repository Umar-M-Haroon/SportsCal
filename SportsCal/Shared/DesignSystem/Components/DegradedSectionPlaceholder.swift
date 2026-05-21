//
//  DegradedSectionPlaceholder.swift
//  SportsCal — Design System v1.0 (edge-case primitive #3 of 4)
//
//  Slim inline "this section's data isn't available" placeholder. Use
//  inside a working detail screen when ONE section degrades — e.g.
//  "Standings not available for this league" inside Game Detail. Smaller
//  than EmptyStateView; takes the slot the data would have filled.
//

import SwiftUI

public struct DegradedSectionPlaceholder: View {
    public let symbol: String           // SF Symbol
    public let message: String          // "Standings not available for this league"
    public var detail: String? = nil    // optional secondary line

    public init(symbol: String, message: String, detail: String? = nil) {
        self.symbol = symbol
        self.message = message
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: .appSpace3) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appInkFaint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.appCallout)
                    .foregroundStyle(Color.appInkSoft)
                if let detail {
                    Text(detail)
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkFaint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, .appSpace3)
        .padding(.horizontal, .appSpace4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle.appShape(.appRadiusSM)
                .fill(Color.appAlt.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(detail.map { "\(message). \($0)" } ?? message))
    }
}
