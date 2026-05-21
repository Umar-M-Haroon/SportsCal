//
//  AppCardStyle.swift
//  SportsCal — Design System v1.0
//
//  Standard surface card style: padding, continuous-corner background,
//  rest-level shadow (auto-disables on Reduce Transparency). Use anywhere
//  you want a "card" surface.
//

import SwiftUI

public struct AppCardStyle: ViewModifier {
    public var radius: CGFloat = .appRadiusMD
    public var padding: CGFloat = .appSpace4
    public var fill: Color = .appSurface
    public var shadow: AppShadow = .rest

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle.appShape(radius)
                    .fill(fill)
            )
            .appShadow(shadow)
    }
}

public extension View {
    func appCard(
        radius: CGFloat = .appRadiusMD,
        padding: CGFloat = .appSpace4,
        fill: Color = .appSurface,
        shadow: AppShadow = .rest
    ) -> some View {
        modifier(AppCardStyle(
            radius: radius, padding: padding, fill: fill, shadow: shadow
        ))
    }
}
