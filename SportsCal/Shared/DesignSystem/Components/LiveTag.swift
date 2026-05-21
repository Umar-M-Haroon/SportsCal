//
//  LiveTag.swift
//  SportsCal — Design System v1.0
//
//  Small "LIVE · period · clock" eyebrow chip with a pulsing dot.
//  Pulse honors Reduce Motion (skips animation, leaves the dot static).
//

import SwiftUI

public struct LiveTag: View {
    public let period: String   // "Q4", "73'", "T9", "L42/78"
    public let clock: String?   // "4:22" — optional (some sports omit)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(period: String, clock: String? = nil) {
        self.period = period
        self.clock = clock
    }

    public var body: some View {
        HStack(spacing: .appSpace1) {
            Circle()
                .fill(Color.appLive)
                .frame(width: 7, height: 7)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text(label)
                .appEyebrow()
                .foregroundStyle(Color.appLive)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Live, \(label)"))
    }

    private var label: String {
        if let clock { return "Live · \(period) · \(clock)" }
        return "Live · \(period)"
    }
}
