//
//  Font+App.swift
//  SportsCal — Design System v1.0
//
//  All system fonts. SF Pro Rounded replaces the wireframe's Kalam
//  (warmest iOS-installed face). SF Mono replaces JetBrains Mono. SF Pro
//  Text covers body. Every token uses .system(.text, design:) so Dynamic
//  Type just works.
//

import SwiftUI

public extension Font {
    // MARK: - Display + titles (SF Pro Rounded)

    static let appDisplay  = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let appTitle    = Font.system(.title2,    design: .rounded).weight(.bold)
    static let appHeadline = Font.system(.headline,  design: .rounded).weight(.semibold)

    // MARK: - Body (SF Pro Text)

    static let appBody    = Font.system(.body)
    static let appCallout = Font.system(.callout)

    // MARK: - Eyebrows + metadata (SF Mono)

    static let appFootnote = Font.system(.caption2, design: .monospaced).weight(.semibold)
    static let appCaption  = Font.system(.caption,  design: .monospaced)

    // MARK: - Scores (rounded, heavy, tabular)

    static let appScore = Font.system(.title, design: .rounded)
        .weight(.heavy)
        .monospacedDigit()
}

// MARK: - Eyebrow modifier

/// Eyebrow style: monospaced, tracked, uppercase, faint ink. Use for
/// "FOR YOU · 4 LIVE" headers and other category labels.
public struct EyebrowStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(.appFootnote)
            .tracking(2.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.appInkFaint)
    }
}

public extension View {
    /// Apply eyebrow type style: mono, tracked 2.5, uppercase, faint ink.
    func appEyebrow() -> some View { modifier(EyebrowStyle()) }
}
