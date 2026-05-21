//
//  Radius.swift
//  SportsCal — Design System v1.0
//
//  Continuous-corner squircle radii. Always pair with
//  RoundedRectangle(style: .continuous) (or the .appShape helper). Values
//  nest properly: a parent's radius ≥ child radius + child padding.
//

import SwiftUI

public extension CGFloat {
    /// 4 pt — chips, tags.
    static let appRadiusXS:   CGFloat = 4
    /// 8 pt — game-grid tiles.
    static let appRadiusSM:   CGFloat = 8
    /// 12 pt — surfaces, standard cards.
    static let appRadiusMD:   CGFloat = 12
    /// 16 pt — hero cards, sheet content.
    static let appRadiusLG:   CGFloat = 16
    /// 22 pt — widget container shape.
    static let appRadiusXL:   CGFloat = 22
    /// Pill / capsule.
    static let appRadiusPill: CGFloat = .infinity
}

public extension RoundedRectangle {
    /// Squircle helper: `RoundedRectangle.appShape(.appRadiusMD)` is shorter
    /// than spelling out `RoundedRectangle(cornerRadius:.appRadiusMD, style:.continuous)`.
    static func appShape(_ r: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: r, style: .continuous)
    }
}
