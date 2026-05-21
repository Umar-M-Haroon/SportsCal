//
//  SportChip.swift
//  SportsCal — Design System v1.0
//
//  Sport-tinted chip with glyph + label. Used in Browse rows and filter
//  bars. Toggle via .selected modifier.
//

import SwiftUI
import SportsCalModel

public struct SportChip: View {
    public let sport: SportType
    public var selected: Bool = false

    public init(sport: SportType, selected: Bool = false) {
        self.sport = sport
        self.selected = selected
    }

    public var body: some View {
        let accent = Color.app(sport)
        HStack(spacing: .appSpace1) {
            Image(systemName: sport.systemImage)
                .imageScale(.small)
            Text(sport.displayName)
                .font(.appCaption)
        }
        .padding(.horizontal, .appSpace3)
        .padding(.vertical, 6)
        .frame(minHeight: .appHit)
        .foregroundStyle(selected ? Color.appBackground : accent)
        .background(
            RoundedRectangle.appShape(.appRadiusPill)
                .fill(selected ? accent : Color.appTint(sport))
        )
        .overlay(
            RoundedRectangle.appShape(.appRadiusPill)
                .strokeBorder(accent.opacity(selected ? 0 : 0.4), lineWidth: 1)
        )
        .accessibilityLabel(Text(sport.displayName))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
