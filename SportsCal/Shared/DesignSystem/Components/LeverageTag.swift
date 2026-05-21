//
//  LeverageTag.swift
//  SportsCal — Design System v1.0
//
//  Gold "★ leverage" tag for high-stakes moments — close score, rivalry,
//  playoff. Optional delta value shown ("★ ↑8" for an 8-point swing).
//

import SwiftUI

public struct LeverageTag: View {
    public let label: String          // "PLAYOFF G7", "RIVALRY", "CLOSE"
    public let delta: Int?            // optional swing magnitude

    public init(label: String, delta: Int? = nil) {
        self.label = label
        self.delta = delta
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .imageScale(.small)
            Text(text)
                .appEyebrow()
                .foregroundStyle(Color.appStar)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appStar.opacity(0.12))
        )
        .overlay(
            RoundedRectangle.appShape(.appRadiusXS)
                .strokeBorder(Color.appStar.opacity(0.30), lineWidth: 1)
        )
        .foregroundStyle(Color.appStar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Leverage, \(text)"))
    }

    private var text: String {
        if let delta { return "\(label) · ↑\(delta)" }
        return label
    }
}
