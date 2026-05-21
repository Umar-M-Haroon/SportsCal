//
//  TeamLogo.swift
//  SportsCal — Design System v1.0
//
//  Team logo with abbreviated-text fallback. When an asset is missing,
//  renders a tinted circle with the team's abbreviation in the sport's
//  accent color.
//

import SwiftUI
import SportsCalModel

public struct TeamLogo: View {
    public let abbreviation: String
    public let sport: SportType
    public let assetName: String?
    public var size: CGFloat = 28

    public init(
        abbreviation: String,
        sport: SportType,
        assetName: String? = nil,
        size: CGFloat = 28
    ) {
        self.abbreviation = abbreviation
        self.sport = sport
        self.assetName = assetName
        self.size = size
    }

    public var body: some View {
        Group {
            if let name = assetName, assetExists(name) {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Circle().fill(Color.appTint(sport))
                    Text(abbreviation)
                        .font(.system(size: size * 0.36,
                                      weight: .heavy,
                                      design: .rounded))
                        .foregroundStyle(Color.app(sport))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(abbreviation))
    }

    private func assetExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #elseif canImport(AppKit)
        return NSImage(named: name) != nil
        #else
        return false
        #endif
    }
}
